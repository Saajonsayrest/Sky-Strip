package io.rea.weather_widget.widget

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * The launcher calls this after the user confirms "Add Widget" in the app. The new widget gets the
 * settings the user picked in the app before pinning.
 */
class PinReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val store = WidgetStore(context)
        val settings = store.pending ?: return
        store.save(id, settings)
        store.pending = null
        val done = goAsync()
        Thread {
            try {
                Refresher.refresh(context, setOf(id), force = false)
            } finally {
                done.finish()
            }
        }.start()
    }
}
