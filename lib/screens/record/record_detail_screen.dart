import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../widgets/fullscreen_image_viewer.dart';

class RecordDetailScreen extends ConsumerStatefulWidget {
  const RecordDetailScreen({super.key, required this.recordId});
  final String recordId;

  @override
  ConsumerState<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends ConsumerState<RecordDetailScreen> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _moneyFmt = NumberFormat.currency(locale: 'zh_CN', symbol: '¥');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FutureBuilder<MedicalRecordRow?>(
      future: ref.read(medicalRecordRepositoryProvider.future).then((r) => r.getById(widget.recordId)),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('就诊详情')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final record = snapshot.data;
        if (record == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('就诊详情')),
            body: const Center(child: Text('记录不存在')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('就诊详情'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => context.push('/record/edit?recordId=${record.id}').then((_) => setState(() {})),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteRecord(record),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header card
              _buildCopyableCard(
                copyText: _buildHeaderCopyText(record),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today, size: 20, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              _dateFmt.format(record.visitTime),
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            Chip(
                              label: Text(record.recordVisitType.label),
                              backgroundColor: _visitTypeColor(record.recordVisitType).withValues(alpha: 0.15),
                            ),
                          ],
                        ),
                        if (record.hospital.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(Icons.local_hospital, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(record.hospital, style: theme.textTheme.bodyLarge),
                            ],
                          ),
                        ],
                        if (record.location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.meeting_room, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text(record.location, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ],
                        if (record.cost != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.payments, size: 18, color: theme.colorScheme.secondary),
                              const SizedBox(width: 8),
                              Text(
                                _moneyFmt.format(record.cost),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.secondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Visit-type specific fields
              _buildTypeSpecificCard(context, record),
              const SizedBox(height: 12),

              // Tags
              _buildTagsSection(context),
              const SizedBox(height: 12),

              // Treatment
              if (record.treatment != null && record.treatment!.isNotEmpty)
                _buildCopyableCard(
                  copyText: '处置: ${record.treatment!}',
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('处置', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Text(record.treatment!, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              if (record.treatment != null && record.treatment!.isNotEmpty)
                const SizedBox(height: 12),

              // Medicine (prescription)
              if (record.medicine != null && record.medicine!.isNotEmpty)
                _buildMedicineCard(context, record.medicine!),
              if (record.medicine != null && record.medicine!.isNotEmpty)
                const SizedBox(height: 12),

              // Notes
              if (record.notes != null && record.notes!.isNotEmpty)
                _buildCopyableCard(
                  copyText: '备注: ${record.notes!}',
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('备注', style: theme.textTheme.titleSmall),
                          const SizedBox(height: 8),
                          Text(record.notes!, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ),
              if (record.notes != null && record.notes!.isNotEmpty)
                const SizedBox(height: 12),

              // Attachments
              _buildAttachmentsSection(context),
              const SizedBox(height: 12),

              // Reminders
              _buildRemindersSection(context),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/record/edit?recordId=${record.id}').then((_) => setState(() {})),
                      icon: const Icon(Icons.edit),
                      label: const Text('编辑'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        final personId = ref.read(selectedPersonIdProvider);
                        context.push('/reminder/edit?personId=$personId&recordId=${record.id}');
                      },
                      icon: const Icon(Icons.add_alarm),
                      label: const Text('添加提醒'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeSpecificCard(BuildContext context, MedicalRecordRow record) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (record.recordVisitType == VisitType.outpatient || record.recordVisitType == VisitType.emergency) {
      if (record.symptoms != null && record.symptoms!.isNotEmpty) {
        children.add(_infoRow('症状', record.symptoms!));
      }
      if (record.diagnosis != null && record.diagnosis!.isNotEmpty) {
        children.add(_infoRow('诊断', record.diagnosis!));
      }
      if (record.doctorName != null && record.doctorName!.isNotEmpty) {
        children.add(_infoRow('医生', record.doctorName!));
      }
    } else if (record.recordVisitType == VisitType.inpatient) {
      if (record.admissionDate != null) {
        children.add(_infoRow('入院日期', _dateFmt.format(record.admissionDate!)));
      }
      if (record.dischargeDate != null) {
        children.add(_infoRow('出院日期', _dateFmt.format(record.dischargeDate!)));
      }
      if (record.hospitalDays != null) {
        children.add(_infoRow('住院天数', '${record.hospitalDays}天'));
      }
      if (record.diagnosis != null && record.diagnosis!.isNotEmpty) {
        children.add(_infoRow('诊断', record.diagnosis!));
      }
      if (record.doctorName != null && record.doctorName!.isNotEmpty) {
        children.add(_infoRow('主治医生', record.doctorName!));
      }
    } else {
      if (record.focusOn != null && record.focusOn!.isNotEmpty) {
        children.add(_infoRow(record.recordVisitType == VisitType.vaccination ? '疫苗名称' : '重点关注', record.focusOn!));
      }
      if (record.result != null && record.result!.isNotEmpty) {
        children.add(_infoRow('结果摘要', record.result!));
      }
      if (record.doctorName != null && record.doctorName!.isNotEmpty) {
        children.add(_infoRow('医生', record.doctorName!));
      }
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('诊疗信息', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return GestureDetector(
      onLongPress: () => _copyToClipboard('$label: $value'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: const TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _buildHeaderCopyText(MedicalRecordRow record) {
    final parts = <String>[];
    parts.add('日期: ${_dateFmt.format(record.visitTime)}');
    parts.add('类型: ${record.recordVisitType.label}');
    if (record.hospital.isNotEmpty) parts.add('医院: ${record.hospital}');
    if (record.location.isNotEmpty) parts.add('科室: ${record.location}');
    if (record.cost != null) parts.add('费用: ${_moneyFmt.format(record.cost)}');
    return parts.join('\n');
  }

  /// Build a copyable card that copies all content on long press
  Widget _buildCopyableCard({required Widget child, required String copyText}) {
    return GestureDetector(
      onLongPress: () => _copyToClipboard(copyText),
      child: child,
    );
  }

  /// Parse medicine string into a list of (name, dosage) pairs.
  /// Supports both legacy newline-separated format and new JSON format.
  List<Map<String, String>> _parseMedicines(String medicine) {
    final trimmed = medicine.trim();
    // Try JSON format first
    if (trimmed.startsWith('[')) {
      try {
        final list = jsonDecode(trimmed) as List<dynamic>;
        return list.map((e) {
          final map = e as Map<String, dynamic>;
          return <String, String>{
            'name': (map['name'] ?? '').toString(),
            'dosage': (map['dosage'] ?? '').toString(),
          };
        }).toList();
      } catch (_) {
        // Fall through to legacy format
      }
    }
    // Legacy format: newline-separated names (possibly with ||| delimiter)
    return trimmed.split('\n').where((l) => l.trim().isNotEmpty).map((line) {
      final parts = line.split('|||');
      return <String, String>{
        'name': parts[0].trim(),
        'dosage': parts.length > 1 ? parts[1].trim() : '',
      };
    }).toList();
  }

  Widget _buildMedicineCard(BuildContext context, String medicine) {
    final theme = Theme.of(context);
    final medicines = _parseMedicines(medicine);
    if (medicines.isEmpty) return const SizedBox.shrink();

    // Build copy text for medicines
    final copyText = medicines.map((m) {
      final name = m['name'] ?? '';
      final dosage = m['dosage'] ?? '';
      return dosage.isNotEmpty ? '$name ($dosage)' : name;
    }).join('\n');

    return GestureDetector(
      onLongPress: () => _copyToClipboard('药品:\n$copyText'),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medication_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('药品', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Icon(Icons.copy, size: 14, color: theme.colorScheme.outline),
                ],
              ),
              const SizedBox(height: 8),
              ...medicines.map((m) {
                final name = m['name'] ?? '';
                final dosage = m['dosage'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                            if (dosage.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  dosage,
                                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagsSection(BuildContext context) {
    return FutureBuilder<List<TagRow>>(
      future: ref.read(tagRepositoryProvider.future).then((r) => r.getTagsForRecord(widget.recordId)),
      builder: (context, snapshot) {
        final tags = snapshot.data ?? [];
        if (tags.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('标签', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: tags.map((t) => Chip(label: Text(t.name))).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttachmentsSection(BuildContext context) {
    return FutureBuilder<List<AttachmentRow>>(
      future: ref.read(attachmentRepositoryProvider.future).then((r) => r.getByRecord(widget.recordId)),
      builder: (context, snapshot) {
        final attachments = snapshot.data ?? [];
        if (attachments.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);

        // Collect all image paths for the full-screen viewer
        final allImagePaths = attachments
            .where((a) => a.attachmentFileType != FileType.pdf)
            .map((a) => a.filePath)
            .toList();

        // Group by type
        final grouped = <String, List<AttachmentRow>>{};
        for (final a in attachments) {
          grouped.putIfAbsent(a.type, () => []).add(a);
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('附件 (${attachments.length})', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...grouped.entries.map((entry) {
                  final typeLabel = AttachmentType.fromCode(entry.key).label;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(typeLabel, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 80,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: entry.value.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final att = entry.value[index];
                            return _AttachmentThumb(attachment: att, allImagePaths: allImagePaths);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemindersSection(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ReminderRow>>(
      future: ref.read(reminderRepositoryProvider.future).then((r) => r.getAll()),
      builder: (context, snapshot) {
        final reminders = (snapshot.data ?? []).where((r) => r.recordId == widget.recordId).toList();
        if (reminders.isEmpty) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('关联提醒', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                ...reminders.map((r) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        r.isCompleted ? Icons.check_circle : Icons.alarm,
                        color: r.isCompleted ? Colors.green : theme.colorScheme.primary,
                      ),
                      title: Text(r.title),
                      subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(r.remindTime)),
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteRecord(MedicalRecordRow record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除就诊记录'),
        content: const Text('确定删除此就诊记录及其所有附件？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final attRepo = await ref.read(attachmentRepositoryProvider.future);
    await attRepo.deleteForRecord(record.id);
    final recRepo = await ref.read(medicalRecordRepositoryProvider.future);
    await recRepo.delete(record.id);
    ref.invalidate(recordsForSelectedPersonProvider);
    ref.invalidate(allRecordsProvider);
    if (context.mounted) context.pop();
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

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.attachment, required this.allImagePaths});
  final AttachmentRow attachment;
  final List<String> allImagePaths;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPdf = attachment.attachmentFileType == FileType.pdf;
    final thumbPath = attachment.thumbnailPath ?? attachment.filePath;

    return GestureDetector(
      onTap: () {
        if (!isPdf) {
          FullscreenImageViewer.show(
            context,
            imagePath: attachment.filePath,
          );
        }
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: isPdf
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf, color: theme.colorScheme.error, size: 32),
                  const SizedBox(height: 4),
                  Text('PDF', style: theme.textTheme.labelSmall),
                ],
              )
            : Image.file(File(thumbPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) {
                return Image.file(File(attachment.filePath), fit: BoxFit.cover);
              }),
      ),
    );
  }
}
