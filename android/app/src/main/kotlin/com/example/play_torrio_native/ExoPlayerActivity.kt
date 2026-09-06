package com.example.play_torrio_native

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView

/**
 * TV playback surface used by the Google TV build.
 *
 * Stremio's Android TV app uses Media3/ExoPlayer internally. Keeping this
 * surface native gives Android TV's D-pad and media keys the same predictable
 * focus and transport behavior as other TV media apps, while the Flutter
 * player remains available for phones and desktop platforms.
 */
@OptIn(UnstableApi::class)
class ExoPlayerActivity : Activity() {
    private lateinit var playerView: PlayerView
    private var player: ExoPlayer? = null
    private var errorView: TextView? = null
    private var lastPositionMs = 0L
    private var finishedNormally = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        applyImmersiveMode()

        val url = intent.getStringExtra(EXTRA_URL)
        if (url.isNullOrBlank()) {
            finishedNormally = true
            setResult(Activity.RESULT_CANCELED)
            super.finish()
            return
        }

        val title = intent.getStringExtra(EXTRA_TITLE).orEmpty()
        val headers = readHeaders()
        setContentView(buildContent(title))
        initialisePlayer(url, title, headers)
    }

    private fun buildContent(title: String): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xFF000000.toInt())
            isFocusable = true
            isFocusableInTouchMode = true
        }

        playerView = PlayerView(this).apply {
            useController = true
            controllerShowTimeoutMs = 4000
            controllerHideOnTouch = true
            setShowSubtitleButton(true)
            setBackgroundColor(0xFF000000.toInt())
            isFocusable = true
            isFocusableInTouchMode = true
            contentDescription = title
        }
        root.addView(
            playerView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )

        errorView = TextView(this).apply {
            setTextColor(0xFFFFFFFF.toInt())
            setTextSize(16f)
            setBackgroundColor(0xCC09090F.toInt())
            gravity = android.view.Gravity.CENTER
            visibility = View.GONE
            isFocusable = true
            isFocusableInTouchMode = true
            setPadding(48, 32, 48, 32)
            setOnClickListener { retryPlayback() }
        }
        root.addView(
            errorView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        playerView.requestFocus()
        return root
    }

    private fun initialisePlayer(
        url: String,
        title: String,
        headers: Map<String, String>,
    ) {
        val httpFactory = DefaultHttpDataSource.Factory()
            .setAllowCrossProtocolRedirects(true)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
            .setDefaultRequestProperties(headers)
        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        val mediaItemBuilder = MediaItem.Builder()
            .setUri(url)
            .setMediaMetadata(
                MediaMetadata.Builder().setTitle(title).build(),
            )
        mimeTypeFor(url)?.let(mediaItemBuilder::setMimeType)

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(5_000, 30_000, 2_500, 1_500)
            .build()

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .build(),
                true,
            )
            .build()
            .also { exo ->
                exo.addListener(object : Player.Listener {
                    override fun onPlayerError(error: PlaybackException) {
                        showError("Playback failed. Press OK to retry.\n${error.errorCodeName}")
                    }

                    override fun onPlaybackStateChanged(playbackState: Int) {
                        if (playbackState == Player.STATE_READY) hideError()
                    }
                })
                playerView.player = exo
        val mediaItem = mediaItemBuilder.build()
                val videoSource = mediaSourceFactory.createMediaSource(mediaItem)
                val audioUrl = intent.getStringExtra(EXTRA_AUDIO_URL)
                if (!audioUrl.isNullOrBlank()) {
                    val audioItem = MediaItem.Builder().setUri(audioUrl).build()
                    exo.setMediaSource(
                        MergingMediaSource(
                            videoSource,
                            mediaSourceFactory.createMediaSource(audioItem),
                        ),
                    )
                } else {
                    exo.setMediaSource(videoSource)
                }
                val startPosition = intent.getLongExtra(EXTRA_START_POSITION_MS, 0L)
                if (startPosition > 0L) exo.seekTo(startPosition)
                exo.prepare()
                exo.playWhenReady = true
            }
    }

    private fun readHeaders(): Map<String, String> {
        val names = intent.getStringArrayListExtra(EXTRA_HEADER_NAMES) ?: return emptyMap()
        val values = intent.getStringArrayListExtra(EXTRA_HEADER_VALUES) ?: return emptyMap()
        return names.mapIndexedNotNull { index, name ->
            values.getOrNull(index)?.let { name to it }
        }.toMap()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (event.action == KeyEvent.ACTION_DOWN) {
            when (event.keyCode) {
                KeyEvent.KEYCODE_BACK -> {
                    if (playerView.isControllerFullyVisible) {
                        playerView.hideController()
                    } else {
                        finishWithPosition()
                    }
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PLAY,
                KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                    togglePlayback()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_PAUSE -> {
                    player?.pause()
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                    seekBy(30_000L)
                    return true
                }
                KeyEvent.KEYCODE_MEDIA_REWIND -> {
                    seekBy(-10_000L)
                    return true
                }
                KeyEvent.KEYCODE_DPAD_CENTER,
                KeyEvent.KEYCODE_ENTER,
                KeyEvent.KEYCODE_NUMPAD_ENTER -> {
                    if (errorView?.visibility == View.VISIBLE) {
                        retryPlayback()
                        return true
                    }
                    if (!playerView.isControllerFullyVisible) {
                        togglePlayback()
                        playerView.showController()
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_LEFT -> {
                    if (!playerView.isControllerFullyVisible) {
                        seekBy(-10_000L)
                        playerView.showController()
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> {
                    if (!playerView.isControllerFullyVisible) {
                        seekBy(10_000L)
                        playerView.showController()
                        return true
                    }
                }
                KeyEvent.KEYCODE_DPAD_UP,
                KeyEvent.KEYCODE_DPAD_DOWN -> {
                    if (!playerView.isControllerFullyVisible) {
                        playerView.showController()
                        return true
                    }
                }
            }
        }
        return super.dispatchKeyEvent(event)
    }

    private fun togglePlayback() {
        player?.let { if (it.isPlaying) it.pause() else it.play() }
    }

    private fun seekBy(deltaMs: Long) {
        player?.let { exo ->
            val duration = exo.duration.takeIf { it > 0 } ?: Long.MAX_VALUE
            exo.seekTo((exo.currentPosition + deltaMs).coerceIn(0L, duration))
        }
    }

    private fun showError(message: String) {
        errorView?.text = message
        errorView?.visibility = View.VISIBLE
        errorView?.requestFocus()
    }

    private fun hideError() {
        errorView?.visibility = View.GONE
    }

    private fun retryPlayback() {
        hideError()
        player?.prepare()
        player?.playWhenReady = true
        playerView.requestFocus()
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode()
    }

    override fun onPause() {
        lastPositionMs = player?.currentPosition ?: lastPositionMs
        super.onPause()
    }

    override fun onDestroy() {
        lastPositionMs = player?.currentPosition ?: lastPositionMs
        if (::playerView.isInitialized) {
            playerView.player = null
        }
        player?.release()
        player = null
        super.onDestroy()
    }

    override fun finish() {
        if (!finishedNormally) finishWithPosition()
        else super.finish()
    }

    private fun finishWithPosition() {
        if (finishedNormally) return
        finishedNormally = true
        lastPositionMs = player?.currentPosition ?: lastPositionMs
        setResult(
            Activity.RESULT_OK,
            Intent().apply {
                putExtra(EXTRA_POSITION_MS, lastPositionMs)
                putExtra(EXTRA_DURATION_MS, player?.duration ?: 0L)
            },
        )
        super.finish()
    }

    private fun applyImmersiveMode() {
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

    private fun mimeTypeFor(url: String): String? {
        val path = url.substringBefore('?').lowercase()
        return when {
            path.endsWith(".m3u8") -> MimeTypes.APPLICATION_M3U8
            path.endsWith(".mpd") -> MimeTypes.APPLICATION_MPD
            path.endsWith(".mp4") -> MimeTypes.VIDEO_MP4
            path.endsWith(".webm") -> MimeTypes.VIDEO_WEBM
            else -> null
        }
    }

    companion object {
        const val EXTRA_URL = "playtorrio.url"
        const val EXTRA_TITLE = "playtorrio.title"
        const val EXTRA_AUDIO_URL = "playtorrio.audio_url"
        const val EXTRA_START_POSITION_MS = "playtorrio.start_position_ms"
        const val EXTRA_HEADER_NAMES = "playtorrio.header_names"
        const val EXTRA_HEADER_VALUES = "playtorrio.header_values"
        const val EXTRA_POSITION_MS = "playtorrio.position_ms"
        const val EXTRA_DURATION_MS = "playtorrio.duration_ms"
    }
}
