import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/notification_service.dart';
import '../../services/widget_service.dart';

class ReminderEditScreen extends ConsumerStatefulWidget {
  const ReminderEditScreen({super.key, this.reminderId, this.personId, this.recordId});
  final String? reminderId;
  final String? personId;
  final String? recordId;

  @override
  ConsumerState<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends ConsumerState<ReminderEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _medicineNameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _durationDaysController = TextEditingController();

  // Medication time slots - list of TimeOfDay for each daily dose
  final List<TimeOfDay> _medicationTimes = [const TimeOfDay(hour: 8, minute: 0)];

  ReminderType _type = ReminderType.recheck;
  RepeatType _repeatType = RepeatType.once;
  DateTime _remindTime = DateTime.now().add(const Duration(hours: 1));
  String? _selectedPersonId;
  bool _loading = true;
  bool _saving = false;
  ReminderRow? _existing;

  bool get _isEdit => widget.reminderId != null;

  static final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _selectedPersonId = widget.personId;
    _load();
  }

  Future<void> _load() async {
    if (widget.reminderId != null) {
      final repo = await ref.read(reminderRepositoryProvider.future);
      final row = await repo.getById(widget.reminderId!);
      if (row != null && mounted) {
        _existing = row;
        _selectedPersonId = row.personId;
        _titleController.text = row.title;
        _type = row.reminderType;
        _repeatType = row.repeat;
        _remindTime = row.remindTime;
        _medicineNameController.text = row.medicineName ?? '';
        _dosageController.text = row.dosage ?? '';
        _durationDaysController.text = row.durationDays?.toString() ?? '';
        // Parse daily_times to medication time slots
        if (row.dailyTimes != null && row.dailyTimes!.isNotEmpty) {
          final times = row.dailyTimes!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
          if (times.isNotEmpty) {
            _medicationTimes.clear();
            for (final t in times) {
              final parts = t.split(':');
              if (parts.length >= 2) {
                _medicationTimes.add(TimeOfDay(
                  hour: int.tryParse(parts[0]) ?? 8,
                  minute: int.tryParse(parts[1]) ?? 0,
                ));
              }
            }
            if (_medicationTimes.isEmpty) {
              _medicationTimes.add(const TimeOfDay(hour: 8, minute: 0));
            }
          }
        }
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _medicineNameController.dispose();
    _dosageController.dispose();
    _durationDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _remindTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      locale: const Locale('zh', 'CN'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_remindTime),
    );
    if (time == null) return;
    setState(() {
      _remindTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final repo = await ref.read(reminderRepositoryProvider.future);

      if (_isEdit && _existing != null) {
        final updated = _existing!.copyWith(
          title: _titleController.text.trim(),
          type: _type.code,
          remindTime: _remindTime,
          repeatType: _repeatType.code,
          medicineName: _type == ReminderType.medication
              ? _medicineNameController.text.trim().isEmpty
                  ? null
                  : _medicineNameController.text.trim()
              : null,
          dailyTimes: _type == ReminderType.medication
              ? _medicationTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(',')
              : null,
          durationDays: _type == ReminderType.medication
              ? _durationDaysController.text.trim().isEmpty
                  ? null
                  : int.tryParse(_durationDaysController.text.trim())
              : null,
          dosage: _type == ReminderType.medication
              ? _dosageController.text.trim().isEmpty
                  ? null
                  : _dosageController.text.trim()
              : null,
        );
        await repo.update(updated);
        // Schedule notification - catch errors so save still completes
        try {
          await _scheduleNotification(updated);
        } catch (e) {
          debugPrint('Failed to schedule notification: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('提醒已保存，但通知调度失败: $e')),
            );
          }
        }
      } else {
        final reminder = await repo.create(
          personId: _selectedPersonId!,
          recordId: widget.recordId,
          title: _titleController.text.trim(),
          type: _type,
          remindTime: _remindTime,
          repeatType: _repeatType,
          medicineName: _type == ReminderType.medication
              ? _medicineNameController.text.trim().isEmpty
                  ? null
                  : _medicineNameController.text.trim()
              : null,
          dailyTimes: _type == ReminderType.medication
              ? _medicationTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(',')
              : null,
          durationDays: _type == ReminderType.medication
              ? _durationDaysController.text.trim().isEmpty
                  ? null
                  : int.tryParse(_durationDaysController.text.trim())
              : null,
          dosage: _type == ReminderType.medication
              ? _dosageController.text.trim().isEmpty
                  ? null
                  : _dosageController.text.trim()
              : null,
        );
        // Schedule notification - catch errors so save still completes
        try {
          await _scheduleNotification(reminder);
        } catch (e) {
          debugPrint('Failed to schedule notification: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('提醒已保存，但通知调度失败: $e')),
            );
          }
        }
      }

      ref.invalidate(activeRemindersProvider);
      ref.invalidate(archivedRemindersProvider);

      // Sync to home screen widget
      final allReminders = await ref.read(reminderRepositoryProvider.future).then((r) => r.getAll());
      await WidgetService.syncRemindersToWidget(allReminders);

      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scheduleNotification(ReminderRow reminder) async {
    final notifId = NotificationService.reminderNotificationId(reminder.id);
    final body = reminder.reminderType == ReminderType.medication
        ? '${reminder.medicineName ?? ''} ${reminder.dosage ?? ''}'.trim()
        : reminder.title;
    final notifBody = body.isEmpty ? '您有一个提醒' : body;

    if (_repeatType == RepeatType.once) {
      // For medication with daily_times, schedule multiple notifications
      if (reminder.reminderType == ReminderType.medication &&
          reminder.dailyTimes != null &&
          reminder.dailyTimes!.isNotEmpty) {
        final times = reminder.dailyTimes!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
        for (int i = 0; i < times.length; i++) {
          final parts = times[i].split(':');
          if (parts.length >= 2) {
            final hour = int.tryParse(parts[0]) ?? 8;
            final minute = int.tryParse(parts[1]) ?? 0;
            final medTime = DateTime(
              reminder.remindTime.year,
              reminder.remindTime.month,
              reminder.remindTime.day,
              hour,
              minute,
            );
            final medNotifId = notifId + i; // Unique ID per time slot
            await NotificationService.scheduleReminder(
              id: medNotifId,
              title: reminder.title,
              body: notifBody,
              scheduledTime: medTime.isBefore(DateTime.now())
                  ? medTime.add(const Duration(days: 1))
                  : medTime,
            );
          }
        }
      } else {
        await NotificationService.scheduleReminder(
          id: notifId,
          title: reminder.title,
          body: notifBody,
          scheduledTime: reminder.remindTime,
        );
      }
    } else {
      DateTimeComponents? match;
      switch (_repeatType) {
        case RepeatType.daily:
          match = DateTimeComponents.time;
          break;
        case RepeatType.weekly:
          match = DateTimeComponents.dayOfWeekAndTime;
          break;
        case RepeatType.monthly:
          match = DateTimeComponents.dayOfMonthAndTime;
          break;
        case RepeatType.quarterly:
          // Quarterly: use yearly match, app will reschedule
          match = DateTimeComponents.dateAndTime;
          break;
        case RepeatType.yearly:
          match = DateTimeComponents.dateAndTime;
          break;
        default:
          match = null;
      }
      if (match != null) {
        await NotificationService.scheduleRepeatingReminder(
          id: notifId,
          title: reminder.title,
          body: notifBody,
          scheduledTime: reminder.remindTime,
          matchComponents: match,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final showMedFields = _type == ReminderType.medication;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑提醒' : '添加提醒'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '提醒标题',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? '请输入标题' : null,
            ),
            const SizedBox(height: 16),

            // Type
            Text('提醒类型', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: ReminderType.values.map((rt) {
                return ChoiceChip(
                  label: Text(rt.label),
                  selected: _type == rt,
                  onSelected: (_) => setState(() => _type = rt),
                  avatar: Icon(_reminderTypeIcon(rt), size: 18),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Medication fields
            if (showMedFields) ...[
              Card(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('用药详情', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _medicineNameController,
                        decoration: const InputDecoration(
                          labelText: '药名',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.medication),
                        ),
                        validator: (v) => showMedFields && (v == null || v.trim().isEmpty) ? '请输入药名' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dosageController,
                        decoration: const InputDecoration(
                          labelText: '服用剂量（如：每次1片饭后服）',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.science),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Medication time slots
                      Text('用药时间', style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      ...List.generate(_medicationTimes.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.access_time, size: 20, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text('第${i + 1}次: '),
                              const SizedBox(width: 4),
                              ActionChip(
                                label: Text(
                                  '${_medicationTimes[i].hour.toString().padLeft(2, '0')}:${_medicationTimes[i].minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: _medicationTimes[i],
                                  );
                                  if (picked != null) {
                                    setState(() => _medicationTimes[i] = picked);
                                  }
                                },
                              ),
                              const Spacer(),
                              if (_medicationTimes.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                                  color: theme.colorScheme.error,
                                  onPressed: () {
                                    setState(() => _medicationTimes.removeAt(i));
                                  },
                                ),
                            ],
                          ),
                        );
                      }),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _medicationTimes.add(const TimeOfDay(hour: 12, minute: 0)));
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('添加用药时间'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _durationDaysController,
                        decoration: const InputDecoration(
                          labelText: '持续天数',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range),
                          hintText: '如：7',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Remind time (hidden for medication with multiple time slots)
            if (!showMedFields || _medicationTimes.length <= 1) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.access_time),
                title: Text(showMedFields ? '用药开始日期' : '提醒时间'),
                subtitle: Text(_dateTimeFmt.format(_remindTime)),
                onTap: _pickDateTime,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: BorderSide(color: theme.colorScheme.outline),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (showMedFields && _medicationTimes.length > 1) ...[
              Card(
                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('用药开始日期'),
                  subtitle: Text(DateFormat('yyyy-MM-dd').format(_remindTime)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _remindTime,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      locale: const Locale('zh', 'CN'),
                    );
                    if (date != null) {
                      setState(() {
                        _remindTime = DateTime(date.year, date.month, date.day, _medicationTimes[0].hour, _medicationTimes[0].minute);
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Repeat type
            Text('重复', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: RepeatType.values.map((rt) {
                return ChoiceChip(
                  label: Text(rt.label),
                  selected: _repeatType == rt,
                  onSelected: (_) => setState(() => _repeatType = rt),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Save button
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('保存提醒'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  IconData _reminderTypeIcon(ReminderType type) {
    switch (type) {
      case ReminderType.medication:
        return Icons.medication;
      case ReminderType.recheck:
        return Icons.event_repeat;
      case ReminderType.vaccination:
        return Icons.vaccines;
      case ReminderType.deworming:
        return Icons.bug_report;
      case ReminderType.custom:
        return Icons.notifications;
    }
  }
}
