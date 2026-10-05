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

  /// Compact sticker size so the QR fills the iOS print preview.
  /// (A4 left a tiny blob on a huge white page that looked "empty".)
  static final PdfPageFormat qrLabelFormat = PdfPageFormat(
    70 * PdfPageFormat.mm,
    100 * PdfPageFormat.mm,
    marginAll: 5 * PdfPageFormat.mm,
  );

  static const int _minPdfBytes = 800;

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
    final pageFormat = format ?? qrLabelFormat;
    final bytes = await buildQrLabelPdf(
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

  /// Opens the system print sheet with [bytes] built for [format].
  /// If iOS requests a different paper size, rebuilds for that size so the
  /// preview is never an empty mismatched page.
  static Future<void> layoutQrLabelPdf({
    required Uint8List bytes,
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    final pageFormat = format ?? qrLabelFormat;
    if (bytes.length < _minPdfBytes) {
      throw StateError('QR label PDF too small (${bytes.length} bytes)');
    }
    await Printing.layoutPdf(
      onLayout: (requested) async {
        // Same size → return prepared bytes (fast path).
        if (_samePageSize(requested, pageFormat)) return bytes;
        // Printer/user changed paper → rebuild so iOS does not show a blank page.
        return buildQrLabelPdf(
          title: title,
          subtitle: subtitle,
          qrData: qrData,
          companyName: companyName,
          format: requested,
        );
      },
      name: 'QR-$title',
      format: pageFormat,
      dynamicLayout: false,
      forceCustomPrintPaper: true,
    );
  }

  static bool _samePageSize(PdfPageFormat a, PdfPageFormat b) {
    return (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }

  /// QR label PDF bytes (used for printing and sharing; testable offline).
  /// Cached for the session while [title]/[subtitle]/[qrData]/company match.
  static Future<Uint8List> buildQrLabelPdf({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat? format,
  }) async {
    format ??= qrLabelFormat;
    final company = companyName?.trim() ?? '';
    final key = '$title\x1f$subtitle\x1f$qrData\x1f$company\x1f${format.width}x${format.height}';
    final hit = _labelPdfBytes;
    if (hit != null && _labelPdfKey == key && hit.isNotEmpty) return hit;

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
    if (bytes.length < _minPdfBytes) {
      // Never cache a failed/empty build — that caused blank sheets forever.
      throw StateError('QR label PDF too small (${bytes.length} bytes)');
    }
    _labelPdfKey = key;
    _labelPdfBytes = bytes;
    return bytes;
  }

  /// True when fonts are already decoded (first print after cold start is slow otherwise).
  static bool get fontsReady => _fontCache != null;

  /// Rasterize page 0 to PNG for an on-screen proof the PDF is not empty.
  static Future<Uint8List?> rasterQrLabelPreview(Uint8List pdfBytes) async {
    if (pdfBytes.length < _minPdfBytes) return null;
    try {
      final page = await Printing.raster(pdfBytes, pages: [0], dpi: 140).first;
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
