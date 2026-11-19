package com.blessing.levels

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.drawable.toBitmap
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * The on-screen level, drawn over whatever app is open.
 *
 * Unlike a passive volume bar it can be used: drag it to change the level
 * (letting go saves it for this app, with Undo), tap it for a small card.
 *
 * The window exists only while the pill is visible and is REMOVED when it
 * fades. A resident window, even an invisible one, marks every touch below it
 * as obscured, and Play's update sheet, UPI PIN screens and banking apps
 * refuse such touches.
 */
class Pill(private val svc: LevelsService) {

    enum class Kind { APPLY, RESTORE, OFFER }

    private val ctx: Context = svc
    private val wm = svc.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val main = Handler(Looper.getMainLooper())
    private var root: FrameLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var bar: LevelBar? = null
    private var pct: TextView? = null
    private var chip: LinearLayout? = null
    private var kind = Kind.APPLY
    private var pkg = ""
    private var label = ""
    var dragging = false
        private set

    private val hideRunnable = Runnable { hide() }

    private fun dp(v: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, ctx.resources.displayMetrics)
    private fun dpi(v: Float) = dp(v).roundToInt()

    private fun animOn() = ValueAnimator.areAnimatorsEnabled()

    // Read once per show: parsing the whole store for every look-up was
    // work on the main thread while an app was opening.
    private var noticeCache: org.json.JSONObject? = null
    private fun notice() = noticeCache ?: Store.state(ctx).optJSONObject("notice")
    private fun side() = notice()?.optString("side", "right") ?: "right"
    private fun rightSide() = side() != "left"
    /** Island style: a horizontal capsule under the camera. */
    private fun top() = side() == "top"
    private fun detailed() = notice()?.optString("style", "detail") != "bar"

    // ── Show / follow / hide ───────────────────────────────────────────
    /**
     * [explain]: the first times the pill shows in an app the user never set,
     * it says why it is there and lets them keep it or turn it off. Without
     * that, a pill in an untouched app reads as Levels misbehaving.
     */
    fun show(k: Kind, p: String, l: String, level: Int, why: String?, explain: Boolean = false) {
        main.removeCallbacks(hideRunnable)
        val st = Store.state(ctx)
        noticeCache = st.optJSONObject("notice")
        useAccent(st.optString("accent", "wheat"))
        val fresh = root == null || kind != k || pkg != p
        kind = k; pkg = p; label = l
        if (fresh) { removeNow(); build(level) }
        else { bar?.set(level); updatePct(level) }
        if (k == Kind.OFFER) {
            svc.markOffered(p)
            showChip("Keep ${level}% for $l?", "Keep") {
                svc.saveAppLevel(pkg, bar?.level ?: level)
                showChip("Saved for $label", null, null)
            }
        }
        if (explain) {
            val name = if (l.length > 14) l.take(13) + "…" else l
            showChip(
                "Volume here. Drag to keep it for $name",
                listOf(
                    "OK" to { svc.answerUnset(pkg, keep = true); hide() },
                    "Not here" to { svc.answerUnset(pkg, keep = false); hide() },
                ),
            )
            scheduleHide(5000)
            return
        }
        // A glance is enough: the level is set either way.
        scheduleHide(if (k == Kind.OFFER) 3500 else 1500)
    }

    /** The real volume moved (a ramp step): the fill follows it. */
    fun follow(level: Int) {
        if (dragging) return
        bar?.set(level); updatePct(level)
    }

    fun hide(now: Boolean = false) {
        main.removeCallbacks(hideRunnable)
        val r = root ?: return
        if (now || !animOn()) { removeNow(); return }
        val a = r.animate().alpha(0f).setDuration(220)
        if (top()) a.translationY(-dp(14f)).scaleX(0.9f)
        else a.translationX(if (rightSide()) dp(18f) else -dp(18f))
        a.withEndAction { if (root === r) removeNow() }.start()
    }

