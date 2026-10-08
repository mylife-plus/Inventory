import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  static const int _minPdfBytes = 800;
  static const int _minPngBytes = 400;
  static const double _rasterDpi = 300;

  /// Bundled Inter TTFs — same family as the UI. Loaded via rootBundle only
  /// (never PdfGoogleFonts / network). Sequential loads avoid a Dart 3.10
  /// Future.wait + SynchronousFuture bug that returned an empty list.
  static Future<({pw.Font regular, pw.Font bold})> _fonts() async {
    final cached = _fontCache;
    if (cached != null) return cached;
    final regularData = await rootBundle.load(
      'assets/google_fonts/Inter-Regular.ttf',
    );
    final boldData = await rootBundle.load(
      'assets/google_fonts/Inter-Bold.ttf',
    );
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
      await _fonts();
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
      final out = sheet
          ? await wrapLabelGridPdf(png, count, target)
          : await wrapLabelImagePdf(png, target);
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
  static const List<int> qrLabelsPerPageOptions = [1, 2, 4, 6, 8, 12];
  static const int qrLabelsPerPageMax = 12;
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

  /// [count] copies of the rasterized label on one [format] page (grid with
  /// light cut lines). Image-only like [wrapLabelImagePdf] — no fonts.
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
    const margin = 8 * PdfPageFormat.mm;
    const gap = 4 * PdfPageFormat.mm;
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
    final bytes = await doc.save();
    _validatePdf(bytes, 'grid');
    return bytes;
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
    final bytes = await doc.save();
    _validatePdf(bytes, 'wrap');
    return bytes;
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

    final fonts = await _fonts();
    final bytes = await _buildQrDoc(
      doc: pw.Document(),
      fonts: fonts,
      format: format,
      qrSize: 52 * PdfPageFormat.mm,
      company: company,
      title: title,
      subtitle: subtitle,
      qrData: qrData,
    );
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
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10),
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
                  style: pw.TextStyle(font: fonts.bold, fontSize: 12),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    subtitle.trim(),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: fonts.regular, fontSize: 10),
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
