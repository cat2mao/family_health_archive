import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    // Only clear corrupted notification data once (first run after install/update)
    // Do NOT clear on every launch as it may interfere with notification scheduling
    await _clearCorruptedNotificationDataIfNeeded();

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'reminder_channel',
      '提醒通知',
      description: '用药、复查等提醒通知',
      importance: Importance.high,
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
        // Handle notification tap
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    _initialized = true;

    // Request permissions
    await requestPermissions();
  }

  /// Clear corrupted notification data only once (flagged in SharedPreferences)
  /// This resolves "Missing type parameter" errors from Gson deserialization
  /// without interfering with future notification scheduling
  static Future<void> _clearCorruptedNotificationDataIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyCleared = prefs.getBool('notification_data_cleared_v2') ?? false;
      if (alreadyCleared) return;

      final keys = prefs.getKeys();
      final notificationKeys = keys.where(
        (key) => key.contains('flutter_local_notifications') ||
                 key.contains('notification') ||
                 key.contains('scheduled_notifications'),
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

  /// Request notification and alarm permissions
  static Future<bool> requestPermissions() async {
    bool allGranted = true;

    // Request POST_NOTIFICATIONS permission (Android 13+)
    if (Platform.isAndroid) {
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        final result = await Permission.notification.request();
        if (!result.isGranted) {
          debugPrint('POST_NOTIFICATIONS permission denied');
          allGranted = false;
        }
      }

      // Request SCHEDULE_EXACT_ALARM permission (Android 12+)
      // On Android 12+, this is critical for exact alarm scheduling
      final alarmStatus = await Permission.scheduleExactAlarm.status;
      debugPrint('Schedule exact alarm status: $alarmStatus');
      if (!alarmStatus.isGranted) {
        try {
          final result = await Permission.scheduleExactAlarm.request();
          debugPrint('Schedule exact alarm request result: $result');
          if (!result.isGranted) {
            debugPrint('SCHEDULE_EXACT_ALARM permission denied - will use inexact alarms');
            allGranted = false;
          }
        } catch (e) {
          debugPrint('Error requesting schedule exact alarm permission: $e');
          allGranted = false;
        }
      }
    }

    return allGranted;
  }

  /// Check if notification permissions are granted
  static Future<bool> arePermissionsGranted() async {
    if (!Platform.isAndroid) return true;
    final notifGranted = await Permission.notification.isGranted;
    final alarmGranted = await Permission.scheduleExactAlarm.isGranted;
    debugPrint('Notification permission: $notifGranted, Alarm permission: $alarmGranted');
    return notifGranted && alarmGranted;
  }

  static Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    // Check permissions before scheduling
    if (!await arePermissionsGranted()) {
      await requestPermissions();
    }

    final now = DateTime.now();
    if (scheduledTime.isBefore(now)) {
      // If the time is in the past, show immediately
      await showNow(id: id, title: title, body: body);
      return;
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
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: title,
    );

    final scheduledDate = tz.TZDateTime.from(scheduledTime, tz.local);
    debugPrint('Scheduling notification $id at $scheduledDate (local: $scheduledTime)');

    // Try exact alarm first, then inexact
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
      debugPrint('Successfully scheduled exact notification $id');
    } catch (e) {
      debugPrint('Failed to schedule exact alarm: $e');
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
        debugPrint('Successfully scheduled inexact notification $id');
      } catch (e2) {
        debugPrint('Failed to schedule inexact alarm: $e2');
      }
    }
  }

  static Future<void> scheduleRepeatingReminder({
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
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      ticker: title,
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
      debugPrint('Successfully scheduled exact repeating notification $id');
    } catch (e) {
      debugPrint('Failed to schedule exact repeating alarm: $e');
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
        debugPrint('Successfully scheduled inexact repeating notification $id');
      } catch (e2) {
        debugPrint('Failed to schedule inexact repeating alarm: $e2');
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
          importance: Importance.high,
          priority: Priority.high,
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
