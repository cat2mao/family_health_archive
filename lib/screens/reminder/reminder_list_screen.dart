import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';

class ReminderListScreen extends ConsumerStatefulWidget {
  const ReminderListScreen({super.key});

  @override
  ConsumerState<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends ConsumerState<ReminderListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('提醒'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '待办'),
            Tab(text: '历史'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveTab(theme),
          _buildArchivedTab(theme),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final personId = ref.read(selectedPersonIdProvider);
          context.push('/reminder/edit?personId=$personId');
        },
        child: const Icon(Icons.add_alarm),
      ),
    );
  }

  Widget _buildActiveTab(ThemeData theme) {
    final remindersAsync = ref.watch(activeRemindersProvider);

    return remindersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (reminders) {
        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.notifications_none, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                const Text('暂无待办提醒'),
                const SizedBox(height: 8),
                const Text('点击右下角 + 添加新提醒', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        // Separate into upcoming and overdue
        final now = DateTime.now();
        final overdue = reminders.where((r) => r.remindTime.isBefore(now) && !r.isCompleted).toList();
        final upcoming = reminders.where((r) => !r.remindTime.isBefore(now) && !r.isCompleted).toList();

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(activeRemindersProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            children: [
              if (overdue.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: theme.colorScheme.error, size: 20),
                      const SizedBox(width: 4),
                      Text('已过期 (${overdue.length})', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.error)),
                    ],
                  ),
                ),
                ...overdue.map((r) => _ReminderCard(
                  reminder: r,
                  isOverdue: true,
                  onComplete: () => _completeReminder(r),
                  onDelete: () => _deleteReminder(r),
                  onEdit: () => context.push('/reminder/edit?reminderId=${r.id}').then((_) {
                    ref.invalidate(activeRemindersProvider);
                    ref.invalidate(archivedRemindersProvider);
                  }),
                )),
              ],
              if (upcoming.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('待办 (${upcoming.length})', style: theme.textTheme.titleSmall),
                ),
                ...upcoming.map((r) => _ReminderCard(
                  reminder: r,
                  isOverdue: false,
                  onComplete: () => _completeReminder(r),
                  onDelete: () => _deleteReminder(r),
                  onEdit: () => context.push('/reminder/edit?reminderId=${r.id}').then((_) {
                    ref.invalidate(activeRemindersProvider);
                    ref.invalidate(archivedRemindersProvider);
                  }),
                )),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildArchivedTab(ThemeData theme) {
    final remindersAsync = ref.watch(archivedRemindersProvider);

    return remindersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (reminders) {
        if (reminders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                const Text('暂无历史提醒'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: reminders.length,
          itemBuilder: (context, index) {
            final r = reminders[index];
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: Icon(
                  r.reminderType == ReminderType.medication
                      ? Icons.medication
                      : r.reminderType == ReminderType.recheck
                          ? Icons.event_repeat
                          : r.reminderType == ReminderType.vaccination
                              ? Icons.vaccines
                              : r.reminderType == ReminderType.deworming
                                  ? Icons.bug_report
                                  : Icons.notifications,
                  color: Colors.green,
                ),
                title: Text(r.title, style: const TextStyle(decoration: TextDecoration.lineThrough)),
                subtitle: Text(_dateFmt.format(r.remindTime)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteReminder(r),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _completeReminder(ReminderRow reminder) async {
    final repo = await ref.read(reminderRepositoryProvider.future);
    await repo.markCompleted(reminder.id);
    ref.invalidate(activeRemindersProvider);
    ref.invalidate(archivedRemindersProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已标记完成')),
      );
    }
  }

  Future<void> _deleteReminder(ReminderRow reminder) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除提醒'),
        content: Text('确定删除「${reminder.title}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(reminderRepositoryProvider.future);
    await repo.delete(reminder.id);
    ref.invalidate(activeRemindersProvider);
    ref.invalidate(archivedRemindersProvider);
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.reminder,
    required this.isOverdue,
    required this.onComplete,
    required this.onDelete,
    required this.onEdit,
  });

  final ReminderRow reminder;
  final bool isOverdue;
  final VoidCallback onComplete;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color color;
    switch (reminder.reminderType) {
      case ReminderType.medication:
        icon = Icons.medication;
        color = const Color(0xFF2A9D8F);
        break;
      case ReminderType.recheck:
        icon = Icons.event_repeat;
        color = const Color(0xFF457B9D);
        break;
      case ReminderType.vaccination:
        icon = Icons.vaccines;
        color = const Color(0xFF8338EC);
        break;
      case ReminderType.deworming:
        icon = Icons.bug_report;
        color = const Color(0xFFE76F51);
        break;
      case ReminderType.custom:
        icon = Icons.notifications;
        color = theme.colorScheme.primary;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isOverdue ? theme.colorScheme.errorContainer.withValues(alpha: 0.3) : null,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reminder.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${_dateFmt.format(reminder.remindTime)}  ·  ${reminder.repeat.label}',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (reminder.reminderType == ReminderType.medication) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${reminder.medicineName ?? ''}  ${reminder.dosage ?? ''}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.check_circle_outline, color: color),
                tooltip: '标记完成',
                onPressed: onComplete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
