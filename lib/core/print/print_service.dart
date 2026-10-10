import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:inventory_app/domain/models/models.dart';

/// Thermal-friendly PDF print (58mm / 80mm) for QR labels & receipts.
/// Uses bundled Inter (assets/google_fonts) so € / Unicode render offline.
class PrintService {
  static ({pw.Font regular, pw.Font bold})? _fontCache;
  static String? _labelPdfKey;
  static Uint8List? _labelPdfBytes;
  static String? _labelPngKey;
  static Uint8List? _labelPngBytes;

  /// Compact sticker size so the QR fills the iOS print preview.
  static final PdfPageFormat qrLabelFormat = PdfPageFormat(
    70 * PdfPageFormat.mm,
    100 * PdfPageFormat.mm,
    marginAll: 5 * PdfPageFormat.mm,
  );

  /// Label text sizes (pt), shared by the printed label and the on-screen
  /// preview. Big by default; long texts step down so they always fit on
  /// two lines instead of being cut off.
  static const double labelCompanySize = 16;
  static const double labelTitleMax = 20;
  static const double labelSubtitleMax = 16;
  static const double labelQrSize = 46 * PdfPageFormat.mm;

  /// Text width available on the 70 mm label (10 pt padding each side).
  static double get _labelTextWidth => qrLabelFormat.width - 20;

  static double _fitSize(String text, double max, double min, double em) {
    final n = text.trim().length;
    if (n == 0) return max;
    final fit = 2 * _labelTextWidth / (em * n);
    return fit.clamp(min, max).toDouble();
  }

  static double labelTitleSize(String title) =>
      _fitSize(title, labelTitleMax, 11, 0.62);

  static double labelSubtitleSize(String subtitle) =>
      _fitSize(subtitle, labelSubtitleMax, 9, 0.56);

  static double labelCompanyFit(String company) {
    final n = company.trim().length;
    if (n == 0) return labelCompanySize;
    final fit = _labelTextWidth / (0.62 * n);
    return fit.clamp(9.0, labelCompanySize).toDouble();
  }

  static const int _minPdfBytes = 800;
  static const int _minPngBytes = 400;
  static const double _rasterDpi = 300;

  /// Bundled Inter TTFs — same family as the UI. Loaded via rootBundle only
  /// (never PdfGoogleFonts / network). Sequential loads avoid a Dart 3.10
  /// Future.wait + SynchronousFuture bug that returned an empty list.
  static ({Uint8List regular, Uint8List bold})? _fontBytesCache;

  /// Raw Inter TTF bytes (sent to the PDF worker isolate).
  static Future<({Uint8List regular, Uint8List bold})> _fontBytes() async {
    final cached = _fontBytesCache;
    if (cached != null) return cached;
    final r = await rootBundle.load('assets/google_fonts/Inter-Regular.ttf');
    final b = await rootBundle.load('assets/google_fonts/Inter-Bold.ttf');
    return _fontBytesCache = (
      regular: Uint8List.sublistView(r),
      bold: Uint8List.sublistView(b),
    );
  }

  static Future<({pw.Font regular, pw.Font bold})> _fonts() async {
    final cached = _fontCache;
    if (cached != null) return cached;
    final raw = await _fontBytes();
    final regularData = ByteData.sublistView(raw.regular);
    final boldData = ByteData.sublistView(raw.bold);
    final fonts = (
      regular: pw.Font.ttf(regularData),
      bold: pw.Font.ttf(boldData),
    );
    debugPrint(
      'PrintService fonts ready: '
      'regular=${fonts.regular.fontName} bold=${fonts.bold.fontName} '
      '(${regularData.lengthInBytes}+${boldData.lengthInBytes} bytes)',
    );
    _fontCache = fonts;
    return fonts;
  }

  /// Warm the font cache (e.g. when the label screen opens) so the first
  /// print opens instantly.
  static Future<void> preload() async {
    try {
      await _fontBytes();
    } catch (e, st) {
      // Printing will surface the error to the user; log for device debugging.
      debugPrint('PrintService.preload failed: $e\n$st');
    }
  }

