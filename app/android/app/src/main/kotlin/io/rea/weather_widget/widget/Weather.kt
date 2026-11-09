package io.rea.weather_widget.widget

import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.util.Locale
import kotlin.math.roundToInt

// Kotlin twin of lib/weather.dart and lib/open_meteo.dart. Keep the request URL in sync.

enum class PrecipType { NONE, RAIN, SNOW }

data class Hour(
    val time: Long,
    val temp: Double,
    val feelsLike: Double,
    /** 0..100 % */
    val cloud: Double,
    val rain: Double,
    val snow: Double,
    /** Liquid equivalent in mm for the hour, rain and snow together. */
    val precipitation: Double,
    val wind: Double,
    val isDay: Boolean,
    /** Share of this hour with the sun up, 0..1 (sunrise and sunset hours are partial). */
    val sun: Double,
) {
    fun tempOf(feels: Boolean) = if (feels) feelsLike else temp

    val precipType: PrecipType
        get() = when {
            precipitation <= 0.0 -> PrecipType.NONE
            snow > 0.0 && snow * 0.7 >= rain -> PrecipType.SNOW
            else -> PrecipType.RAIN
        }
}

data class Day(val time: Long, val min: Double, val max: Double, val precipitation: Double)

class Forecast(val utcOffset: Int, val fetchedAt: Long, val hours: List<Hour>, val days: List<Day>) {
    fun local(utcSeconds: Long): LocalDateTime =
        LocalDateTime.ofInstant(Instant.ofEpochSecond(utcSeconds), ZoneOffset.ofTotalSeconds(utcOffset))

    fun from(nowUtc: Long): List<Hour> {
        val start = hours.indexOfLast { it.time <= nowUtc }
        return hours.subList(maxOf(0, start), hours.size)
    }

    companion object {
        fun parse(raw: String): Forecast {
            val json = JSONObject(raw)
            val h = json.getJSONObject("hourly")
            val d = json.getJSONObject("daily")
            fun at(o: JSONObject, key: String, i: Int): Double {
                val arr = o.optJSONArray(key) ?: return 0.0
                return if (i >= arr.length() || arr.isNull(i)) 0.0 else arr.optDouble(i, 0.0)
            }
            fun has(o: JSONObject, key: String) = o.optJSONArray(key) != null

            // Sun up and down times, so each hour gets its share of daylight.
            val rises = d.optJSONArray("sunrise")
            val sets = d.optJSONArray("sunset")
            val sunTimes = if (rises != null && sets != null) {
                (0 until minOf(rises.length(), sets.length())).mapNotNull { i ->
                    if (rises.isNull(i) || sets.isNull(i)) null else rises.getLong(i) to sets.getLong(i)
                }
            } else emptyList()

            val times = h.getJSONArray("time")
            val hours = (0 until times.length()).map { i ->
                val t = times.getLong(i)
                val rain = at(h, "rain", i) + at(h, "showers", i)
                val snow = at(h, "snowfall", i)
                val isDay = at(h, "is_day", i) > 0
                Hour(
                    time = t,
                    temp = at(h, "temperature_2m", i),
                    feelsLike = at(h, "apparent_temperature", i),
                    cloud = at(h, "cloud_cover", i),
                    rain = rain,
                    snow = snow,
                    // Older saved forecasts have no total: snowfall cm is about 0.7 mm of water per cm.
                    precipitation = if (has(h, "precipitation")) at(h, "precipitation", i) else rain + snow * 0.7,
                    wind = at(h, "wind_speed_10m", i),
                    isDay = isDay,
                    sun = sunShare(t, sunTimes) ?: if (isDay) 1.0 else 0.0,
                )
            }
            val dayTimes = d.getJSONArray("time")
            val days = (0 until dayTimes.length()).map { i ->
                Day(
                    time = dayTimes.getLong(i),
                    min = at(d, "temperature_2m_min", i),
                    max = at(d, "temperature_2m_max", i),
                    precipitation = at(d, "precipitation_sum", i),
                )
            }
            return Forecast(
                utcOffset = json.getInt("utc_offset_seconds"),
                fetchedAt = json.optLong("fetched_at", System.currentTimeMillis() / 1000),
                hours = hours,
                days = days,
            )
        }

        /** Part of the hour starting at [t] with the sun up, or null when no sun times cover it. */
        private fun sunShare(t: Long, sunTimes: List<Pair<Long, Long>>): Double? {
            if (sunTimes.isEmpty()) return null
            val end = t + 3600
            if (t < sunTimes.first().first - 86_400 || t > sunTimes.last().second + 86_400) return null
            var up = 0L
            for ((rise, set) in sunTimes) {
                val a = maxOf(t, rise)
                val b = minOf(end, set)
                if (b > a) up += b - a
            }
            return (up / 3600.0).coerceIn(0.0, 1.0)
        }

        /** Same request as `OpenMeteo.forecastUri` in Dart. Returns the JSON stamped with fetched_at. */
        fun fetch(lat: Double, lon: Double): String {
            val url = URL(
                "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=${"%.4f".format(Locale.US, lat)}&longitude=${"%.4f".format(Locale.US, lon)}" +
                    "&hourly=temperature_2m,apparent_temperature,cloud_cover,rain,showers,snowfall,precipitation,wind_speed_10m,is_day" +
                    // Only what the widget draws: the long span on a wide widget shows about 5 days.
                    "&daily=sunrise,sunset" +
                    "&wind_speed_unit=ms&timeformat=unixtime&timezone=auto&forecast_days=6&past_hours=1",
            )
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 15_000
            conn.readTimeout = 15_000
            try {
                if (conn.responseCode != 200) error("forecast HTTP ${conn.responseCode}")
                val body = conn.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(body)
                json.put("fetched_at", System.currentTimeMillis() / 1000)
                return json.toString()
            } finally {
                conn.disconnect()
            }
        }
    }
}

