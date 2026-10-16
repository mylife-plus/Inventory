import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:pdf/pdf.dart';

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

  /// Opens the print preview as a modal bottom sheet (Android and iOS).
  static Future<void> show(BuildContext context, QrPrintArgs args) =>
      showAppSheet<void>(
        context: context,
        heightFactor: 0.92,
        builder: (_) => QrPrintPreviewPage(args: args),
      );

  final QrPrintArgs args;

  @override
  ConsumerState<QrPrintPreviewPage> createState() => _QrPrintPreviewPageState();
}

class _QrPrintPreviewPageState extends ConsumerState<QrPrintPreviewPage> {
  int _perPage = 1;
  bool _busy = false;

  /// The label rendered once (high-DPI PNG, cached by content). The preview
  /// shows this same image in every cell — exactly what prints — so the
  /// grid never lays out or paints QR codes / text per label.
  Uint8List? _png;
  ImageProvider? _image;

  QrPrintArgs get _a => widget.args;

  @override
  void initState() {
    super.initState();
    // Let the page slide in first; then render (cache hit = instant).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPerPage());
      unawaited(_prepareWithRetry());
    });
  }

  /// Render the label for the preview; one retry if the first raster fails
  /// (the cells would otherwise stay empty boxes).
  Future<void> _prepareWithRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _prepare();
        return;
      } catch (e, st) {
        debugPrint('QR label preview raster failed ($attempt): $e\n$st');
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }
    }
  }

  Future<void> _loadPerPage() async {
    final n = await PrintService.lastQrLabelsPerPage();
    if (!mounted) return;
    if (n != _perPage) setState(() => _perPage = n);
    _warmSheet();
  }

  Future<Uint8List> _prepare() async {
    final hit = _png;
    if (hit != null) return hit;
    final png = await PrintService.rasterQrLabelPng(
      title: _a.title,
      subtitle: _a.subtitle,
      qrData: _a.qrData,
      companyName: _a.company,
    );
    if (mounted && _png == null) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final w = (MediaQuery.sizeOf(context).width * dpr).round();
      // Decoded once at screen size, shared by every cell. Decode BEFORE
      // showing it, so the cells never paint as empty boxes while the
      // image is still decoding (seen on iOS, Oct 15).
      final image = ResizeImage(MemoryImage(png), width: w.clamp(200, 1000));
      await precacheImage(image, context);
      if (!mounted || _png != null) return png;
      setState(() {
        _png = png;
        _image = image;
      });
      _warmSheet();
    }
    return png;
  }

  /// Build the print page for the current count in the background so
  /// Print opens the system window straight away.
  void _warmSheet() {
    final png = _png;
    if (png == null) return;
    final n = _perPage;
    unawaited(
      PrintService.labelSheetPdf(
        png,
        n,
        PrintService.labelSheetFormat(n),
      ).then<void>(
        (_) {},
        onError: (Object e) {
          debugPrint('QR sheet warm failed: $e');
        },
      ),
    );
  }

  void _setPerPage(int n) {
    if (n == _perPage) return;
    AppHaptics.selection();
    setState(() => _perPage = n);
    unawaited(PrintService.saveQrLabelsPerPage(n));
    _warmSheet();
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final png = await _prepare();
      final n = _perPage;
      final bytes = await PrintService.labelSheetPdf(
        png,
        n,
        PrintService.labelSheetFormat(n),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      // OS print window. Everything is prebuilt; onLayout only hands the
      // cached page over (1 label, or a grid of [n] on A4).
      await PrintService.layoutQrLabelPdf(
        bytes: bytes,
        title: _a.title,
        subtitle: _a.subtitle,
        qrData: _a.qrData,
        companyName: _a.company,
        format: PrintService.qrLabelFormat,
        perPage: n,
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
    // Client (Oct 13b): a pop-up from the bottom (drag handle, rounded top
    // corners, no X). Dismiss: swipe down, tap outside, Back.
    return SafeArea(
      top: false,
      child: Padding(
        // Client (Oct 13): compact — less padding / spacing, same order.
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textMuted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            AppSheetTitle(
              t('print_preview_title'),
              padding: const EdgeInsets.only(
                top: AppSheetTitle.gapAbove - 8,
                bottom: AppSheetTitle.gapBelow,
              ),
            ),
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
            const SizedBox(height: 10),
            // The sheet sits right under the description and the button
            // right under the sheet (no empty band above / below it).
            Flexible(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1,
                child: RepaintBoundary(
                  child: QrSheetPreview(count: _perPage, image: _image),
                ),
              ),
            ),
            const SizedBox(height: 12),
            AccentButton(
              label: t('print_label'),
              icon: (_busy || _png == null)
                  ? Icons.hourglass_top_rounded
                  : Icons.print_rounded,
              onPressed: _busy ? null : _print,
            ),
          ],
        ),
      ),
    );
  }
}

/// A sheet of paper showing exactly [count] labels in the same grid the
/// print uses (1 = full sticker page, more = A4 with 8 mm margin, 4 mm gap).
/// Every cell shows the same pre-rendered label [image] (null = still
/// rendering: blank cells).
class QrSheetPreview extends StatelessWidget {
  const QrSheetPreview({super.key, required this.count, required this.image});

  final int count;
  final ImageProvider? image;

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
    return AspectRatio(
      aspectRatio: sheet.width / sheet.height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 12)],
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final scale = box.maxWidth / sheet.width;
            final gap = gapPt * scale;
            final cellSize = PrintService.qrLabelCell(
              grid,
              sheet.width - margin * 2,
              sheet.height - margin * 2,
              gap: gapPt,
            );
            // Same geometry as the printed page: cells fill the sheet so
            // margins and gaps are even; the label sits centered inside.
            final w = (single ? grid.labelW : cellSize.w) * scale;
            final h = (single ? grid.labelH : cellSize.h) * scale;
            Widget cell() => Container(
              width: w,
              height: h,
              alignment: Alignment.center,
              decoration: single
                  ? null
                  : BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFBDBDBD),
                        width: 0.5,
                      ),
                    ),
              child: image == null
                  ? null
                  : SizedBox(
                      width: grid.labelW * scale,
                      height: grid.labelH * scale,
                      child: Image(
                        image: image!,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                        gaplessPlayback: true,
                      ),
                    ),
            );
            final rows = <Widget>[];
            var placed = 0;
            for (var r = 0; r < grid.rows && placed < count; r++) {
              final cells = <Widget>[];
              for (var c = 0; c < grid.cols && placed < count; c++) {
                if (c > 0) cells.add(SizedBox(width: gap));
                cells.add(cell());
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
            final page = Padding(
              padding: EdgeInsets.all(margin * scale),
              child: Column(
                mainAxisAlignment: single
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: rows,
              ),
            );
            if (image != null) return page;
            // Still rendering the label: show progress, not empty boxes.
            return Stack(
              fit: StackFit.expand,
              children: [
                page,
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF9E9E9E),
                    ),
                  ),
                ),
              ],
            );
          },
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
