import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// iPad requires a non-zero [ShareParams.sharePositionOrigin] inside the root
/// view; otherwise UIActivityViewController throws PlatformException
/// (origin {{0,0},{0,0}}) and the share sheet never appears.
Rect sharePositionOrigin([BuildContext? context]) {
  if (context != null) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null &&
        box.hasSize &&
        box.size.width > 0 &&
        box.size.height > 0) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.width > 0 && rect.height > 0) return rect;
    }
    final mq = MediaQuery.maybeSizeOf(context);
    if (mq != null && mq.width > 0 && mq.height > 0) {
      return _centered(mq);
    }
  }
  return _centered(_viewLogicalSize());
}

Rect _centered(Size size) {
  final w = size.width > 0 ? size.width : 428.0;
  final h = size.height > 0 ? size.height : 926.0;
  return Rect.fromCenter(
    center: Offset(w / 2, h / 2),
    width: 2,
    height: 2,
  );
}

Size _viewLogicalSize() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return const Size(428, 926);
  final FlutterView view = views.first;
  final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
  return view.physicalSize / dpr;
}

/// Share with a guaranteed non-zero [sharePositionOrigin].
Future<ShareResult> shareWithOrigin(
  ShareParams params, [
  BuildContext? context,
]) {
  final origin = params.sharePositionOrigin;
  final resolved = (origin != null && origin.width > 0 && origin.height > 0)
      ? origin
      : sharePositionOrigin(context);
  return SharePlus.instance.share(
    ShareParams(
      text: params.text,
      subject: params.subject,
      title: params.title,
      previewThumbnail: params.previewThumbnail,
      uri: params.uri,
      files: params.files,
      fileNameOverrides: params.fileNameOverrides,
      downloadFallbackEnabled: params.downloadFallbackEnabled,
      mailToFallbackEnabled: params.mailToFallbackEnabled,
      excludedCupertinoActivities: params.excludedCupertinoActivities,
      sharePositionOrigin: resolved,
    ),
  );
}
