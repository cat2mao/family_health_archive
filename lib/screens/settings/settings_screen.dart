import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

import '../../providers/app_providers.dart';
import '../../services/ai_ocr_service.dart';
import '../../services/notification_service.dart';

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

          // AI OCR settings
          _SectionHeader(title: 'AI 智能识别'),
          _AiOcrSettings(),
          const Divider(indent: 16, endIndent: 16),

          // Notification test
          _SectionHeader(title: '通知测试'),
          ListTile(
            leading: const Icon(Icons.notifications_active),
            title: const Text('测试通知'),
            subtitle: const Text('发送一条 5 秒后的测试通知'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _testNotification,
          ),
          ListTile(
            leading: const Icon(Icons.alarm),
            title: const Text('查看待发通知'),
            subtitle: const Text('查看当前所有已调度的通知'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showPendingNotifications,
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('通知权限设置'),
            subtitle: const Text('打开系统通知权限设置页面'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await openAppSettings();
            },
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
            subtitle: const Text('v1.0.4'),
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

  Future<void> _testNotification() async {
    try {
      await NotificationService.requestPermissions();
      final scheduledTime = DateTime.now().add(const Duration(seconds: 5));
      await NotificationService.scheduleReminder(
        id: 999999,
        title: '测试通知',
        body: '这是一条测试通知，通知功能正常工作！',
        scheduledTime: scheduledTime,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('测试通知已发送，5 秒后显示')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    }
  }

  Future<void> _showPendingNotifications() async {
    try {
      final pending = await NotificationService.getPendingNotifications();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('待发通知'),
          content: SizedBox(
            width: double.maxFinite,
            child: pending.isEmpty
                ? const Text('暂无待发通知')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: pending.length,
                    itemBuilder: (context, index) {
                      final n = pending[index];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.notifications_outlined, size: 20),
                        title: Text(n.title ?? '无标题'),
                        subtitle: Text(n.body ?? '无内容'),
                        trailing: Text('ID: ${n.id}'),
                      );
                    },
                  ),
          ),
          actions: [
            if (pending.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await NotificationService.cancelAll();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清除所有通知')),
                    );
                  }
                },
                child: const Text('清除全部'),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取失败: $e')),
        );
      }
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
            Text('版本：v1.0.4'),
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

/// AI provider preset configuration
class _AiProvider {
  final String name;
  final String defaultEndpoint;
  final String defaultModel;
  final List<String> models;
  final List<String> endpoints;

  const _AiProvider({
    required this.name,
    required this.defaultEndpoint,
    required this.defaultModel,
    required this.models,
    required this.endpoints,
  });
}

const List<_AiProvider> _aiProviders = [
  _AiProvider(
    name: 'DeepSeek',
    defaultEndpoint: 'https://api.deepseek.com/v1',
    defaultModel: 'deepseek-chat',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    endpoints: ['https://api.deepseek.com/v1'],
  ),
  _AiProvider(
    name: 'Kimi (Moonshot)',
    defaultEndpoint: 'https://api.moonshot.cn/v1',
    defaultModel: 'moonshot-v1-8k',
    models: ['moonshot-v1-8k', 'moonshot-v1-32k', 'moonshot-v1-128k'],
    endpoints: ['https://api.moonshot.cn/v1'],
  ),
  _AiProvider(
    name: 'MiMo (小米)',
    defaultEndpoint: 'https://api.mimo.ai/v1',
    defaultModel: 'mimo-7b',
    models: ['mimo-7b'],
    endpoints: ['https://api.mimo.ai/v1'],
  ),
  _AiProvider(
    name: 'OpenAI',
    defaultEndpoint: 'https://api.openai.com/v1',
    defaultModel: 'gpt-4o-mini',
    models: ['gpt-4o-mini', 'gpt-4o', 'gpt-3.5-turbo'],
    endpoints: ['https://api.openai.com/v1'],
  ),
  _AiProvider(
    name: '通义千问 (阿里)',
    defaultEndpoint: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-turbo',
    models: ['qwen-turbo', 'qwen-plus', 'qwen-max'],
    endpoints: ['https://dashscope.aliyuncs.com/compatible-mode/v1'],
  ),
  _AiProvider(
    name: '文心一言 (百度)',
    defaultEndpoint: 'https://aip.baidubce.com/rpc/2.0/ai_custom/v1',
    defaultModel: 'ernie-4.0-8k',
    models: ['ernie-4.0-8k', 'ernie-3.5-8k'],
    endpoints: ['https://aip.baidubce.com/rpc/2.0/ai_custom/v1'],
  ),
  _AiProvider(
    name: '自定义',
    defaultEndpoint: '',
    defaultModel: '',
    models: [],
    endpoints: [],
  ),
];

