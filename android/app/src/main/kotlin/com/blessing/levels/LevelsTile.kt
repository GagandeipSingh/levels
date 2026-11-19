package com.blessing.levels

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import java.text.DateFormat
import java.util.Date

/** Pause or resume Levels from the shade. A pause lasts as long as the
 *  user chose in the app ("pauseFor", minutes; 0 = until turned back on),
 *  and the tile says what is happening: on, paused until when, or what the
 *  app in front is playing at. */
class LevelsTile : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        val s = Store.state(this)
        if (Store.active(this, s)) {
            s.put("enabled", false)
            val mins = s.optInt("pauseFor", 0)
            if (mins > 0) s.put("pausedUntil", System.currentTimeMillis() + mins * 60_000L)
            else s.remove("pausedUntil")
        } else {
            s.put("enabled", true); s.remove("pausedUntil")
        }
        Store.save(this, s)
        LevelsService.instance?.reapply()
        refresh()
    }

    private fun refresh() {
        val t = qsTile ?: return
        val serviceOn = LevelsService.instance != null
        val s = Store.state(this)
        val on = Store.active(this, s) && serviceOn
        t.state = if (on) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        t.label = getString(R.string.tile_label)
        if (android.os.Build.VERSION.SDK_INT >= 29) {
            val until = s.optLong("pausedUntil", 0L)
            t.subtitle = when {
                !serviceOn -> "Needs setup"
                !on && until > 0 ->
                    "Paused till " + DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(until))
                !on -> "Paused"
                Live.managed && Live.label != null -> "${Live.label} ${Live.level}%"
                else -> "On"
            }
        }
        t.updateTile()
    }
}

/** Ask the system to redraw the tile after a change made elsewhere. */
object LevelsTileRefresh {
    fun request(ctx: Context) {
        try {
            TileService.requestListeningState(ctx, ComponentName(ctx, LevelsTile::class.java))
        } catch (_: Exception) {}
    }
}
