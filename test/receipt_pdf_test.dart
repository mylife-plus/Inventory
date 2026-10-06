import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    await rootBundle.load('assets/google_fonts/Inter-Regular.ttf');
  });

  final sale = Sale(
    id: '0123456789abcdef',
    customerName: 'Müller',
    total: 12.5,
    createdAt: DateTime(2026, 10, 6, 12),
    lines: const [
      SaleLine(
        itemId: 'i1',
        title: 'Käse 100g',
        unitPrice: 6.25,
        quantity: 2,
      ),
    ],
  );
  String money(num v) => '€ ${v.toStringAsFixed(2)}';

  test('receipt builds for A4 and both thermal rolls with finite height',
      () async {
    const shop = ShopSettings(companyName: 'Tocca Shop', vatRate: 19);
    for (final id in [
      PrintService.receiptPaperA4,
      PrintService.receiptPaperRoll80,
      PrintService.receiptPaperRoll58,
    ]) {
      final format = PrintService.receiptFormatFor(id);
      final pdf = await PrintService.buildReceiptPdf(
        shop: shop,
        sale: sale,
        money: money,
        format: format,
      );
      expect(utf8.decode(pdf.bytes.sublist(0, 5)), '%PDF-');
      expect(pdf.bytes.length, greaterThan(800));
      expect(pdf.format.height.isFinite, isTrue, reason: id);
      expect(pdf.format.height, greaterThan(0));
      expect(pdf.format.width, closeTo(format.width, 0.01));
    }
  });

  test('receipt QR only when a QR-Link is set', () {
    const none = ShopSettings(companyName: 'A');
    const blank = ShopSettings(companyName: 'A', receiptQrLink: '   ');
    const link = ShopSettings(
      companyName: 'A',
      receiptQrLink: ' https://example.com/shop ',
    );
    expect(none.receiptQrData, isNull);
    expect(blank.receiptQrData, isNull);
    expect(link.receiptQrData, 'https://example.com/shop');
    expect(
      ShopSettings.fromMap(link.toMap()).receiptQrLink,
      link.receiptQrLink,
    );
  });

  test('roll receipt with and without QR both build', () async {
    for (final shop in const [
      ShopSettings(companyName: 'A'),
      ShopSettings(companyName: 'A', receiptQrLink: 'https://example.com'),
    ]) {
      final pdf = await PrintService.buildReceiptPdf(
        shop: shop,
        sale: sale,
        money: money,
        format: PdfPageFormat.roll80,
      );
      expect(pdf.bytes.length, greaterThan(800));
    }
  });
}
