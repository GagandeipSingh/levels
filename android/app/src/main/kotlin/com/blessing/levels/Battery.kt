package com.blessing.levels

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings

/**
 * Battery saving can stop the accessibility service, and then every app plays
 * at the user's own level with nothing saying why. Ported from Go Echoo's
 * `Battery.kt`.
 *
 * Two separate switches, and only one is standard:
 *  1. Android's own exemption ([isExempt] / [requestExemption]): readable,
 *     with a real dialog.
 *  2. The phone maker's battery manager ([openOem]): not readable, not
 *     documented, and on Xiaomi, Oppo, Vivo, Huawei and Transsion it is the
 *     one that actually stops the service. We can only open the nearest page.
 *
 * On Vivo the first can still read false after the user said yes, because it
 * is derived from the second. So "still not exempt" must never re-ask in a
 * loop; the Dart side records that it asked once and then offers [openOem].
 */
object Battery {

    fun isExempt(context: Context): Boolean = try {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        pm?.isIgnoringBatteryOptimizations(context.packageName) == true
    } catch (_: Throwable) {
        false
    }

    /** Lowercase maker family with its own battery manager, or empty. */
    fun oemKey(): String = when (Build.MANUFACTURER.lowercase()) {
        "xiaomi", "redmi", "poco", "blackshark" -> "xiaomi"
        "huawei", "honor" -> "huawei"
        "oppo", "realme", "oneplus" -> "oppo"
        "vivo", "iqoo" -> "vivo"
        "samsung" -> "samsung"
        "tecno", "infinix", "itel", "transsion" -> "transsion"
        else -> ""
    }

    @SuppressLint("BatteryLife")
    fun requestExemption(context: Context) {
        if (isExempt(context)) return
        val ask = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:" + context.packageName),
        ).addFlags(Flags.ONE)
        if (!start(context, ask)) {
            start(
                context,
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Flags.ONE),
            ) || openAppInfo(context)
        }
    }

    /** Candidates from AutoStarter and XXPermissions, most specific first. */
    private fun oemCandidates(): List<Pair<String, String>> =
        when (Build.MANUFACTURER.lowercase()) {
            "xiaomi", "redmi", "poco", "blackshark" -> listOf(
                "com.miui.securitycenter" to
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                "com.miui.powerkeeper" to
                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
            )
            "huawei", "honor" -> listOf(
                "com.huawei.systemmanager" to
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                "com.huawei.systemmanager" to
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
            )
            "vivo", "iqoo" -> listOf(
                "com.iqoo.secure" to
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                "com.vivo.permissionmanager" to
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                "com.vivo.abe" to
                    "com.vivo.applicationbehaviorengine.ui.ExcessivePowerManagerActivity",
            )
            "tecno", "infinix", "itel", "transsion" -> listOf(
                "com.transsion.phonemanager" to
                    "com.itel.autobootmanager.activity.AutoBootMgrActivity",
                "com.transsion.phonemanager" to
                    "com.cyin.himgr.autostart.AutoStartActivity",
            )
            else -> emptyList()
        }

    /**
     * Opens the maker's own manager, else Levels' App info (every maker hangs
     * its battery section off that page). Oppo, realme and OnePlus go straight
     * to App info: their real page is unexported (measured on ColorOS 12).
     */
    fun openOem(context: Context): Boolean {
        if (oemKey() == "oppo") return openAppInfo(context)
        for ((pkg, cls) in oemCandidates()) {
            val i = Intent().setComponent(ComponentName(pkg, cls))
                .addFlags(Flags.FRESH)
            if (start(context, i)) return true
        }
        return openAppInfo(context)
    }

    private fun openAppInfo(context: Context): Boolean = start(
        context,
        Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:" + context.packageName),
        ).addFlags(Flags.FRESH),
    )

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }
}
