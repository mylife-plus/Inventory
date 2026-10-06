import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:pdf/pdf.dart';

/// One selectable paper size on the print screen (e.g. A4 / 80 mm roll).
@immutable
class PrintPaperChoice {
  const PrintPaperChoice({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.format,
  });

  final String id;
  final String label;
  final String subtitle;
  final IconData icon;
  final PdfPageFormat format;
}

/// Opens the dedicated full-screen print window: a preview of exactly what
/// will be printed, an optional paper picker and a Print button that hands
/// the job to the system print dialog.
///
/// [preview] returns a PNG for the selected paper (or `null` paper when
/// [papers] is empty). [onPrint] opens the system dialog for that paper.
Future<void> openPrintPage(
  BuildContext context, {
  required String title,
  required Future<Uint8List> Function(PrintPaperChoice? paper) preview,
  required Future<void> Function(PrintPaperChoice? paper) onPrint,
  List<PrintPaperChoice> papers = const [],
  String? initialPaperId,
  ValueChanged<PrintPaperChoice>? onPaperChanged,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => PrintPreviewPage(
        title: title,
        preview: preview,
        onPrint: onPrint,
        papers: papers,
        initialPaperId: initialPaperId,
        onPaperChanged: onPaperChanged,
      ),
    ),
  );
}

class PrintPreviewPage extends ConsumerStatefulWidget {
  const PrintPreviewPage({
    super.key,
    required this.title,
    required this.preview,
    required this.onPrint,
    this.papers = const [],
    this.initialPaperId,
    this.onPaperChanged,
  });

  final String title;
  final Future<Uint8List> Function(PrintPaperChoice? paper) preview;
  final Future<void> Function(PrintPaperChoice? paper) onPrint;
  final List<PrintPaperChoice> papers;
  final String? initialPaperId;
  final ValueChanged<PrintPaperChoice>? onPaperChanged;

  @override
  ConsumerState<PrintPreviewPage> createState() => _PrintPreviewPageState();
}

class _PrintPreviewPageState extends ConsumerState<PrintPreviewPage> {
  PrintPaperChoice? _paper;
  Uint8List? _png;
  Object? _previewError;
  bool _printing = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    if (widget.papers.isNotEmpty) {
      _paper = widget.papers.firstWhere(
        (p) => p.id == widget.initialPaperId,
        orElse: () => widget.papers.first,
      );
    }
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final gen = ++_gen;
    setState(() {
      _png = null;
      _previewError = null;
    });
    try {
      final png = await widget.preview(_paper);
      if (!mounted || gen != _gen) return;
      setState(() => _png = png);
    } catch (e, st) {
      debugPrint('Print preview failed: $e\n$st');
      if (!mounted || gen != _gen) return;
      setState(() => _previewError = e);
    }
  }

  void _selectPaper(PrintPaperChoice paper) {
    if (paper.id == _paper?.id) return;
    AppHaptics.selection();
    setState(() => _paper = paper);
    widget.onPaperChanged?.call(paper);
    _loadPreview();
  }

  Future<void> _print() async {
    if (_printing) return;
    AppHaptics.medium();
    setState(() => _printing = true);
    try {
      await widget.onPrint(_paper);
    } catch (e, st) {
      debugPrint('Print failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.read(tProvider)('print_failed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.print_rounded, size: 18, color: p.textPrimary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(widget.title, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.papers.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 8),
                  child: Text(
                    t('printer_paper_size'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.papers.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _PaperTile(
                          paper: widget.papers[i],
                          selected: widget.papers[i].id == _paper?.id,
                          onTap: () => _selectPaper(widget.papers[i]),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.stroke),
                  ),
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.center,
                  child: _buildPreview(p, t),
                ),
              ),
              const SizedBox(height: 14),
              AccentButton(
                label: t('print'),
                icon: _printing
                    ? Icons.hourglass_top_rounded
                    : Icons.print_rounded,
                onPressed: (_printing || _png == null) ? null : _print,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreview(AppPalette p, S t) {
    if (_previewError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: p.danger, size: 36),
          const SizedBox(height: 8),
          Text(
            t('print_failed'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          ),
          TextButton(onPressed: _loadPreview, child: Text(t('retry'))),
        ],
      );
    }
    final png = _png;
    if (png == null) return const AppLoader();
    return FadeSlide(
      key: ValueKey(png.hashCode),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: InteractiveViewer(
            maxScale: 4,
            child: Image.memory(
              png,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperTile extends StatelessWidget {
  const _PaperTile({
    required this.paper,
    required this.selected,
    required this.onTap,
  });

  final PrintPaperChoice paper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            color: selected ? p.fabBorder.withValues(alpha: 0.18) : p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? p.fabBorder : p.stroke,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                paper.icon,
                size: 22,
                color: selected ? p.fabBorder : p.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                paper.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                paper.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  color: p.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
