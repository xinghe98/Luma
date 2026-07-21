package com.luma.luma

import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val playerControlsChannel = "com.luma.luma/player_controls"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            playerControlsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(readPlayerControlState())
                "setVolume" -> {
                    val value = call.argument<Double>("value")
                    result.success(value != null && setMediaVolume(value))
                }
                "setBrightness" -> {
                    val value = call.argument<Double>("value")
                    result.success(value != null && setWindowBrightness(value))
                }
                "restoreBrightness" -> {
                    restoreWindowBrightness()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    private fun readPlayerControlState(): Map<String, Any> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val currentVolume = audio.getStreamVolume(AudioManager.STREAM_MUSIC)
        val windowBrightness = window.attributes.screenBrightness
        val systemBrightness = Settings.System.getInt(
            contentResolver,
            Settings.System.SCREEN_BRIGHTNESS,
            128,
        ) / 255.0
        return mapOf(
            "volume" to currentVolume.toDouble() / maxVolume,
            "brightness" to if (windowBrightness >= 0f) {
                windowBrightness.toDouble()
            } else {
                systemBrightness.coerceIn(0.05, 1.0)
            },
            "volumeAvailable" to !audio.isVolumeFixed,
            "brightnessAvailable" to true,
        )
    }

    private fun setMediaVolume(value: Double): Boolean {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.isVolumeFixed) return false
        val maxVolume = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
        val target = (value.coerceIn(0.0, 1.0) * maxVolume).roundToInt()
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
        return true
    }

    private fun setWindowBrightness(value: Double): Boolean {
        val params = window.attributes
        params.screenBrightness = value.coerceIn(0.05, 1.0).toFloat()
        window.attributes = params
        return true
    }

    private fun restoreWindowBrightness() {
        val params = window.attributes
        params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = params
    }
}
