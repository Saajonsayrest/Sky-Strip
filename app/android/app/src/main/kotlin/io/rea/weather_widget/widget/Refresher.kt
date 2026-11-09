package io.rea.weather_widget.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.util.Log

/**
 * Brings every widget up to date: finds the place (device location for automatic widgets),
 * downloads the forecast when the saved one is old, and redraws. Call off the main thread.
 */
object Refresher {
    private const val TAG = "Refresher"

    /** A saved forecast younger than this is used as it is. */
    private const val MAX_AGE_S = 30 * 60L

    /** Returns false when a download failed (the caller may retry later). */
    fun refresh(context: Context, only: Set<Int>?, force: Boolean): Boolean {
        val store = WidgetStore(context)
        val all = WideWidget.ids(context).toList()
        val ids = if (only == null) all else all.filter { it in only } + only.filter { it !in all }
        var ok = true

        // Automatic widgets share one device location lookup.
        val needsDevice = ids.any { store.settings(it)?.mode == WidgetStore.LocationMode.AUTOMATIC }
        if (needsDevice) {
            DeviceLocation.find(context, store.devicePlace)?.let { store.devicePlace = it }
        }

        val now = System.currentTimeMillis() / 1000
        val fetched = mutableSetOf<String>()
        for (id in ids) {
            val place = placeFor(store, id) ?: continue
            if (place.key in fetched) continue
            val age = now - (store.forecast(place)?.fetchedAt ?: 0)
            if (!force && age < MAX_AGE_S) continue
            try {
                store.saveForecast(place, Forecast.fetch(place.lat, place.lon))
                fetched += place.key
            } catch (e: Exception) {
                Log.w(TAG, "forecast download failed for ${place.key}", e)
                ok = false
            }
        }
        store.pruneForecasts(all.mapNotNull { placeFor(store, it)?.key }.toSet())

        val manager = AppWidgetManager.getInstance(context)
        val provider = WideWidget()
        ids.forEach { provider.render(context, manager, it) }
        return ok
    }

    fun placeFor(store: WidgetStore, id: Int): WidgetStore.Place? {
        val s = store.settings(id) ?: return null
        return when (s.mode) {
            WidgetStore.LocationMode.AUTOMATIC -> store.devicePlace
            WidgetStore.LocationMode.MANUAL -> s.place
        }
    }
}
