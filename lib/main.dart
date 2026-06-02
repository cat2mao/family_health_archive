import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/enums.dart';
import 'providers/app_providers.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  runApp(
    const ProviderScope(
      child: _BootstrapApp(),
    ),
  );
}

class _BootstrapApp extends ConsumerStatefulWidget {
  const _BootstrapApp();

  @override
  ConsumerState<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends ConsumerState<_BootstrapApp> {
  bool _notificationsRescheduled = false;

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(bootstrapProvider);
    return bootstrap.when(
      loading: () => MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.favorite,
                  size: 48,
                  color: Colors.teal.shade400,
                ),
                const SizedBox(height: 16),
                const Text('家庭健康档案'),
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      error: (e, _) => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('启动失败: $e')),
        ),
      ),
      data: (selfId) {
        if (selfId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final current = ref.read(selectedPersonIdProvider);
            if (current == null) {
              ref.read(selectedPersonIdProvider.notifier).state = selfId;
            }
            // Reschedule all active reminders on app startup
            _rescheduleNotificationsIfNeeded();
          });
        }
        return FamilyHealthApp();
      },
    );
  }

  /// Reschedule all active reminders' notifications on app startup.
  /// This ensures notifications are restored after device reboot or
  /// when the OS clears scheduled alarms.
  Future<void> _rescheduleNotificationsIfNeeded() async {
    if (_notificationsRescheduled) return;
    _notificationsRescheduled = true;

    try {
      final reminderRepo = await ref.read(reminderRepositoryProvider.future);
      final activeReminders = await reminderRepo.getActive();

      debugPrint('Rescheduling ${activeReminders.length} active reminders');
      int scheduled = 0;
      for (final reminder in activeReminders) {
        // Only schedule future reminders
        if (reminder.remindTime.isAfter(DateTime.now())) {
          final notifId = NotificationService.reminderNotificationId(reminder.id);
          final body = reminder.reminderType == ReminderType.medication
              ? '${reminder.medicineName ?? ''} ${reminder.dosage ?? ''}'.trim()
              : reminder.title;

          try {
            await NotificationService.scheduleReminder(
              id: notifId,
              title: reminder.title,
              body: body.isEmpty ? '您有一个提醒' : body,
              scheduledTime: reminder.remindTime,
            );
            scheduled++;
          } catch (e) {
            debugPrint('Failed to reschedule notification for ${reminder.id}: $e');
          }
        }
      }
      debugPrint('Successfully rescheduled $scheduled notifications');
    } catch (e) {
      debugPrint('Failed to reschedule notifications: $e');
    }
  }
}
