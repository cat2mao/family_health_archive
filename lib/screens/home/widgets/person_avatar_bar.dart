import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/enums.dart';
import '../../../data/database/app_database.dart';
import '../../../providers/app_providers.dart';
import '../../../widgets/person_avatar.dart';

class PersonAvatarBar extends ConsumerWidget {
  const PersonAvatarBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final personsAsync = ref.watch(personsProvider);
    final selectedId = ref.watch(selectedPersonIdProvider);

    return personsAsync.when(
      loading: () => const SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败: $e'),
      ),
      data: (persons) {
        if (persons.isEmpty) {
          return const SizedBox.shrink();
        }
        final activeId = selectedId ??
            persons
                .where((p) => p.relationship == Relationship.self.code)
                .map((p) => p.id)
                .firstOrNull ??
            persons.first.id;

        return SizedBox(
          height: 88,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: persons.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final person = persons[index];
              final selected = person.id == activeId;
              return _AvatarChip(
                person: person,
                selected: selected,
                onTap: () {
                  ref.read(selectedPersonIdProvider.notifier).state = person.id;
                },
                onLongPress: () {
                  context.push('/persons/edit?id=${person.id}');
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _AvatarChip extends StatelessWidget {
  const _AvatarChip({
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: theme.colorScheme.primary, width: 2.5)
                  : null,
            ),
            child: PersonAvatar(
              avatarPath: person.avatarPath,
              name: person.name,
              type: person.personType,
              radius: 24,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 56,
            child: Text(
              person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : null,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
