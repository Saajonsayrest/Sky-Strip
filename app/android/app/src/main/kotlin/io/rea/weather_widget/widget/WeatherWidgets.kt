package io.rea.weather_widget.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.text.format.DateFormat
import android.util.TypedValue
import android.widget.RemoteViews
import io.rea.weather_widget.R

/**
 * The one resizable weather widget. Draws from the forecast the app or [RefreshWorker] saved, so it
 * never waits for the network. Tapping the diagram cycles the time span for that one widget.
 */
class WideWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        ids.forEach { render(context, manager, it) }
        RefreshWorker.schedule(context)
        RefreshWorker.refreshSoon(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context, manager: AppWidgetManager, id: Int, options: android.os.Bundle,
    ) = render(context, manager, id)

    override fun onDeleted(context: Context, ids: IntArray) {
        val store = WidgetStore(context)
        ids.forEach { store.forget(it) }
    }

    override fun onDisabled(context: Context) {
        if (allIds(context).isEmpty()) RefreshWorker.cancel(context)
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_TOGGLE) {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) {
                val store = WidgetStore(context)
                store.setSpan(id, (store.settings(id)?.span ?: Span.MEDIUM).next)
                render(context, AppWidgetManager.getInstance(context), id)
            }
            return
        }
        super.onReceive(context, intent)
    }

    fun render(context: Context, manager: AppWidgetManager, id: Int) {
        val options = manager.getAppWidgetOptions(id)
        fun opt(key: String, fallback: Float) = options.getInt(key).toFloat().takeIf { it > 0 } ?: fallback
        val minW = opt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, FALLBACK_W)
        val maxW = opt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, minW)
        // Portrait size: narrowest width, tallest height.
        val w = minW
        val h = opt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, FALLBACK_H)
        val density = context.resources.displayMetrics.density
        val scale = Renderer.scaleFor(density, w, h)
        val fonts = Fonts.of(context)
        val store = WidgetStore(context)
        val settings = store.settings(id)
        val place = Refresher.placeFor(store, id)
        val forecast = place?.let { store.forecast(it) }
        val now = System.currentTimeMillis() / 1000
        val look = if (settings != null && place != null) {
            Look(
                fahrenheit = settings.fahrenheit,
                feels = settings.feelsLike,
                span = settings.span,
                place = place.name,
                use24h = DateFormat.is24HourFormat(context),
                alsoOtherUnit = settings.alsoOtherUnit,
                noLocation = settings.mode == WidgetStore.LocationMode.AUTOMATIC && !DeviceLocation.allowed(context),
            )
        } else null

        fun picture(dark: Boolean): Drawn {
            val r = Renderer(scale, density, dark, fonts)
            return when {
                settings == null -> r.message(w, h, "Tap to set up this widget")
                place == null -> r.message(w, h, "Waiting for your location…")
                forecast == null || look == null -> r.message(w, h, "Loading…")
                else -> r.widget(w, h, minW, maxW, forecast, look, now)
            }
        }

        val light = picture(dark = false)
        val dark = picture(dark = true)
        val views = RemoteViews(context.packageName, R.layout.widget_wide)
        views.setImageViewBitmap(R.id.image_light, light.bitmap)
        views.setImageViewBitmap(R.id.image_dark, dark.bitmap)

        // Tap areas follow the drawn layout: left column and place name open the app, the diagram
        // switches the time span.
        if (Build.VERSION.SDK_INT >= 31) {
            views.setViewLayoutWidth(R.id.tap_open, light.graphLeftDp, TypedValue.COMPLEX_UNIT_DIP)
            views.setViewLayoutWidth(R.id.tap_open_end, (w - light.graphRightDp).coerceAtLeast(0f), TypedValue.COMPLEX_UNIT_DIP)
        }

        // Left column and place name: open this widget's settings in the app.
        val open = PendingIntent.getActivity(
            context, id,
            Intent(context, io.rea.weather_widget.MainActivity::class.java)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val toggle = PendingIntent.getBroadcast(
            context, id,
            Intent(context, javaClass).setAction(ACTION_TOGGLE).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        views.setOnClickPendingIntent(R.id.root, open)
        views.setOnClickPendingIntent(R.id.tap_open, open)
        views.setOnClickPendingIntent(R.id.tap_open_end, open)
        views.setOnClickPendingIntent(R.id.tap_toggle, if (look != null && forecast != null) toggle else open)
        manager.updateAppWidget(id, views)
    }

    companion object {
        const val ACTION_TOGGLE = "io.rea.weather_widget.TOGGLE_SPAN"
        private const val FALLBACK_W = 320f
        private const val FALLBACK_H = 110f

        fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, WideWidget::class.java))

        private fun allIds(context: Context) = ids(context)
    }
}
