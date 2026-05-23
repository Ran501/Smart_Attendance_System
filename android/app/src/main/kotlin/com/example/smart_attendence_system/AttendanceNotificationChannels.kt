package com.example.smart_attendence_system

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * Must exist before FCM shows tray notifications when the app is closed.
 * Flutter also creates this channel; native registration covers cold / killed starts.
 */
object AttendanceNotificationChannels {
    const val CHANNEL_ID = "attendance_alerts_v2"
    const val CHANNEL_NAME = "Attendance Alerts"

    fun ensureCreated(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel =
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Live sessions and attendance alerts with sound"
                enableVibration(true)
                enableLights(true)
            }
        manager.createNotificationChannel(channel)
    }
}
