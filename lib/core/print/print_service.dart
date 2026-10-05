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
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    // Build the PDF once up front (not inside onLayout) so the system print
    // sheet opens immediately and onLayout can never stall it.
    final bytes = await buildQrLabelPdf(
      title: title,
      subtitle: subtitle,
      qrData: qrData,
      companyName: companyName,
      format: format,
    );

    // System print UI (printers list + Cancel) — Cancel returns to the app.
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'QR-$title',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
    );
  }

  /// QR label PDF bytes (used for printing and sharing; testable offline).
  static Future<Uint8List> buildQrLabelPdf({
    required String title,
    required String subtitle,
    required String qrData,
    String? companyName,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final fonts = await _fonts();
    return _buildQrDoc(
      doc: pw.Document(),
      fonts: fonts,
      format: format,
      qrSize: format.width < 200 ? 110.0 : 160.0,
      company: companyName?.trim() ?? '',
      title: title,
      subtitle: subtitle,
      qrData: qrData,
    );
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

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        theme: pw.ThemeData.withFont(
          base: fonts.regular,
          bold: fonts.bold,
          italic: fonts.regular,
          boldItalic: fonts.bold,
          icons: fonts.regular,
        ),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (company.isNotEmpty) ...[
                pw.Text(
                  company,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 11,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: qrSize,
                height: qrSize,
                drawText: false,
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                ),
              ),
              pw.SizedBox(height: 4),
              if (subtitle.isNotEmpty)
                pw.Text(
                  subtitle,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: fonts.regular, fontSize: 12),
                ),
            ],
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
