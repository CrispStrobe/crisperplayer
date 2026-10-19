package com.crispstrobe.crisperplayer

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var companion: MethodChannel? = null
    private var ready = false
    private var pending: String? = null
    private val actions = setOf("open", "play", "pause", "toggle", "backward", "forward")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(AudioEffectsPlugin::class.java)) {
            flutterEngine.plugins.add(AudioEffectsPlugin())
        }
        pending = intent?.getStringExtra("companion_action")?.takeIf { it in actions }
        companion = MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.crispstrobe.crisperplayer/companion").also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> {
                        ready = true
                        val action = pending
                        pending = null
                        result.success(if (action != null && action != "open") mapOf("action" to action) else null)
                    }
                    "update" -> {
                        val data = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                        val prefs = getSharedPreferences("player_companion", MODE_PRIVATE)
                        val title = data["title"] as? String ?: "CrisperPlayer"
                        val author = data["author"] as? String ?: ""
                        val playing = data["playing"] as? Boolean ?: false
                        if (prefs.getString("title", null) != title || prefs.getString("author", null) != author ||
                            prefs.getBoolean("playing", false) != playing) {
                            prefs.edit().putString("title", title).putString("author", author)
                                .putBoolean("playing", playing).apply()
                            PlayerWidget.updateAll(this)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = intent.getStringExtra("companion_action") ?: return
        if (action !in actions || action == "open") return
        if (ready) companion?.invokeMethod("command", mapOf("action" to action))
        else pending = action
    }
}
