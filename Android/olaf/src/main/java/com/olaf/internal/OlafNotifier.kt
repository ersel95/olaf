package com.olaf.internal

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import com.olaf.LogCategory
import com.olaf.LogEntry
import com.olaf.R
import java.util.concurrent.atomic.AtomicInteger

/**
 * Surfaces captured traffic in the notification shade, so the viewer is one tap away.
 *
 * Shaking is the primary gesture, but it is awkward on an emulator and impossible while the device
 * is on a desk — this is the always-available route in. It also adds a launcher shortcut, so the
 * viewer can be opened from the app icon without the host wiring up a button.
 *
 * Everything here degrades quietly: no permission, no channel, no notification — capture and the
 * viewer keep working regardless.
 */
internal class OlafNotifier(context: Context) {

    private val appContext = context.applicationContext
    private val manager = appContext.getSystemService(NotificationManager::class.java)

    /** The most recent captures, newest first — the notification shows a few of them. */
    private val recent = ArrayDeque<String>()
    private val captureCount = AtomicInteger()

    init {
        createChannel()
        createShortcut()
    }

    fun onEntry(entry: LogEntry) {
        // Only network records: an app log line in the shade would be noise, not a signal.
        if (entry.category != LogCategory.Network) return
        if (!canNotify()) return

        synchronized(recent) {
            recent.addFirst(entry.message)
            while (recent.size > MAX_LINES) recent.removeLast()
        }
        val total = captureCount.incrementAndGet()

        runCatching { manager?.notify(NOTIFICATION_ID, buildNotification(total)) }
    }

    /** Clears the notification — called when the viewer opens, since it has been seen. */
    fun dismiss() {
        runCatching { manager?.cancel(NOTIFICATION_ID) }
        captureCount.set(0)
        synchronized(recent) { recent.clear() }
    }

    private fun buildNotification(total: Int): Notification {
        val lines = synchronized(recent) { recent.toList() }

        val style = Notification.InboxStyle()
        lines.forEach(style::addLine)

        return Notification.Builder(appContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Olaf — $total request${if (total == 1) "" else "s"}")
            .setContentText(lines.firstOrNull().orEmpty())
            .setStyle(style)
            .setContentIntent(viewerIntent())
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setLocalOnly(true)
            .build()
    }

    private fun viewerIntent(): PendingIntent = PendingIntent.getActivity(
        appContext,
        0,
        viewerLaunchIntent(appContext),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )

    private fun createChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Olaf network capture",
            // LOW: informative, never a heads-up interruption while debugging.
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Captured requests, with a shortcut into the Olaf viewer."
            setShowBadge(false)
        }
        runCatching { manager?.createNotificationChannel(channel) }
    }

    /** Long-pressing the app icon offers "Olaf" — no host code required. */
    private fun createShortcut() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return
        val shortcutManager = appContext.getSystemService(ShortcutManager::class.java) ?: return

        val shortcut = ShortcutInfo.Builder(appContext, SHORTCUT_ID)
            .setShortLabel("Olaf")
            .setLongLabel("Open the Olaf viewer")
            .setIcon(Icon.createWithResource(appContext, R.drawable.olaf_logo))
            .setIntent(viewerLaunchIntent(appContext).setAction(Intent.ACTION_VIEW))
            .build()

        runCatching { shortcutManager.addDynamicShortcuts(listOf(shortcut)) }
    }

    private fun canNotify(): Boolean {
        if (manager?.areNotificationsEnabled() != true) return false
        // Android 13+ needs the runtime permission; asking for it is the host's call, so if it
        // hasn't been granted we simply stay quiet.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return appContext.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    companion object {
        private const val CHANNEL_ID = "olaf.capture"
        private const val SHORTCUT_ID = "olaf.viewer"
        private const val NOTIFICATION_ID = 0x01AF
        private const val MAX_LINES = 5

        /**
         * Intent that opens the viewer in its own task, so it can sit side by side with the host
         * app in split screen instead of replacing it.
         */
        fun viewerLaunchIntent(context: Context): Intent =
            Intent().setClassName(context, "com.olaf.ui.presentation.OlafViewerActivity")
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or
                        Intent.FLAG_ACTIVITY_RETAIN_IN_RECENTS
                )
    }
}
