package com.softthrive.inventory_app

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.core.content.FileProvider
import java.io.File

class MainActivity : FlutterActivity() {
    private val hapticsChannel = "softthrive.inventory/haptics"
    private val filesChannel = "softthrive.inventory/files"

    /**
     * One task only. A launcher intent that arrives while this activity is not
     * the root of its task (a stale second window, e.g. the app was opened from
     * the installer and the icon was tapped afterwards) is dropped so the icon
     * always brings the existing window forward instead of opening a second one.
     * Real intents (links, shares) are delivered to the single task as usual.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!isTaskRoot &&
            intent.action == Intent.ACTION_MAIN &&
            intent.hasCategory(Intent.CATEGORY_LAUNCHER)
        ) {
            finish()
        }
    }

    /**
     * System Back on the app's first screen: keep the app in its one task and
     * send it to the background (like Android's own launcher apps) instead of
     * destroying the window, so tapping the icon resumes exactly where the
     * user was rather than starting the app again.
     *
     * Below Android 13 Flutter routes a root Back to [popSystemNavigator].
     * On 13+ Flutter unregisters its back callback on the first screen and the
     * system would finish the activity, so a fallback callback is registered
     * for exactly that state.
     */
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    private var rootBackCallback: OnBackInvokedCallback? = null

    override fun setFrameworkHandlesBack(frameworkHandlesBack: Boolean) {
        super.setFrameworkHandlesBack(frameworkHandlesBack)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (frameworkHandlesBack) {
            rootBackCallback?.let { onBackInvokedDispatcher.unregisterOnBackInvokedCallback(it) }
            rootBackCallback = null
        } else if (rootBackCallback == null) {
            val cb = OnBackInvokedCallback { moveTaskToBack(true) }
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                cb,
            )
            rootBackCallback = cb
        }
    }

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, filesChannel)
            .setMethodCallHandler { call, result ->
                if (call.method != "openPdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                val title = call.argument<String>("title") ?: "PDF"
                if (path == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                try {
                    result.success(openPdf(path, title))
                } catch (e: Exception) {
                    result.error("open_pdf", e.message, null)
                }
            }
    }

    /**
     * "Open as PDF": the system chooser with PDF viewers (ACTION_VIEW) plus
     * share targets (ACTION_SEND) as extra choices, so it works even when no
     * PDF viewer is installed. Started without NEW_TASK, so the other app
     * opens on top of ours in the same task: its own Back/X returns here and
     * the app stays a single window.
     */
    private fun openPdf(path: String, title: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        val uri = FileProvider.getUriForFile(this, "$packageName.pdfprovider", file)
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/pdf")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val hasViewer = view.resolveActivity(packageManager) != null
        val chooser = if (hasViewer) {
            Intent.createChooser(view, title).apply {
                putExtra(Intent.EXTRA_INITIAL_INTENTS, arrayOf(send))
            }
        } else {
            Intent.createChooser(send, title)
        }
        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        startActivity(chooser)
        return true
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
