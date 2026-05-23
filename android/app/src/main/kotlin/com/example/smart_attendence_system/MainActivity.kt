package com.example.smart_attendence_system

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        AttendanceNotificationChannels.ensureCreated(this)
        super.onCreate(savedInstanceState)
    }
}
