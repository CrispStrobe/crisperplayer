package com.crispstrobe.crisperplayer

import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

/** Effects attach to just_audio's existing session; failures never replace its player. */
class AudioEffectsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var session = 0
    private var equalizer: Equalizer? = null
    private var enhancer: LoudnessEnhancer? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.crispstrobe.crisperplayer/audio-effects")
        channel?.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        release()
        channel?.setMethodCallHandler(null)
        channel = null
    }
    private fun release() {
        try { equalizer?.release() } catch (_: Exception) { }
        try { enhancer?.release() } catch (_: Exception) { }
        equalizer = null
        enhancer = null
        session = 0
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "configure") { result.notImplemented(); return }
        val requestedSession = call.argument<Number>("sessionId")?.toInt() ?: 0
        val gain = call.argument<Number>("boostDb")?.toDouble() ?: 0.0
        val preset = call.argument<String>("equalizer") ?: "off"
        if (!gain.isFinite() || gain < 0 || gain > 12 || preset !in listOf("off", "speech", "warm", "bass-reduction")) {
            result.error("INVALID_EFFECT", "Invalid audio effect", null)
            return
        }
        if (requestedSession <= 0 || (gain == 0.0 && preset == "off")) {
            release()
            result.success(null)
            return
        }
        try {
            if (session != requestedSession) { release(); session = requestedSession }
            if (gain > 0) {
                if (enhancer == null) enhancer = LoudnessEnhancer(session)
                enhancer?.setTargetGain((gain * 100).roundToInt())
                enhancer?.enabled = true
            } else { enhancer?.release(); enhancer = null }
            if (preset != "off") {
                if (equalizer == null) equalizer = Equalizer(0, session)
                val eq = equalizer!!
                val range = eq.bandLevelRange
                for (index in 0 until eq.numberOfBands.toInt()) {
                    val band = index.toShort()
                    val hz = eq.getCenterFreq(band) / 1000.0
                    val db = when (preset) {
                        "speech" -> when { hz < 250 -> -4.0; hz < 1000 -> -1.0; hz < 5000 -> 3.0; else -> -1.0 }
                        "warm" -> when { hz < 250 -> 3.0; hz < 2000 -> 0.0; else -> -2.0 }
                        "bass-reduction" -> if (hz < 400) -6.0 else 0.0
                        else -> 0.0
                    }
                    eq.setBandLevel(band, (db * 100).roundToInt().coerceIn(range[0].toInt(), range[1].toInt()).toShort())
                }
                eq.enabled = true
            } else { equalizer?.release(); equalizer = null }
            result.success(null)
        } catch (_: Exception) {
            release()
            result.error("EFFECTS_UNAVAILABLE", "Audio effects are unavailable on this device", null)
        }
    }
}
