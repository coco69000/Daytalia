package com.parrel.daytalia

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val restartChannel = "daytalia/app_restart"

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, restartChannel).setMethodCallHandler { call, result ->
			when (call.method) {
				"restartApp" -> {
					restartApp()
					result.success(null)
				}
				else -> result.notImplemented()
			}
		}
	}

	private fun restartApp() {
		val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
		if (launchIntent != null) {
			launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)

			val pendingIntentFlags = PendingIntent.FLAG_CANCEL_CURRENT or
				if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

			val pendingIntent = PendingIntent.getActivity(
				this,
				0,
				launchIntent,
				pendingIntentFlags,
			)

			val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
			alarmManager.setExact(
				AlarmManager.RTC,
				System.currentTimeMillis() + 100,
				pendingIntent,
			)
		}

		finishAffinity()
		android.os.Process.killProcess(android.os.Process.myPid())
	}
}
