package com.exaltedcoding.exalted

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Starts the app again after an uncaught crash in the Android (Kotlin/Java)
 * code, when startup.autoRestart is true in config.json. Stops after
 * maxRestartsPerHour restarts in one hour, so a crash loop cannot spin.
 * Native engine crashes never reach this handler.
 */
object CrashRestart {
    private const val PREFS = "crash_restart"
    private const val KEY_TIMES = "times"
    private const val WINDOW_MS = 60L * 60L * 1000L
    private const val MAX_LOG_BYTES = 200L * 1024L

    @Volatile
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            var restarted = false
            try {
                writeLog(app, thread, error)
                restarted = tryRestart(app)
            } catch (_: Throwable) {
            }
            if (restarted) {
                android.os.Process.killProcess(android.os.Process.myPid())
                kotlin.system.exitProcess(10)
            } else {
                previous?.uncaughtException(thread, error)
            }
        }
    }

    private fun writeLog(app: Context, thread: Thread, error: Throwable) {
        val f = File(app.filesDir, "crash.log")
        if (f.exists() && f.length() > MAX_LOG_BYTES) f.delete()
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        val trace = error.stackTraceToString().lines().take(40).joinToString("\n")
        f.appendText("[${fmt.format(Date())}] android-native (${thread.name})\n$error\n$trace\n\n")
    }

    private fun readSettings(app: Context): Pair<Boolean, Int> {
        return try {
            val f = File(app.filesDir, "config.json")
            if (!f.exists()) return Pair(false, 3)
            val startup = JSONObject(f.readText()).optJSONObject("startup")
                ?: return Pair(false, 3)
            val max = startup.optInt("maxRestartsPerHour", 3).coerceIn(1, 20)
            Pair(startup.optBoolean("autoRestart", false), max)
        } catch (_: Throwable) {
            Pair(false, 3)
        }
    }

    private fun tryRestart(app: Context): Boolean {
        val (enabled, max) = readSettings(app)
        if (!enabled) return false
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val now = System.currentTimeMillis()
        val recent = (prefs.getString(KEY_TIMES, "") ?: "")
            .split(",")
            .mapNotNull { it.toLongOrNull() }
            .filter { now - it < WINDOW_MS }
        if (recent.size >= max) return false
        val intent = app.packageManager.getLaunchIntentForPackage(app.packageName)
            ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        prefs.edit().putString(KEY_TIMES, (recent + now).joinToString(",")).commit()
        app.startActivity(intent)
        return true
    }
}
