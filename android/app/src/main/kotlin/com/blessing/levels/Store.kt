package com.blessing.levels

import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioDeviceInfo
import android.media.AudioManager
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * The one store both sides share. Kotlin owns it (the service runs with no
 * Flutter engine alive); Dart reads and writes it whole over the channel.
 *
 * Shape:
 * {
 *   enabled, keyMode ("ignore"|"remember"|"lock"), ramp (bool),
 *   notice: { show, side ("right"|"left"), y (0..1), style ("bar"|"detail") },
 *   cap (null | 0..100, headphones only), offer (bool), offered: [pkg],
 *   apps: { pkg: { on, vol, keyMode|null, rules: [ {vol, device, from, to} ] } },
 *   cats: { game|video|social|audio|news|maps|image|productivity: {on, vol} },
 *   custom: [ {id, name, vol, on, apps:[pkg]} ]
 * }
 */
object Store {
    private const val PREFS = "levels"
    private const val KEY = "state"
    private const val LOG = "log"
    private const val LOG_MAX = 200

    @Volatile private var cache: JSONObject? = null

    fun state(ctx: Context): JSONObject {
        cache?.let { return it }
        val raw = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        val s = try { if (raw != null) JSONObject(raw) else JSONObject() } catch (_: Exception) { JSONObject() }
        fillDefaults(s)
        cache = s
        return s
    }

