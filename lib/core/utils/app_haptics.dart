import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Cross-platform haptics.
///
/// iOS uses Flutter [HapticFeedback] (already premium).
/// Android uses a platform channel with [VibrationEffect] CLICK / HEAVY_CLICK
/// — stock Flutter ticks are nearly silent on many Android devices.
class AppHaptics {
  AppHaptics._();

  static const _channel = MethodChannel('softthrive.inventory/haptics');

  static Future<void> selection() => _play('selection');
  static Future<void> light() => _play('light');
  static Future<void> medium() => _play('medium');
  static Future<void> heavy() => _play('heavy');

  static Future<void> _play(String kind) async {
    if (kIsWeb) return;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('haptic', {'type': kind});
        return;
      } catch (_) {
        // Fall through to Flutter APIs if the channel is unavailable.
      }
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
