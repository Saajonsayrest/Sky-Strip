package io.rea.weather_widget.widget

import android.content.Context
import android.graphics.Bitmap
import java.io.ByteArrayOutputStream
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max

/** Made-up forecast for the app's tour picture: a sunny morning, a warm peak, rain at night. */
object Sample {
    fun forecast(nowUtc: Long): Forecast {
        val start = nowUtc - nowUtc % 3600 - 3 * 3600
        val offset = 8 * 3600 // fixed zone so the picture is the same everywhere
        val hours = (0 until 60).map { i ->
            val t = start + i * 3600L
            val localHour = ((t + offset) / 3600 % 24).toInt()
            val warm = cos((localHour - 14) / 24.0 * 2 * PI)
            val temp = 25 + 7 * warm
            val cloud = when (i) {
                in 0..6 -> 0.0
                in 7..12 -> (i - 6) * 15.0
                in 13..26 -> 90.0
                else -> max(0.0, 90.0 - (i - 26) * 8)
            }
            val rain = when (i) {
                in 15..18 -> 3.0
                in 19..22 -> 1.0
                in 23..24 -> 8.0
                else -> 0.0
            }
            val sun = if (localHour in 7..18) 1.0 else 0.0
            Hour(
                time = t, temp = temp, feelsLike = temp + 2, cloud = cloud, rain = rain, snow = 0.0,
                precipitation = rain, wind = 1.0 + 4 * (1 - warm), isDay = sun > 0, sun = sun,
            )
        }
        return Forecast(offset, nowUtc, hours, emptyList())
    }

    /** PNG of the widget drawn with the sample forecast. */
    fun png(context: Context, wDp: Float, hDp: Float, dark: Boolean, fahrenheit: Boolean): ByteArray {
        val density = context.resources.displayMetrics.density
        val renderer = Renderer(density, density, dark, Fonts.of(context))
        val now = System.currentTimeMillis() / 1000
        val look = Look(fahrenheit, feels = false, span = Span.MEDIUM, place = "Singapore", use24h = true)
        val bmp = renderer.widget(wDp, hDp, wDp, wDp, forecast(now), look, now).bitmap
        return ByteArrayOutputStream().use {
            bmp.compress(Bitmap.CompressFormat.PNG, 100, it)
            it.toByteArray()
        }
    }
}