    fun save(ctx: Context, s: JSONObject) {
        fillDefaults(s)
        cache = s
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, s.toString()).apply()
    }

    private fun fillDefaults(s: JSONObject) {
        if (!s.has("enabled")) s.put("enabled", true)
        if (!s.has("keyMode")) s.put("keyMode", "remember")
        // Remember became the default: a change made inside an app is kept
        // for next time. Moved once, for stores written before that.
        if (!s.has("km2")) { s.put("keyMode", "remember"); s.put("km2", true) }
        if (!s.has("ramp")) s.put("ramp", true)
        if (!s.has("offer")) s.put("offer", true)
        if (!s.has("offered")) s.put("offered", JSONArray())
        if (!s.has("apps")) s.put("apps", JSONObject())
        if (!s.has("cats")) s.put("cats", JSONObject())
        if (!s.has("custom")) s.put("custom", JSONArray())
        val n = s.optJSONObject("notice") ?: JSONObject().also { s.put("notice", it) }
        if (!n.has("show")) n.put("show", true)
        if (!n.has("side")) n.put("side", "right")
        if (!n.has("y")) n.put("y", 0.38)
        if (!n.has("style")) n.put("style", "detail")
    }

    // ── Activity log ───────────────────────────────────────────────────
    // Written off the main thread: reading and rewriting the whole log on
    // every app switch was work done while the app was opening.
    private val logIo = java.util.concurrent.Executors.newSingleThreadExecutor()

    fun log(ctx: Context, pkg: String, label: String, kind: String, level: Int, why: String) {
        val app = ctx.applicationContext
        logIo.execute { writeLog(app, pkg, label, kind, level, why) }
    }

    private fun writeLog(ctx: Context, pkg: String, label: String, kind: String, level: Int, why: String) {
        val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = try { JSONArray(p.getString(LOG, "[]")) } catch (_: Exception) { JSONArray() }
        arr.put(JSONObject().apply {
            put("t", System.currentTimeMillis())
            put("pkg", pkg); put("label", label); put("kind", kind)
            put("level", level); put("why", why)
        })
        val trimmed = JSONArray()
        val from = maxOf(0, arr.length() - LOG_MAX)
        for (i in from until arr.length()) trimmed.put(arr.get(i))
        p.edit().putString(LOG, trimmed.toString()).apply()
    }

    fun logJson(ctx: Context): String =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(LOG, "[]") ?: "[]"

    fun clearLog(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(LOG, "[]").apply()

    // ── Output device ──────────────────────────────────────────────────
    fun device(ctx: Context): String {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val outs = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        var wired = false
        for (d in outs) {
            when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER -> return "bt"
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_USB_HEADSET -> wired = true
            }
        }
        return if (wired) "wired" else "speaker"
    }

    fun btName(ctx: Context): String? {
        val am = ctx.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP || it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
        }?.productName?.toString()
    }

    // ── Categories ─────────────────────────────────────────────────────
    fun categoryOf(ctx: Context, pkg: String): String? = try {
        val info = ctx.packageManager.getApplicationInfo(pkg, 0)
        when (info.category) {
            ApplicationInfo.CATEGORY_GAME -> "game"
            ApplicationInfo.CATEGORY_VIDEO -> "video"
            ApplicationInfo.CATEGORY_SOCIAL -> "social"
            ApplicationInfo.CATEGORY_AUDIO -> "audio"
            ApplicationInfo.CATEGORY_NEWS -> "news"
            ApplicationInfo.CATEGORY_MAPS -> "maps"
            ApplicationInfo.CATEGORY_IMAGE -> "image"
            ApplicationInfo.CATEGORY_PRODUCTIVITY -> "productivity"
            else -> null
        }
    } catch (_: Exception) { null }

    // ── Resolution: which level, and why ───────────────────────────────
    data class Resolved(val level: Int, val why: String, val keyMode: String, val perApp: Boolean)

    fun resolve(ctx: Context, s: JSONObject, pkg: String): Resolved? {
        val dev = device(ctx)
        val globalKeys = s.optString("keyMode", "remember")
        val now = Now.of(ctx)
        var r: Resolved? = null

        val app = s.optJSONObject("apps")?.optJSONObject(pkg)
        if (app != null && app.optBoolean("on", true)) {
            var level = app.optInt("vol", 50)
            var why = "Own level"
            val rules = app.optJSONArray("rules")
            if (rules != null) for (i in 0 until rules.length()) {
                val rule = rules.optJSONObject(i) ?: continue
                if (matches(rule, dev, now)) {
                    level = rule.optInt("vol", level)
                    why = ruleLabel(rule)
                    break
                }
            }
            val km = app.optString("keyMode", "").ifEmpty { globalKeys }
            r = Resolved(level, why, km, true)
        }

        if (r == null) {
            val custom = s.optJSONArray("custom")
            if (custom != null) for (i in 0 until custom.length()) {
                val c = custom.optJSONObject(i) ?: continue
                if (!c.optBoolean("on", true)) continue
                val apps = c.optJSONArray("apps") ?: continue
                for (j in 0 until apps.length()) if (apps.optString(j) == pkg) {
                    r = Resolved(c.optInt("vol", 50), c.optString("name", "Group"), globalKeys, false)
                    break
                }
                if (r != null) break
            }
        }

        if (r == null) {
            val key = categoryOf(ctx, pkg)
            val cat = if (key != null) s.optJSONObject("cats")?.optJSONObject(key) else null
            if (cat != null && cat.optBoolean("on", false)) {
                r = Resolved(cat.optInt("vol", 50), catName(key!!), globalKeys, false)
            }
        }

        if (r != null && dev != "speaker" && !s.isNull("cap") && s.has("cap")) {
            val cap = s.optInt("cap", 100)
            if (r.level > cap) r = r.copy(level = cap, why = "Headphone limit")
        }
        return r
    }

    /** What a rule can ask about, read once per decision. */
    data class Now(
        val minutes: Int, val day: Int, val charging: Boolean,
        val quiet: Boolean, val lowBattery: Boolean,
    ) {
        companion object {
            fun of(ctx: Context): Now {
                val c = Calendar.getInstance()
                // 1 = Monday ... 7 = Sunday.
                val day = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7 + 1
                val bm = ctx.getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
                val am = ctx.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                val pct = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                return Now(
                    minutes = c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE),
                    day = day,
                    charging = bm.isCharging,
                    quiet = am.ringerMode != android.media.AudioManager.RINGER_MODE_NORMAL,
                    lowBattery = pct in 1..20 && !bm.isCharging,
                )
            }
        }
    }

    /** Every condition a rule names must hold; a rule names at least one. */
    private fun matches(rule: JSONObject, dev: String, now: Now): Boolean {
        val want = rule.optString("device", "any")
        if (want != "any" && want != dev) return false
        val from = rule.optString("from", "")
        val to = rule.optString("to", "")
        if (from.isNotEmpty() && to.isNotEmpty()) {
            val a = mins(from); val b = mins(to)
            val inside = if (a <= b) now.minutes in a until b else now.minutes >= a || now.minutes < b
            if (!inside) return false
        }
        val days = rule.optJSONArray("days")
        if (days != null && days.length() in 1..6) {
            var hit = false
            for (i in 0 until days.length()) if (days.optInt(i) == now.day) hit = true
            if (!hit) return false
        }
        when (rule.optString("when", "")) {
            "charging" -> if (!now.charging) return false
            "quiet" -> if (!now.quiet) return false
            "lowBattery" -> if (!now.lowBattery) return false
        }
        return true
    }

    private fun mins(hm: String): Int {
        val p = hm.split(":")
        return (p.getOrNull(0)?.toIntOrNull() ?: 0) * 60 + (p.getOrNull(1)?.toIntOrNull() ?: 0)
    }

    private fun ruleLabel(rule: JSONObject): String {
        val dev = when (rule.optString("device", "any")) {
            "speaker" -> "Speaker"; "wired" -> "Wired"; "bt" -> "Bluetooth"; else -> null
        }
        val from = rule.optString("from", ""); val to = rule.optString("to", "")
        val time = if (from.isNotEmpty() && to.isNotEmpty()) "$from–$to" else null
        val days = rule.optJSONArray("days")?.let { d ->
            val l = (0 until d.length()).map { d.optInt(it) }.sorted()
            when (l) {
                listOf(1, 2, 3, 4, 5) -> "Weekdays"
                listOf(6, 7) -> "Weekends"
                else -> if (l.isEmpty() || l.size == 7) null else
                    l.joinToString(" ") { listOf("Mon","Tue","Wed","Thu","Fri","Sat","Sun")[it - 1] }
            }
        }
        val cond = when (rule.optString("when", "")) {
            "charging" -> "Charging"; "quiet" -> "Silent mode"; "lowBattery" -> "Low battery"; else -> null
        }
        return listOfNotNull(dev, cond, days, time).joinToString(" · ").ifEmpty { "Rule" }
    }

    /** Paused for a while: once the time is up, Levels is on again. */
    fun active(ctx: Context, s: JSONObject): Boolean {
        if (s.optBoolean("enabled", true)) return true
        val until = s.optLong("pausedUntil", 0L)
        if (until > 0 && System.currentTimeMillis() >= until) {
            s.put("enabled", true); s.remove("pausedUntil")
            save(ctx, s)
            return true
        }
        return false
    }

    fun catName(key: String) = when (key) {
        "game" -> "Games"; "video" -> "Video"; "social" -> "Social"; "audio" -> "Music & audio"
        "news" -> "News"; "maps" -> "Maps"; "image" -> "Photos"; "productivity" -> "Productivity"
        else -> key
    }
}

/** What is happening right now, for the app's Home card. In-process only. */
object Live {
    @Volatile var pkg: String? = null
    @Volatile var label: String? = null
    @Volatile var level: Int = -1
    @Volatile var why: String? = null
    @Volatile var managed: Boolean = false
    @Volatile var baseline: Int = -1

    fun json(): JSONObject = JSONObject().apply {
        put("pkg", pkg ?: JSONObject.NULL)
        put("label", label ?: JSONObject.NULL)
        put("level", level)
        put("why", why ?: JSONObject.NULL)
        put("managed", managed)
        put("baseline", baseline)
    }
}
