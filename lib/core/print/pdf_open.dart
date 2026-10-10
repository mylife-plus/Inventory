import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _channel = MethodChannel('softthrive.inventory/files');

/// Safe file name: letters, digits, dash, underscore.
String pdfFileName(String base) {
  final clean = base.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  final trimmed = clean.replaceAll(RegExp(r'-+'), '-').replaceAll(
        RegExp(r'^-|-$'),
        '',
      );
  return '${trimmed.isEmpty ? 'document' : trimmed}.pdf';
}

/// "Open as PDF": saves [bytes] to the app cache and opens it in another
/// app. Android: system chooser with PDF viewers + share targets
/// (ACTION_VIEW via FileProvider). iOS: the share sheet (Open in Files /
/// Books / Print …). Whatever opens closes with its own Back / Done / X.
Future<void> openPdfExternally({
  required Uint8List bytes,
  required String name,
  required String chooserTitle,
  BuildContext? context,
}) async {
  // iPad share sheet anchor, taken before any await.
  final origin = sharePositionOrigin(context);
  final dir = Directory('${(await getTemporaryDirectory()).path}/pdfs');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${pdfFileName(name)}');
  await file.writeAsBytes(bytes, flush: true);
  if (!kIsWeb && Platform.isAndroid) {
    final ok = await _channel.invokeMethod<bool>('openPdf', {
      'path': file.path,
      'title': chooserTitle,
    });
    if (ok == true) return;
  }
  await shareWithOrigin(
    ShareParams(
      files: [XFile(file.path, mimeType: 'application/pdf')],
      subject: chooserTitle,
      sharePositionOrigin: origin,
    ),
  );
}