    private fun scheduleHide(ms: Long) {
        main.removeCallbacks(hideRunnable)
        main.postDelayed(hideRunnable, ms)
    }

    private fun removeNow() {
        val r = root ?: return
        root = null; bar = null; pct = null; chip = null; dragging = false
        try { wm.removeView(r) } catch (_: Exception) {}
    }

    // ── Build ──────────────────────────────────────────────────────────
    @SuppressLint("ClickableViewAccessibility")
    private fun build(level: Int) {
        val right = rightSide()
        val touchable = kind != Kind.RESTORE

        val island = top()
        val column = LinearLayout(ctx).apply {
            orientation = if (island) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
            gravity = if (island) Gravity.CENTER_VERTICAL else Gravity.CENTER_HORIZONTAL
            if (island) setPadding(dpi(8f), dpi(7f), dpi(12f), dpi(7f))
            else setPadding(dpi(6f), dpi(8f), dpi(6f), dpi(8f))
            background = glass(dp(22f))
        }
        if (detailed()) {
            column.addView(if (kind == Kind.RESTORE) backGlyph(dpi(24f)) else icon(dpi(24f)),
                LinearLayout.LayoutParams(dpi(24f), dpi(24f)).apply {
                if (island) marginEnd = dpi(10f) else bottomMargin = dpi(8f)
            })
        }
        val b = LevelBar(ctx, vertical = !island).apply { set(level) }
        bar = b
        column.addView(b, if (island) LinearLayout.LayoutParams(dpi(150f), dpi(12f))
            else LinearLayout.LayoutParams(dpi(14f), dpi(140f)))
        if (detailed()) {
            val t = TextView(ctx).apply {
                setTextColor(Color.WHITE)
                textSize = 12f
                typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                fontFeatureSettings = "tnum"
                gravity = Gravity.CENTER
            }
            pct = t
            column.addView(t, LinearLayout.LayoutParams(dpi(40f), LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (island) marginStart = dpi(6f) else topMargin = dpi(6f)
            })
            updatePct(level)
        }

        val row = LinearLayout(ctx).apply {
            orientation = if (island) LinearLayout.VERTICAL else LinearLayout.HORIZONTAL
            if (island) gravity = Gravity.CENTER_HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutDirection = if (right) View.LAYOUT_DIRECTION_LTR else View.LAYOUT_DIRECTION_RTL
        }
        val chipBox = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            visibility = View.GONE
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            background = glass(dp(18f))
            setPadding(dpi(14f), dpi(9f), dpi(14f), dpi(9f))
        }
        chip = chipBox
        val chipLp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT
        )
        if (island) {
            row.addView(column)
            row.addView(chipBox, chipLp.apply { topMargin = dpi(8f) })
        } else {
            row.addView(chipBox, chipLp.apply { marginEnd = dpi(8f) })
            row.addView(column)
        }

        val frame = FrameLayout(ctx)
        frame.addView(row)
        root = frame

        if (touchable) attachGestures(column, b)
        column.contentDescription = "$label, volume $level percent"
        b.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        b.onA11yStep = { delta -> applyDrag((b.level + delta).coerceIn(0, 100), haptic = false); commitDrag() }

        val dm = ctx.resources.displayMetrics
        val y = (notice()?.optDouble("y", 0.38) ?: 0.38).toFloat()
        var flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH
        if (!touchable) flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            flags,
            PixelFormat.TRANSLUCENT,
        ).apply {
            if (island) {
                gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                this.y = statusBar() + dpi(6f)
            } else {
                gravity = Gravity.TOP or (if (right) Gravity.END else Gravity.START)
                x = dpi(10f)
                this.y = (dm.heightPixels * y).roundToInt()
            }
        }
        params = lp
        frame.setOnTouchListener { _, e ->
            if (e.action == MotionEvent.ACTION_OUTSIDE && !dragging) hide()
            false
        }
        try { wm.addView(frame, lp) } catch (_: Exception) { root = null; return }

        if (animOn()) {
            frame.alpha = 0f
            if (island) { frame.translationY = -dp(16f); frame.scaleX = 0.86f }
            else frame.translationX = if (right) dp(24f) else -dp(24f)
            frame.animate().alpha(1f).translationX(0f).translationY(0f).scaleX(1f).setDuration(220)
                .setInterpolator(DecelerateInterpolator(2f)).start()
        }
    }

    private fun updatePct(level: Int) {
        pct?.text = if (level == 0) "Mute" else "$level"
        root?.getChildAt(0)?.let { (it as? LinearLayout)?.getChildAt(1)?.contentDescription =
            "$label, volume $level percent" }
    }

    // ── Gestures ───────────────────────────────────────────────────────
    private var downY = 0f
    private var downX = 0f
    private var downRawY = 0f
    private var startY = 0
    private var moving = false
    private var lastTick = -1
    private var before = -1
    private var hadApp = false
    private var prevVol = -1
    private val slop by lazy { ViewConfiguration.get(ctx).scaledTouchSlop }
    private val longPress = Runnable {
        moving = true
        root?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        bar?.setWide(true)
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun attachGestures(column: View, b: LevelBar) {
        column.setOnTouchListener { _, e ->
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    main.removeCallbacks(hideRunnable)
                    downY = e.y; downX = e.x; downRawY = e.rawY; startY = params?.y ?: 0
                    moving = false; dragging = false; lastTick = b.level / 10
                    if (!top()) main.postDelayed(longPress, 450)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    if (moving) {
                        params?.let { p ->
                            p.y = (startY + (e.rawY - downRawY)).roundToInt()
                            try { wm.updateViewLayout(root, p) } catch (_: Exception) {}
                        }
                    } else if (dragging || abs(e.y - downY) > slop || (top() && abs(e.x - downX) > slop)) {
                        main.removeCallbacks(longPress)
                        if (!dragging) {
                            dragging = true
                            before = svc.levelNow()
                            val app = Store.state(ctx).optJSONObject("apps")?.optJSONObject(pkg)
                            hadApp = app != null; prevVol = app?.optInt("vol", -1) ?: -1
                            b.setWide(true)
                        }
                        val loc = IntArray(2); b.getLocationOnScreen(loc)
                        val frac = if (top()) (e.rawX - loc[0]) / b.width
                            else 1f - ((e.rawY - loc[1]) / b.height)
                        applyDrag((frac * 100).roundToInt().coerceIn(0, 100), haptic = true)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    main.removeCallbacks(longPress)
                    b.setWide(false)
                    when {
                        moving -> {
                            moving = false
                            val h = ctx.resources.displayMetrics.heightPixels.toFloat()
                            svc.savePillY(((params?.y ?: 0) / h).coerceIn(0.08f, 0.8f))
                            scheduleHide(1600)
                        }
                        dragging -> commitDrag()
                        e.actionMasked == MotionEvent.ACTION_UP -> expand()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun applyDrag(level: Int, haptic: Boolean) {
        bar?.set(level); updatePct(level)
        svc.setLevel(level, smooth = false)
        val tick = level / 10
        if (haptic && tick != lastTick) {
            lastTick = tick
            root?.performHapticFeedback(
                if (level == 0 || level == 100) HapticFeedbackConstants.LONG_PRESS
                else HapticFeedbackConstants.CLOCK_TICK
            )
        }
    }

    /** Letting go keeps the level for this app. Undo puts everything back. */
    private fun commitDrag() {
        dragging = false
        val level = bar?.level ?: return
        if (before < 0) before = level
        val wasBefore = before; val had = hadApp; val prev = prevVol; val p = pkg
        svc.saveAppLevel(p, level)
        root?.performHapticFeedback(HapticFeedbackConstants.CONFIRM)
        showChip("Saved $level% for $label", "Undo") {
            if (had && prev >= 0) svc.saveAppLevel(p, prev) else svc.removeApp(p)
            svc.setLevel(wasBefore, smooth = true) { follow(it) }
            showChip("Undone", null, null)
        }
        before = -1
        scheduleHide(3500)
    }

    private fun showChip(text: String, action: String?, onAction: (() -> Unit)?) =
        showChip(text, if (action != null && onAction != null) listOf(action to onAction) else emptyList())

    private fun showChip(text: String, actions: List<Pair<String, () -> Unit>>) {
        val c = chip ?: return
        c.removeAllViews()
        c.addView(TextView(ctx).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 13f
            maxWidth = dpi(200f) // wraps to two lines rather than leaving the screen
            typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        })
        for ((action, onAction) in actions) {
            c.addView(TextView(ctx).apply {
                this.text = action
                setTextColor(ACCENT_LIGHT)
                textSize = 13f
                typeface = Typeface.create("sans-serif", Typeface.BOLD)
                setPadding(dpi(12f), dpi(4f), 0, dpi(4f))
                setOnClickListener { onAction(); scheduleHide(1800) }
            })
        }
        if (c.visibility != View.VISIBLE) {
            c.visibility = View.VISIBLE
            if (animOn()) { c.alpha = 0f; c.animate().alpha(1f).setDuration(180).start() }
        }
        scheduleHide(3500)
    }

    // ── Card ───────────────────────────────────────────────────────────
    private fun expand() {
        val r = root ?: return
        root?.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
        val level = bar?.level ?: svc.levelNow()
        val card = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            background = glass(dp(26f), solid = true)
            // Room at the sides, so the controls do not run to the edge.
            setPadding(dpi(22f), dpi(18f), dpi(22f), dpi(18f))
        }
        val head = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL }
        head.addView(icon(dpi(34f)), LinearLayout.LayoutParams(dpi(34f), dpi(34f)))
        val names = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(dpi(10f), 0, 0, 0) }
        names.addView(TextView(ctx).apply {
            text = label; setTextColor(Color.WHITE); textSize = 15f
            typeface = Typeface.create("sans-serif", Typeface.NORMAL); maxLines = 1
        })
        val sub = TextView(ctx).apply {
            text = subText(level); setTextColor(0xB3FFFFFF.toInt()); textSize = 12f
            fontFeatureSettings = "tnum"
        }
        names.addView(sub)
        head.addView(names, LinearLayout.LayoutParams(dpi(CARD_W - 44f), LinearLayout.LayoutParams.WRAP_CONTENT))
        card.addView(head)

        val h = LevelBar(ctx, vertical = false).apply { set(level) }
        card.addView(h, LinearLayout.LayoutParams(dpi(CARD_W), dpi(30f)).apply { topMargin = dpi(14f) })
        var cardBefore = -1
        h.onDrag = { lv, done ->
            main.removeCallbacks(hideRunnable)
            if (cardBefore < 0) cardBefore = svc.levelNow()
            svc.setLevel(lv, smooth = false)
            sub.text = subText(lv)
            if (done) {
                svc.saveAppLevel(pkg, lv)
                sub.text = "Saved $lv% for this app"
                cardBefore = -1
                scheduleHide(3000)
            }
        }

        val actions = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL }
        // One line, one height: a label that wraps makes a lopsided row.
        fun action(t: String, onTap: () -> Unit) = TextView(ctx).apply {
            text = t; setTextColor(Color.WHITE); textSize = 13f; gravity = Gravity.CENTER
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            isSingleLine = true; maxLines = 1
            background = GradientDrawable().apply { cornerRadius = dp(20f); setColor(0x1FFFFFFF) }
            setPadding(dpi(4f), 0, dpi(4f), 0)
            setOnClickListener { performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK); onTap() }
        }
        val lp = { LinearLayout.LayoutParams(0, dpi(40f), 1f).apply { marginEnd = dpi(8f) } }
        actions.addView(action("Mute") {
            h.set(0); svc.setLevel(0, smooth = true); svc.saveAppLevel(pkg, 0); sub.text = subText(0)
            scheduleHide(2500)
        }, lp())
        if (Store.state(ctx).optJSONObject("apps")?.has(pkg) == true) {
            actions.addView(action("Pause here") { svc.pauseApp(pkg); hide() }, lp())
        }
        actions.addView(action("Open") { hide(now = true); svc.openApp() }, LinearLayout.LayoutParams(0, dpi(40f), 1f))
        card.addView(actions, LinearLayout.LayoutParams(dpi(CARD_W), LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(14f) })

        // Volume keys inside this app, chosen right here.
        val app = Store.state(ctx).optJSONObject("apps")?.optJSONObject(pkg)
        if (app != null) {
            val keys = LinearLayout(ctx).apply {
                gravity = Gravity.CENTER_VERTICAL
                background = GradientDrawable().apply { cornerRadius = dp(14f); setColor(0x14FFFFFF) }
                setPadding(dpi(3f), dpi(3f), dpi(3f), dpi(3f))
            }
            val modes = listOf("remember" to "Remember", "ignore" to "Ignore", "lock" to "Lock")
            val chips = mutableListOf<TextView>()
            fun paint(current: String) = chips.forEachIndexed { i, t ->
                val on = modes[i].first == current
                t.setTextColor(if (on) ON_ACCENT else 0xCCFFFFFF.toInt())
                t.background = if (on) GradientDrawable().apply { cornerRadius = dp(11f); setColor(ACCENT) } else null
            }
            for ((mode, name) in modes) {
                val t = TextView(ctx).apply {
                    text = name; textSize = 12.5f; gravity = Gravity.CENTER
                    isSingleLine = true
                    setPadding(0, dpi(8f), 0, dpi(8f))
                    setOnClickListener {
                        performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                        svc.setKeyMode(pkg, mode); paint(mode); scheduleHide(3000)
                    }
                }
                chips += t
                keys.addView(t, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
            }
            paint(app.optString("keyMode", "").ifEmpty { Store.state(ctx).optString("keyMode", "remember") })
            card.addView(TextView(ctx).apply {
                text = "Volume keys here"; setTextColor(0x99FFFFFF.toInt()); textSize = 11.5f
            }, LinearLayout.LayoutParams(dpi(CARD_W), LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(12f) })
            card.addView(keys, LinearLayout.LayoutParams(dpi(CARD_W), LinearLayout.LayoutParams.WRAP_CONTENT).apply { topMargin = dpi(6f) })
        }

        card.setOnTouchListener { _, _ -> main.removeCallbacks(hideRunnable); scheduleHide(3500); false }
        r.removeAllViews()
        r.addView(card)
        bar = null; pct = null; chip = null
        if (animOn()) {
            card.scaleX = 0.92f; card.scaleY = 0.92f; card.alpha = 0f
            card.pivotX = if (top()) dp(CARD_W / 2 + 22f) else if (rightSide()) dp(CARD_W + 44f) else 0f
            if (top()) card.pivotY = 0f
            card.animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(200)
                .setInterpolator(DecelerateInterpolator(2f)).start()
        }
        scheduleHide(3500)
    }

    private fun statusBar(): Int {
        val id = ctx.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) ctx.resources.getDimensionPixelSize(id) else dpi(28f)
    }

    private fun subText(level: Int) = if (level == 0) "Muted" else "$level% · media"

    // ── Pieces ─────────────────────────────────────────────────────────
    /** Matte ink-teal: an even fill and a faint edge. No shine. */
    private fun glass(radius: Float, solid: Boolean = false) = GradientDrawable(
        GradientDrawable.Orientation.TOP_BOTTOM,
        // The card is solid: over a busy video a see-through card lets the
        // app's own dots and text bleed into the controls.
        if (solid) intArrayOf(0xFF12303A.toInt(), 0xFF0B2229.toInt())
        else intArrayOf(0xF0102B33.toInt(), 0xF00A1E25.toInt()),
    ).apply {
        cornerRadius = radius
        setStroke(dpi(0.8f).coerceAtLeast(1), 0x14FFFFFF)
    }

    /**
     * The leaving pill's mark: not the app being left (it is no longer in
     * front) but what is happening, your own level coming back. A glass
     * disc with a return arrow, in the accent.
     */
    private fun backGlyph(size: Int): View = object : View(ctx) {
        val disc = Paint(Paint.ANTI_ALIAS_FLAG)
        val rim = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; color = 0x66FFFFFF; strokeWidth = dp(0.8f)
        }
        val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; color = ON_ACCENT
            strokeWidth = dp(1.7f); strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        }
        override fun onDraw(c: Canvas) {
            val w = width.toFloat(); val r = w / 2f
            disc.shader = LinearGradient(0f, 0f, 0f, w, ACCENT, ACCENT,
                Shader.TileMode.CLAMP)
            c.drawCircle(r, r, r, disc)
            c.drawCircle(r, r, r - dp(0.4f), rim)
            // A house: your own level, the mark Home uses for it.
            val path = android.graphics.Path().apply {
                moveTo(w * 0.27f, w * 0.50f)
                lineTo(w * 0.50f, w * 0.29f)
                lineTo(w * 0.73f, w * 0.50f)
                moveTo(w * 0.34f, w * 0.45f)
                lineTo(w * 0.34f, w * 0.72f)
                lineTo(w * 0.66f, w * 0.72f)
                lineTo(w * 0.66f, w * 0.45f)
                moveTo(w * 0.46f, w * 0.72f)
                lineTo(w * 0.46f, w * 0.59f)
                lineTo(w * 0.54f, w * 0.59f)
                lineTo(w * 0.54f, w * 0.72f)
            }
            c.drawPath(path, stroke)
        }
    }.apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }

    private fun icon(size: Int): View = object : View(ctx) {
        val bmp: Bitmap? = try {
            ctx.packageManager.getApplicationIcon(pkg).toBitmap(size, size)
        } catch (_: Exception) { null }
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            if (bmp != null) shader = BitmapShader(bmp, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
            else color = Color.GRAY
        }
        override fun onDraw(c: Canvas) {
            val r = width / 2f
            c.drawCircle(r, r, r, paint)
        }
    }.apply { importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO }

    companion object {
        const val CARD_W = 256f
        // The accent chosen in Settings (fill, glyph on it, link on dark).
        // Mirrors Accent.all in kit.dart: keep the two lists in step.
        private val ACCENTS = mapOf(
            "wheat" to intArrayOf(0xFFE3CF9C.toInt(), 0xFF4E3F1E.toInt(), 0xFFE9D8A6.toInt()),
            "sage" to intArrayOf(0xFFC3D5B0.toInt(), 0xFF34452A.toInt(), 0xFFCFE0BE.toInt()),
            "seafoam" to intArrayOf(0xFFA9D9C8.toInt(), 0xFF0E4A3E.toInt(), 0xFFB7E2D3.toInt()),
            "mist" to intArrayOf(0xFFB9CDE4.toInt(), 0xFF23384F.toInt(), 0xFFC6D7EB.toInt()),
            "lilac" to intArrayOf(0xFFCFC2E5.toInt(), 0xFF3B2E55.toInt(), 0xFFDACFEC.toInt()),
            "rose" to intArrayOf(0xFFE9C1B9.toInt(), 0xFF55302A.toInt(), 0xFFEFCDC6.toInt()),
            "stone" to intArrayOf(0xFFD8D4CB.toInt(), 0xFF3A3833.toInt(), 0xFFE0DCD4.toInt()),
        )
        private var tone = ACCENTS.getValue("wheat")
        fun useAccent(id: String?) { tone = ACCENTS[id] ?: ACCENTS.getValue("wheat") }
        val ACCENT get() = tone[0]
        val ON_ACCENT get() = tone[1]
        val ACCENT_LIGHT get() = tone[2]
    }
}

