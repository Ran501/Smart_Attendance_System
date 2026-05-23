package com.example.smart_attendence_system

import io.flutter.embedding.android.FlutterApplication

class FacePassApplication : FlutterApplication() {
    override fun onCreate() {
        super.onCreate()
        AttendanceNotificationChannels.ensureCreated(this)
    }
}
