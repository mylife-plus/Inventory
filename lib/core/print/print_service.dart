import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

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
    final regularData =
        await rootBundle.load('assets/google_fonts/Inter-Regular.ttf');
    final boldData =
        await rootBundle.load('assets/google_fonts/Inter-Bold.ttf');
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

  static Future<PdfPageFormat?> pickRollFormat(BuildContext context) {
    return showAppSheet<PdfPageFormat>(
      context: context,
      isScrollControlled: false,
      heightFactor: 0.42,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(
                title: ProviderScope.containerOf(context).read(tProvider)('printer_paper_size'),
                subtitle: ProviderScope.containerOf(context).read(tProvider)('printer_paper_sub'),
              ),
              ListTile(
                leading: const Icon(Icons.receipt_long_rounded),
                title: const Text('58 mm (roll)'),
                subtitle: const Text('Common pocket / label printers'),
                onTap: () => Navigator.pop(ctx, PdfPageFormat.roll57),
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: const Text('80 mm (roll)'),
                subtitle: const Text('Standard receipt printers'),
                onTap: () => Navigator.pop(ctx, PdfPageFormat.roll80),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
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

  /// Opens the system print sheet. [onLayout] always returns an image PDF for
  /// the *requested* paper size (PNG is cached; wrap is cheap and deterministic).
  static Future<void> layoutQrLabelPdf({
    required Uint8List bytes,
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    final pageFormat = _finiteFormat(format);
    _validatePdf(bytes, 'prebuilt');

    Future<Uint8List> buildFor(PdfPageFormat requested) async {
      final png = await rasterQrLabelPng(
        title: title,
        subtitle: subtitle,
        qrData: qrData,
        companyName: companyName,
      );
      final out = await wrapLabelImagePdf(png, _finiteFormat(requested));
      debugPrint(
        'QR label print open: ${out.length} bytes '
        '(${_finiteFormat(requested).width.toStringAsFixed(1)}x'
        '${_finiteFormat(requested).height.toStringAsFixed(1)}pt)',
      );
      return out;
    }

    Future<bool> openOnce() {
      return Printing.layoutPdf(
        onLayout: (requested) async {
          try {
            final out = await buildFor(requested);
            _validatePdf(out, 'onLayout');
            return out;
          } catch (e, st) {
            debugPrint('QR label onLayout failed, retrying once: $e\n$st');
            // Bust PNG cache and retry once with a fresh raster.
            _labelPngKey = null;
            _labelPngBytes = null;
            final out = await buildFor(requested);
            _validatePdf(out, 'onLayout-retry');
            return out;
          }
        },
        name: 'QR-$title',
        format: pageFormat,
        dynamicLayout: true,
        forceCustomPrintPaper: true,
      );
    }

    debugPrint('QR label print sheet opening with ${bytes.length} bytes');
    var ok = await openOnce();
    if (!ok) {
      // User cancel returns false — not an error. Only retry on throw.
      return;
    }
  }

  static void _validatePdf(Uint8List bytes, String label) {
    if (bytes.length < _minPdfBytes) {
      throw StateError('QR label PDF too small ($label: ${bytes.length} bytes)');
    }
    if (bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
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
    final page =
        await Printing.raster(vector, pages: const [0], dpi: _rasterDpi).first;
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
      final page =
          await Printing.raster(pdfBytes, pages: const [0], dpi: 140).first;
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

  static Future<void> printReceipt({
    required ShopSettings shop,
    required Sale sale,
    required String Function(num) money,
    PdfPageFormat format = PdfPageFormat.roll80,
  }) async {
    final fonts = await _fonts();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.regular,
          boldItalic: fonts.bold,
          icons: fonts.regular,
        ),
        build: (context) {
          pw.TextStyle body([double size = 8]) =>
              pw.TextStyle(font: fonts.regular, fontSize: size);
          pw.TextStyle bold([double size = 9]) => pw.TextStyle(
                font: fonts.bold,
                fontSize: size,
              );

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
                'Receipt ${sale.id.substring(0, 8).toUpperCase()}',
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
                          '${l.quantity} x ${l.title}',
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
                    pw.Text('Subtotal', style: body()),
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
                      'VAT ${formatQty(shop.vatRate)}%',
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
                  pw.Text('TOTAL', style: bold(11)),
                  pw.Text(money(sale.total), style: bold(11)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'https://tocca.io/r/${sale.id}',
                  width: 72,
                  height: 72,
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Thank you',
                textAlign: pw.TextAlign.center,
                style: body(9),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Receipt-${sale.id.substring(0, 8)}',
    );
  }

  static Future<void> pickFormatAndPrintReceipt({
    required BuildContext context,
    required ShopSettings shop,
    required Sale sale,
    required String Function(num) money,
  }) async {
    await printReceipt(
      shop: shop,
      sale: sale,
      money: money,
      format: PdfPageFormat.a4,
    );
  }
}
