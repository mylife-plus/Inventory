import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';

/// Thermal-friendly PDF print (58mm / 80mm) for QR labels & receipts.
/// Uses Noto Sans so € / Unicode currency symbols render correctly.
class PrintService {
  static Future<({pw.Font regular, pw.Font bold})> _fonts() async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    return (regular: regular, bold: bold);
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
    required String payload,
    String? companyName,
    String? link,
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final fonts = await _fonts();
    final doc = pw.Document();
    final qrSize = format.width < 200 ? 110.0 : 160.0;
    final company = companyName?.trim() ?? '';
    // Link is encoded in the QR only — never printed as text on the label.
    final qrData = () {
      final l = link?.trim() ?? '';
      if (l.isEmpty) return payload;
      if (l.startsWith('http://') || l.startsWith('https://')) return l;
      return 'https://$l';
    }();

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
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
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 10),
              ],
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: qrSize,
                height: qrSize,
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
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

    // System print UI (printers list + Cancel). A4 avoids custom-paper trap
    // that could leave the user stuck after picking a printer.
    // Prefer layoutPdf over sharePdf so Cancel returns to the app.
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'QR-$title',
      format: PdfPageFormat.a4,
      dynamicLayout: false,
    );
  }

  static Future<void> pickFormatAndPrintQr({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String payload,
    String? companyName,
    String? link,
  }) async {
    await printQrLabel(
      title: title,
      subtitle: subtitle,
      payload: payload,
      companyName: companyName,
      link: link,
    );
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
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
        build: (context) {
          pw.TextStyle body([double size = 8]) =>
              pw.TextStyle(font: fonts.regular, fontSize: size);
          pw.TextStyle bold([double size = 9]) => pw.TextStyle(
                font: fonts.bold,
                fontSize: size,
                fontWeight: pw.FontWeight.bold,
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

    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
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
