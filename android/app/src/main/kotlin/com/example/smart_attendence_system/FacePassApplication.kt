package com.example.smart_attendence_system

import android.app.Application

class FacePassApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AttendanceNotificationChannels.ensureCreated(this)
    }
}
