package com.blessing.levels

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Watches which app is on screen and sets the media volume for it.
 *
 * It reads one thing: the package and class of the window that just came to
 * the front. Never the content of any screen.
 */
class LevelsService : AccessibilityService() {

    companion object {
        @Volatile var instance: LevelsService? = null

        /** Browsers play video too, but Android files them as nothing. */
        val BROWSERS = setOf(
            "com.android.chrome", "com.brave.browser", "org.mozilla.firefox",
            "com.microsoft.emmx", "com.opera.browser", "com.opera.mini.native",
            "com.sec.android.app.sbrowser", "com.duckduckgo.mobile.android",
            "com.vivaldi.browser",
        )

        /** Caller ID and calling apps: never a media pill there. */
        val CALLERS = setOf(
            "com.truecaller",
            "com.google.android.dialer",
            "com.samsung.android.dialer",
            "com.android.dialer",
            "com.android.server.telecom",
            "com.whosecall.android",
            "com.callapp.contacts",
            "com.hiya.star",
            "com.eyecon.global",
        )
        const val VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION"
        const val EXTRA_STREAM = "android.media.EXTRA_VOLUME_STREAM_TYPE"
    }

    private val main = Handler(Looper.getMainLooper())
    private lateinit var am: AudioManager
    private lateinit var pill: Pill

    private var current: String? = null       // package on screen
    private var managed: String? = null       // managed package we applied for
    private var managedLevel = -1             // level we set for it
    private var managedKeys = "ignore"
    private var managedPerApp = false
    private var baseline = -1                 // level the user had before
    private var userChanged = false
    private var oursUntil = 0L                // ignore volume broadcasts we caused
    private val activityCache = HashMap<String, Boolean>()
    private var ramp: Runnable? = null

