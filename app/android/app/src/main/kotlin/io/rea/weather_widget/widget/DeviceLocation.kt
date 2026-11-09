package io.rea.weather_widget.widget

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.CancellationSignal
import android.util.Log
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Finds where the phone is, without Google Play services. Call off the main thread.
 * Works in the background only when the user picked "Allow all the time".
 */
object DeviceLocation {
    private const val TAG = "DeviceLocation"

    /** A recent fix (under 20 minutes) is reused instead of waking the GPS. */
    private const val FRESH_MS = 20 * 60 * 1000L

    fun allowed(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** [previous]: the last place found; its name is reused when the phone has not moved ~1 km. */
    fun find(context: Context, previous: WidgetStore.Place? = null): WidgetStore.Place? {
        if (!allowed(context)) return null
        val lm = context.getSystemService(LocationManager::class.java) ?: return null
        val location = try {
            lastKnown(lm)?.takeIf { System.currentTimeMillis() - it.time < FRESH_MS } ?: current(lm) ?: lastKnown(lm)
        } catch (e: SecurityException) {
            Log.w(TAG, "no permission", e)
            null
        } ?: return null
        if (previous != null) {
            val moved = FloatArray(1)
            Location.distanceBetween(previous.lat, previous.lon, location.latitude, location.longitude, moved)
            if (moved[0] < SAME_PLACE_M) return previous
        }
        return WidgetStore.Place(placeName(context, location), location.latitude, location.longitude)
    }

    /** Closer than this counts as the same place: no new name lookup, same forecast. */
    private const val SAME_PLACE_M = 1000f

    private fun providers(lm: LocationManager): List<String> {
        val all = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= 31) all += LocationManager.FUSED_PROVIDER
        all += LocationManager.NETWORK_PROVIDER
        all += LocationManager.GPS_PROVIDER
        return all.filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
    }

    @Suppress("MissingPermission")
    private fun lastKnown(lm: LocationManager): Location? =
        providers(lm).mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }

    @Suppress("MissingPermission")
    private fun current(lm: LocationManager): Location? {
        if (Build.VERSION.SDK_INT < 30) return null
        val provider = providers(lm).firstOrNull() ?: return null
        val done = CountDownLatch(1)
        var found: Location? = null
        val cancel = CancellationSignal()
        val executor = Executors.newSingleThreadExecutor()
        if (Build.VERSION.SDK_INT >= 31) {
            // Low power: Wi-Fi and cell towers, no GPS. Town-level is plenty for a forecast.
            val request = android.location.LocationRequest.Builder(0)
                .setQuality(android.location.LocationRequest.QUALITY_LOW_POWER)
                .setDurationMillis(20_000)
                .build()
            lm.getCurrentLocation(provider, request, cancel, executor) { found = it; done.countDown() }
        } else {
            lm.getCurrentLocation(provider, cancel, executor) { found = it; done.countDown() }
        }
        if (!done.await(20, TimeUnit.SECONDS)) cancel.cancel()
        executor.shutdown()
        return found
    }

    /** Town name for the widget's side label, from Android's own geocoder. */
    private fun placeName(context: Context, l: Location): String {
        if (!Geocoder.isPresent()) return "My location"
        return runCatching {
            val geocoder = Geocoder(context, Locale.getDefault())
            val address = if (Build.VERSION.SDK_INT >= 33) {
                val done = CountDownLatch(1)
                var first: android.location.Address? = null
                geocoder.getFromLocation(l.latitude, l.longitude, 1) { list -> first = list.firstOrNull(); done.countDown() }
                done.await(10, TimeUnit.SECONDS)
                first
            } else {
                @Suppress("DEPRECATION")
                geocoder.getFromLocation(l.latitude, l.longitude, 1)?.firstOrNull()
            }
            listOfNotNull(address?.subLocality, address?.locality, address?.subAdminArea, address?.adminArea)
                .firstOrNull { it.isNotBlank() }
        }.getOrNull() ?: "My location"
    }
}
