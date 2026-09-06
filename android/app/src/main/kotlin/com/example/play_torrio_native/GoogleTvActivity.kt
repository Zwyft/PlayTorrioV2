package com.example.play_torrio_native

import android.os.Bundle
import android.view.WindowManager
import androidx.annotation.Keep

@Keep
class GoogleTvActivity : MainActivity() {
    override fun getInitialRoute(): String = "/google-tv"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the TV UI in landscape on launch.
        requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
