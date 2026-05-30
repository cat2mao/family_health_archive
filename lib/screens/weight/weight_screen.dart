import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';

class WeightScreen extends ConsumerStatefulWidget {
  const WeightScreen({super.key, required this.personId});
  final String personId;

  @override
  ConsumerState<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends ConsumerState<WeightScreen> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<List<WeightRecordRow>>(
      future: ref.read(weightRepositoryProvider.future).then((r) => r.getByPerson(widget.personId)),
      builder: (context, snapshot) {
        final records = snapshot.data ?? [];

        return Scaffold(
          appBar: AppBar(
            title: const Text('体重记录'),
          ),
          body: records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.show_chart, size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                      const SizedBox(height: 16),
                      const Text('暂无体重记录'),
                      const SizedBox(height: 8),
                      const Text('点击右下角 + 添加体重', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Chart
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: SizedBox(
                          height: 250,
                          child: _buildChart(theme, records),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('历史记录', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    // Record list (newest first)
                    ...records.reversed.map((r) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Icon(Icons.monitor_weight, color: theme.colorScheme.primary, size: 20),
                            ),
                            title: Text('${r.weight.toStringAsFixed(1)} kg'),
                            subtitle: Text(r.recordDate),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteRecord(r),
                            ),
                          ),
                        )),
                  ],
                ),
          floatingActionButton: FloatingActionButton(
            onPressed: _addWeight,
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildChart(ThemeData theme, List<WeightRecordRow> records) {
    if (records.length == 1) {
      // Single point - just show text
      return Center(
        child: Text(
          '${records.first.weight.toStringAsFixed(1)} kg',
          style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.primary),
        ),
      );
    }

    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    for (int i = 0; i < records.length; i++) {
      spots.add(FlSpot(i.toDouble(), records[i].weight));
      if (records[i].weight < minY) minY = records[i].weight;
      if (records[i].weight > maxY) maxY = records[i].weight;
    }

    final padding = (maxY - minY) * 0.2;
    if (padding < 1) {
      minY -= 2;
      maxY += 2;
    } else {
      minY -= padding;
      maxY += padding;
    }

    return LineChart(
      LineChartData(
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 100),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (records.length / 5).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= records.length) return const SizedBox.shrink();
                final parts = records[idx].recordDate.split('-');
                return Text(
                  parts.length >= 2 ? '${parts[1]}/${parts[2]}' : records[idx].recordDate,
                  style: theme.textTheme.bodySmall,
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: theme.colorScheme.primary,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, __, ___, ____) => FlDotCirclePainter(
                radius: 4,
                color: theme.colorScheme.primary,
                strokeWidth: 2,
                strokeColor: theme.colorScheme.surface,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final r = records[s.x.toInt()];
              return LineTooltipItem(
                '${r.weight.toStringAsFixed(1)} kg\n${r.recordDate}',
                TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _addWeight() async {
    final weightController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('添加体重'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightController,
                decoration: const InputDecoration(
                  labelText: '体重 (kg)',
                  border: OutlineInputBorder(),
                  suffixText: 'kg',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('日期'),
                subtitle: Text(_dateFmt.format(selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    locale: const Locale('zh', 'CN'),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;

    final weight = double.tryParse(weightController.text.trim());
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的体重')),
        );
      }
      return;
    }

    final repo = await ref.read(weightRepositoryProvider.future);
    await repo.create(
      personId: widget.personId,
      weight: weight,
      recordDate: _dateFmt.format(selectedDate),
    );
    setState(() {});
  }

  Future<void> _deleteRecord(WeightRecordRow record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除体重记录'),
        content: Text('确定删除 ${record.recordDate} 的 ${record.weight.toStringAsFixed(1)} kg 记录？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await ref.read(weightRepositoryProvider.future);
    await repo.delete(record.id);
    setState(() {});
  }
}