/** The level itself: a track with a gradient fill. Vertical on the pill,
 *  horizontal on the card. Fully drawn, so it stays crisp at any size. */
@SuppressLint("ViewConstructor")
class LevelBar(ctx: Context, private val vertical: Boolean) : View(ctx) {
    var level = 0
        private set
    private var shown = 0f
    private var wide = 0f
    private var anim: ValueAnimator? = null
    private var wideAnim: ValueAnimator? = null
    var onDrag: ((Int, Boolean) -> Unit)? = null
    var onA11yStep: ((Int) -> Unit)? = null

    private val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x33FFFFFF }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    init {
        if (!vertical) {
            isClickable = true
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        }
    }

    fun set(v: Int) {
        level = v.coerceIn(0, 100)
        anim?.cancel()
        if (!ValueAnimator.areAnimatorsEnabled()) { shown = level.toFloat(); invalidate(); return }
        anim = ValueAnimator.ofFloat(shown, level.toFloat()).apply {
            duration = 140
            addUpdateListener { shown = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    fun setWide(on: Boolean) {
        wideAnim?.cancel()
        wideAnim = ValueAnimator.ofFloat(wide, if (on) 1f else 0f).apply {
            duration = 160
            addUpdateListener { wide = it.animatedValue as Float; invalidate() }
            start()
        }
    }

    override fun onDraw(c: Canvas) {
        val w = width.toFloat(); val h = height.toFloat()
        if (vertical) {
            val grow = w * 0.35f * wide
            rect.set(-grow / 2, 0f, w + grow / 2, h)
            val r = rect.width() / 2
            c.drawRoundRect(rect, r, r, track)
            val top = h - h * (shown / 100f)
            fill.shader = LinearGradient(0f, h, w, 0f, Pill.ACCENT, Pill.ACCENT, Shader.TileMode.CLAMP)
            if (shown > 0.5f) {
                c.save()
                c.clipRect(rect.left, top, rect.right, h)
                c.drawRoundRect(rect, r, r, fill)
                c.restore()
            }
        } else {
            val th = h * 0.42f
            rect.set(0f, (h - th) / 2, w, (h + th) / 2)
            val r = th / 2
            c.drawRoundRect(rect, r, r, track)
            val right = w * (shown / 100f)
            fill.shader = LinearGradient(0f, h, w, 0f, Pill.ACCENT, Pill.ACCENT, Shader.TileMode.CLAMP)
            if (shown > 0.5f) {
                c.save(); c.clipRect(0f, 0f, right, h); c.drawRoundRect(rect, r, r, fill); c.restore()
            }
            // Thumb
            val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
            c.drawCircle(right.coerceIn(h / 2, w - h / 2), h / 2, h * 0.42f, p)
        }
    }

    private var lastTick = -1

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (vertical || onDrag == null) return false
        parent?.requestDisallowInterceptTouchEvent(true)
        val v = ((e.x / width) * 100).roundToInt().coerceIn(0, 100)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                set(v)
                if (v / 10 != lastTick) {
                    lastTick = v / 10
                    performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                }
                onDrag?.invoke(v, false)
            }
            MotionEvent.ACTION_UP -> onDrag?.invoke(v, true)
        }
        return true
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.SeekBar"
        info.rangeInfo = AccessibilityNodeInfo.RangeInfo.obtain(
            AccessibilityNodeInfo.RangeInfo.RANGE_TYPE_PERCENT, 0f, 100f, level.toFloat()
        )
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD)
    }

    override fun performAccessibilityAction(action: Int, args: Bundle?): Boolean {
        val step = when (action) {
            AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> 10
            AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD -> -10
            else -> return super.performAccessibilityAction(action, args)
        }
        val v = (level + step).coerceIn(0, 100)
        set(v)
        onA11yStep?.invoke(step) ?: onDrag?.invoke(v, true)
        return true
    }
}
