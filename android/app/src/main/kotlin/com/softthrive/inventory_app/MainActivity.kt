package com.softthrive.inventory_app

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val hapticsChannel = "softthrive.inventory/haptics"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, hapticsChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "haptic") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val type = call.argument<String>("type") ?: "selection"
                performAppHaptic(type)
                result.success(null)
            }
    }

    /**
     * Premium click feel on Android. Stock EFFECT_TICK / Flutter selectionClick
     * are nearly silent on many devices; map selection/light to a real CLICK and
     * use short one-shot pulses as a fallback so taps feel like iOS.
     */
    private fun performAppHaptic(type: String) {
        val vibrator = resolveVibrator()
        if (vibrator != null && vibrator.hasVibrator()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val effect = when (type) {
                    "selection" -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    "light" -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    "medium" -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                    "heavy" -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
                    else -> VibrationEffect.createPredefined(VibrationEffect.EFFECT_CLICK)
                }
                vibrator.vibrate(effect)
            } else {
                val ms: Long
                val amp: Int
                when (type) {
                    "heavy" -> {
                        ms = 40L
                        amp = 255
                    }
                    "medium" -> {
                        ms = 28L
                        amp = 220
                    }
                    "light" -> {
                        ms = 18L
                        amp = 180
                    }
                    else -> {
                        ms = 22L
                        amp = 200
                    }
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator.vibrate(VibrationEffect.createOneShot(ms, amp))
                } else {
                    @Suppress("DEPRECATION")
                    vibrator.vibrate(ms)
                }
            }
        }

        val feedback = when (type) {
            "heavy" -> HapticFeedbackConstants.LONG_PRESS
            "medium" -> HapticFeedbackConstants.KEYBOARD_TAP
            "light" -> HapticFeedbackConstants.KEYBOARD_TAP
            else -> HapticFeedbackConstants.KEYBOARD_TAP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING
        } else {
            @Suppress("DEPRECATION")
            HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
        }
        window?.decorView?.performHapticFeedback(feedback, flags)
    }

    private fun resolveVibrator(): Vibrator? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        }
    }
}