class _AiOcrSettings extends StatefulWidget {
  const _AiOcrSettings();

  @override
  State<_AiOcrSettings> createState() => _AiOcrSettingsState();
}

class _AiOcrSettingsState extends State<_AiOcrSettings> {
  final _apiKeyController = TextEditingController();
  final _customEndpointController = TextEditingController();
  final _customModelController = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _testing = false;
  bool _checkingModels = false;

  int _selectedProviderIndex = 0;
  int _selectedModelIndex = 0;
  int _selectedEndpointIndex = 0;

  // Fetched models from API
  List<String> _fetchedModels = [];
  String? _selectedFetchedModel;
  bool _useFetchedModels = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  _AiProvider get _currentProvider => _aiProviders[_selectedProviderIndex];
  bool get _isCustom => _currentProvider.name == '自定义';

  String get _currentEndpoint {
    if (_isCustom) return _customEndpointController.text.trim();
    return _currentProvider.endpoints.isNotEmpty
        ? _currentProvider.endpoints[_selectedEndpointIndex]
        : _currentProvider.defaultEndpoint;
  }

  Future<void> _loadConfig() async {
    final config = await AiOcrService.getConfig();
    if (!mounted) return;

    final savedModel = config['model']!;
    final savedEndpoint = config['endpoint']!;

    int matchedProvider = _aiProviders.length - 1;
    for (int i = 0; i < _aiProviders.length - 1; i++) {
      if (_aiProviders[i].endpoints.contains(savedEndpoint)) {
        matchedProvider = i;
        break;
      }
    }

    setState(() {
      _apiKeyController.text = config['apiKey']!;
      _enabled = config['enabled'] == 'true';
      _selectedProviderIndex = matchedProvider;

      if (_isCustom) {
        _customEndpointController.text = savedEndpoint;
        _customModelController.text = savedModel;
      } else {
        final provider = _aiProviders[matchedProvider];
        final modelIdx = provider.models.indexOf(savedModel);
        _selectedModelIndex = modelIdx >= 0 ? modelIdx : 0;
        final endIdx = provider.endpoints.indexOf(savedEndpoint);
        _selectedEndpointIndex = endIdx >= 0 ? endIdx : 0;
      }

      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    String endpoint;
    String model;

    if (_useFetchedModels && _selectedFetchedModel != null) {
      endpoint = _currentEndpoint;
      model = _selectedFetchedModel!;
    } else if (_isCustom) {
      endpoint = _customEndpointController.text.trim();
      model = _customModelController.text.trim();
    } else {
      endpoint = _currentProvider.endpoints.isNotEmpty
          ? _currentProvider.endpoints[_selectedEndpointIndex]
          : _currentProvider.defaultEndpoint;
      model = _currentProvider.models.isNotEmpty
          ? _currentProvider.models[_selectedModelIndex]
          : _currentProvider.defaultModel;
    }

    await AiOcrService.saveConfig(
      apiKey: _apiKeyController.text.trim(),
      endpoint: endpoint.isEmpty ? 'https://api.openai.com/v1' : endpoint,
      model: model.isEmpty ? 'gpt-4o-mini' : model,
      enabled: _enabled,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 配置已保存')),
      );
    }
  }

  /// Fetch available models from the API
  Future<void> _fetchModels() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写 API Key')),
        );
      }
      return;
    }

    final endpoint = _currentEndpoint;
    if (endpoint.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写 API 地址')),
        );
      }
      return;
    }

    setState(() => _checkingModels = true);

    try {
      final url = Uri.parse('$endpoint/models');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['data'] as List<dynamic>?;
        if (modelsList != null && modelsList.isNotEmpty) {
          final models = modelsList
              .map((m) => m['id'] as String?)
              .where((id) => id != null && id.isNotEmpty)
              .cast<String>()
              .toList()
            ..sort();

          setState(() {
            _fetchedModels = models;
            _useFetchedModels = true;
            _selectedFetchedModel = models.isNotEmpty ? models.first : null;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ 获取到 ${models.length} 个模型'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ 未获取到模型列表，请检查 API Key 和地址'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ 获取模型失败: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 错误: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingModels = false);
    }
  }

  Future<void> _testConnection() async {
    if (_apiKeyController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写 API Key')),
        );
      }
      return;
    }

    await _saveConfig();
    setState(() => _testing = true);

    try {
      final result = await AiOcrService.analyzeWithAi('测试连接请回复"连接成功"。');

      if (mounted) {
        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ 连接成功！AI 接口正常工作'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ 连接失败，请检查配置'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 错误: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customEndpointController.dispose();
    _customModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('启用 AI 辅助识别'),
          subtitle: const Text('使用 AI 提升 OCR 识别准确率'),
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _saveConfig();
          },
        ),
        if (_enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // 1. Provider selection (服务商)
                Text('服务商', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  value: _selectedProviderIndex,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud_outlined),
                    isDense: true,
                  ),
                  items: List.generate(_aiProviders.length, (i) {
                    return DropdownMenuItem(
                      value: i,
                      child: Text(_aiProviders[i].name),
                    );
                  }),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedProviderIndex = v;
                      _selectedModelIndex = 0;
                      _selectedEndpointIndex = 0;
                      _fetchedModels = [];
                      _useFetchedModels = false;
                      _selectedFetchedModel = null;
                    });
                  },
                ),
                const SizedBox(height: 12),

                // 2. API Key with check button
                Text('API Key', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _apiKeyController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.key),
                          hintText: 'sk-xxx...',
                          isDense: true,
                        ),
                        obscureText: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _checkingModels ? null : _fetchModels,
                        icon: _checkingModels
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.search, size: 18),
                        label: Text(_checkingModels ? '检查中...' : '检查'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 3. Endpoint display/edit
                Text('API 地址', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                if (_isCustom)
                  TextFormField(
                    controller: _customEndpointController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                      hintText: 'https://api.example.com/v1',
                      isDense: true,
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _currentEndpoint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 12),

                // 4. Model selection
                if (_useFetchedModels && _fetchedModels.isNotEmpty) ...[
                  // Fetched models from API
                  Text('模型（已获取 ${_fetchedModels.length} 个）', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _selectedFetchedModel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.smart_toy_outlined),
                      isDense: true,
                    ),
                    items: _fetchedModels.map((m) {
                      return DropdownMenuItem(
                        value: m,
                        child: Text(m, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedFetchedModel = v);
                    },
                  ),
                  const SizedBox(height: 12),
                ] else if (_isCustom) ...[
                  // Custom model text field
                  Text('模型名称', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  TextFormField(
                    controller: _customModelController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.smart_toy_outlined),
                      hintText: 'gpt-4o-mini',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  // Preset models dropdown
                  Text('模型', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: _selectedModelIndex < _currentProvider.models.length
                        ? _selectedModelIndex
                        : 0,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.smart_toy_outlined),
                      isDense: true,
                    ),
                    items: List.generate(_currentProvider.models.length, (i) {
                      final isDefault = i == 0;
                      return DropdownMenuItem(
                        value: i,
                        child: Row(
                          children: [
                            Text(_currentProvider.models[i]),
                            if (isDefault) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('推荐',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.primary)),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedModelIndex = v);
                    },
                  ),
                  const SizedBox(height: 12),
                ],

                // 5. Test connection button
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.wifi_tethering, size: 18),
                        label: Text(_testing ? '测试中...' : '测试连接'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Info text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: theme.colorScheme.outline),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '选择服务商后，输入 API Key 并点击"检查"获取可用模型。选择模型后点击"测试连接"验证配置。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ],
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
