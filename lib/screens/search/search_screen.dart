import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../providers/app_providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _moneyFmt = NumberFormat.currency(locale: 'zh_CN', symbol: '¥');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _doSearch() {
    ref.read(searchKeywordProvider.notifier).state = _searchController.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resultsAsync = ref.watch(searchResultsProvider);
    final personFilter = ref.watch(searchPersonFilterProvider);
    final visitTypeFilter = ref.watch(searchVisitTypeFilterProvider);
    final personsAsync = ref.watch(personsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索症状、诊断、医院、备注...',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(searchKeywordProvider.notifier).state = '';
                              },
                            )
                          : null,
                    ),
                    onSubmitted: (_) => _doSearch(),
                    onChanged: (v) {
                      if (v.isEmpty) {
                        ref.read(searchKeywordProvider.notifier).state = '';
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _doSearch,
                  child: const Text('搜索'),
                ),
              ],
            ),
          ),
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Person filter
                personsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (persons) => FilterChip(
                    label: Text(personFilter != null
                        ? persons.where((p) => p.id == personFilter).firstOrNull?.name ?? '人员'
                        : '全部人员'),
                    selected: personFilter != null,
                    onSelected: (_) async {
                      final chosen = await showModalBottomSheet<String?>(
                        context: context,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                title: const Text('全部人员'),
                                onTap: () => Navigator.pop(ctx, null),
                                selected: personFilter == null,
                              ),
                              ...persons.map((p) => ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(p.personRelationship.label),
                                    selected: p.id == personFilter,
                                    onTap: () => Navigator.pop(ctx, p.id),
                                  )),
                            ],
                          ),
                        ),
                      );
                      ref.read(searchPersonFilterProvider.notifier).state = chosen;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Visit type filter
                FilterChip(
                  label: Text(visitTypeFilter != null
                      ? VisitType.fromCode(visitTypeFilter).label
                      : '全部类型'),
                  selected: visitTypeFilter != null,
                  onSelected: (_) async {
                    final chosen = await showModalBottomSheet<String?>(
                      context: context,
                      builder: (ctx) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: const Text('全部类型'),
                              onTap: () => Navigator.pop(ctx, null),
                              selected: visitTypeFilter == null,
                            ),
                            ...VisitType.values.map((vt) => ListTile(
                                  title: Text(vt.label),
                                  selected: vt.code == visitTypeFilter,
                                  onTap: () => Navigator.pop(ctx, vt.code),
                                )),
                          ],
                        ),
                      ),
                    );
                    ref.read(searchVisitTypeFilterProvider.notifier).state = chosen;
                  },
                ),
                const SizedBox(width: 8),
                // Clear all filters
                if (personFilter != null || visitTypeFilter != null)
                  ActionChip(
                    label: const Text('清除筛选'),
                    avatar: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      ref.read(searchPersonFilterProvider.notifier).state = null;
                      ref.read(searchVisitTypeFilterProvider.notifier).state = null;
                      ref.read(searchHospitalFilterProvider.notifier).state = null;
                    },
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: resultsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('搜索失败: $e')),
              data: (results) {
                final keyword = ref.watch(searchKeywordProvider);
                if (keyword.isEmpty &&
                    ref.watch(searchPersonFilterProvider) == null &&
                    ref.watch(searchVisitTypeFilterProvider) == null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                        const SizedBox(height: 16),
                        Text('输入关键词或选择筛选条件开始搜索', style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        )),
                      ],
                    ),
                  );
                }
                if (results.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        const Text('未找到匹配的就诊记录'),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final record = results[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _visitTypeColor(record.recordVisitType),
                          child: Icon(
                            _visitTypeIcon(record.recordVisitType),
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          record.hospital.isEmpty ? record.recordVisitType.label : record.hospital,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record.diagnosis != null && record.diagnosis!.isNotEmpty)
                              Text(record.diagnosis!, maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(
                              '${_dateFmt.format(record.visitTime)}  ${record.recordVisitType.label}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                        trailing: record.cost != null
                            ? Text(
                                _moneyFmt.format(record.cost),
                                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.secondary),
                              )
                            : null,
                        onTap: () => context.push('/record/detail?id=${record.id}'),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _visitTypeColor(VisitType type) {
    switch (type) {
      case VisitType.outpatient:
        return const Color(0xFF2A9D8F);
      case VisitType.emergency:
        return const Color(0xFFE76F51);
      case VisitType.inpatient:
        return const Color(0xFF457B9D);
      case VisitType.checkup:
        return const Color(0xFF264653);
      case VisitType.vaccination:
        return const Color(0xFF8338EC);
    }
  }

  IconData _visitTypeIcon(VisitType type) {
    switch (type) {
      case VisitType.outpatient:
        return Icons.local_hospital;
      case VisitType.emergency:
        return Icons.emergency;
      case VisitType.inpatient:
        return Icons.hotel;
      case VisitType.checkup:
        return Icons.health_and_safety;
      case VisitType.vaccination:
        return Icons.vaccines;
    }
  }
}
