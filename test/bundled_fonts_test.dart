import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Inter loads from bundled assets with runtime fetching disabled',
      () async {
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final w in const [
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ]) {
      GoogleFonts.inter(fontWeight: w);
    }
    // Throws if any requested variant is missing from the asset bundle.
    await expectLater(GoogleFonts.pendingFonts(), completes);
  });
}
