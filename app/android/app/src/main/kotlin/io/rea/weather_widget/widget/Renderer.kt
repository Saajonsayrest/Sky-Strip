package io.rea.weather_widget.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.text.TextPaint
import android.text.TextUtils
import java.time.format.TextStyle
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * Widget colours, the same values as the studied app (user decision 2026-11-09): sky by cloud and
 * daylight, a 15-step temperature scale every 5 °C, blue rain, white snow.
 */
object Palette {
    fun card(dark: Boolean) = if (dark) 0xFF212121.toInt() else 0xFFFFFFFF.toInt()
    fun ink(dark: Boolean) = if (dark) 0xFF8A8A8A.toInt() else 0xFF949494.toInt()

    /** Colour of the "light snow" style word: grey on light cards, white on dark ones. */
    fun snowWord(dark: Boolean) = if (dark) SNOW else ink(dark)

    private const val DAY_CLEAR = 0xFF3BC2FF.toInt()
    private const val DAY_CLOUDY = 0xFFC2C2C2.toInt()
    private const val NIGHT_CLEAR = 0xFF0059B3.toInt()
    private const val NIGHT_CLOUDY = 0xFF6B6B6B.toInt()
    const val RAIN = 0xFF008AF4.toInt()
    const val SNOW = 0xFFFFFFFF.toInt()

    /** [sun] 0 night .. 1 day, [cloud] 0..100 %. */
    fun sky(sun: Double, cloud: Double): Int {
        val c = (cloud / 100).coerceIn(0.0, 1.0).toFloat()
        return mix(mix(NIGHT_CLEAR, NIGHT_CLOUDY, c), mix(DAY_CLEAR, DAY_CLOUDY, c), sun.coerceIn(0.0, 1.0).toFloat())
    }

    private const val RAMP_FROM = -28.0
    private const val RAMP_STEP = 5.0
    private val ramp = intArrayOf(
        0xFFDA00FF.toInt(), 0xFFBF40FF.toInt(), 0xFF8A54FF.toInt(), 0xFF5E6EFF.toInt(), 0xFF337EFF.toInt(),
        0xFF00B0FF.toInt(), 0xFF00BCD4.toInt(), 0xFF00BFA5.toInt(), 0xFF52D400.toInt(), 0xFFEEC800.toInt(),
        0xFFFFA000.toInt(), 0xFFFF6F00.toInt(), 0xFFFF3D3D.toInt(), 0xFFFF3B7C.toInt(), 0xFFFF30C4.toInt(),
    )

    fun temp(celsius: Double): Int {
        val pos = (celsius - RAMP_FROM) / RAMP_STEP
        if (pos <= 0) return ramp.first()
        if (pos >= ramp.size - 1) return ramp.last()
        val i = pos.toInt()
        return mix(ramp[i], ramp[i + 1], (pos - i).toFloat())
    }

