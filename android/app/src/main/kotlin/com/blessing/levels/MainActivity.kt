package com.blessing.levels

import android.content.ComponentName
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.TextUtils
import androidx.core.graphics.drawable.toBitmap
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var pendingExport: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handlePay(intent)
        // Edge to edge, as in Breeze: bars visible and transparent.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        @Suppress("DEPRECATION")
        window.statusBarColor = Color.TRANSPARENT
        @Suppress("DEPRECATION")
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onPostResume() {
        super.onPostResume()
        // Flutter's PlatformPlugin rewrites the decor flags on every resume to
        // LAYOUT_STABLE | LAYOUT_FULLSCREEN, dropping LAYOUT_HIDE_NAVIGATION
        // below Android 10 (its edge-to-edge mode returns early there). The
        // app then stopped above an opaque white navigation bar. Put it back.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val decor = window.decorView
            @Suppress("DEPRECATION")
            decor.systemUiVisibility = decor.systemUiVisibility or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            // Then ask for the insets again once the window is laid out.
            // Below Android 11 Flutter guesses "keyboard" when the bottom
            // inset is 18% or more of the root view height, and on the
            // first pass that height is still 0: the 48 dp nav bar reads
            // as a keyboard and the Scaffold shrinks, clipping the page
            // above an empty strip. Light mode hid it (setting the light
            // nav-icon flag re-sends the insets); dark kept the wrong value.
            decor.post { decor.requestApplyInsets() }
        }
    }

    private var channel: MethodChannel? = null

    // While Levels is on screen, a volume change (the buttons, the shade)
    // reaches the dial at once rather than at the next poll.
    private val volReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(c: android.content.Context, i: Intent) {
            channel?.invokeMethod("volumeChanged", null)
        }
    }

    override fun onResume() {
        super.onResume()
        PayShortcut.refresh(this)
        KnobWidget.refresh(this)
        // Notifications allowed in Settings meanwhile: show the entry now.
        if (PayNote.canPost(this)) LevelsService.instance?.let { PayNote.refresh(it) }
        val f = android.content.IntentFilter("android.media.VOLUME_CHANGED_ACTION")
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(volReceiver, f, RECEIVER_EXPORTED)
        else registerReceiver(volReceiver, f)
    }

    override fun onPause() {
        try { unregisterReceiver(volReceiver) } catch (_: Exception) {}
        super.onPause()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "levels")
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getState" -> result.success(Store.state(this).toString())
                "setState" -> {
                    Store.save(this, JSONObject(call.arguments as String))
                    LevelsService.instance?.reapply()
                    LevelsTileRefresh.request(this)
                    result.success(null)
                }
                "status" -> result.success(JSONObject().apply {
                    put("service", serviceOn())
                    put("connected", LevelsService.instance != null)
                    put("device", Store.device(this@MainActivity))
                    put("bt", Store.btName(this@MainActivity) ?: JSONObject.NULL)
                    // The real media volume, not a copy: the buttons change it
                    // in apps Levels does not manage too.
                    put("live", Live.json().apply {
                        val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
                        val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                            .coerceAtLeast(1)
                        put("level", Math.round(
                            am.getStreamVolume(android.media.AudioManager.STREAM_MUSIC) * 100f / max))
                    })
                    put("battery", Battery.isExempt(this@MainActivity))
                    put("oem", Battery.oemKey())
                    put("notif", PayNote.canPost(this@MainActivity))
                    put("paidPause", getSharedPreferences("levels", MODE_PRIVATE)
                        .getBoolean("paid_pause", false))
                }.toString())
                "apps" -> io.execute {
                    val out = listApps()
                    runOnUiThread { result.success(out) }
                }
                "icon" -> io.execute {
                    val bytes = icon(call.arguments as String)
                    runOnUiThread { result.success(bytes) }
                }
                "openA11y" -> {
                    // Remember that we sent the user there, so the service can
                    // bring Levels back the moment the switch is turned on.
                    getSharedPreferences("levels", MODE_PRIVATE).edit()
                        .putLong("a11y_sent_at", System.currentTimeMillis()).apply()
                    startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            .addFlags(Flags.FRESH)
                    )
                    result.success(null)
                }
                "volume" -> {
                    // The Home dial: the media volume now, through the
                    // service when it runs so it does not read as a key press.
                    val v = (call.arguments as Int).coerceIn(0, 100)
                    val svc = LevelsService.instance
                    if (svc != null) svc.setLevel(v, smooth = false)
                    else {
                        val am = getSystemService(AUDIO_SERVICE) as android.media.AudioManager
                        val max = am.getStreamMaxVolume(android.media.AudioManager.STREAM_MUSIC)
                        am.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, Math.round(v * max / 100f), 0)
                    }
                    Live.level = v
                    result.success(null)
                }
                "payPause" -> {
                    val svc = LevelsService.instance
                    if (svc == null) result.success(false)
                    else { svc.pauseForPayment(); result.success(true) }
                }
                "appInfo" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            .addFlags(Flags.FRESH)
                    )
                    result.success(null)
                }
                "batteryAsk" -> { Battery.requestExemption(this); result.success(null) }
                "batteryOem" -> result.success(Battery.openOem(this))
                // The 1x1 knob widget: Levels on or off in one tap, from
                // the home screen. False when the launcher cannot pin.
                "pinWidget" -> {
                    var ok = false
                    if (Build.VERSION.SDK_INT >= 26) try {
                        val mgr = android.appwidget.AppWidgetManager.getInstance(this)
                        if (mgr.isRequestPinAppWidgetSupported) {
                            ok = mgr.requestPinAppWidget(
                                ComponentName(this, KnobWidget::class.java), null, null)
                        }
                    } catch (_: Exception) {}
                    result.success(ok)
                }
                "pinPay" -> {
                    // A real "Paying" icon on the home screen: the manifest
                    // shortcut "pay", pinned. Found where the user looks,
                    // unlike the long-press menu.
                    var ok = false
                    if (Build.VERSION.SDK_INT >= 26) try {
                        val sm = getSystemService(android.content.pm.ShortcutManager::class.java)
                        if (sm.isRequestPinShortcutSupported) {
                            ok = sm.requestPinShortcut(
                                PayShortcut.build(this)!!, null)
                        }
                    } catch (_: Exception) {}
                    result.success(ok)
                }
                "addTile" -> {
                    if (Build.VERSION.SDK_INT >= 33) {
                        val sbm = getSystemService(android.app.StatusBarManager::class.java)
                        sbm.requestAddTileService(
                            ComponentName(this, LevelsTile::class.java),
                            getString(R.string.tile_label),
                            android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_tile),
                            mainExecutor,
                        ) { code -> result.success(code == android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                            code == android.app.StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED) }
                    } else result.success(false)
                }
                // The Pause for a payment button lives in Levels' notification,
                // which Android 13+ shows only once notifications are allowed.
                "notifOk" -> result.success(PayNote.canPost(this))
                "askNotif" -> {
                    if (PayNote.canPost(this)) { result.success(true) }
                    else if (Build.VERSION.SDK_INT >= 33 &&
                        !getSharedPreferences("levels", MODE_PRIVATE).getBoolean("notif_asked", false) ||
                        Build.VERSION.SDK_INT >= 33 &&
                        shouldShowRequestPermissionRationale(android.Manifest.permission.POST_NOTIFICATIONS)) {
                        getSharedPreferences("levels", MODE_PRIVATE).edit()
                            .putBoolean("notif_asked", true).apply()
                        notifResult = result
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 43)
                    } else {
                        // Refused for good: Android ignores repeat asks, so
                        // open Levels' notification settings instead.
                        try {
                            startActivity(
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                    .addFlags(Flags.FRESH)
                            )
                        } catch (_: Exception) {}
                        result.success(false)
                    }
                }
                "log" -> result.success(Store.logJson(this))
                "clearLog" -> { Store.clearLog(this); result.success(null) }
                "export" -> {
                    pending = result
                    pendingExport = Store.state(this).toString(2)
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, "levels-backup.json")
                    }, 41)
                }
                "import" -> {
                    pending = result
                    @Suppress("DEPRECATION")
                    startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                    }, 42)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handlePay(intent)
    }

    /**
     * The "Paying" shortcut opens Levels itself (a real screen, no invisible
     * window). On: Levels steps aside and Home says so. Off: Home shows
     * where things stand with a Turn back on button; nothing else opens.
     */
    private fun handlePay(i: Intent?) {
        when (i?.action) {
            "com.blessing.levels.PAY" -> {
                i.action = Intent.ACTION_MAIN
                LevelsService.instance?.pauseForPayment()
            }
            // "Turn back on" from the paused note: straight to the switch,
            // and the service brings Levels back once it is on.
            PayNote.ACTION_TURN_ON -> {
                i.action = Intent.ACTION_MAIN
                if (LevelsService.instance != null) return
                getSharedPreferences("levels", MODE_PRIVATE).edit()
                    .putLong("a11y_sent_at", System.currentTimeMillis()).apply()
                try {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Flags.FRESH))
                } catch (_: Exception) {}
            }
        }
    }

    private var notifResult: MethodChannel.Result? = null

    override fun onRequestPermissionsResult(code: Int, perms: Array<out String>, res: IntArray) {
        super.onRequestPermissionsResult(code, perms, res)
        if (code != 43) return
        val ok = PayNote.canPost(this)
        // Allowed while Levels runs: the entry goes up at once.
        if (ok) LevelsService.instance?.let { PayNote.start(it) }
        notifResult?.success(ok)
        notifResult = null
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        val r = pending ?: return
        pending = null
        val uri: Uri? = data?.data
        if (resultCode != RESULT_OK || uri == null) { r.success(null); return }
        try {
            when (requestCode) {
                41 -> {
                    contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write((pendingExport ?: "{}").toByteArray())
                    }
                    r.success("saved")
                }
                42 -> {
                    val text = contentResolver.openInputStream(uri)?.use { it.readBytes().decodeToString() } ?: ""
                    val parsed = JSONObject(text)
                    if (!parsed.has("apps")) { r.success("invalid"); return }
                    r.success(text)
                }
                else -> r.success(null)
            }
        } catch (_: Exception) {
            r.success("invalid")
        }
    }

    private fun serviceOn(): Boolean {
        val want = ComponentName(this, LevelsService::class.java).flattenToString()
        val list = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val split = TextUtils.SimpleStringSplitter(':')
        split.setString(list)
        for (s in split) if (s.equals(want, ignoreCase = true)) return true
        return false
    }

    private fun listApps(): String {
        val pm = packageManager
        val launch = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val seen = HashSet<String>()
        val arr = JSONArray()
        for (ri in pm.queryIntentActivities(launch, 0)) {
            val pkg = ri.activityInfo.packageName
            if (pkg == packageName || !seen.add(pkg)) continue
            arr.put(JSONObject().apply {
                put("pkg", pkg)
                put("label", ri.loadLabel(pm).toString())
                put("cat", Store.categoryOf(this@MainActivity, pkg) ?: JSONObject.NULL)
            })
        }
        return arr.toString()
    }

    private fun icon(pkg: String): ByteArray? = try {
        val bmp = packageManager.getApplicationIcon(pkg).toBitmap(108, 108)
        ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    } catch (_: Exception) { null }
}