// Beaufort scale, lower bound of each force in m/s (public WMO table).
private val beaufortFrom = doubleArrayOf(0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7)

fun beaufort(ms: Double): Int = beaufortFrom.count { ms >= it }

private val beaufortNames = arrayOf(
    "calm", "light air", "light breeze", "gentle breeze", "moderate breeze", "fresh breeze",
    "strong breeze", "near gale", "gale", "strong gale", "storm", "violent storm", "hurricane",
)

fun windWord(ms: Double): String = beaufortNames[beaufort(ms)]

fun cloudWord(cloudPercent: Double): String {
    val c = cloudPercent / 100
    return when {
        c <= 0.0 -> "clear"
        c <= 0.25 -> "mostly clear"
        c <= 0.5 -> "partly cloudy"
        c <= 0.875 -> "mostly cloudy"
        else -> "overcast"
    }
}

/** Rows of dots for one hour: 0 dry, 1 light, 2 moderate, 3 heavy, 4 violent (rain only). */
fun precipLevel(h: Hour): Int = when (h.precipType) {
    PrecipType.NONE -> 0
    PrecipType.RAIN -> when {
        h.precipitation > 50.0 -> 4
        h.precipitation > 7.6 -> 3
        h.precipitation > 2.5 -> 2
        else -> 1
    }
    PrecipType.SNOW -> when {
        h.precipitation > 2.5 -> 3
        h.precipitation > 1.0 -> 2
        else -> 1
    }
}

fun precipWord(h: Hour): String {
    val level = precipLevel(h)
    return when (h.precipType) {
        PrecipType.NONE -> "dry"
        PrecipType.RAIN -> arrayOf("dry", "light rain", "moderate rain", "heavy rain", "violent rain")[level]
        PrecipType.SNOW -> arrayOf("dry", "light snowfall", "moderate snowfall", "heavy snowfall")[level]
    }
}

// Rounds half away from zero, like Dart's round(), so app and widget show the same number.
fun displayTemp(celsius: Double, fahrenheit: Boolean): Int {
    val v = if (fahrenheit) celsius * 9 / 5 + 32 else celsius
    return if (v < 0) -(-v).roundToInt() else v.roundToInt()
}

fun toUnit(celsius: Double, fahrenheit: Boolean) = if (fahrenheit) celsius * 9 / 5 + 32 else celsius

/** Time span of the diagram, as the width of one hour. Tapping the diagram goes to the next one. */
enum class Span(val hourDp: Float, val labelEvery: Int) {
    SHORT(30f, 3), MEDIUM(13.5f, 6), LONG(4.5f, 24);

    val next get() = entries[(ordinal + 1) % entries.size]
}
