package com.crispstrobe.crisperplayer

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class PlayerWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        updateAll(context)
    }
    companion object {
        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val prefs = context.getSharedPreferences("player_companion", Context.MODE_PRIVATE)
            for (id in manager.getAppWidgetIds(ComponentName(context, PlayerWidget::class.java))) {
                val view = RemoteViews(context.packageName, R.layout.widget_player)
                view.setTextViewText(R.id.widget_title, prefs.getString("title", "CrisperPlayer"))
                view.setTextViewText(R.id.widget_author, prefs.getString("author", "Open the app to add books"))
                val playing = prefs.getBoolean("playing", false)
                view.setTextViewText(R.id.widget_toggle, if (playing) "Pause" else "Play")
                for ((button, action) in listOf(R.id.widget_title to "open", R.id.widget_back to "backward",
                    R.id.widget_toggle to "toggle", R.id.widget_forward to "forward")) {
                    val intent = Intent(context, MainActivity::class.java)
                        .setAction("com.crispstrobe.crisperplayer.WIDGET.$action")
                        .putExtra("companion_action", action)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    val pending = PendingIntent.getActivity(context, action.hashCode(), intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    view.setOnClickPendingIntent(button, pending)
                }
                manager.updateAppWidget(id, view)
            }
        }
    }
}
