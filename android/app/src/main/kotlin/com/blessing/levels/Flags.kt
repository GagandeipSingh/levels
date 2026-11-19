package com.blessing.levels

import android.content.Intent

/**
 * Launch flags for Settings pages. Ported from Go Echoo's `GrantReturn`.
 *
 * The Settings task outlives every trip there, with the last page still on
 * top. `NEW_TASK` alone re-uses it, so the battery popup came up over the
 * accessibility page from the trip before: a popup AND a Settings screen.
 * `CLEAR_TASK` empties that task first (safe: it is Settings' task, not ours).
 */
object Flags {
    /** Pages the user may walk deeper from (accessibility list, App info,
     *  the maker's battery page). */
    const val FRESH = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK

    /**
     * One-step pages (the battery popup and its list fallback). `NO_HISTORY`
     * finishes the page once Levels is back, so nothing stale sits behind it.
     */
    const val ONE = FRESH or Intent.FLAG_ACTIVITY_NO_HISTORY
}
