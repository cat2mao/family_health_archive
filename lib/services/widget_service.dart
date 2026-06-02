import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/enums.dart';
import '../data/database/app_database.dart';

class WidgetService {
  static const _channel = MethodChannel('com.familyhealth.archive/widget');
  static final _dateFmt = DateFormat('MM/dd HH:mm');

  /// Sync active reminders to SharedPreferences for the home screen widget
  static Future<void> syncRemindersToWidget(List<ReminderRow> reminders) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Filter active (not completed, not archived) reminders, sorted by time
      final active = reminders
          .where((r) => !r.isCompleted && !r.archived)
          .toList()
        ..sort((a, b) => a.remindTime.compareTo(b.remindTime));

      // Take at most 5 items for the widget
      final items = active.take(5).map((r) {
        String subtitle = '';
        if (r.reminderType == ReminderType.medication) {
          subtitle = '${r.medicineName ?? ''} ${r.dosage ?? ''}'.trim();
        }
        subtitle = subtitle.isEmpty ? r.repeat.label : '$subtitle · ${r.repeat.label}';

        return {
          'title': r.title,
          'subtitle': subtitle,
          'time': _dateFmt.format(r.remindTime),
          'type': r.reminderType.code,
        };
      }).toList();

      await prefs.setString('widget_reminders', jsonEncode(items));

      // Notify the native widget to refresh
      await notifyWidgetUpdate();
    } catch (e) {
      debugPrint('Failed to sync reminders to widget: $e');
    }
  }

  /// Notify the native widget to update its data
  static Future<void> notifyWidgetUpdate() async {
    try {
      await _channel.invokeMethod('updateWidget');
    } catch (e) {
      // Method channel might not be set up, use broadcast fallback
      debugPrint('Widget update method channel not available: $e');
    }
  }
}
