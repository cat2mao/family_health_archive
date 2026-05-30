import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../widgets/person_avatar.dart';

class PersonListScreen extends ConsumerWidget {
  const PersonListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personsAsync = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('人员管理'),
      ),
      body: personsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (persons) {
          if (persons.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
                  const SizedBox(height: 16),
                  const Text('暂无人员，请点击右下角添加'),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: persons.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final person = persons[index];
              return _PersonTile(
                person: person,
                onTap: () => context.push('/persons/edit?id=${person.id}'),
                onDelete: () => _confirmDelete(context, ref, person),
                onViewRecords: () {
                  ref.read(selectedPersonIdProvider.notifier).state = person.id;
                  context.go('/');
                },
                onViewWeight: () => context.push('/weight?personId=${person.id}'),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/persons/edit'),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PersonRow person,
  ) async {
    if (person.relationship == Relationship.self.code) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('不能删除「本人」档案')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除人员'),
        content: Text('确定删除「${person.name}」及其全部就诊记录？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final repo = await ref.read(personRepositoryProvider.future);
    await repo.delete(person.id);
    ref.invalidate(personsProvider);
    ref.invalidate(recordsForSelectedPersonProvider);
    if (ref.read(selectedPersonIdProvider) == person.id) {
      ref.read(selectedPersonIdProvider.notifier).state = null;
    }
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({
    required this.person,
    required this.onTap,
    required this.onDelete,
    required this.onViewRecords,
    required this.onViewWeight,
  });

  final PersonRow person;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onViewRecords;
  final VoidCallback onViewWeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: PersonAvatar(
        avatarPath: person.avatarPath,
        name: person.name,
        type: person.personType,
        radius: 24,
      ),
      title: Text(person.name),
      subtitle: Text(
        '${person.personRelationship.label} · ${person.personType.label}',
        style: theme.textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'records':
              onViewRecords();
              break;
            case 'weight':
              onViewWeight();
              break;
            case 'edit':
              onTap();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'records', child: Text('查看就诊记录')),
          const PopupMenuItem(value: 'weight', child: Text('体重曲线')),
          const PopupMenuItem(value: 'edit', child: Text('编辑')),
          const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
      onTap: onTap,
    );
  }
}
