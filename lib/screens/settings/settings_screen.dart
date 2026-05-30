import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // Data section
          _SectionHeader(title: '数据管理'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('导出数据 (JSON)'),
            subtitle: const Text('完整备份，可用于恢复'),
            trailing: _exporting
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _exporting ? null : _exportJson,
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('导出数据 (Excel)'),
            subtitle: const Text('表格格式，方便电脑查看'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _exportExcel,
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('导入数据 (JSON)'),
            subtitle: const Text('从备份文件恢复数据'),
            trailing: _importing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _importing ? null : _importJson,
          ),
          const Divider(indent: 16, endIndent: 16),

          // Maintenance
          _SectionHeader(title: '维护'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理残留图片'),
            subtitle: const Text('清理已删除病例的残留附件文件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _cleanOrphanedFiles,
          ),
          const Divider(indent: 16, endIndent: 16),

          // About
          _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于家庭健康档案'),
            subtitle: const Text('v1.0.0'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAbout(context),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('使用帮助'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showHelp(context),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _exportJson() async {
    setState(() => _exporting = true);
    try {
      final db = await ref.read(databaseProvider.future);
      final data = await db.exportAllData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);

      final dir = await getApplicationDocumentsDirectory();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/health_backup_$now.json');
      await file.writeAsString(jsonStr);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: '家庭健康档案备份',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导出成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    try {
      final db = await ref.read(databaseProvider.future);
      final data = await db.exportAllData();

      final persons = data['persons'] as List<dynamic>;
      final records = data['medical_records'] as List<dynamic>;

      // Build a simple CSV-like text for sharing
      final buffer = StringBuffer();
      buffer.writeln('=== 人员列表 ===');
      buffer.writeln('姓名,类型,关系,性别,出生日期');
      for (final p in persons) {
        final m = p as Map<String, dynamic>;
        buffer.writeln('${m['name']},${m['type']},${m['relationship']},${m['gender'] ?? ''},${m['birth_date'] ?? ''}');
      }
      buffer.writeln();
      buffer.writeln('=== 就诊记录 ===');
      buffer.writeln('就诊时间,医院,就诊类型,诊断,医生,花费');
      for (final r in records) {
        final m = r as Map<String, dynamic>;
        final time = DateTime.fromMillisecondsSinceEpoch(m['visit_time'] as int);
        buffer.writeln(
            '${DateFormat('yyyy-MM-dd HH:mm').format(time)},${m['hospital']},${m['visit_type']},${m['diagnosis'] ?? ''},${m['doctor_name'] ?? ''},${m['cost'] ?? ''}');
      }

      final dir = await getApplicationDocumentsDirectory();
      final now = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/health_export_$now.csv');
      await file.writeAsString(buffer.toString(), encoding: utf8);

      if (mounted) {
        await Share.shareXFiles(
          [XFile(file.path)],
          subject: '家庭健康档案数据导出',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  Future<void> _importJson() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: const Text('导入将覆盖当前所有数据，确定继续？\n\n建议先导出当前数据备份。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('继续')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _importing = false);
        return;
      }

      final path = result.files.first.path;
      if (path == null) {
        setState(() => _importing = false);
        return;
      }

      final file = File(path);
      final jsonStr = await file.readAsString();
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      final db = await ref.read(databaseProvider.future);
      await db.importAllData(data);

      // Refresh all providers
      ref.invalidate(personsProvider);
      ref.invalidate(recordsForSelectedPersonProvider);
      ref.invalidate(allRecordsProvider);
      ref.invalidate(activeRemindersProvider);
      ref.invalidate(archivedRemindersProvider);
      ref.invalidate(allTagsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('导入成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _cleanOrphanedFiles() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理残留图片'),
        content: const Text('将清理已删除病例的残留附件文件，释放存储空间。继续？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('清理')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final attRepo = await ref.read(attachmentRepositoryProvider.future);
      final cleaned = await attRepo.cleanOrphanedFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理完成，释放了 $cleaned 个文件')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败: $e')),
        );
      }
    }
  }

  void _showAbout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于家庭健康档案'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本：v1.0.0'),
            SizedBox(height: 8),
            Text('管理个人及家人/宠物的就诊记录、健康数据与用药提醒。'),
            SizedBox(height: 8),
            Text('所有数据存储在本地，不会上传到任何服务器。'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
        ],
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('使用帮助'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🏠 时间轴', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('默认显示本人的就诊记录。顶部头像栏可切换成员，长按头像可编辑人员信息。'),
              SizedBox(height: 12),
              Text('➕ 添加就诊', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('点击右下角 + 按钮添加就诊记录。支持门诊、急诊、住院、体检、疫苗接种等类型。'),
              SizedBox(height: 12),
              Text('📎 附件管理', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('每个就诊记录可上传病例、检查报告、处方、发票等图片和PDF文件。'),
              SizedBox(height: 12),
              Text('🔔 提醒功能', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('可设置用药提醒、复查提醒等。支持一次性、每天、每周、每月、每年重复。'),
              SizedBox(height: 12),
              Text('⚖️ 体重记录', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('在人员详情页可查看体重变化曲线，支持添加和删除记录。'),
              SizedBox(height: 12),
              Text('📊 年度回顾', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('查看年度就诊统计、花费分布、病情分布等。'),
              SizedBox(height: 12),
              Text('🔍 搜索', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('支持按关键词、人员、医院、就诊类型等多维度筛选。'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
