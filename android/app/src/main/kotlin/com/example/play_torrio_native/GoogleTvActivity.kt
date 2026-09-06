package com.example.play_torrio_native

import io.flutter.embedding.android.FlutterActivity
import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.Keep

@Keep
class GoogleTvActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the TV UI in landscape on launch.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