  static Future<void> printQrLabel({
    required String title,
    required String subtitle,

    /// Exact QR content (see `QrPayload.labelData`) — same as the preview.
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    final pageFormat = _finiteFormat(format);
    final bytes = await prepareQrLabelPrintPdf(
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: companyName,
      format: pageFormat,
    );
    await layoutQrLabelPdf(
      bytes: bytes,
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: companyName,
      format: pageFormat,
    );
  }

  /// Build a print-ready PDF: vector label → high-DPI PNG → full-bleed image page.
  /// Image pages do not go blank on iOS from font/paper-size mismatches.
  static Future<Uint8List> prepareQrLabelPrintPdf({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    final pageFormat = _finiteFormat(format);
    try {
      final png = await rasterQrLabelPng(
        title: title,
        subtitle: subtitle,
        qrData: qrData,
        companyName: companyName,
      );
      return wrapLabelImagePdf(png, pageFormat);
    } catch (e, st) {
      // Unit tests / rare host failures: still return a valid vector PDF.
      debugPrint('QR label raster unavailable, vector fallback: $e\n$st');
      return buildQrLabelPdf(
        title: title,
        subtitle: subtitle,
        qrData: qrData,
        companyName: companyName,
        format: pageFormat,
      );
    }
  }

  /// Opens the system print sheet.
  ///
  /// Critical: [onLayout] must NEVER call [Printing.raster] / nested print
  /// channels — on Android that deadlocks the system print dialog so it never
  /// finishes loading and the user cannot leave (no working back/X).
  /// Rasterize up front; [onLayout] only wraps the cached PNG for the
  /// requested paper size (fast, deterministic).
  /// The label sheet exactly as Print lays it out ([perPage] labels; 1 =
  /// single sticker page: A6 on Android, 70×100 mm on iOS), for "Open as
  /// PDF".
  static Future<Uint8List> qrLabelSheetPdf({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    int perPage = 1,
  }) async {
    final int count = perPage.clamp(1, qrLabelsPerPageMax);
    final png = await rasterQrLabelPng(
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: companyName,
    );
    final bool android = !kIsWeb && Platform.isAndroid;
    if (count > 1) return wrapLabelGridPdf(png, count, PdfPageFormat.a4);
    return wrapLabelImagePdf(
      png,
      android ? PdfPageFormat.a6 : _finiteFormat(qrLabelFormat),
    );
  }

  static Future<void> layoutQrLabelPdf({
    required Uint8List bytes,
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,

    /// How many copies of the label to lay out on one page (grid). 1 keeps
    /// the single-sticker page (A6 on Android, 70×100 mm on iOS).
    int perPage = 1,
  }) async {
    _validatePdf(bytes, 'prebuilt');
    final int count = perPage.clamp(1, qrLabelsPerPageMax);

    // Finish raster BEFORE opening the system UI.
    final png = await rasterQrLabelPng(
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: companyName,
    );

    // Android PrintManager maps unknown sizes to UNKNOWN_PORTRAIT and some
    // OEM print UIs then omit a reliable cancel/back. Use ISO A6 (predefined)
    // so the system dialog always has a normal dismiss control. iOS keeps the
    // compact sticker size + forceCustomPrintPaper.
    // Several labels per page always go on a predefined A4 sheet (both
    // platforms), so the system dialog keeps its normal paper handling.
    final bool android = !kIsWeb && Platform.isAndroid;
    final bool sheet = count > 1;
    final pageFormat = sheet
        ? PdfPageFormat.a4
        : (android ? PdfPageFormat.a6 : _finiteFormat(format));

    Future<Uint8List> wrapOnly(PdfPageFormat requested) async {
      final target = _finiteFormat(android ? pageFormat : requested);
      final out = await labelSheetPdf(png, count, target);
      debugPrint(
        'QR label print open: ${out.length} bytes '
        '(${target.width.toStringAsFixed(1)}x${target.height.toStringAsFixed(1)}pt'
        ', $count/page${android ? ', android' : ''})',
      );
      _validatePdf(out, 'onLayout');
      return out;
    }

    debugPrint(
      'QR label print sheet opening with ${bytes.length} bytes '
      '(png ${png.length}, format '
      '${pageFormat.width.toStringAsFixed(0)}x${pageFormat.height.toStringAsFixed(0)})',
    );

    await Printing.layoutPdf(
      onLayout: (requested) async {
        try {
          return await wrapOnly(requested);
        } catch (e, st) {
          debugPrint('QR label onLayout wrap failed, using prebuilt: $e\n$st');
          // Last resort: return already-validated bytes (never re-raster here).
          return bytes;
        }
      },
      name: 'QR-$title',
      format: pageFormat,
      // Android: false avoids repeated onLayout while the dialog is open.
      dynamicLayout: !android,
      // iOS: the compact sticker needs the custom paper; an A4 sheet does not.
      forceCustomPrintPaper: !android && !sheet,
    );
  }

  /// Choices for "labels per page" on the QR label screen.
  /// Every option fills complete rows on A4 (client, Oct 10): 1, 1×2, 2×2,
  /// 2×3, 3×3, 3×4, 4×4, 4×5, 5×5. (8 used to print 3×3 with 2 in the
  /// last row, so it became 9.)
  static const List<int> qrLabelsPerPageOptions = [
    1, 2, 4, 6, 9, 12, 16, 20, 25, //
  ];
  static const int qrLabelsPerPageMax = 25;

  /// A4 label sheet: outer margin and gap between labels (print + preview).
  static const double labelSheetMargin = 8 * PdfPageFormat.mm;
  static const double labelSheetGap = 4 * PdfPageFormat.mm;
  static const String _qrPerPagePrefKey = 'qr_labels_per_page';

  static Future<int> lastQrLabelsPerPage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_qrPerPagePrefKey) ?? 1;
      return qrLabelsPerPageOptions.contains(v) ? v : 1;
    } catch (_) {
      return 1;
    }
  }

  static Future<void> saveQrLabelsPerPage(int n) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_qrPerPagePrefKey, n);
    } catch (e) {
      debugPrint('Saving labels per page failed: $e');
    }
  }

  /// Columns × rows that give the largest label for [count] labels in the
  /// [width]×[height] area (label aspect 70:100, [gap] between cells).
  static ({int cols, int rows, double labelW, double labelH}) qrLabelGrid(
    int count,
    double width,
    double height, {
    double gap = 4 * PdfPageFormat.mm,
  }) {
    final n = count < 1 ? 1 : count;
    final aspectW = qrLabelFormat.width;
    final aspectH = qrLabelFormat.height;
    var best = (cols: 1, rows: n, labelW: 0.0, labelH: 0.0);
    var bestScale = -1.0;
    for (var cols = 1; cols <= n; cols++) {
      final rows = (n + cols - 1) ~/ cols;
      final cellW = (width - gap * (cols - 1)) / cols;
      final cellH = (height - gap * (rows - 1)) / rows;
      if (cellW <= 0 || cellH <= 0) continue;
      final scale = (cellW / aspectW) < (cellH / aspectH)
          ? cellW / aspectW
          : cellH / aspectH;
      if (scale > bestScale + 1e-9) {
        bestScale = scale;
        best = (
          cols: cols,
          rows: rows,
          labelW: aspectW * scale,
          labelH: aspectH * scale,
        );
      }
    }
    return best;
  }

  static final Map<String, Uint8List> _sheetCache = {};

  /// The print page for [count] labels of [png] on [format], cached so the
  /// print preview can build it ahead of time and the print window opens
  /// with it instantly. Built off the UI thread.
  static Future<Uint8List> labelSheetPdf(
    Uint8List png,
    int count,
    PdfPageFormat format,
  ) async {
    final f = _finiteFormat(format);
    final key =
        '${identityHashCode(png)}:${png.length}:$count:${f.width}x${f.height}';
    final hit = _sheetCache[key];
    if (hit != null) return hit;
    final out = count > 1
        ? await wrapLabelGridPdf(png, count, f)
        : await wrapLabelImagePdf(png, f);
    if (_sheetCache.length > 12) _sheetCache.clear();
    return _sheetCache[key] = out;
  }

  /// Page format Print uses for [count] labels (A4 grid, or the single
  /// sticker page: A6 on Android, 70×100 mm on iOS).
  static PdfPageFormat labelSheetFormat(int count) {
    if (count > 1) return PdfPageFormat.a4;
    final bool android = !kIsWeb && Platform.isAndroid;
    return android ? PdfPageFormat.a6 : _finiteFormat(qrLabelFormat);
  }

  /// [count] copies of the rasterized label on one [format] page (grid with
  /// light cut lines). Image-only like [wrapLabelImagePdf] — no fonts.
  /// Encoded in a worker isolate (PNG decode + PDF save are pure Dart).
  static Future<Uint8List> wrapLabelGridPdf(
    Uint8List png,
    int count,
    PdfPageFormat format,
  ) async {
    if (count <= 1) return wrapLabelImagePdf(png, format);
    if (png.length < _minPngBytes) {
      throw StateError('Cannot wrap tiny PNG (${png.length} bytes)');
    }
    final pageFormat = _finiteFormat(format);
    final bytes = await compute(_gridPdfWorker, (
      png: png,
      count: count,
      w: pageFormat.width,
      h: pageFormat.height,
    ));
    _validatePdf(bytes, 'grid');
    return bytes;
  }

  static Future<Uint8List> _gridPdf(
    Uint8List png,
    int count,
    PdfPageFormat pageFormat,
  ) async {
    const margin = labelSheetMargin;
    const gap = labelSheetGap;
    final grid = qrLabelGrid(
      count,
      pageFormat.width - margin * 2,
      pageFormat.height - margin * 2,
      gap: gap,
    );
    final image = pw.MemoryImage(png);
    pw.Widget cell() => pw.Container(
      width: grid.labelW,
      height: grid.labelH,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
      ),
      child: pw.Image(image, fit: pw.BoxFit.contain),
    );
    final rows = <pw.Widget>[];
    var placed = 0;
    for (var r = 0; r < grid.rows && placed < count; r++) {
      final cells = <pw.Widget>[];
      for (var c = 0; c < grid.cols && placed < count; c++) {
        if (c > 0) cells.add(pw.SizedBox(width: gap));
        cells.add(cell());
        placed++;
      }
      if (r > 0) rows.add(pw.SizedBox(height: gap));
      rows.add(
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: cells),
      );
    }
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: rows,
        ),
      ),
    );
    return doc.save();
  }

  static void _validatePdf(Uint8List bytes, String label) {
    if (bytes.length < _minPdfBytes) {
      throw StateError(
        'QR label PDF too small ($label: ${bytes.length} bytes)',
      );
    }
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('QR label PDF missing header ($label)');
    }
  }

  static PdfPageFormat _finiteFormat(PdfPageFormat? format) {
    final f = format ?? qrLabelFormat;
    if (f.width.isFinite && f.height.isFinite && f.width > 0 && f.height > 0) {
      return f;
    }
    return qrLabelFormat;
  }

  /// High-DPI PNG of the label (cached per content). Uses Printing.raster.
  static Future<Uint8List> rasterQrLabelPng({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
  }) async {
    final company = companyName?.trim() ?? '';
    final key = '$title\x1f$subtitle\x1f$qrData\x1f$company';
    final hit = _labelPngBytes;
    if (hit != null && _labelPngKey == key && hit.length >= _minPngBytes) {
      return hit;
    }

    final vector = await buildQrLabelPdf(
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: company,
      format: qrLabelFormat,
    );
    final page = await Printing.raster(
      vector,
      pages: const [0],
      dpi: _rasterDpi,
    ).first;
    final png = await page.toPng();
    if (png.length < _minPngBytes) {
      throw StateError('QR label PNG too small (${png.length} bytes)');
    }
    _labelPngKey = key;
    _labelPngBytes = png;
    return png;
  }

  /// Wrap a PNG as a single full-bleed PDF page for [format].
  /// No fonts — immune to Type1/Courier and paper-size blank pages.
  static Future<Uint8List> wrapLabelImagePdf(
    Uint8List png,
    PdfPageFormat format,
  ) async {
    if (png.length < _minPngBytes) {
      throw StateError('Cannot wrap tiny PNG (${png.length} bytes)');
    }
    final pageFormat = _finiteFormat(format);
    final bytes = await compute(_imagePdfWorker, (
      png: png,
      count: 1,
      w: pageFormat.width,
      h: pageFormat.height,
    ));
    _validatePdf(bytes, 'wrap');
    return bytes;
  }

  static Future<Uint8List> _imagePdf(
    Uint8List png,
    PdfPageFormat pageFormat,
  ) async {
    final doc = pw.Document();
    final image = pw.MemoryImage(png);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.zero,
        build: (_) {
          return pw.Container(
            width: pageFormat.width,
            height: pageFormat.height,
            color: PdfColors.white,
            alignment: pw.Alignment.center,
            child: pw.Image(image, fit: pw.BoxFit.contain),
          );
        },
      ),
    );
    return doc.save();
  }

  /// Vector QR label PDF bytes (source art before raster). Cached per content+format.
  static Future<Uint8List> buildQrLabelPdf({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    format = _finiteFormat(format);
    final company = companyName?.trim() ?? '';
    final key =
        '$title\x1f$subtitle\x1f$qrData\x1f$company\x1f${format.width}x${format.height}';
    final hit = _labelPdfBytes;
    if (hit != null && _labelPdfKey == key && hit.length >= _minPdfBytes) {
      return hit;
    }

    final fonts = await _fontBytes();
    // Font subsetting + PDF encoding are pure Dart: worker isolate.
    final bytes = await compute(_qrDocWorker, (
      regular: fonts.regular,
      bold: fonts.bold,
      w: format.width,
      h: format.height,
      company: company,
      title: title,
      subtitle: subtitle,
      qrData: qrData,
    ));
    _validatePdf(bytes, 'vector');
    _labelPdfKey = key;
    _labelPdfBytes = bytes;
    // Content changed → PNG cache is stale.
    if (_labelPngKey != '$title\x1f$subtitle\x1f$qrData\x1f$company') {
      _labelPngKey = null;
      _labelPngBytes = null;
    }
    return bytes;
  }

  /// True when fonts are already decoded.
  static bool get fontsReady => _fontCache != null;

  /// @nodoc kept for callers; prefer [rasterQrLabelPng].
  static Future<Uint8List?> rasterQrLabelPreview(Uint8List pdfBytes) async {
    if (pdfBytes.length < _minPdfBytes) return null;
    try {
      final page = await Printing.raster(
        pdfBytes,
        pages: const [0],
        dpi: 140,
      ).first;
      return page.toPng();
    } catch (e, st) {
      debugPrint('QR label raster failed: $e\n$st');
      return null;
    }
  }

  static Future<Uint8List> _buildQrDoc({
    required pw.Document doc,
    required ({pw.Font regular, pw.Font bold}) fonts,
    required PdfPageFormat format,
    required double qrSize,
    required String company,
    required String title,
    required String subtitle,
    required String qrData,
  }) async {
    // Finite page size only — infinity (roll*) breaks some iOS print previews.
    final pageFormat = (format.width.isFinite && format.height.isFinite)
        ? format
        : qrLabelFormat;
    final safeTitle = title.trim().isEmpty ? '—' : title.trim();
    final safeQr = qrData.trim().isEmpty ? 'empty' : qrData;
    // Fill most of the sticker; keep room for text under the QR.
    final maxQr = (pageFormat.width - 24).clamp(80.0, 220.0);
    final fittedQr = qrSize.clamp(80.0, maxQr);

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(10),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.regular,
          boldItalic: fonts.bold,
          icons: fonts.regular,
        ),
        build: (context) {
          return pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (company.trim().isNotEmpty) ...[
                  pw.Text(
                    company.trim(),
                    textAlign: pw.TextAlign.center,
                    maxLines: 1,
                    style: pw.TextStyle(
                      font: fonts.bold,
                      fontSize: labelCompanyFit(company),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                ],
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: safeQr,
                  width: fittedQr,
                  height: fittedQr,
                  drawText: false,
                  color: PdfColors.black,
                  backgroundColor: PdfColors.white,
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  safeTitle,
                  textAlign: pw.TextAlign.center,
                  maxLines: 2,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: labelTitleSize(safeTitle),
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    subtitle.trim(),
                    textAlign: pw.TextAlign.center,
                    maxLines: 2,
                    style: pw.TextStyle(
                      font: fonts.regular,
                      fontSize: labelSubtitleSize(subtitle),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    return doc.save();
  }

  /// Receipt paper sizes offered on the print window. Roll widths are
  /// continuous (infinite height); the page grows to fit the receipt.
  static const String receiptPaperA4 = 'a4';
  static const String receiptPaperRoll80 = 'roll80';
  static const String receiptPaperRoll58 = 'roll57';
  static const String _receiptPaperPrefKey = 'receipt_paper';

  static PdfPageFormat receiptFormatFor(String id) => switch (id) {
    receiptPaperRoll80 => PdfPageFormat.roll80,
    receiptPaperRoll58 => PdfPageFormat.roll57,
    _ => PdfPageFormat.a4,
  };

  static Future<String> lastReceiptPaper() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_receiptPaperPrefKey) ?? receiptPaperA4;
    } catch (_) {
      return receiptPaperA4;
    }
  }

  static Future<void> saveReceiptPaper(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_receiptPaperPrefKey, id);
    } catch (e) {
      debugPrint('Saving receipt paper failed: $e');
    }
  }

  /// Builds the receipt PDF. Roll formats come back with a finite page height
  /// fitted to the content (see [receiptPdfFormat]). The QR is only drawn when
  /// the shop has a QR-Link ([ShopSettings.receiptQrData]).
  static Future<({Uint8List bytes, PdfPageFormat format})> buildReceiptPdf({
    required ShopSettings shop,
    required Sale sale,
    required String Function(num) money,
    PdfPageFormat format = PdfPageFormat.roll80,

    /// App translations (same labels as the on-screen receipt). English
    /// fallbacks when omitted (tests).
    String Function(String key)? t,

    /// Friendly localized sale date/time (same as the receipts list). Falls
    /// back to the plain timestamp when omitted (tests).
    String? dateText,
  }) async {
    final fonts = await _fonts();
    String label(String key, String fallback) {
      final v = t?.call(key);
      return (v == null || v.isEmpty || v == key) ? fallback : v;
    }

    final roll = !format.height.isFinite;
    final qrData = shop.receiptQrData;
    // Thermal rolls need small type; A4 gets readable sizes.
    final scale = roll ? 1.0 : 1.35;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: roll
            ? const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 48),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.regular,
          boldItalic: fonts.bold,
          icons: fonts.regular,
        ),
        build: (context) {
          pw.TextStyle body([double size = 8]) =>
              pw.TextStyle(font: fonts.regular, fontSize: size * scale);
          pw.TextStyle bold([double size = 9]) =>
              pw.TextStyle(font: fonts.bold, fontSize: size * scale);

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                shop.companyName,
                textAlign: pw.TextAlign.center,
                style: bold(13),
              ),
              if (shop.street.isNotEmpty)
                pw.Text(
                  shop.street.replaceAll('\u001F', ' '),
                  textAlign: pw.TextAlign.center,
                  style: body(),
                ),
              if ('${shop.zip} ${shop.city}'.trim().isNotEmpty)
                pw.Text(
                  '${shop.zip} ${shop.city}'.trim(),
                  textAlign: pw.TextAlign.center,
                  style: body(),
                ),
              if (shop.phone.isNotEmpty)
                pw.Text(
                  shop.phone,
                  textAlign: pw.TextAlign.center,
                  style: body(),
                ),
              pw.Divider(thickness: 0.6),
              pw.Text(
                '${label('receipt', 'Receipt')} ${sale.id.substring(0, 8).toUpperCase()}',
                style: bold(9),
              ),
              pw.Text(
                dateText ??
                    sale.createdAt.toLocal().toString().split('.').first,
                style: body(7),
              ),
              pw.Divider(thickness: 0.6),
              ...sale.lines.map(
                (l) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${formatQty(l.quantity)} x ${l.title}',
                          style: body(),
                        ),
                      ),
                      pw.SizedBox(width: 4),
                      pw.Text(money(l.lineTotal), style: body()),
                    ],
                  ),
                ),
              ),
              pw.Divider(thickness: 0.6),
              if (shop.vatRate > 0) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(label('subtotal', 'Subtotal'), style: body()),
                    pw.Text(
                      money(
                        VatBreakdown.inclusive(
                          gross: sale.total,
                          rate: shop.vatRate,
                        ).net,
                      ),
                      style: body(),
                    ),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${label('vat', 'VAT')} ${formatQty(shop.vatRate)}%',
                      style: body(),
                    ),
                    pw.Text(
                      money(
                        VatBreakdown.inclusive(
                          gross: sale.total,
                          rate: shop.vatRate,
                        ).vat,
                      ),
                      style: body(),
                    ),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    label('total', 'Total').toUpperCase(),
                    style: bold(11),
                  ),
                  pw.Text(money(sale.total), style: bold(11)),
                ],
              ),
              pw.SizedBox(height: 8),
              if (qrData != null) ...[
                pw.Center(
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: qrData,
                    width: 72 * scale,
                    height: 72 * scale,
                    drawText: false,
                  ),
                ),
                pw.SizedBox(height: 6),
              ],
              pw.Text(
                label('thank_you', 'Thank you'),
                textAlign: pw.TextAlign.center,
                style: body(9),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    // pdf resolves an infinite roll height to the laid-out content height.
    var pageFormat = format;
    final pages = doc.document.pdfPageList.pages;
    if (pages.isNotEmpty) pageFormat = pages.first.pageFormat;
    if (!pageFormat.height.isFinite || pageFormat.height <= 0) {
      pageFormat = PdfPageFormat(format.width, 200 * PdfPageFormat.mm);
    }
    debugPrint(
      'Receipt PDF: ${bytes.length} bytes '
      '(${pageFormat.width.toStringAsFixed(0)}x${pageFormat.height.toStringAsFixed(0)}pt, '
      'qr=${qrData != null})',
    );
    return (bytes: bytes, format: pageFormat);
  }

  /// Opens the system print dialog for a receipt built by [buildReceiptPdf].
  /// Bytes are prebuilt; `onLayout` only returns them (no nested work).
  static Future<void> layoutReceiptPdf({
    required Uint8List bytes,
    required PdfPageFormat format,
    required Sale sale,
  }) async {
    if (bytes.length < _minPdfBytes ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw StateError('Receipt PDF invalid (${bytes.length} bytes)');
    }
    final bool android = !kIsWeb && Platform.isAndroid;
    // Android: hint a predefined media size (custom sizes map to
    // UNKNOWN_PORTRAIT on some OEM print UIs); the system scales the page and
    // thermal print services still offer their roll widths.
    final hint = android
        ? (format.width > PdfPageFormat.a5.width
              ? PdfPageFormat.a4
              : PdfPageFormat.a6)
        : format;
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Receipt-${sale.id.substring(0, 8)}',
      format: hint,
      dynamicLayout: !android,
    );
  }
}

typedef _SheetJob = ({Uint8List png, int count, double w, double h});

Future<Uint8List> _gridPdfWorker(_SheetJob j) =>
    PrintService._gridPdf(j.png, j.count, PdfPageFormat(j.w, j.h));

Future<Uint8List> _imagePdfWorker(_SheetJob j) =>
    PrintService._imagePdf(j.png, PdfPageFormat(j.w, j.h));

Future<Uint8List> _qrDocWorker(
  ({
    Uint8List regular,
    Uint8List bold,
    double w,
    double h,
    String company,
    String title,
    String subtitle,
    String qrData,
  })
  j,
) => PrintService._buildQrDoc(
  doc: pw.Document(),
  fonts: (
    regular: pw.Font.ttf(ByteData.sublistView(j.regular)),
    bold: pw.Font.ttf(ByteData.sublistView(j.bold)),
  ),
  format: PdfPageFormat(j.w, j.h),
  qrSize: PrintService.labelQrSize,
  company: j.company,
  title: j.title,
  subtitle: j.subtitle,
  qrData: j.qrData,
);
