import 'package:flutter/material.dart';
import 'package:inventory_app/shared/widgets/app_webview_page.dart';

/// Opens [url] in an embedded in-app [AppWebViewPage] (not the system browser).
Future<void> openInAppWebView(
  BuildContext context,
  String url, {
  String? title,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => AppWebViewPage(url: url, title: title),
    ),
  );
}
