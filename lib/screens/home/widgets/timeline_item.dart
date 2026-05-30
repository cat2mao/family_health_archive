import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/enums.dart';
import '../../../data/database/app_database.dart';

class TimelineItem extends StatelessWidget {
  const TimelineItem({
    super.key,
    required this.record,
    required this.isFirst,
    required this.isLast,
    this.onTap,
  });

  final MedicalRecordRow record;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _moneyFmt = NumberFormat.currency(locale: 'zh_CN', symbol: '¥');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visitLabel = record.recordVisitType.label;
    final dateStr = _dateFmt.format(record.visitTime);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    width: 2,
                    color: isFirst
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _visitTypeColor(record.recordVisitType),
                    border: Border.all(
                      color: theme.colorScheme.surface,
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 8 : 20),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              dateStr,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Chip(
                              label: Text(visitLabel),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              labelStyle: theme.textTheme.labelSmall,
                              backgroundColor: _visitTypeColor(record.recordVisitType)
                                  .withValues(alpha: 0.15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (record.hospital.isNotEmpty)
                          Row(
                            children: [
                              Icon(Icons.local_hospital, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  record.hospital,
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ),
                            ],
                          ),
                        if (record.diagnosis != null && record.diagnosis!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              record.diagnosis!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (record.doctorName != null && record.doctorName!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '医生：${record.doctorName}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (record.cost != null)
                              Text(
                                _moneyFmt.format(record.cost),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const Spacer(),
                            Icon(
                              Icons.chevron_right,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
}
