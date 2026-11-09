package io.rea.weather_widget

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.rea.weather_widget.widget.DeviceLocation
import io.rea.weather_widget.widget.PinReceiver
import io.rea.weather_widget.widget.Refresher
import io.rea.weather_widget.widget.Sample
import io.rea.weather_widget.widget.WideWidget
import io.rea.weather_widget.widget.WidgetStore
import org.json.JSONObject
import java.util.concurrent.Executors

/**
 * The app. Also opened by a widget (left side tap: edit that widget's settings).
 * [ConfigureActivity] is the same screen opened by the launcher when a widget is added.
 */
open class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var permissionReply: MethodChannel.Result? = null

    open val launchMode: String? get() = if (widgetIdFrom(intent) != null) "edit" else null

    protected fun widgetIdFrom(i: Intent?): Int? =
        i?.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?.takeIf { it != AppWidgetManager.INVALID_APPWIDGET_ID }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result -> handle(call, result) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // A widget was tapped while the app was open: tell Flutter to show its settings.
        widgetIdFrom(intent)?.let { channel?.invokeMethod("openWidget", it) }
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            val value = runCatching(work)
            main.post {
                value.fold({ result.success(it) }, { result.error("failed", it.message, null) })
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val store = WidgetStore(this)
        when (call.method) {
            "launch" -> result.success(
                mapOf("widgetId" to widgetIdFrom(intent), "mode" to launchMode),
            )
            "widgetIds" -> result.success(WideWidget.ids(this).toList())
            "settings" -> {
                val id = call.argument<Int>("id")!!
                result.success(store.settings(id)?.toJson()?.toString())
            }
            "saveSettings" -> {
                val id = call.argument<Int>("id")!!
                val s = WidgetStore.Settings.from(JSONObject(call.argument<String>("json")!!))
                store.save(id, s)
                background(result) { Refresher.refresh(this, setOf(id), force = true); null }
            }
            "finishConfigure" -> {
                val id = call.argument<Int>("id")!!
                val ok = call.argument<Boolean>("ok") == true
                setResult(
                    if (ok) Activity.RESULT_OK else Activity.RESULT_CANCELED,
                    Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id),
                )
                result.success(null)
                finish()
            }
            "canPin" -> result.success(
                Build.VERSION.SDK_INT >= 26 &&
                    AppWidgetManager.getInstance(this).isRequestPinAppWidgetSupported,
            )
            "pin" -> {
                if (Build.VERSION.SDK_INT < 26) return result.success(false)
                store.pending = WidgetStore.Settings.from(JSONObject(call.argument<String>("json")!!))
                val callback = PendingIntent.getBroadcast(
                    this, 0, Intent(this, PinReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                )
                val ok = AppWidgetManager.getInstance(this)
                    .requestPinAppWidget(ComponentName(this, WideWidget::class.java), null, callback)
                result.success(ok)
            }
            "locationAccess" -> result.success(locationAccess())
            "requestLocation" -> {
                // Step 1: while in use (precise or approximate, the user picks).
                permissionReply = result
                requestPermissions(
                    arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                    REQUEST_FOREGROUND,
                )
            }
            "requestBackgroundLocation" -> {
                // Step 2: "Allow all the time". Android shows its location settings page for this.
                if (Build.VERSION.SDK_INT < 29) return result.success(locationAccess())
                permissionReply = result
                requestPermissions(arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQUEST_BACKGROUND)
            }
            "devicePlace" -> background(result) {
                DeviceLocation.find(this, store.devicePlace)?.also { store.devicePlace = it }?.toJson()?.toString()
                    ?: store.devicePlace?.toJson()?.toString()
            }
            "refreshAll" -> background(result) { Refresher.refresh(this, null, force = false); null }
            "getFlag" -> result.success(
                getSharedPreferences("app_flags", MODE_PRIVATE).getBoolean(call.argument<String>("name"), false),
            )
            "setFlag" -> {
                getSharedPreferences("app_flags", MODE_PRIVATE).edit()
                    .putBoolean(call.argument<String>("name"), call.argument<Boolean>("value") == true).apply()
                result.success(null)
            }
            "share" -> {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, "Sky Strip: the next hours of weather in one picture on your home screen.")
                startActivity(Intent.createChooser(send, null))
                result.success(null)
            }
            "preview" -> background(result) {
                Sample.png(
                    this,
                    (call.argument<Double>("width") ?: 320.0).toFloat(),
                    (call.argument<Double>("height") ?: 100.0).toFloat(),
                    call.argument<Boolean>("dark") == true,
                    call.argument<Boolean>("fahrenheit") == true,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun granted(p: String) = checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED

    /** "none", "foreground" or "background". */
    private fun locationAccess(): String {
        val foreground = granted(Manifest.permission.ACCESS_FINE_LOCATION) ||
            granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        if (!foreground) return "none"
        val background = Build.VERSION.SDK_INT < 29 || granted(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        return if (background) "background" else "foreground"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_FOREGROUND || requestCode == REQUEST_BACKGROUND) {
            permissionReply?.success(locationAccess())
            permissionReply = null
        }
    }

    override fun onResume() {
        super.onResume()
        // Back from the system location page: let Flutter re-read the permission.
        channel?.invokeMethod("resumed", null)
    }

    companion object {
        const val CHANNEL = "io.rea.weather_widget/widgets"
        private const val REQUEST_FOREGROUND = 41
        private const val REQUEST_BACKGROUND = 42
    }
}

/** Opened by the launcher when the widget is added from the widget list. */
class ConfigureActivity : MainActivity() {
    override val launchMode: String? get() = "configure"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        // Leaving without OK must not add the widget.
        setResult(
            Activity.RESULT_CANCELED,
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetIdFrom(intent) ?: AppWidgetManager.INVALID_APPWIDGET_ID),
        )
        super.onCreate(savedInstanceState)
    }
}
