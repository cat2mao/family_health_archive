import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// Callback for notification tap navigation.
  /// Set this in main.dart after router is available.
  static void Function(String? payload)? onNotificationTap;

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    // Only clear corrupted notification data once (first run after install/update)
    await _clearCorruptedNotificationDataIfNeeded();

    // Create notification channel for Android with max importance
    const androidChannel = AndroidNotificationChannel(
      'reminder_channel',
      '提醒通知',
      description: '用药、复查等提醒通知',
      importance: Importance.max, // Max for heads-up on HyperOS/Xiaomi
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification tapped: ${details.payload}');
        onNotificationTap?.call(details.payload);
      },
    );

    _initialized = true;

    // Request permissions
    await requestPermissions();
  }

  /// Clear corrupted notification data only once (flagged in SharedPreferences)
  static Future<void> _clearCorruptedNotificationDataIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyCleared = prefs.getBool('notification_data_cleared_v2') ?? false;
      if (alreadyCleared) return;

      final keys = prefs.getKeys();
      final notificationKeys = keys.where(
        (key) => key.contains('flutter_local_notifications'),
      );
      for (final key in notificationKeys) {
        debugPrint('Clearing notification preference: $key');
        await prefs.remove(key);
      }
      await prefs.setBool('notification_data_cleared_v2', true);
      debugPrint('Notification data corruption cleanup completed (one-time)');
    } catch (e) {
      debugPrint('Error clearing notification data: $e');
    }
  }

  /// Request notification, alarm, and battery optimization permissions
  static Future<bool> requestPermissions() async {
    bool allGranted = true;

    if (Platform.isAndroid) {
      // Request POST_NOTIFICATIONS permission (Android 13+)
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          debugPrint('POST_NOTIFICATIONS permission denied');
          allGranted = false;
        }
      }

      // Request SCHEDULE_EXACT_ALARM permission (Android 12+)
      final alarmStatus = await Permission.scheduleExactAlarm.status;
      debugPrint('Schedule exact alarm status: $alarmStatus');
      if (!alarmStatus.isGranted) {
        try {
          final result = await Permission.scheduleExactAlarm.request();
          debugPrint('Schedule exact alarm request result: $result');
          if (!result.isGranted) {
            debugPrint('SCHEDULE_EXACT_ALARM permission denied');
            allGranted = false;
          }
        } catch (e) {
          debugPrint('Error requesting schedule exact alarm permission: $e');
          allGranted = false;
        }
      }

      // Request ignore battery optimization (critical for Xiaomi/HyperOS)
      try {
        final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
        if (!batteryStatus.isGranted) {
          await Permission.ignoreBatteryOptimizations.request();
        }
      } catch (e) {
        debugPrint('Battery optimization request failed: $e');
      }
    }

    return allGranted;
  }

  /// Check if notification permissions are granted
  static Future<bool> arePermissionsGranted() async {
    if (!Platform.isAndroid) return true;
    final notifGranted = await Permission.notification.isGranted;
    final alarmGranted = await Permission.scheduleExactAlarm.isGranted;
    debugPrint('Notification: $notifGranted, Alarm: $alarmGranted');
    return notifGranted && alarmGranted;
  }

  /// Detect if device is Xiaomi/HyperOS and guide user to enable required settings
  static bool isXiaomiDevice() {
    if (!Platform.isAndroid) return false;
    // Xiaomi devices have ro.miui.ui.version in system properties
    // We use a heuristic: check if the manufacturer contains "Xiaomi"
    return true; // Simplified; always show the guide on Android
  }

  /// Show a dialog guiding user to enable Xiaomi-specific permissions
  static Future<void> showXiaomiPermissionGuide(BuildContext context) async {
    if (!Platform.isAndroid) return;
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('通知权限设置指南'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('为确保通知正常显示，请检查以下设置：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 12),
              Text('1. 自启动'),
              Text('   设置 > 应用设置 > 应用管理 > 家庭健康档案 > 自启动（开启）',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              SizedBox(height: 8),
              Text('2. 通知权限'),
              Text('   设置 > 通知管理 > 家庭健康档案 > 允许通知 + 悬浮通知（开启）',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              SizedBox(height: 8),
              Text('3. 电池优化'),
              Text('   设置 > 电池 > 电池优化 > 家庭健康档案 > 无限制',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('打开系统设置'),
          ),
        ],
      ),
    );
  }

  /// Schedule a one-time notification. Returns true on success.
  static Future<bool> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    if (!await arePermissionsGranted()) {
      await requestPermissions();
    }

    final now = DateTime.now();
    if (scheduledTime.isBefore(now)) {
      await showNow(id: id, title: title, body: body);
      return true;
    }

    final androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '提醒通知',
      channelDescription: '用药、复查等提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF2A9D8F),
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: title,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      usesChronometer: false,
      onlyAlertOnce: false,
      autoCancel: true,
    );

    final scheduledDate = tz.TZDateTime.from(scheduledTime, tz.local);
    debugPrint('Scheduling notification $id at $scheduledDate');

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('Scheduled exact notification $id');
      return true;
    } catch (e) {
      debugPrint('Failed exact schedule: $e');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
        debugPrint('Scheduled inexact notification $id');
        return true;
      } catch (e2) {
        debugPrint('Failed inexact schedule: $e2');
        // Last resort: try alarmClock mode for best reliability on Xiaomi
        try {
          final alarmDetails = AndroidNotificationDetails(
            'reminder_channel',
            '提醒通知',
            channelDescription: '用药、复查等提醒通知',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: const Color(0xFF2A9D8F),
            fullScreenIntent: false,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            showWhen: true,
            when: DateTime.now().millisecondsSinceEpoch,
            onlyAlertOnce: false,
            autoCancel: true,
          );
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            scheduledDate,
            NotificationDetails(android: alarmDetails),
            androidScheduleMode: AndroidScheduleMode.alarmClock,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          debugPrint('Scheduled alarmClock notification $id');
          return true;
        } catch (e3) {
          debugPrint('Failed alarmClock schedule: $e3');
          return false;
        }
      }
    }
  }

  /// Schedule a repeating notification. Returns true on success.
  static Future<bool> scheduleRepeatingReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    required DateTimeComponents matchComponents,
  }) async {
    if (!await arePermissionsGranted()) {
      await requestPermissions();
    }

    final androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      '提醒通知',
      channelDescription: '用药、复查等提醒通知',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF2A9D8F),
      ledOnMs: 1000,
      ledOffMs: 500,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: title,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      usesChronometer: false,
      onlyAlertOnce: false,
      autoCancel: true,
    );

    final scheduledDate = tz.TZDateTime.from(scheduledTime, tz.local);
    debugPrint('Scheduling repeating notification $id at $scheduledDate');

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchComponents,
      );
      debugPrint('Scheduled exact repeating notification $id');
      return true;
    } catch (e) {
      debugPrint('Failed exact repeating schedule: $e');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          NotificationDetails(android: androidDetails),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchComponents,
        );
        debugPrint('Scheduled inexact repeating notification $id');
        return true;
      } catch (e2) {
        debugPrint('Failed inexact repeating schedule: $e2');
        // Last resort: try alarmClock mode
        try {
          final alarmDetails = AndroidNotificationDetails(
            'reminder_channel',
            '提醒通知',
            channelDescription: '用药、复查等提醒通知',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            playSound: true,
            enableVibration: true,
            enableLights: true,
            ledColor: const Color(0xFF2A9D8F),
            fullScreenIntent: false,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            showWhen: true,
            when: DateTime.now().millisecondsSinceEpoch,
            onlyAlertOnce: false,
            autoCancel: true,
          );
          await _plugin.zonedSchedule(
            id,
            title,
            body,
            scheduledDate,
            NotificationDetails(android: alarmDetails),
            androidScheduleMode: AndroidScheduleMode.alarmClock,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            matchDateTimeComponents: matchComponents,
          );
          debugPrint('Scheduled alarmClock repeating notification $id');
          return true;
        } catch (e3) {
          debugPrint('Failed alarmClock repeating schedule: $e3');
          return false;
        }
      }
    }
  }

  /// Show notification immediately (for testing or past-due reminders)
  static Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          '提醒通知',
          channelDescription: '用药、复查等提醒通知',
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
  }

  static Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }

  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  /// Generate a deterministic notification ID from reminder ID
  static int reminderNotificationId(String reminderId) {
    return reminderId.hashCode.abs() % 2147483647;
  }

  /// Get all pending notifications for debugging
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _plugin.pendingNotificationRequests();
  }
}
