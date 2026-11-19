package com.blessing.levels

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * A 1x1 home-screen knob. A widget, not a pinned shortcut, because the
 * launcher badges every shortcut with the app icon and an app cannot turn
 * that off. Same look and tap as the shortcut: on, the tap switches Levels
 * off; off, it opens Levels to turn it back on.
 */
class KnobWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        draw(ctx, mgr, ids)
    }

    companion object {
        fun refresh(ctx: Context) {
            try {
                val mgr = AppWidgetManager.getInstance(ctx)
                val ids = mgr.getAppWidgetIds(ComponentName(ctx, KnobWidget::class.java))
                if (ids.isNotEmpty()) draw(ctx, mgr, ids)
            } catch (_: Exception) {}
        }

        private fun draw(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
            val on = LevelsService.instance != null
            val tap = PendingIntent.getActivity(
                ctx, 11,
                Intent("com.blessing.levels.PAY").setClassName(ctx, MainActivity::class.java.name)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val v = RemoteViews(ctx.packageName, R.layout.widget_knob).apply {
                setImageViewResource(R.id.widget_knob,
                    if (on) R.drawable.ic_shortcut_pay_fg else R.drawable.ic_shortcut_paid_fg)
                setContentDescription(R.id.widget_knob,
                    ctx.getString(if (on) R.string.shortcut_on_label else R.string.shortcut_off_label))
                setOnClickPendingIntent(R.id.widget_root, tap)
            }
            mgr.updateAppWidget(ids, v)
        }
    }
}
