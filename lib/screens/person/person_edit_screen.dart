import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/avatar_service.dart';
import '../../widgets/person_avatar.dart';

class PersonEditScreen extends ConsumerStatefulWidget {
  const PersonEditScreen({super.key, this.personId});

  final String? personId;

  @override
  ConsumerState<PersonEditScreen> createState() => _PersonEditScreenState();
}

class _PersonEditScreenState extends ConsumerState<PersonEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _breedController = TextEditingController();
  final _chipController = TextEditingController();
  final _bloodTypeController = TextEditingController();
  final _allergiesController = TextEditingController();
  final _chronicController = TextEditingController();
  final _medsController = TextEditingController();

  PersonType _type = PersonType.human;
  Relationship _relationship = Relationship.other;
  Gender? _gender;
  String? _birthDate;
  String? _avatarPath;
  bool _neutered = false;
  bool _loading = true;
  bool _saving = false;
  PersonRow? _existing;

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  bool get _isEdit => widget.personId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.personId == null) {
      setState(() => _loading = false);
      return;
    }
    final repo = await ref.read(personRepositoryProvider.future);
    final row = await repo.getById(widget.personId!);
    if (row != null && mounted) {
      _existing = row;
      _nameController.text = row.name;
      _type = row.personType;
      _relationship = row.personRelationship;
      _gender = row.personGender;
      _birthDate = row.birthDate;
      _avatarPath = row.avatarPath;
      _breedController.text = row.breed ?? '';
      _chipController.text = row.chipId ?? '';
      _neutered = row.neutered ?? false;
      _bloodTypeController.text = row.bloodType ?? '';
      _allergiesController.text = row.allergies ?? '';
      _chronicController.text = row.chronicDiseases ?? '';
      _medsController.text = row.longTermMeds ?? '';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _breedController.dispose();
    _chipController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _chronicController.dispose();
    _medsController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, maxWidth: 800, imageQuality: 85);
    if (file == null) return;
    final path = await AvatarService.saveAvatarFromFile(File(file.path));
    if (mounted) setState(() => _avatarPath = path);
  }

  Future<void> _pickBirthDate() async {
    final initial = _birthDate != null ? _dateFmt.parse(_birthDate!) : DateTime(1990);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'CN'),
    );
    if (picked != null) {
      setState(() => _birthDate = _dateFmt.format(picked));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = await ref.read(personRepositoryProvider.future);

    try {
      if (_isEdit && _existing != null) {
        final updated = _existing!.copyWith(
          name: _nameController.text.trim(),
          avatarPath: _avatarPath,
          type: _type.code,
          relationship: _relationship.code,
          gender: _gender?.code,
          birthDate: _birthDate,
          bloodType: _bloodTypeController.text.trim().isEmpty
              ? null
              : _bloodTypeController.text.trim(),
          allergies: _allergiesController.text.trim().isEmpty
              ? null
              : _allergiesController.text.trim(),
          chronicDiseases: _chronicController.text.trim().isEmpty
              ? null
              : _chronicController.text.trim(),
          longTermMeds: _medsController.text.trim().isEmpty
              ? null
              : _medsController.text.trim(),
          breed: _breedController.text.trim().isEmpty ? null : _breedController.text.trim(),
          neutered: _type == PersonType.human ? null : _neutered,
          chipId: _chipController.text.trim().isEmpty ? null : _chipController.text.trim(),
        );
        await repo.update(updated);
      } else {
        await repo.create(
          name: _nameController.text.trim(),
          type: _type,
          relationship: _relationship,
          avatarPath: _avatarPath,
          gender: _gender,
          birthDate: _birthDate,
          bloodType: _bloodTypeController.text.trim().isEmpty
              ? null
              : _bloodTypeController.text.trim(),
          allergies: _allergiesController.text.trim().isEmpty
              ? null
              : _allergiesController.text.trim(),
          chronicDiseases: _chronicController.text.trim().isEmpty
              ? null
              : _chronicController.text.trim(),
          longTermMeds: _medsController.text.trim().isEmpty
              ? null
              : _medsController.text.trim(),
          breed: _breedController.text.trim().isEmpty ? null : _breedController.text.trim(),
          neutered: _type == PersonType.human ? null : _neutered,
          chipId: _chipController.text.trim().isEmpty ? null : _chipController.text.trim(),
        );
      }
      ref.invalidate(personsProvider);
      ref.invalidate(recordsForSelectedPersonProvider);
      if (context.mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isHuman = _type == PersonType.human;
    final isPet = !isHuman;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑档案' : '添加人员'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  PersonAvatar(
                    avatarPath: _avatarPath,
                    name: _nameController.text.isEmpty ? '?' : _nameController.text,
                    type: _type,
                    radius: 48,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: () => _pickAvatar(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('拍照'),
                      ),
                      TextButton.icon(
                        onPressed: () => _pickAvatar(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 18),
                        label: const Text('相册'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '姓名/昵称',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请输入姓名' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PersonType>(
              value: _type,
              decoration: const InputDecoration(
                labelText: '类型',
                border: OutlineInputBorder(),
              ),
              items: PersonType.values
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                  .toList(),
              onChanged: _existing?.relationship == Relationship.self.code
                  ? null
                  : (v) {
                      if (v != null) setState(() => _type = v);
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Relationship>(
              value: _relationship,
              decoration: const InputDecoration(
                labelText: '关系',
                border: OutlineInputBorder(),
              ),
              items: Relationship.values
                  .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                  .toList(),
              onChanged: _existing?.relationship == Relationship.self.code
                  ? null
                  : (v) {
                      if (v != null) setState(() => _relationship = v);
                    },
            ),
            if (isHuman) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Gender>(
                value: _gender ?? Gender.unknown,
                decoration: const InputDecoration(
                  labelText: '性别',
                  border: OutlineInputBorder(),
                ),
                items: Gender.values
                    .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                    .toList(),
                onChanged: (v) => setState(() => _gender = v),
              ),
            ],
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('出生日期'),
              subtitle: Text(_birthDate ?? '未设置'),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickBirthDate,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            if (isHuman) ...[
              const SizedBox(height: 16),
              Text('紧急卡片信息', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              TextFormField(
                controller: _bloodTypeController,
                decoration: const InputDecoration(
                  labelText: '血型',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _allergiesController,
                decoration: const InputDecoration(
                  labelText: '过敏史',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _chronicController,
                decoration: const InputDecoration(
                  labelText: '慢性病',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _medsController,
                decoration: const InputDecoration(
                  labelText: '长期用药',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
            if (isPet) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _breedController,
                decoration: const InputDecoration(
                  labelText: '品种',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('已绝育'),
                value: _neutered,
                onChanged: (v) => setState(() => _neutered = v),
              ),
              TextFormField(
                controller: _chipController,
                decoration: const InputDecoration(
                  labelText: '芯片号（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
