import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform haptics. iOS `HapticFeedback` is strong; Android needs
/// VibrationEffect (via platform channel) or the light OS ticks feel absent.
class AppHaptics {
  AppHaptics._();

  static const _channel = MethodChannel('softthrive.inventory/haptics');

  static Future<void> selection() => _play('selection');
  static Future<void> light() => _play('light');
  static Future<void> medium() => _play('medium');
  static Future<void> heavy() => _play('heavy');

  static Future<void> _play(String kind) async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('haptic', {'type': kind});
        return;
      }
    } catch (_) {
      // Fall through to Flutter APIs if the channel is unavailable.
    }
    switch (kind) {
      case 'selection':
        await HapticFeedback.selectionClick();
      case 'light':
        await HapticFeedback.lightImpact();
      case 'medium':
        await HapticFeedback.mediumImpact();
      case 'heavy':
        await HapticFeedback.heavyImpact();
      default:
        await HapticFeedback.selectionClick();
    }
  }
}
