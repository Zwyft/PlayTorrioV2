package com.example.play_torrio_native

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pendingExoResult: MethodChannel.Result? = null
    private val exoRequestCode = 7412

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, EXO_CHANNEL)
            .setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
                if (call.method != "openExoPlayer") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingExoResult != null) {
                    result.error("PLAYER_BUSY", "A TV player is already open", null)
                    return@setMethodCallHandler
                }

                val args = call.arguments as? Map<*, *>
                val url = args?.get("url") as? String
                if (url.isNullOrBlank()) {
                    result.error("INVALID_URL", "The stream URL is empty", null)
                    return@setMethodCallHandler
                }

                val intent = Intent(this, ExoPlayerActivity::class.java).apply {
                    putExtra(ExoPlayerActivity.EXTRA_URL, url)
                    putExtra(ExoPlayerActivity.EXTRA_TITLE, args?.get("title") as? String ?: "PlayTorrio")
                    putExtra(ExoPlayerActivity.EXTRA_AUDIO_URL, args?.get("audioUrl") as? String)
                    putExtra(
                        ExoPlayerActivity.EXTRA_START_POSITION_MS,
                        (args?.get("startPositionMs") as? Number)?.toLong() ?: 0L,
                    )
                    val headers = args?.get("headers") as? Map<*, *>
                    val names = ArrayList<String>()
                    val values = ArrayList<String>()
                    headers?.forEach { (name, value) ->
                        if (name is String && value is String) {
                            names.add(name)
                            values.add(value)
                        }
                    }
                    putStringArrayListExtra(ExoPlayerActivity.EXTRA_HEADER_NAMES, names)
                    putStringArrayListExtra(ExoPlayerActivity.EXTRA_HEADER_VALUES, values)
                }
                pendingExoResult = result
                startActivityForResult(intent, exoRequestCode)
            }
    }

    @Deprecated("Deprecated in Android SDK but retained for Android TV compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exoRequestCode) return
        val result = pendingExoResult ?: return
        pendingExoResult = null
        if (resultCode == Activity.RESULT_OK) {
            result.success(
                mapOf(
                    "positionMs" to (data?.getLongExtra(ExoPlayerActivity.EXTRA_POSITION_MS, 0L) ?: 0L),
                    "durationMs" to (data?.getLongExtra(ExoPlayerActivity.EXTRA_DURATION_MS, 0L) ?: 0L),
                ),
            )
        } else {
            result.success(null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(0xFF0B0B12.toInt())

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        window.decorView.postDelayed({ applyImmersiveMode() }, 300)
    }

    private fun applyImmersiveMode() {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                hide(WindowInsets.Type.systemBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                    or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    or View.SYSTEM_UI_FLAG_FULLSCREEN
            )
        }
    }

    companion object {
        private const val EXO_CHANNEL = "com.example.play_torrio_native/tv_player"
    }
}
