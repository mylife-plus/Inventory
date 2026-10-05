import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/share/share_origin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QR label PDF builds with Inter (no Courier) for € and ä', () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final logs = <String>[];
    final old = debugPrint;
    debugPrint = (msg, {wrapWidth}) {
      logs.add(msg ?? '');
      old(msg, wrapWidth: wrapWidth);
    };
    addTearDown(() => debugPrint = old);

    // Warm asset cache (SynchronousFuture path).
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
    expect(
      logs.any((l) => l.contains('Courier')),
      isFalse,
      reason: 'PDF must not fall back to Courier: $logs',
    );
    expect(
      logs.any((l) => l.contains('PrintService fonts ready')),
      isTrue,
    );
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
    // Fallback without a sized box still non-zero.
    final fallback = sharePositionOrigin();
    expect(fallback.width, greaterThan(0));
    expect(fallback.height, greaterThan(0));
  });
}
