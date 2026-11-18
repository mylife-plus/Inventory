import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Chrome/web debug: [View.didChangeViewFocus] walks focus with
/// ReadingOrderTraversalPolicy and can assert when the navigator Overlay
/// (`_RenderTheater`) is still `NEEDS-LAYOUT`.
///
/// [WidgetsBinding.handleViewFocusChanged] already catches observer errors
/// and reports them via [FlutterError], so a custom binding cannot suppress
/// the red screen. Filter the known assert instead.
bool isWebUnlaidOutFocusAssert(Object? exception) {
  final msg = exception?.toString() ?? '';
  if (!msg.contains('RenderBox was not laid out') &&
      !msg.contains('NEEDS-LAYOUT') &&
      !msg.contains('hasSize')) {
    return false;
  }
  return msg.contains('_RenderTheater') ||
      msg.contains('renderObject.attached') ||
      msg.contains('ReadingOrderTraversalPolicy') ||
      msg.contains('FocusNode.rect');
}

void installWebFocusAssertFilter() {
  if (!kIsWeb) return;

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (isWebUnlaidOutFocusAssert(details.exception)) {
      debugPrint(
        'Ignored web focus assert (overlay not laid out yet)',
      );
      return;
    }
    previousOnError?.call(details);
  };

  final previousPresent = FlutterError.presentError;
  FlutterError.presentError = (details) {
    if (isWebUnlaidOutFocusAssert(details.exception)) return;
    previousPresent(details);
  };
}
