import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/app_providers.dart';
import 'widgets/empty_timeline.dart';
import 'widgets/person_avatar_bar.dart';
import 'widgets/timeline_item.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsForSelectedPersonProvider);
    final personsAsync = ref.watch(personsProvider);

    final personName = personsAsync.maybeWhen(
      data: (list) {
        final selectedId = ref.watch(selectedPersonIdProvider);
        final p = list.where((e) => e.id == selectedId).firstOrNull ??
            list.where((e) => e.relationship == 'self').firstOrNull ??
            (list.isNotEmpty ? list.first : null);
        return p?.name ?? '健康档案';
      },
      orElse: () => '健康档案',
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(personName),
            Text(
              '就诊时间轴',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: '年度回顾',
            onPressed: () => context.push('/annual-review'),
          ),
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: '人员管理',
            onPressed: () => context.push('/persons'),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PersonAvatarBar(),
          const Divider(height: 1),
          Expanded(
            child: recordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
              data: (records) {
                if (records.isEmpty) {
                  return const EmptyTimeline();
                }
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
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final selectedId = ref.read(selectedPersonIdProvider);
          context.push('/record/edit?personId=$selectedId');
        },
        icon: const Icon(Icons.add),
        label: const Text('添加就诊'),
      ),
    );
  }
}