    fun mix(a: Int, b: Int, t: Float): Int = Color.argb(
        (Color.alpha(a) + (Color.alpha(b) - Color.alpha(a)) * t).toInt(),
        (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
        (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
        (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt(),
    )
}

/** Outfit (SIL Open Font License), bundled in assets/fonts. */
class Fonts private constructor(val medium: Typeface, val bold: Typeface) {
    companion object {
        @Volatile private var cached: Fonts? = null

        fun of(context: Context): Fonts = cached ?: synchronized(this) {
            cached ?: load(context).also { cached = it }
        }

        private fun load(context: Context): Fonts {
            val path = "fonts/Outfit.ttf"
            return runCatching {
                if (Build.VERSION.SDK_INT >= 26) {
                    fun weight(w: Int) = Typeface.Builder(context.assets, path)
                        .setFontVariationSettings("'wght' $w").build()
                    Fonts(weight(500), weight(700))
                } else {
                    val base = Typeface.createFromAsset(context.assets, path)
                    Fonts(base, Typeface.create(base, Typeface.BOLD))
                }
            }.getOrElse { Fonts(Typeface.DEFAULT, Typeface.DEFAULT_BOLD) }
        }
    }
}

data class Look(
    val fahrenheit: Boolean,
    val feels: Boolean,
    val span: Span,
    val place: String,
    val use24h: Boolean,
    /** Also show the other unit (°F next to °C or the other way round), smaller and faded. */
    val alsoOtherUnit: Boolean = false,
    /** Automatic place without location access: the place name gets a warning mark. */
    val noLocation: Boolean = false,
)

/** Where the tap areas go, in dp from the left edge. */
data class Drawn(val bitmap: Bitmap, val graphLeftDp: Float, val graphRightDp: Float)

/**
 * Draws the whole widget into one bitmap. Sizes are dp, turned into pixels with [scale].
 *
 * Layout, left to right: current conditions column, the hourly diagram, place name turned on its side.
 * The diagram is split into three equal bands: sky on top (with rain dots), the temperature curve in
 * the middle (with high and low bubbles), temperature colour at the bottom (with hour labels and
 * wind arrows). One column per hour.
 */
class Renderer(
    private val scale: Float,
    private val density: Float,
    private val dark: Boolean,
    private val fonts: Fonts,
) {
    private val card = Palette.card(dark)
    private val ink = Palette.ink(dark)

    private fun dp(v: Float) = v * scale
    private fun dp(v: Double) = (v * scale).toFloat()

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }

    private fun textPaint(sizePx: Float, face: Typeface, color: Int) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = sizePx
        typeface = face
        this.color = color
        letterSpacing = -0.04f
    }

    private fun bounds(p: Paint, s: String) = Rect().also { p.getTextBounds(s, 0, s.length, it) }

    private fun start(wDp: Float, hDp: Float): Pair<Bitmap, Canvas> {
        val bmp = Bitmap.createBitmap(max(1, dp(wDp).roundToInt()), max(1, dp(hDp).roundToInt()), Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val radius = min(dp(CORNER), bmp.height / 2f)
        val clip = Path().apply {
            addRoundRect(RectF(0f, 0f, bmp.width.toFloat(), bmp.height.toFloat()), radius, radius, Path.Direction.CW)
        }
        c.clipPath(clip)
        c.drawColor(card)
        return bmp to c
    }

    fun message(wDp: Float, hDp: Float, msg: String): Drawn {
        val (bmp, c) = start(wDp, hDp)
        val p = textPaint(dp(14f), fonts.medium, ink)
        val cut = TextUtils.ellipsize(msg, p, c.width - dp(32f), TextUtils.TruncateAt.END).toString()
        c.drawText(cut, (c.width - p.measureText(cut)) / 2, c.height / 2f - (p.ascent() + p.descent()) / 2, p)
        return Drawn(bmp, 0f, wDp)
    }

    /**
     * A small text label. The text is sized so that the tall-letter box ("d" top to "p" bottom)
     * is exactly [heightPx]; returns its width and a drawer that puts it with its box top at y.
     */
    private inner class BoxText(val text: String, heightPx: Float, face: Typeface, color: Int) {
        private val paint: TextPaint
        private val baseline: Float
        val width: Float
        val height = heightPx

        init {
            val probe = textPaint(heightPx, face, color)
            val box = bounds(probe, "dp").height().toFloat()
            val descent = box - bounds(probe, "d").height()
            val k = heightPx / max(1f, box)
            paint = textPaint(heightPx * k, face, color)
            baseline = (box - descent) * k
            width = paint.measureText(text)
        }

        fun drawRight(c: Canvas, right: Float, top: Float) = c.drawText(text, right - width, top + baseline, paint)
        fun drawLeft(c: Canvas, left: Float, top: Float) = c.drawText(text, left, top + baseline, paint)
    }

    /** Big current temperature with our own degree mark, cropped to its ink like the study notes say. */
    private fun bigTemp(value: Int, color: Int, fahrenheit: Boolean, feels: Boolean, heightPx: Float): Bitmap {
        val size = max(8f, heightPx * 1.2f)
        val p = textPaint(size, fonts.bold, color)
        val digits = value.toString()
        val digitsW = p.measureText(digits)
        val markW = size * 0.8f
        val w = ceil(digitsW + size * 0.08f + markW).toInt() + 2
        val h = ceil(size * 1.3f).toInt()
        val raw = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(raw)
        val base = size
        c.drawText(digits, 0f, base, p)

        // Degree ring, then a small unit letter, both raised to the top of the digits.
        val x0 = digitsW + size * 0.08f
        val capTop = base - bounds(p, "0").height()
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color; style = Paint.Style.STROKE; strokeWidth = size * 0.075f
        }
        val r = size * 0.1f
        c.drawCircle(x0 + r + ring.strokeWidth / 2, capTop + r + ring.strokeWidth / 2, r, ring)
        val unit = textPaint(size * 0.36f, fonts.bold, color)
        val letter = if (fahrenheit) "F" else "C"
        val unitX = x0 + 2 * r + ring.strokeWidth + size * 0.04f
        c.drawText(letter, unitX, capTop + bounds(unit, letter).height(), unit)
        if (feels) {
            // Small wave under the unit: "feels like".
            val wave = Paint(ring).apply { strokeWidth = size * 0.06f; strokeCap = Paint.Cap.ROUND }
            val wy = capTop + size * 0.42f
            val wl = x0 + size * 0.02f
            val ww = size * 0.5f
            c.drawPath(Path().apply {
                moveTo(wl, wy)
                cubicTo(wl + ww * 0.25f, wy - size * 0.08f, wl + ww * 0.25f, wy + size * 0.08f, wl + ww * 0.5f, wy)
                cubicTo(wl + ww * 0.75f, wy - size * 0.08f, wl + ww * 0.75f, wy + size * 0.08f, wl + ww, wy)
            }, wave)
        }
        return cropToInk(raw)
    }

    private fun cropToInk(b: Bitmap): Bitmap {
        val w = b.width
        val h = b.height
        val px = IntArray(w * h)
        b.getPixels(px, 0, w, 0, 0, w, h)
        var top = h; var bottom = -1; var left = w; var right = -1
        for (y in 0 until h) for (x in 0 until w) {
            if (Color.alpha(px[y * w + x]) > 8) {
                if (y < top) top = y
                if (y > bottom) bottom = y
                if (x < left) left = x
                if (x > right) right = x
            }
        }
        if (bottom < 0) return b
        return Bitmap.createBitmap(b, left, top, right - left + 1, bottom - top + 1)
    }

    /** [minWDp]/[maxWDp] are the widget's narrow and wide sizes; hours shown follow their average. */
    fun widget(wDp: Float, hDp: Float, minWDp: Float, maxWDp: Float, f: Forecast, look: Look, nowUtc: Long): Drawn {
        val ahead = f.from(nowUtc)
        val hourDp = look.span.hourDp
        val wanted = max(1, ((((minWDp + maxWDp) / 2) - LABELS_DP) / hourDp).roundToInt())
        val needed = (wanted * 0.2).roundToInt().coerceIn(2, 24)
        if (ahead.size < needed) return message(wDp, hDp, "Open Sky Strip to update")
        val hours = ahead.take(wanted)
        val now = hours.first()

        val (bmp, c) = start(wDp, hDp)
        val H = bmp.height.toFloat()
        val W = bmp.width.toFloat()

        // ---- Left column: rain word, cloud word, big temperature, wind word (right aligned).
        val inner = max(0f, hDp - 16f)
        val unit = inner / 78f
        val smallH = dp(min(SMALL_LABEL_DP, unit * 12f))
        val nowTemp = now.tempOf(look.feels)
        val precipColor = when (now.precipType) {
            PrecipType.RAIN -> Palette.RAIN
            PrecipType.SNOW -> Palette.snowWord(dark)
            PrecipType.NONE -> ink
        }
        val rainText = BoxText(precipWord(now), smallH, fonts.medium, precipColor)
        val cloudText = BoxText(cloudWord(now.cloud), smallH, fonts.medium, Palette.sky(now.sun, now.cloud))
        val windText = BoxText(windWord(now.wind), smallH, fonts.medium, ink)
        val tempSlot = dp(unit * 26f)
        val tempColor = Palette.temp(nowTemp)
        val tempBmp = bigTemp(displayTemp(nowTemp, look.fahrenheit), tempColor, look.fahrenheit, look.feels, dp(BIG_LABEL_DP))
        val tempH = min(dp(BIG_LABEL_DP), tempSlot)
        val tempW = tempBmp.width * tempH / tempBmp.height
        // Optional other unit: half the height, half the opacity, left of the main number.
        val otherBmp = if (look.alsoOtherUnit) {
            bigTemp(displayTemp(nowTemp, !look.fahrenheit), faded(tempColor), !look.fahrenheit, look.feels, dp(BIG_LABEL_DP))
        } else null
        val otherH = tempH / 2
        val otherW = otherBmp?.let { it.width * otherH / it.height + dp(2f) } ?: 0f

        val colInner = maxOf(rainText.width, cloudText.width, windText.width, tempW + otherW)
        val graphLeft = (dp(16f) + colInner + dp(8f)).roundToInt().toFloat()
        val right = graphLeft - dp(8f)
        var y = dp(8f)
        rainText.drawRight(c, right, y)
        y += dp(unit * 16f)
        cloudText.drawRight(c, right, y)
        y += dp(unit * 19f)
        val tempTop = y + (tempSlot - tempH) / 2
        c.drawBitmap(tempBmp, null, RectF(right - tempW, tempTop, right, tempTop + tempH), Paint(Paint.FILTER_BITMAP_FLAG))
        if (otherBmp != null) {
            val oRight = right - tempW - dp(2f)
            val oTop = tempTop + (tempH - otherH) / 2
            c.drawBitmap(otherBmp, null, RectF(oRight - (otherW - dp(2f)), oTop, oRight, oTop + otherH), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        windText.drawRight(c, right, H - dp(8f) - windText.height)

        // ---- Place name on the right edge, turned to read top to bottom.
        val placePaint = textPaint(dp(PLACE_DP), fonts.medium, ink)
        val fm = placePaint.fontMetrics
        val lineH = fm.descent - fm.ascent
        val graphRight = (W - dp(4f) - lineH - dp(4f)).roundToInt().toFloat()
        val placeRoom = H - dp(16f)
        // No location access for an automatic widget: a small crossed-out ring before the name.
        val markW = if (look.noLocation) dp(PLACE_DP) * 1.6f else 0f
        val placeText = TextUtils.ellipsize(look.place, placePaint, placeRoom - markW, TextUtils.TruncateAt.END).toString()
        val placeLen = placePaint.measureText(placeText) + markW
        c.save()
        // Turned a quarter clockwise: letter tops face right, the line fills graphRight+4dp .. +lineH.
        c.translate(graphRight + dp(4f), (H - placeLen) / 2)
        c.rotate(90f)
        if (look.noLocation) {
            val r = dp(PLACE_DP) * 0.4f
            val cy = -fm.descent - (fm.descent - fm.ascent) * 0.35f
            val mark = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ink; style = Paint.Style.STROKE; strokeWidth = r * 0.3f }
            c.drawCircle(r, cy, r, mark)
            c.drawLine(r - r * 0.7f, cy + r * 0.7f, r + r * 0.7f, cy - r * 0.7f, mark)
        }
        c.drawText(placeText, markW, -fm.descent, placePaint)
        c.restore()

        // ---- Diagram.
        diagram(c, graphLeft, graphRight, H, f, hours, look)
        return Drawn(bmp, graphLeft / scale, graphRight / scale)
    }

    private fun diagram(c: Canvas, left: Float, right: Float, H: Float, f: Forecast, hours: List<Hour>, look: Look) {
        val n = hours.size
        val gw = right - left
        if (gw < 4f || n == 0) return
        // Whole pixels, so neighbouring hour columns meet without a pale seam.
        fun x(i: Int) = (left + gw * i / n).roundToInt().toFloat()
        val third = H / 3f

        val temps = hours.map { toUnit(it.tempOf(look.feels), look.fahrenheit) }
        val rounded = temps.map { displayRound(it) }
        val lo = rounded.min()
        val hi = rounded.max()
        val level = rounded.map { if (hi == lo) 0.5 else (it - lo).toDouble() / (hi - lo) }

        // Curve band inside the middle third.
        val curveTop = third + dp(6.5f)
        val curveH = max(1f, third - dp(16f))
        fun curveY(i: Int) = curveTop + ((1 - level[i]) * curveH).toFloat()
        val gap = dp(3f)

        // Temperature colour columns, from just under the curve band top to the bottom edge.
        val tempTop = third + dp(9.5f)
        for (i in 0 until n) {
            c.drawRect(x(i), tempTop, x(i + 1), H, fill(Palette.temp(hours[i].tempOf(look.feels))))
        }
        // Card-coloured shape that leaves a thin gap line under the sky.
        val gapPaint = fill(card)
        for (i in 0 until n) {
            val yr = curveY(i) + gap
            val yl = curveY(max(0, i - 1)) + gap
            c.drawPath(column(x(i), x(i + 1), tempTop, yl, yr), gapPaint)
        }

        // Hour labels and divider lines (dividers only show in the temperature part).
        val segments = timeline(f, hours, look)
        val px = scale / density
        var at = 0
        for (s in segments) {
            if (s.divider != null) {
                val thick = max(1f, (if (s.divider == Divider.DAY) 3f else 1f) * px)
                c.drawRect(x(at), 0f, x(at) + thick, H, gapPaint)
            }
            at += s.hours
        }

        // Sky: each hour column coloured by cloud and daylight, down to the curve.
        for (i in 0 until n) {
            val h = hours[i]
            c.drawPath(column(x(i), x(i + 1), 0f, curveY(max(0, i - 1)), curveY(i)), fill(Palette.sky(h.sun, h.cloud)))
        }

        // Rain and snow dots hanging from the top, one row per intensity step.
        val row = third / 4f
        val dotHalfH = row * 0.8f / 2
        for (i in 0 until n) {
            val steps = precipLevel(hours[i])
            if (steps == 0) continue
            val dot = fill(if (hours[i].precipType == PrecipType.SNOW) Palette.SNOW else Palette.RAIN)
            val halfW = (x(i + 1) - x(i)) * 0.8f / 2
            val r = min(halfW, dotHalfH)
            val cx = (x(i) + x(i + 1)) / 2
            for (k in 1..steps) {
                val cy = (k - 0.5f) * row
                c.drawRoundRect(cx - halfW, cy - dotHalfH, cx + halfW, cy + dotHalfH, r, r, dot)
            }
        }

        // High and low bubbles on the curve.
        bubbles(c, hours, temps, rounded, lo, hi, look, third, ::x)

        // Hour and day labels, in card colour on the temperature colours.
        val labelBandTop = third * 2
        val labelBandH = third * 0.4f
        var seg = 0
        for (s in segments) {
            if (s.label != null) {
                val t = BoxText(s.label, dp(TIME_LABEL_DP), fonts.medium, card)
                t.drawLeft(c, x(seg) + dp(4f), labelBandTop + (labelBandH - t.height) / 2)
            }
            seg += s.hours
        }

        // Wind: thin arrows pointing right, one per Beaufort force, stacked from the bottom.
        val windTop = labelBandTop + labelBandH
        val windH = H - windTop
        val forces = hours.map { beaufort(it.wind) }
        val most = max(1, forces.max())
        val step = windH / most
        val arrowH = windH / 12f
        for (i in 0 until n) {
            for (k in 1..forces[i]) {
                val cy = H - step * (k - 0.5f)
                c.drawPath(Path().apply {
                    moveTo(x(i), cy - arrowH / 2)
                    lineTo(x(i + 1), cy)
                    lineTo(x(i), cy + arrowH / 2)
                    close()
                }, gapPaint)
            }
        }
    }

    /** Filled column from [top] down to a sloped bottom edge (left y, right y). */
    private fun column(x0: Float, x1: Float, top: Float, yl: Float, yr: Float) = Path().apply {
        moveTo(x0, top); lineTo(x1, top); lineTo(x1, yr); lineTo(x0, yl); close()
    }

    private enum class Divider { DAY, QUARTER }

    private class Segment(val label: String?, val hours: Int, val divider: Divider?)

    /** Splits the hours at every label hour (3, 6 or 24 h). Midnight gets the day name and a thick line. */
    private fun timeline(f: Forecast, hours: List<Hour>, look: Look): List<Segment> {
        val every = look.span.labelEvery
        val out = mutableListOf<Segment>()
        var label: String? = null
        var divider: Divider? = null
        var count = 0
        hours.forEachIndexed { i, h ->
            val t = f.local(h.time)
            if (t.hour % every != 0) {
                count++
                return@forEachIndexed
            }
            if (count > 0) out += Segment(label, count, divider)
            when {
                i == 0 -> { label = null; divider = null }
                t.hour == 0 -> {
                    label = t.dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.getDefault())
                    divider = Divider.DAY
                }
                else -> {
                    label = if (look.use24h) "${t.hour}" else "${(t.hour + 11) % 12 + 1}"
                    divider = Divider.QUARTER
                }
            }
            count = 1
        }
        if (count > 0) {
            val l = label
            // The last label is dropped when its piece is too narrow for it.
            val fits = l == null || count * look.span.hourDp > TIME_LABEL_DP * l.length
            out += Segment(if (fits) l else null, count, divider)
        }
        return out
    }

    private class Mark(val index: Int, val priority: Double)

    /**
     * Picks where the temperature bubbles go: highest peaks first, then deepest dips, then long flat
     * stretches, never two closer than one bubble width. Adds one near the end if the last quarter
     * has none.
     */
    private fun bubbles(
        c: Canvas, hours: List<Hour>, temps: List<Double>, rounded: List<Int>, lo: Int, hi: Int,
        look: Look, third: Float, x: (Int) -> Float,
    ) {
        val n = hours.size
        val width = run {
            var w = ceil(BUBBLE_DP * (if (look.alsoOtherUnit) 8.5 else 4.5) / look.span.hourDp).toInt()
            if (w % 2 == 0) w++
            w.coerceIn(5, 21)
        }
        val half = width / 2
        val minT = temps.min()
        val maxT = temps.max()

        val peaks = mutableListOf<Mark>()
        val dips = mutableListOf<Mark>()
        val flats = mutableListOf<Mark>()
        var runStart = 0
        for (i in 1..n) {
            val next = if (i < n) rounded[i] else null
            val cur = rounded[runStart]
            if (next == cur) continue
            if (runStart > 0) {
                val before = rounded[runStart - 1]
                val after = next ?: cur
                val mid = (runStart + i - 1) / 2
                val isPeak = cur >= before && cur >= after && (cur > before || cur > after)
                val isDip = cur <= before && cur <= after && (cur < before || cur < after)
                when {
                    isPeak -> peaks += Mark(mid, temps[mid] - minT)
                    isDip -> dips += Mark(mid, maxT - temps[mid])
                    i - runStart >= width -> flats += Mark(mid, (i - runStart).toDouble())
                }
            }
            runStart = i
        }

        val taken = BooleanArray(n)
        val placed = mutableListOf<Mark>()
        fun place(m: Mark): Boolean {
            val i = m.index
            if (i - half < 0 || i + half > n - 1 || taken[i]) return false
            placed += m
            for (k in max(0, i - width + 1)..min(n - 1, i + width - 1)) taken[k] = true
            return true
        }
        val p = peaks.sortedByDescending { it.priority }.toMutableList()
        val d = dips.sortedByDescending { it.priority }.toMutableList()
        while (p.isNotEmpty() || d.isNotEmpty()) {
            while (p.isNotEmpty() && !place(p.removeAt(0))) Unit
            while (d.isNotEmpty() && !place(d.removeAt(0))) Unit
        }
        flats.sortedByDescending { it.priority }.forEach { place(it) }
        if (placed.none { it.index >= n * 3 / 4 }) {
            val i = max(0, n - 1 - half)
            place(Mark(i, 0.0))
        }

        val textPx = dp(BUBBLE_DP)
        for (m in placed) {
            val celsius = hours[m.index].tempOf(look.feels)
            val text = "${displayTemp(celsius, look.fahrenheit)}°"
            val color = Palette.temp(celsius)
            val paint = textPaint(textPx, fonts.bold, color)
            val b = bounds(paint, text)
            // Optional other unit: three quarters size, faded, left of the main value.
            val other = if (look.alsoOtherUnit) "${displayTemp(celsius, !look.fahrenheit)}°" else null
            val otherPaint = textPaint(textPx * 0.75f, fonts.bold, faded(color))
            val ob = other?.let { bounds(otherPaint, it) }
            val otherW = ob?.let { it.width() + dp(2f) } ?: 0f
            val pillW = otherW + b.width() + dp(10f)
            val pillH = b.height() + dp(5f)
            val step = if (maxT == minT) 5 else (((temps[m.index] - minT) / (maxT - minT)) * 10).roundToInt()
            val top = third + (third - pillH) * (10 - step) / 10f
            val cx = (x(m.index) + x(m.index + 1)) / 2
            val r = min(dp(10.5f), pillH / 2)
            c.drawRoundRect(cx - pillW / 2, top, cx + pillW / 2, top + pillH, r, r, fill(card))
            val textLeft = cx - pillW / 2 + dp(5f)
            if (other != null && ob != null) {
                val oTop = top + (pillH - ob.height()) / 2
                c.drawText(other, textLeft - ob.left, oTop - ob.top, otherPaint)
            }
            c.drawText(text, textLeft + otherW - b.left, top + dp(2.5f) - b.top, paint)
        }
    }

    private fun faded(c: Int) = Color.argb(Color.alpha(c) / 2, Color.red(c), Color.green(c), Color.blue(c))

    private fun displayRound(v: Double) = if (v < 0) -(-v).roundToInt() else v.roundToInt()

    companion object {
        private const val CORNER = 28f
        private const val SMALL_LABEL_DP = 15f
        private const val BIG_LABEL_DP = 34f
        private const val PLACE_DP = 11f
        private const val TIME_LABEL_DP = 10f
        private const val BUBBLE_DP = 16f
        /** Room the side labels take, used to work out how many hours fit. */
        private const val LABELS_DP = 3 * SMALL_LABEL_DP + BIG_LABEL_DP + PLACE_DP

        /** Pixel scale for a widget, kept under ~1.2 MP per bitmap (two bitmaps per update). */
        fun scaleFor(density: Float, wDp: Float, hDp: Float): Float {
            val limit = sqrt(1_200_000f / (wDp * hDp))
            return min(density, limit)
        }
    }
}
