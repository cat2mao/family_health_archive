import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';

class AnnualReviewScreen extends ConsumerStatefulWidget {
  const AnnualReviewScreen({super.key});

  @override
  ConsumerState<AnnualReviewScreen> createState() => _AnnualReviewScreenState();
}

class _AnnualReviewScreenState extends ConsumerState<AnnualReviewScreen> {
  int _selectedYear = DateTime.now().year;
  static final _moneyFmt = NumberFormat.currency(locale: 'zh_CN', symbol: '¥');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('$_selectedYear 年度回顾'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _selectedYear--),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              if (_selectedYear < DateTime.now().year) {
                setState(() => _selectedYear++);
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<_AnnualData>(
        future: _loadData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary cards
              Row(
                children: [
                  Expanded(child: _SummaryCard(
                    title: '就诊次数',
                    value: '${data.totalVisits}',
                    icon: Icons.local_hospital,
                    color: const Color(0xFF2A9D8F),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: _SummaryCard(
                    title: '总花费',
                    value: _moneyFmt.format(data.totalCost),
                    icon: Icons.payments,
                    color: const Color(0xFF457B9D),
                  )),
                ],
              ),
              const SizedBox(height: 16),

              // Hospital distribution
              if (data.hospitalDist.isNotEmpty) ...[
                Text('医院分布', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 200,
                      child: _buildHospitalPie(theme, data.hospitalDist),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Tag distribution
              if (data.tagDist.isNotEmpty) ...[
                Text('病情分布', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildTagBar(theme, data.tagDist),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Person distribution
              if (data.personDist.isNotEmpty) ...[
                Text('人员分布', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 200,
                      child: _buildPersonPie(theme, data.personDist),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Visit type distribution
              if (data.visitTypeDist.isNotEmpty) ...[
                Text('就诊类型分布', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...data.visitTypeDist.entries.map((e) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_visitTypeIcon(VisitType.fromCode(e.key)), color: _visitTypeColor(VisitType.fromCode(e.key))),
                      title: Text(VisitType.fromCode(e.key).label),
                      trailing: Text('${e.value}次', style: theme.textTheme.titleSmall),
                    )),
                const SizedBox(height: 16),
              ],

              // Monthly trend
              if (data.monthlyVisits.isNotEmpty) ...[
                Text('月度就诊趋势', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                    child: SizedBox(
                      height: 200,
                      child: _buildMonthlyChart(theme, data.monthlyVisits),
                    ),
                  ),
                ),
              ],

              if (data.totalVisits == 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.bar_chart, size: 64, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text('$_selectedYear年暂无就诊记录', style: theme.textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<_AnnualData> _loadData() async {
    final recordRepo = await ref.read(medicalRecordRepositoryProvider.future);
    final personRepo = await ref.read(personRepositoryProvider.future);
    final tagRepo = await ref.read(tagRepositoryProvider.future);
    final db = await ref.read(databaseProvider.future);

    final allRecords = await recordRepo.getAll();
    final yearRecords = allRecords.where((r) => r.visitTime.year == _selectedYear).toList();
    final persons = await personRepo.getAll();

    double totalCost = 0;
    final hospitalDist = <String, int>{};
    final visitTypeDist = <String, int>{};
    final monthlyVisits = <int, int>{};
    final personDist = <String, int>{};

    for (final r in yearRecords) {
      totalCost += r.cost ?? 0;

      if (r.hospital.isNotEmpty) {
        hospitalDist[r.hospital] = (hospitalDist[r.hospital] ?? 0) + 1;
      }

      visitTypeDist[r.visitType] = (visitTypeDist[r.visitType] ?? 0) + 1;
      monthlyVisits[r.visitTime.month] = (monthlyVisits[r.visitTime.month] ?? 0) + 1;

      final personName = persons.where((p) => p.id == r.personId).firstOrNull?.name ?? '未知';
      personDist[personName] = (personDist[personName] ?? 0) + 1;
    }

    // Tag distribution
    final tagDist = await db.getTagDistribution();

    return _AnnualData(
      totalVisits: yearRecords.length,
      totalCost: totalCost,
      hospitalDist: hospitalDist,
      tagDist: tagDist,
      visitTypeDist: visitTypeDist,
      monthlyVisits: monthlyVisits,
      personDist: personDist,
    );
  }

  Widget _buildHospitalPie(ThemeData theme, Map<String, int> data) {
    final colors = [
      const Color(0xFF2A9D8F),
      const Color(0xFF457B9D),
      const Color(0xFFE76F51),
      const Color(0xFF8338EC),
      const Color(0xFF264653),
      const Color(0xFFF4A261),
      const Color(0xFFE9C46A),
    ];
    final entries = data.entries.toList();
    final total = entries.fold(0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: List.generate(entries.length, (i) {
                final pct = (entries[i].value / total * 100).toStringAsFixed(0);
                return PieChartSectionData(
                  value: entries[i].value.toDouble(),
                  color: colors[i % colors.length],
                  title: '$pct%',
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  radius: 60,
                );
              }),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(entries.length.clamp(0, 5), (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, color: colors[i % colors.length]),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 100,
                    child: Text(
                      entries[i].key,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(' (${entries[i].value})', style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildTagBar(ThemeData theme, Map<String, int> data) {
    final entries = data.entries.toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    final maxVal = entries.first.value;

    return Column(
      children: List.generate(entries.length.clamp(0, 10), (i) {
        final e = entries[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 60, child: Text(e.key, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.value / maxVal,
                    minHeight: 16,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: const Color(0xFF2A9D8F),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${e.value}次', style: theme.textTheme.bodySmall),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPersonPie(ThemeData theme, Map<String, int> data) {
    final colors = [
      const Color(0xFF2A9D8F),
      const Color(0xFF457B9D),
      const Color(0xFFE76F51),
      const Color(0xFF8338EC),
      const Color(0xFF264653),
      const Color(0xFFF4A261),
    ];
    final entries = data.entries.toList();
    final total = entries.fold(0, (sum, e) => sum + e.value);

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: List.generate(entries.length, (i) {
                final pct = (entries[i].value / total * 100).toStringAsFixed(0);
                return PieChartSectionData(
                  value: entries[i].value.toDouble(),
                  color: colors[i % colors.length],
                  title: '$pct%',
                  titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  radius: 60,
                );
              }),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(entries.length, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 12, color: colors[i % colors.length]),
                  const SizedBox(width: 4),
                  Text('${entries[i].key} (${entries[i].value})', style: theme.textTheme.bodySmall),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMonthlyChart(ThemeData theme, Map<int, int> data) {
    final spots = List.generate(12, (i) => FlSpot((i + 1).toDouble(), (data[i + 1] ?? 0).toDouble()));
    final maxVal = data.values.fold(0, (a, b) => a > b ? a : b).toDouble();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxVal + 1).ceilToDouble(),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${value.toInt()}月', style: theme.textTheme.bodySmall),
              ),
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxVal > 0 ? (maxVal / 4).ceilToDouble().clamp(1, 100) : 1,
        ),
        barGroups: spots.map((s) => BarChartGroupData(
          x: s.x.toInt(),
          barRods: [
            BarChartRodData(
              toY: s.y,
              color: const Color(0xFF2A9D8F),
              width: 16,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ],
        )).toList(),
      ),
    );
  }

  Color _visitTypeColor(VisitType type) {
    switch (type) {
      case VisitType.outpatient: return const Color(0xFF2A9D8F);
      case VisitType.emergency: return const Color(0xFFE76F51);
      case VisitType.inpatient: return const Color(0xFF457B9D);
      case VisitType.checkup: return const Color(0xFF264653);
      case VisitType.vaccination: return const Color(0xFF8338EC);
    }
  }

  IconData _visitTypeIcon(VisitType type) {
    switch (type) {
      case VisitType.outpatient: return Icons.local_hospital;
      case VisitType.emergency: return Icons.emergency;
      case VisitType.inpatient: return Icons.hotel;
      case VisitType.checkup: return Icons.health_and_safety;
      case VisitType.vaccination: return Icons.vaccines;
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.icon, required this.color});
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _AnnualData {
  const _AnnualData({
    required this.totalVisits,
    required this.totalCost,
    required this.hospitalDist,
    required this.tagDist,
    required this.visitTypeDist,
    required this.monthlyVisits,
    required this.personDist,
  });

  final int totalVisits;
  final double totalCost;
  final Map<String, int> hospitalDist;
  final Map<String, int> tagDist;
  final Map<String, int> visitTypeDist;
  final Map<int, int> monthlyVisits;
  final Map<String, int> personDist;
}
