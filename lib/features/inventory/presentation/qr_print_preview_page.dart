import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// What the print preview shows / prints (handed over from the QR Label page).
class QrPrintArgs {
  const QrPrintArgs({
    required this.title,
    required this.subtitle,
    required this.qrData,
    required this.company,
  });

  final String title;
  final String subtitle;
  final String qrData;

  /// Shop name on the label ('' = none).
  final String company;
}

/// QR label Print → this full-screen preview: the sheet exactly as it will
/// print, the labels-per-page dropdown, and Print, which opens the system
/// print window.
class QrPrintPreviewPage extends ConsumerStatefulWidget {
  const QrPrintPreviewPage({super.key, required this.args});

  final QrPrintArgs args;

  @override
  ConsumerState<QrPrintPreviewPage> createState() => _QrPrintPreviewPageState();
}

class _QrPrintPreviewPageState extends ConsumerState<QrPrintPreviewPage> {
  int _perPage = 1;
  bool _busy = false;
  Uint8List? _pdf;

  QrPrintArgs get _a => widget.args;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPerPage());
    unawaited(_prepare());
  }

  Future<void> _loadPerPage() async {
    final n = await PrintService.lastQrLabelsPerPage();
    if (mounted && n != _perPage) setState(() => _perPage = n);
  }

  /// Label PDF + PNG are built before Print can open the system window
  /// (cached by content, so this is instant when the QR page warmed it).
  Future<Uint8List> _prepare() async {
    final hit = _pdf;
    if (hit != null) return hit;
    await PrintService.preload();
    final bytes = await PrintService.prepareQrLabelPrintPdf(
      title: _a.title,
      subtitle: _a.subtitle,
      qrData: _a.qrData,
      companyName: _a.company,
    );
    if (mounted) setState(() => _pdf = bytes);
    return bytes;
  }

  void _setPerPage(int n) {
    if (n == _perPage) return;
    AppHaptics.selection();
    setState(() => _perPage = n);
    unawaited(PrintService.saveQrLabelsPerPage(n));
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _prepare();
      if (!mounted) return;
      setState(() => _busy = false);
      debugPrint('QR label print tap: ${bytes.length} bytes, $_perPage/page');
      // OS print window. PNG is rasterized before the sheet opens; onLayout
      // only wraps it (1 label, or a grid of [_perPage] on A4).
      await PrintService.layoutQrLabelPdf(
        bytes: bytes,
        title: _a.title,
        subtitle: _a.subtitle,
        qrData: _a.qrData,
        companyName: _a.company,
        format: PrintService.qrLabelFormat,
        perPage: _perPage,
      );
    } catch (e, st) {
      debugPrint('Print label failed: $e\n$st');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.read(tProvider)('print_failed')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final caption = _perPage > 1
        ? t('labels_on_a4').replaceAll('{n}', '$_perPage')
        : t('one_label_page');
    return Scaffold(
      appBar: AppBar(
        title: Text(t('print_preview_title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t('labels_per_page'),
                          style: TextStyle(
                            color: p.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          caption,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  QrPerPagePicker(
                    value: _perPage,
                    label: t('per_page'),
                    menuTitle: t('labels_per_page'),
                    enabled: !_busy,
                    onChanged: _setPerPage,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: QrSheetPreview(
                    count: _perPage,
                    company: _a.company,
                    title: _a.title,
                    subtitle: _a.subtitle,
                    qrData: _a.qrData,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AccentButton(
                label: t('print_label'),
                icon: (_busy || _pdf == null)
                    ? Icons.hourglass_top_rounded
                    : Icons.print_rounded,
                onPressed: _busy ? null : _print,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sheet of paper showing exactly [count] labels in the same grid the
/// print uses (1 = full sticker page, more = A4 with 8 mm margin, 4 mm gap).
class QrSheetPreview extends StatelessWidget {
  const QrSheetPreview({
    super.key,
    required this.count,
    required this.company,
    required this.title,
    required this.subtitle,
    required this.qrData,
  });

  final int count;
  final String company;
  final String title;
  final String subtitle;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    final single = count <= 1;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final sheet = single
        ? (ios ? PrintService.qrLabelFormat : PdfPageFormat.a6)
        : PdfPageFormat.a4;
    final margin = single ? 0.0 : PrintService.labelSheetMargin;
    final gapPt = PrintService.labelSheetGap;
    final grid = PrintService.qrLabelGrid(
      count,
      sheet.width - margin * 2,
      sheet.height - margin * 2,
      gap: gapPt,
    );
    final text = GoogleFonts.interTextTheme(Theme.of(context).textTheme);
    return AspectRatio(
      aspectRatio: sheet.width / sheet.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: const [
            BoxShadow(color: Color(0x55000000), blurRadius: 12),
          ],
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final scale = box.maxWidth / sheet.width;
            final gap = gapPt * scale;
            final w = grid.labelW * scale;
            final h = grid.labelH * scale;
            final rows = <Widget>[];
            var placed = 0;
            for (var r = 0; r < grid.rows && placed < count; r++) {
              final cells = <Widget>[];
              for (var c = 0; c < grid.cols && placed < count; c++) {
                if (c > 0) cells.add(SizedBox(width: gap));
                cells.add(
                  _MiniLabel(
                    cutLine: !single,
                    width: w,
                    height: h,
                    text: text,
                    company: company,
                    title: title,
                    subtitle: subtitle,
                    qrData: qrData,
                  ),
                );
                placed++;
              }
              if (r > 0) rows.add(SizedBox(height: gap));
              rows.add(
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: cells,
                ),
              );
            }
            return Padding(
              padding: EdgeInsets.all(margin * scale),
              child: Column(
                mainAxisAlignment: single
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: rows,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One label on the page preview, scaled to the cell size. Text uses the
/// same point sizes as the printed label so the preview matches the print.
class _MiniLabel extends StatelessWidget {
  const _MiniLabel({
    this.cutLine = true,
    required this.width,
    required this.height,
    required this.text,
    required this.company,
    required this.title,
    required this.subtitle,
    required this.qrData,
  });

  final bool cutLine;
  final double width;
  final double height;
  final TextTheme text;
  final String company;
  final String title;
  final String subtitle;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    // Laid out once at the real label size (pt) and scaled as a picture, so
    // line breaks are identical to the print at every labels-per-page count.
    final fmt = PrintService.qrLabelFormat;
    final shownTitle = title.trim().isEmpty ? '—' : title.trim();
    TextStyle style(double size, FontWeight w) => text.bodyMedium!.copyWith(
      color: Colors.black,
      fontWeight: w,
      fontSize: size,
      height: 1.15,
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: cutLine
            ? Border.all(color: const Color(0xFFBDBDBD), width: 0.5)
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: fmt.width,
          height: fmt.height,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (company.trim().isNotEmpty) ...[
                  Text(
                    company.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: style(
                      PrintService.labelCompanyFit(company),
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                QrImageView(
                  data: qrData,
                  size: PrintService.labelQrSize,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
                const SizedBox(height: 8),
                Text(
                  shownTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: style(
                    PrintService.labelTitleSize(shownTitle),
                    FontWeight.w700,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: style(
                      PrintService.labelSubtitleSize(subtitle),
                      FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Labels per page" dropdown on the print preview page. Opens a compact
/// menu with the counts in [PrintService.qrLabelsPerPageOptions].
class QrPerPagePicker extends StatelessWidget {
  const QrPerPagePicker({
    super.key,
    required this.value,
    required this.label,
    required this.menuTitle,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final String label;
  final String menuTitle;
  final bool enabled;
  final ValueChanged<int> onChanged;

  Future<void> _open(BuildContext context) async {
    final p = AppPalette.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    AppHaptics.light();
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<int>(
      context: context,
      color: p.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.stroke),
      ),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        overlay.size.height - topLeft.dy,
      ),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 36,
          child: Text(
            menuTitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final n in PrintService.qrLabelsPerPageOptions)
          PopupMenuItem<int>(
            value: n,
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  n == 1
                      ? Icons.crop_portrait_rounded
                      : Icons.grid_view_rounded,
                  size: 18,
                  color: p.textMuted,
                ),
                const SizedBox(width: 24),
                if (n == value)
                  Icon(Icons.check_rounded, size: 20, color: p.fabBorder),
              ],
            ),
          ),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: '$menuTitle: $value',
      child: Pressable(
        onTap: enabled ? () => _open(context) : null,
        enabled: enabled,
        child: Container(
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.stroke),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.1,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 20,
                    color: p.textSecondary,
                  ),
                ],
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