    private val volReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) {
            if (i.getIntExtra(EXTRA_STREAM, -1) != AudioManager.STREAM_MUSIC) return
            onVolumeChanged()
        }
    }

    /**
     * Google Pay, PhonePe, Paytm and many banks refuse payments while any
     * accessibility switch is on (as Go Echoo found). One tap turns Levels'
     * switch off; the flag lets Home say why it is off and how to come back.
     */
    fun pauseForPayment() {
        PayNote.markPaused(this)
        disableSelf()
    }

    /** The last app seen in front: a switch-off made in Settings counts as
     *  for a payment (PayNote.stopped). */
    private var lastPkg: String? = null
    private var lastNight = -1

    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        val night = newConfig.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK
        if (lastNight != -1 && night != lastNight) PayNote.refresh(this)
        lastNight = night
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Back on after a payment pause: the notes go, and the entry with
        // "Pause for a payment" comes up in its place.
        lastNight = resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK
        PayNote.start(this)
        PayRefresh.request(this)
        am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        pill = Pill(this)
        val f = IntentFilter(VOLUME_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(volReceiver, f, RECEIVER_EXPORTED)
        else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(volReceiver, f)
        // A smart rule can turn on charging or the ringer mode: decide again
        // when either changes, not only when the app in front does.
        val g = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_LOW)
            addAction(Intent.ACTION_BATTERY_OKAY)
            addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
        }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(stateReceiver, g, RECEIVER_NOT_EXPORTED)
        else @Suppress("UnspecifiedRegisterReceiverFlag") registerReceiver(stateReceiver, g)
        scheduleResume()
        returnToApp()
    }

    private val stateReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(c: Context, i: Intent) { reapply() }
    }

    private val resume = Runnable {
        // Store.active turns Levels back on once the pause has run out.
        if (Store.active(this, Store.state(this))) {
            LevelsTileRefresh.request(this)
            reapply()
        }
    }

    /** A pause with an end: wake at that moment and switch back on. */
    fun scheduleResume() {
        main.removeCallbacks(resume)
        val s = Store.state(this)
        val until = s.optLong("pausedUntil", 0L)
        if (s.optBoolean("enabled", true) || until <= 0) return
        main.postDelayed(resume, (until - System.currentTimeMillis()).coerceAtLeast(0) + 500)
    }

    /** The user turned the switch on after Levels sent them to Settings:
     *  bring them straight back instead of leaving them in the list. Only
     *  within a few minutes of that hand-off, so a reboot or an update that
     *  reconnects the service never opens the app by itself. */
    private fun returnToApp() {
        val prefs = getSharedPreferences("levels", MODE_PRIVATE)
        val sent = prefs.getLong("a11y_sent_at", 0L)
        prefs.edit().remove("a11y_sent_at").apply()
        if (sent == 0L || System.currentTimeMillis() - sent > 5 * 60_000L) return
        main.postDelayed({
            try {
                startActivity(
                    Intent(this, MainActivity::class.java).addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                    )
                )
            } catch (_: Exception) {}
        }, 350)
    }

    override fun onDestroy() {
        instance = null
        PayNote.stopped(this, lastPkg?.let { it == "com.android.settings" || it.endsWith(".settings") } == true)
        PayRefresh.request(this)
        pendingPill?.let { main.removeCallbacks(it) }
        try { unregisterReceiver(volReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(stateReceiver) } catch (_: Exception) {}
        main.removeCallbacks(resume)
        if (::pill.isInitialized) pill.hide(now = true)
        super.onDestroy()
    }

    override fun onInterrupt() {}

    override fun onAccessibilityEvent(e: AccessibilityEvent) {
        if (e.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = e.packageName?.toString() ?: return
        if (pkg != packageName && pkg != "com.android.systemui") lastPkg = pkg
        val cls = e.className?.toString() ?: return
        // The home screen counts as leaving, whatever its window reports:
        // launchers announce a FrameLayout, not an activity.
        if (!isActivity(pkg, cls) && pkg !in homes()) return
        if (pkg == current) return
        onForeground(pkg)
    }

    /** Only a real activity coming forward counts: not a toast, a dialog
     *  from the system, the keyboard, or our own pill. */
    private fun isActivity(pkg: String, cls: String): Boolean {
        val key = "$pkg/$cls"
        activityCache[key]?.let { return it }
        val ok = try {
            packageManager.getActivityInfo(ComponentName(pkg, cls), 0); true
        } catch (_: Exception) { false }
        activityCache[key] = ok
        return ok
    }

    private var homeCache: Set<String>? = null
    private fun homes(): Set<String> = homeCache ?: packageManager
        .queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0)
        .map { it.activityInfo.packageName }.toSet().also { homeCache = it }

    fun label(pkg: String): String = try {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) { pkg }

    // ── Volume ─────────────────────────────────────────────────────────
    private fun max() = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
    fun levelNow(): Int = (am.getStreamVolume(AudioManager.STREAM_MUSIC) * 100f / max()).roundToInt()
    private fun index(pct: Int) = (pct.coerceIn(0, 100) * max() / 100f).roundToInt()

    /** Moves to [pct], stepping through the indices so it fades rather than
     *  jumps. Calls [onStep] with each level for the pill to follow. */
    /**
     * [settle]: an app is opening. Each volume step is a system call and a
     * broadcast to every listening app, so a ramp run during the opening
     * animation made switching stutter. It waits for the animation, and
     * moves in at most five steps.
     */
    fun setLevel(pct: Int, smooth: Boolean, settle: Boolean = false, onStep: ((Int) -> Unit)? = null) {
        ramp?.let { main.removeCallbacks(it) }
        val target = index(pct)
        val from = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        val steps = abs(target - from)
        if (!smooth || steps <= 1) {
            oursUntil = SystemClock.uptimeMillis() + 600
            am.setStreamVolume(AudioManager.STREAM_MUSIC, target, 0)
            onStep?.invoke(pct)
            return
        }
        val jumps = minOf(steps, 5)
        val stride = (steps + jumps - 1) / jumps
        val dt = 60L
        val wait = if (settle) 350L else 0L
        oursUntil = SystemClock.uptimeMillis() + wait + dt * jumps + 600
        var i = from
        val dir = if (target > from) 1 else -1
        val r = object : Runnable {
            override fun run() {
                i = if (dir > 0) minOf(target, i + stride) else maxOf(target, i - stride)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, i, 0)
                onStep?.invoke((i * 100f / max()).roundToInt())
                if (i != target) main.postDelayed(this, dt) else onStep?.invoke(pct)
            }
        }
        ramp = r
        main.postDelayed(r, wait)
    }

    // ── Foreground changes ─────────────────────────────────────────────
    // The pill waits until the user settles on an app. Swiping through
    // recents or across apps passes several in a second; drawing a window
    // for each one is what made switching feel slow.
    private var pendingPill: Runnable? = null
    private fun pillLater(show: () -> Unit) {
        pendingPill?.let { main.removeCallbacks(it) }
        // Never on the home screen or launcher, even one given a level.
        if (isSwitcher(current ?: "") || current in homes()) return
        val r = Runnable { pendingPill = null; show() }
        pendingPill = r
        main.postDelayed(r, 420)
    }

    private fun onForeground(pkg: String) {
        current = pkg
        // Leaving for the home screen, recents or the shade: nothing to show,
        // and any pill on screen goes at once.
        pendingPill?.let { main.removeCallbacks(it) }; pendingPill = null
        if (isSwitcher(pkg)) pill.hide(now = true)
        val s = Store.state(this)
        leaveManaged(s, next = pkg)
        // Levels itself is never managed: opening it gives the level back.
        if (pkg == packageName || !Store.active(this, s)) { publish(pkg, null); return }

        val res = Store.resolve(this, s, pkg)
        val label = label(pkg)
        if (res == null) {
            publish(pkg, null)
            // No level here: still show where the volume stands, so the user
            // sees it and can drag to give this app its own.
            if (showNotice(s) && s.optJSONObject("notice")?.optBoolean("unset", true) != false &&
                isApp(pkg) && !isCaller(pkg) && !hiddenHere(s, pkg)) {
                pillLater {
                    // Checked when the pill would show, so a video that
                    // started in the meantime counts.
                    if (current == pkg && isMediaApp(pkg)) {
                        pill.show(Pill.Kind.APPLY, pkg, label, levelNow(), "Your level",
                            explain = explainUnset())
                    }
                }
            }
            return
        }
        if (baseline < 0) baseline = levelNow()
        managed = pkg
        managedLevel = res.level
        managedKeys = res.keyMode
        managedPerApp = res.perApp
        userChanged = false
        Live.pkg = pkg; Live.label = label; Live.level = res.level
        Live.why = res.why; Live.managed = true; Live.baseline = baseline
        val smooth = s.optBoolean("ramp", true)
        if (showNotice(s)) pillLater {
            if (current == pkg) pill.show(Pill.Kind.APPLY, pkg, label, levelNow(), res.why)
        }
        setLevel(res.level, smooth, settle = true) { pill.follow(it) }
        Store.log(this, pkg, label, "apply", res.level, res.why)
    }

    /** Leaving a managed app: keep a changed level if asked, then give the
     *  user's own level back unless the next app is managed too. */
    private fun leaveManaged(s: JSONObject, next: String) {
        val was = managed ?: return
        if (userChanged && managedKeys == "remember" && managedPerApp) {
            saveAppLevel(was, levelNow())
        }
        managed = null
        val nextManaged = next.isNotEmpty() && next != packageName &&
            Store.active(this, s) && Store.resolve(this, s, next) != null
        if (nextManaged || baseline < 0) return
        val back = baseline
        baseline = -1
        val label = label(was)
        // No pill on the way out: it shows only on entering an app.
        setLevel(back, s.optBoolean("ramp", true), settle = true) { pill.follow(it) }
        Store.log(this, was, label, "restore", back, "Back to your level")
    }

    /**
     * Only where media plays: an app Android files as video, music or games,
     * or any app playing sound right now. A dialer, a caller ID app or a
     * banking app has no media volume worth showing.
     */
    private fun isMediaApp(pkg: String): Boolean {
        // By what the app is, never by whether something is playing: music
        // left on in the background made every app count, Settings and the
        // Secure Folder screen included.
        val cat = Store.categoryOf(this, pkg)
        return cat == "video" || cat == "audio" || cat == "game" || cat == "social" ||
            pkg in BROWSERS
    }

    private var dialerPkg: String? = null
    /** The default phone app, and caller ID apps such as Truecaller. */
    private fun isCaller(pkg: String): Boolean {
        if (dialerPkg == null) dialerPkg = try {
            (getSystemService(TELECOM_SERVICE) as android.telecom.TelecomManager)
                .defaultDialerPackage ?: ""
        } catch (_: Exception) { "" }
        return pkg == dialerPkg || pkg in CALLERS ||
            pkg.contains("dialer") || pkg.contains("telecom") || pkg.contains(".contacts")
    }

    private var homePkg: String? = null
    /** The home screen, recents or System UI: places the user passes through. */
    private fun isSwitcher(pkg: String): Boolean {
        if (homePkg == null) homePkg = try {
            packageManager.resolveActivity(
                Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0,
            )?.activityInfo?.packageName ?: ""
        } catch (_: Exception) { "" }
        return pkg == homePkg || pkg == "com.android.systemui" ||
            pkg.endsWith(".launcher") || pkg.contains("launcher3")
    }

    /** A real app the user opened: has a launcher icon and is not the home screen. */
    private fun isApp(pkg: String): Boolean = try {
        val home = packageManager.resolveActivity(
            Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME), 0,
        )?.activityInfo?.packageName
        pkg != home && pkg != "com.android.systemui" &&
            packageManager.getLaunchIntentForPackage(pkg) != null
    } catch (_: Exception) { false }

    private fun publish(pkg: String, why: String?) {
        Live.pkg = pkg; Live.label = label(pkg); Live.level = levelNow()
        Live.why = why; Live.managed = false; Live.baseline = baseline
    }

    private fun showNotice(s: JSONObject) = s.optJSONObject("notice")?.optBoolean("show", true) ?: true

    // ── Volume keys ────────────────────────────────────────────────────
    private fun onVolumeChanged() {
        if (SystemClock.uptimeMillis() < oursUntil) return
        if (pill.dragging) return
        val s = Store.state(this)
        val m = managed
        if (m != null) {
            when (managedKeys) {
                "lock" -> main.postDelayed({ if (managed == m) setLevel(managedLevel, false) }, 150)
                "remember" -> userChanged = true
            }
            Live.level = levelNow()
            return
        }
        // An app with no rule: offer to keep this level for it, once.
        val pkg = current ?: return
        if (pkg == packageName || !Store.active(this, s) || !s.optBoolean("offer", true)) return
        val offered = s.optJSONArray("offered") ?: JSONArray()
        for (i in 0 until offered.length()) if (offered.optString(i) == pkg) return
        main.removeCallbacks(offerRunnable)
        offerPkg = pkg
        main.postDelayed(offerRunnable, 900) // after the user settles
    }

    private var offerPkg: String? = null
    private val offerRunnable = Runnable {
        val pkg = offerPkg ?: return@Runnable
        if (pkg != current || managed != null) return@Runnable
        pill.show(Pill.Kind.OFFER, pkg, label(pkg), levelNow(), null)
    }

    // ── Called from the pill ───────────────────────────────────────────
    fun saveAppLevel(pkg: String, level: Int) {
        val s = Store.state(this)
        val apps = s.optJSONObject("apps") ?: JSONObject().also { s.put("apps", it) }
        val a = apps.optJSONObject(pkg) ?: JSONObject().apply {
            put("on", true); put("rules", JSONArray())
        }.also { apps.put(pkg, it) }
        a.put("vol", level); a.put("on", true)
        Store.save(this, s)
        if (pkg == current) {
            if (managed == null && baseline < 0) baseline = levelNow()
            managed = pkg; managedLevel = level; managedPerApp = true
            managedKeys = a.optString("keyMode", "").ifEmpty { s.optString("keyMode", "ignore") }
            Live.managed = true; Live.level = level; Live.why = "Own level"
        }
        Store.log(this, pkg, label(pkg), "saved", level, "Set from the pill")
    }

    // The unset-app pill explains itself up to three times, or until the
    // user answers Keep or Off.
    private fun explainUnset(): Boolean {
        val p = getSharedPreferences("levels", MODE_PRIVATE)
        if (p.getBoolean("unset_answered", false)) return false
        val n = p.getInt("unset_explained", 0)
        if (n >= 3) return false
        p.edit().putInt("unset_explained", n + 1).apply()
        return true
    }

    /** The user's "Hide in" list (Settings, or "Not here" on the pill). */
    private fun hiddenHere(s: JSONObject, pkg: String): Boolean {
        val a = s.optJSONObject("notice")?.optJSONArray("hide") ?: return false
        for (i in 0 until a.length()) if (a.optString(i) == pkg) return true
        return false
    }

    /** Keep, or "Not here": this one app joins the "Hide in" list. */
    fun answerUnset(pkg: String, keep: Boolean) {
        getSharedPreferences("levels", MODE_PRIVATE).edit()
            .putBoolean("unset_answered", true).apply()
        if (!keep) {
            val s = Store.state(this)
            val n = s.optJSONObject("notice") ?: JSONObject().also { s.put("notice", it) }
            val a = n.optJSONArray("hide") ?: JSONArray().also { n.put("hide", it) }
            if (!hiddenHere(s, pkg)) a.put(pkg)
            Store.save(this, s)
        }
    }

    fun removeApp(pkg: String) {
        val s = Store.state(this)
        s.optJSONObject("apps")?.remove(pkg)
        Store.save(this, s)
    }

    fun markOffered(pkg: String) {
        val s = Store.state(this)
        val arr = s.optJSONArray("offered") ?: JSONArray().also { s.put("offered", it) }
        arr.put(pkg)
        Store.save(this, s)
    }

    fun pauseApp(pkg: String) {
        val s = Store.state(this)
        s.optJSONObject("apps")?.optJSONObject(pkg)?.put("on", false)
        Store.save(this, s)
        if (managed == pkg) leaveManaged(s, next = "")
    }

    fun openApp() {
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** The app changed the store: re-apply to what is on screen now. */
    fun reapply() {
        scheduleResume()
        val pkg = current ?: return
        if (pkg == packageName) return
        current = null
        onForeground(pkg)
    }

    /** From the notice: how the volume keys behave inside [pkg]. */
    fun setKeyMode(pkg: String, mode: String) {
        val s = Store.state(this)
        s.optJSONObject("apps")?.optJSONObject(pkg)?.put("keyMode", mode) ?: return
        Store.save(this, s)
        if (managed == pkg) managedKeys = mode
    }

    fun savePillY(y: Float) {
        val s = Store.state(this)
        s.optJSONObject("notice")?.put("y", y.toDouble())
        Store.save(this, s)
    }
}
