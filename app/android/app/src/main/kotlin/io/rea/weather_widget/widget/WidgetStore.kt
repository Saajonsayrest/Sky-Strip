package io.rea.weather_widget.widget

import android.content.Context
import org.json.JSONObject

/**
 * Settings of each placed widget (one entry per widget id), the last device location and the
 * forecast cache. The Flutter app reads and writes the settings through [WidgetChannel].
 */
class WidgetStore(context: Context) {
    private val prefs = context.getSharedPreferences("weather_widget_store", Context.MODE_PRIVATE)

    data class Place(val name: String, val lat: Double, val lon: Double) {
        fun toJson(): JSONObject = JSONObject().put("name", name).put("lat", lat).put("lon", lon)

        /** Forecast cache key: about 1 km, so close places share one download. */
        val key get() = "%.2f,%.2f".format(java.util.Locale.US, lat, lon)

        companion object {
            fun from(raw: String?): Place? = raw?.let {
                runCatching {
                    val j = JSONObject(it)
                    Place(j.getString("name"), j.getDouble("lat"), j.getDouble("lon"))
                }.getOrNull()
            }
        }
    }

    enum class LocationMode { AUTOMATIC, MANUAL }

    data class Settings(
        val span: Span = Span.MEDIUM,
        val fahrenheit: Boolean = false,
        val feelsLike: Boolean = false,
        val alsoOtherUnit: Boolean = false,
        val mode: LocationMode = LocationMode.MANUAL,
        val place: Place? = null,
    ) {
        fun toJson(): JSONObject = JSONObject()
            .put("span", span.name.lowercase())
            .put("unit", if (fahrenheit) "f" else "c")
            .put("feelsLike", feelsLike)
            .put("alsoOtherUnit", alsoOtherUnit)
            .put("mode", mode.name.lowercase())
            .put("place", place?.toJson() ?: JSONObject.NULL)

        companion object {
            fun from(j: JSONObject) = Settings(
                span = runCatching { Span.valueOf(j.optString("span", "medium").uppercase()) }.getOrDefault(Span.MEDIUM),
                fahrenheit = j.optString("unit", "c") == "f",
                feelsLike = j.optBoolean("feelsLike", false),
                alsoOtherUnit = j.optBoolean("alsoOtherUnit", false),
                mode = if (j.optString("mode") == "automatic") LocationMode.AUTOMATIC else LocationMode.MANUAL,
                place = j.optJSONObject("place")?.let { Place.from(it.toString()) },
            )
        }
    }

    fun settings(widgetId: Int): Settings? =
        prefs.getString("w_$widgetId", null)?.let { runCatching { Settings.from(JSONObject(it)) }.getOrNull() }

    fun save(widgetId: Int, s: Settings) = prefs.edit().putString("w_$widgetId", s.toJson().toString()).apply()

    fun setSpan(widgetId: Int, span: Span) {
        val s = settings(widgetId) ?: Settings()
        save(widgetId, s.copy(span = span))
    }

    fun forget(widgetId: Int) = prefs.edit().remove("w_$widgetId").apply()

    /** Settings chosen before a pin request; given to the new widget when the launcher confirms. */
    var pending: Settings?
        get() = prefs.getString("pending", null)?.let { runCatching { Settings.from(JSONObject(it)) }.getOrNull() }
        set(value) = prefs.edit().apply { if (value == null) remove("pending") else putString("pending", value.toJson().toString()) }.apply()

    /** Last place found from the device location (used by automatic widgets). */
    var devicePlace: Place?
        get() = Place.from(prefs.getString("device_place", null))
        set(value) = prefs.edit().putString("device_place", value?.toJson()?.toString()).apply()

    fun forecastJson(place: Place): String? = prefs.getString("f_${place.key}", null)

    fun forecast(place: Place): Forecast? =
        forecastJson(place)?.let { runCatching { Forecast.parse(it) }.getOrNull() }

    fun saveForecast(place: Place, json: String) = prefs.edit().putString("f_${place.key}", json).apply()

    /** Drops cached forecasts no widget uses any more. */
    fun pruneForecasts(keep: Set<String>) {
        val stale = prefs.all.keys.filter { it.startsWith("f_") && it.removePrefix("f_") !in keep }
        if (stale.isNotEmpty()) prefs.edit().apply { stale.forEach { remove(it) } }.apply()
    }
}
