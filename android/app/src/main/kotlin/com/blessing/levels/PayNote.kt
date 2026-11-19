package com.blessing.levels

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Paying with a bank app, the way Go Echoo does it.
 *
 * Google Pay, PhonePe, Paytm and many banks refuse payments while any
 * accessibility switch is on, and Levels needs one. So the way out lives
 * where the user already looks, in the shade:
 *
 *  - **While Levels is on**, its notification carries "Pause for a payment".
 *    One tap switches Levels off with a broadcast, so nothing is opened over
 *    the payment. The notification is a foreground one and COLORIZED in the
 *    app's own background, so it looks like Levels and sits at the top of
 *    the shade instead of under whatever arrived later.
 *  - **Once it is off for a payment** (the button, or the user switching it
 *    off in Settings, which is where a bank's block screen sends them), a
 *    note says so and is the way back: "tap to turn Levels back on", and a
 *    restart if the bank still refuses.
 *  - **After a restart** the note comes back ONCE. A restart is what Google
 *    Pay asks for, it wipes the shade, and it is exactly when the user has
 *    just paid.
 *  - **Turning it back on** clears all of it.
 */
object PayNote {

    const val ACTION_PAUSE = "com.blessing.levels.PAUSE_FOR_PAYMENT"
    const val ACTION_TURN_ON = "com.blessing.levels.TURN_ON"

    private const val CH_ON = "levels_on"
    private const val CH_PAUSED = "levels_paused"
    const val ID_ON = 1
    private const val ID_PAUSED = 2

    private const val PREFS = "levels"
    private const val KEY_PAUSED = "paid_pause"
    private const val KEY_BOOT_REMINDED = "paid_boot_reminded"

    /** The app's own background (lib/ui/kit.dart, Pal.bg) for the phone's
     *  mode, so the entry looks like Levels itself. */
    private fun fill(ctx: Context): Int {
        val night = ctx.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        return if (night) 0xFF001219.toInt() else 0xFFF5F3EE.toInt()
    }

    private fun channels(ctx: Context, nm: NotificationManager) {
        if (Build.VERSION.SDK_INT < 26) return
        // DEFAULT, not LOW: LOW lands in the Silent section, out of sight.
        // No sound, no vibration, no badge: it never interrupts anyone.
        nm.createNotificationChannel(
            NotificationChannel(CH_ON, "Levels is on", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Shows while Levels sets volumes, with a pause for payments"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_PAUSED, "Paused for a payment", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "The way to turn Levels back on after you pay"
                setShowBadge(false)
                setSound(null, null)
                enableVibration(false)
            },
        )
    }

    private fun openApp(ctx: Context, code: Int, action: String? = null) = PendingIntent.getActivity(
        ctx,
        code,
        Intent(ctx, MainActivity::class.java).apply {
            if (action != null) this.action = action
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        },
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /** The entry shown while Levels runs. */
    fun running(ctx: Context): Notification {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (nm != null) channels(ctx, nm)
        val pause = PendingIntent.getBroadcast(
            ctx,
            3,
            Intent(ctx, Receiver::class.java).setAction(ACTION_PAUSE).setPackage(ctx.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(ctx, CH_ON)
            .setSmallIcon(R.drawable.ic_tile)
            .setContentTitle("Levels is on")
            .setContentText("Paying with a bank app? Pause Levels first.")
            .addAction(R.drawable.ic_tile, "Pause for a payment", pause)
            .setContentIntent(openApp(ctx, 1))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setColor(fill(ctx))
            .setColorized(true)
            .setOngoing(true)
            .build()
    }

    /** Called from the service's connect: go foreground with [running]. */
    fun start(svc: LevelsService) {
        cancelPaused(svc)
        clear(svc)
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                svc.startForeground(ID_ON, running(svc), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                svc.startForeground(ID_ON, running(svc))
            }
        } catch (_: Throwable) {
            // Refused as a foreground entry: still post it, only uncolored.
            try {
                svc.getSystemService(NotificationManager::class.java)?.notify(ID_ON, running(svc))
            } catch (_: Throwable) {}
        }
    }

    /** Day/night switched: re-post so the background follows the mode. */
    fun refresh(ctx: Context) {
        try {
            ctx.getSystemService(NotificationManager::class.java)?.notify(ID_ON, running(ctx))
        } catch (_: Throwable) {}
    }

    /**
     * Called from the service's destroy. [fromSettings] is true when the last
     * app on screen was Settings: a switch-off there counts as for a payment,
     * since that is where a bank's block screen sends the user.
     */
    fun stopped(svc: LevelsService, fromSettings: Boolean) {
        try {
            if (Build.VERSION.SDK_INT >= 24) svc.stopForeground(android.app.Service.STOP_FOREGROUND_REMOVE)
            else @Suppress("DEPRECATION") svc.stopForeground(true)
        } catch (_: Throwable) {}
        try {
            svc.getSystemService(NotificationManager::class.java)?.cancel(ID_ON)
        } catch (_: Throwable) {}
        val paused = isPaused(svc)
        if (!paused && !fromSettings) return
        if (!paused) prefs(svc).edit().putBoolean(KEY_PAUSED, true).apply()
        postPaused(svc, paused)
    }

    fun isPaused(ctx: Context) = try {
        prefs(ctx).getBoolean(KEY_PAUSED, false)
    } catch (_: Throwable) { false }

    /** Mark the pause BEFORE the switch goes off: destroy reads it. */
    fun markPaused(ctx: Context) {
        try {
            prefs(ctx).edit()
                .putBoolean(KEY_PAUSED, true)
                .putBoolean(KEY_BOOT_REMINDED, false)
                .commit()
        } catch (_: Throwable) {}
    }

    private fun clear(ctx: Context) {
        try {
            prefs(ctx).edit()
                .putBoolean(KEY_PAUSED, false)
                .putBoolean(KEY_BOOT_REMINDED, false)
                .apply()
        } catch (_: Throwable) {}
    }

    private fun postPaused(ctx: Context, byButton: Boolean) {
        if (!canPost(ctx)) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        channels(ctx, nm)
        val text = "Pay now. If the app still says no, restart your phone. " +
            "Tap here to turn Levels back on when you are done."
        val n = NotificationCompat.Builder(ctx, CH_PAUSED)
            .setSmallIcon(R.drawable.ic_tile)
            .setContentTitle(if (byButton) "Levels is paused for your payment" else "Levels is off")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .addAction(R.drawable.ic_tile, "Turn back on", openApp(ctx, 5, ACTION_TURN_ON))
            .setContentIntent(openApp(ctx, 4, ACTION_TURN_ON))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setColor(fill(ctx))
            // Swipeable: an undismissable nag is a dark pattern.
            .setOngoing(false)
            .setAutoCancel(true)
            .build()
        try { nm.notify(ID_PAUSED, n) } catch (_: Throwable) {}
    }

    private fun cancelPaused(ctx: Context) {
        try { ctx.getSystemService(NotificationManager::class.java)?.cancel(ID_PAUSED) } catch (_: Throwable) {}
    }

    /** Android 13+ gates delivery on POST_NOTIFICATIONS. */
    fun canPost(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 33) return true
        return ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun prefs(ctx: Context) =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun serviceEnabled(ctx: Context): Boolean = try {
        val want = ComponentName(ctx, LevelsService::class.java).flattenToString()
        val list = Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
        if (list == null) false else {
            val split = TextUtils.SimpleStringSplitter(':')
            split.setString(list)
            split.any { it.equals(want, ignoreCase = true) }
        }
    } catch (_: Throwable) {
        // Unknown: claim it is on, so no note is posted on a guess.
        true
    }

    /**
     *  - [ACTION_PAUSE] from the notification's button: a broadcast, so
     *    nothing is dragged over the payment.
     *  - BOOT_COMPLETED / MY_PACKAGE_REPLACED: the restart wiped the note.
     *    Re-post it ONCE, and only while it is still true.
     */
    class Receiver : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_PAUSE -> {
                    val svc = LevelsService.instance
                    val msg = if (svc != null) {
                        svc.pauseForPayment()
                        "Levels is off. Pay now, then turn it back on."
                    } else {
                        "Levels is already off."
                    }
                    try { Toast.makeText(ctx, msg, Toast.LENGTH_LONG).show() } catch (_: Throwable) {}
                }
                Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                    try {
                        if (!isPaused(ctx)) return
                        if (serviceEnabled(ctx)) return
                        val p = prefs(ctx)
                        if (p.getBoolean(KEY_BOOT_REMINDED, false)) return
                        p.edit().putBoolean(KEY_BOOT_REMINDED, true).apply()
                        postPaused(ctx, true)
                    } catch (_: Throwable) {}
                }
            }
        }
    }
}

