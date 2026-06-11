import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../widgets/person_avatar.dart';
import 'widgets/empty_timeline.dart';
import 'widgets/timeline_item.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _drawerKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(recordsForSelectedPersonProvider);
    final personsAsync = ref.watch(personsProvider);
    final theme = Theme.of(context);

    // Resolve current person
    final currentPerson = personsAsync.maybeWhen(
      data: (list) {
        final selectedId = ref.watch(selectedPersonIdProvider);
        return list.where((e) => e.id == selectedId).firstOrNull ??
            list.where((e) => e.relationship == 'self').firstOrNull ??
            (list.isNotEmpty ? list.first : null);
      },
      orElse: () => null,
    );

    return Scaffold(
      key: _drawerKey,
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () => _drawerKey.currentState?.openEndDrawer(),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: currentPerson != null
                ? PersonAvatar(
                    avatarPath: currentPerson.avatarPath,
                    name: currentPerson.name,
                    type: currentPerson.personType,
                    radius: 16,
                  )
                : const Icon(Icons.person_outline),
          ),
        ),
        title: GestureDetector(
          onTap: () => _drawerKey.currentState?.openEndDrawer(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  currentPerson?.name ?? '健康档案',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: '年度回顾',
            onPressed: () => context.push('/annual-review'),
          ),
        ],
      ),
      endDrawer: _buildFamilyDrawer(context, ref, personsAsync),
      body: _buildBody(recordsAsync),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final selectedId = ref.read(selectedPersonIdProvider);
          if (selectedId == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('请先添加家庭成员')),
            );
            return;
          }
          context.push('/record/edit?personId=$selectedId');
        },
        icon: const Icon(Icons.add),
        label: const Text('添加就诊'),
      ),
    );
  }

  Widget _buildBody(AsyncValue<List<MedicalRecordRow>> recordsAsync) {
    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('加载失败: $e')),
      data: (records) {
        if (records.isEmpty) return const EmptyTimeline();
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(recordsForSelectedPersonProvider);
            await ref.read(recordsForSelectedPersonProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 88),
            itemCount: records.length,
            itemBuilder: (context, index) => TimelineItem(
              record: records[index],
              isFirst: index == 0,
              isLast: index == records.length - 1,
              onTap: () => context.push('/record/detail?id=${records[index].id}'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFamilyDrawer(
      BuildContext context, WidgetRef ref, AsyncValue personsAsync) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(selectedPersonIdProvider);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.family_restroom,
                      color: theme.colorScheme.primary, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    '家庭成员',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: '人员管理',
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/persons');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Person list
            Expanded(
              child: personsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
                data: (persons) {
                  if (persons.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.people_outline,
                              size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text('暂无家庭成员',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.outline)),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              context.push('/persons/edit');
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('添加成员'),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: persons.length,
                    itemBuilder: (context, index) {
                      final person = persons[index];
                      final selected = person.id == selectedId;
                      return _PersonTile(
                        person: person,
                        selected: selected,
                        onTap: () {
                          ref.read(selectedPersonIdProvider.notifier).state =
                              person.id;
                          Navigator.pop(context);
                        },
                        onLongPress: () {
                          Navigator.pop(context);
                          context.push('/persons/edit?id=${person.id}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
            // Bottom action
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  context.push('/persons');
                },
                icon: const Icon(Icons.manage_accounts_outlined),
                label: const Text('管理家庭成员'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Person tile in the drawer
class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final PersonRow person;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // Avatar
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: theme.colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: PersonAvatar(
                    avatarPath: person.avatarPath,
                    name: person.name,
                    type: person.personType,
                    radius: 24,
                  ),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${person.personRelationship.label} · ${person.personType.label}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Selected indicator
                if (selected)
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
