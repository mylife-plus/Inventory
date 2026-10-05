import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:pdf/pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QR label PDF is label-sized, non-empty, no Courier', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      logs.add(msg ?? '');
      old(msg, wrapWidth: wrapWidth);
    };
    addTearDown(() => debugPrint = old);

    await rootBundle.load('assets/google_fonts/Inter-Regular.ttf');
    await rootBundle.load('assets/google_fonts/Inter-Bold.ttf');

    final payload = QrPayload.encodeItem(
      id: 'item-1',
      title: 'Käse äöü',
      price: 3.5,
      unit: 'kg',
    );
    final bytes = await PrintService.buildQrLabelPdf(
      title: 'Käse äöü',
      subtitle: '3,50 € per kg',
      qrData: QrPayload.labelData(
        itemId: 'item-1',
        payload: payload,
        link: 'https://example.com/p',
      ),
      companyName: 'Café München',
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // At least one page object in the PDF.
    expect(asciiCount(bytes, '/Type/Page'), greaterThanOrEqualTo(1));
    expect(asciiCount(bytes, 'stream'), greaterThanOrEqualTo(1));
    expect(asciiCount(bytes, 'Inter'), greaterThanOrEqualTo(1));
    // Label format, not A4 (A4 width ~595pt; label ~198pt).
    expect(PrintService.qrLabelFormat.width, lessThan(250));
    expect(PrintService.qrLabelFormat.height, lessThan(350));
    expect(PrintService.qrLabelFormat.width, closeTo(70 * PdfPageFormat.mm, 0.1));
    expect(logs.any((l) => l.contains('Courier')), isFalse);
  });

  test('QR label PDF still draws QR when title/company empty', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final bytes = await PrintService.buildQrLabelPdf(
      title: '   ',
      subtitle: '',
      qrData: 'inv-only-payload',
      companyName: '',
    );
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('QR label PDF session cache hits for identical content', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final a = await PrintService.buildQrLabelPdf(
      title: 'Cache Me',
      subtitle: '1,00 €',
      qrData: 'cache-key-1',
      companyName: 'Shop',
    );
    final b = await PrintService.buildQrLabelPdf(
      title: 'Cache Me',
      subtitle: '1,00 €',
      qrData: 'cache-key-1',
      companyName: 'Shop',
    );
    expect(identical(a, b), isTrue);
  });

  testWidgets('sharePositionOrigin never returns an empty rect', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: Size(428, 926)),
          child: SizedBox(width: 428, height: 926),
        ),
      ),
    );
    final ctx = tester.element(find.byType(SizedBox));
    final origin = sharePositionOrigin(ctx);
    expect(origin.width, greaterThan(0));
    expect(origin.height, greaterThan(0));
  });
}

int asciiCount(Uint8List bytes, String needle) {
  final src = String.fromCharCodes(bytes);
  return needle.allMatches(src).length;
}