/** Redraw what shows Levels' state outside the app. */
object PayRefresh {
    fun request(ctx: Context) {
        PayShortcut.refresh(ctx)
        KnobWidget.refresh(ctx)
    }
}

/**
 * The pinned home-screen icon follows the real state: "Levels on" with a
 * pause while Levels runs, "Levels off" once it has stepped aside. A dynamic
 * shortcut ([ID]) because a manifest shortcut's icon cannot change once
 * pinned.
 */
object PayShortcut {
    const val ID = "pay_live"

    fun build(ctx: Context): android.content.pm.ShortcutInfo? {
        if (Build.VERSION.SDK_INT < 26) return null
        val on = LevelsService.instance != null
        val label = ctx.getString(if (on) R.string.shortcut_on_label else R.string.shortcut_off_label)
        val intent = Intent("com.blessing.levels.PAY")
            .setClassName(ctx, MainActivity::class.java.name)
        return android.content.pm.ShortcutInfo.Builder(ctx, ID)
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(android.graphics.drawable.Icon.createWithResource(
                ctx, if (on) R.drawable.ic_shortcut_pay else R.drawable.ic_shortcut_paid))
            .setIntent(intent)
            .build()
    }

    fun refresh(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        try {
            val sm = ctx.getSystemService(android.content.pm.ShortcutManager::class.java)
            build(ctx)?.let { sm.addDynamicShortcuts(listOf(it)) }
        } catch (_: Exception) {}
    }
}
