import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/app_providers.dart';
import '../../services/image_compress_service.dart';
import '../../widgets/person_avatar.dart';

class RecordEditScreen extends ConsumerStatefulWidget {
  const RecordEditScreen({super.key, this.recordId, this.personId});
  final String? recordId;
  final String? personId;

  @override
  ConsumerState<RecordEditScreen> createState() => _RecordEditScreenState();
}

class _RecordEditScreenState extends ConsumerState<RecordEditScreen> {
  final _formKey = GlobalKey<FormState>();
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _dateTimeFmt = DateFormat('yyyy-MM-dd HH:mm');

  // Form controllers
  final _hospitalController = TextEditingController();
  final _locationController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _doctorController = TextEditingController();
  final _focusOnController = TextEditingController();
  final _resultController = TextEditingController();
  final _notesController = TextEditingController();
  final _costController = TextEditingController();
  final _hospitalDaysController = TextEditingController();

  VisitType _visitType = VisitType.outpatient;
  DateTime _visitTime = DateTime.now();
  DateTime? _admissionDate;
  DateTime? _dischargeDate;
  String? _selectedPersonId;

  // Tags
  List<String> _selectedTagIds = [];

  // Attachments - grouped by type
  final Map<AttachmentType, List<_AttachmentDraft>> _attachmentDrafts = {};

  // Existing attachments (for edit mode)
  List<AttachmentRow> _existingAttachments = [];

  bool _loading = true;
  bool _saving = false;
  MedicalRecordRow? _existing;

  bool get _isEdit => widget.recordId != null;

  @override
  void initState() {
    super.initState();
    _selectedPersonId = widget.personId;
    for (final type in AttachmentType.values) {
      _attachmentDrafts[type] = [];
    }
    _load();
  }

  Future<void> _load() async {
    if (widget.recordId != null) {
      final repo = await ref.read(medicalRecordRepositoryProvider.future);
      final row = await repo.getById(widget.recordId!);
      if (row != null && mounted) {
        _existing = row;
        _selectedPersonId = row.personId;
        _visitType = row.recordVisitType;
        _visitTime = row.visitTime;
        _hospitalController.text = row.hospital;
        _locationController.text = row.location;
        _symptomsController.text = row.symptoms ?? '';
        _diagnosisController.text = row.diagnosis ?? '';
        _doctorController.text = row.doctorName ?? '';
        _focusOnController.text = row.focusOn ?? '';
        _resultController.text = row.result ?? '';
        _notesController.text = row.notes ?? '';
        _costController.text = row.cost?.toString() ?? '';
        _admissionDate = row.admissionDate;
        _dischargeDate = row.dischargeDate;
        _hospitalDaysController.text = row.hospitalDays?.toString() ?? '';

        // Load existing tags
        final tagRepo = await ref.read(tagRepositoryProvider.future);
        final tags = await tagRepo.getTagsForRecord(row.id);
        _selectedTagIds = tags.map((t) => t.id).toList();

        // Load existing attachments
        final attRepo = await ref.read(attachmentRepositoryProvider.future);
        _existingAttachments = await attRepo.getByRecord(row.id);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _hospitalController.dispose();
    _locationController.dispose();
    _symptomsController.dispose();
    _diagnosisController.dispose();
    _doctorController.dispose();
    _focusOnController.dispose();
    _resultController.dispose();
    _notesController.dispose();
    _costController.dispose();
    _hospitalDaysController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _visitTime,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'CN'),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_visitTime),
    );
    if (time == null) return;
    setState(() {
      _visitTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickDate({required bool isAdmission}) async {
    final initial = isAdmission ? _admissionDate ?? DateTime.now() : _dischargeDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'CN'),
    );
    if (picked == null) return;
    setState(() {
      if (isAdmission) {
        _admissionDate = picked;
      } else {
        _dischargeDate = picked;
      }
      if (_admissionDate != null && _dischargeDate != null) {
        _hospitalDaysController.text = _dischargeDate!.difference(_admissionDate!).inDays.toString();
      }
    });
  }

  Future<void> _addImageAttachment(AttachmentType type, ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file == null) return;

    final original = File(file.path);
    final compressed = await ImageCompressService.compressImage(original);
    if (compressed == null) return;

    final thumb = await ImageCompressService.generateThumbnail(compressed);

    setState(() {
      _attachmentDrafts[type]!.add(_AttachmentDraft(
        filePath: compressed.path,
        thumbnailPath: thumb,
        fileType: FileType.image,
      ));
    });
  }

  Future<void> _addPdfAttachment(AttachmentType type) async {
    final result = await fp.FilePicker.platform.pickFiles(
      type: fp.FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _attachmentDrafts[type]!.add(_AttachmentDraft(
        filePath: path,
        fileType: FileType.pdf,
      ));
    });
  }

  void _removeDraft(AttachmentType type, int index) {
    setState(() {
      _attachmentDrafts[type]!.removeAt(index);
    });
  }

  Future<void> _removeExistingAttachment(AttachmentRow att) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除附件'),
        content: const Text('确定删除此附件？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final attRepo = await ref.read(attachmentRepositoryProvider.future);
    await attRepo.delete(att.id);
    setState(() {
      _existingAttachments.removeWhere((a) => a.id == att.id);
    });
  }

  Future<void> _showTagPicker() async {
    final tagRepo = await ref.read(tagRepositoryProvider.future);
    final allTags = await tagRepo.getAll();

    if (!mounted) return;

    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TagPickerSheet(
        allTags: allTags,
        selectedIds: _selectedTagIds,
      ),
    );

    if (selected != null) {
      setState(() => _selectedTagIds = selected);
    }
  }

  bool _hasPrescriptionAttachments() {
    final newDrafts = _attachmentDrafts[AttachmentType.prescription] ?? [];
    final existingPrescriptions = _existingAttachments.where((a) => a.type == AttachmentType.prescription.code);
    return newDrafts.isNotEmpty || existingPrescriptions.isNotEmpty;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final recordRepo = await ref.read(medicalRecordRepositoryProvider.future);
      final tagRepo = await ref.read(tagRepositoryProvider.future);
      final attRepo = await ref.read(attachmentRepositoryProvider.future);

      final cost = _costController.text.trim().isEmpty
          ? null
          : double.tryParse(_costController.text.trim());

      MedicalRecordRow record;

      if (_isEdit && _existing != null) {
        // Update existing
        record = MedicalRecordRow(
          id: _existing!.id,
          personId: _selectedPersonId!,
          visitTime: _visitTime,
          location: _locationController.text.trim(),
          hospital: _hospitalController.text.trim(),
          visitType: _visitType.code,
          symptoms: _symptomsController.text.trim().isEmpty ? null : _symptomsController.text.trim(),
          diagnosis: _diagnosisController.text.trim().isEmpty ? null : _diagnosisController.text.trim(),
          doctorName: _doctorController.text.trim().isEmpty ? null : _doctorController.text.trim(),
          admissionDate: _admissionDate,
          dischargeDate: _dischargeDate,
          hospitalDays: _hospitalDaysController.text.trim().isEmpty ? null : int.tryParse(_hospitalDaysController.text.trim()),
          focusOn: _focusOnController.text.trim().isEmpty ? null : _focusOnController.text.trim(),
          result: _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          cost: cost,
          createdAt: _existing!.createdAt,
        );
        await recordRepo.update(record);
      } else {
        record = await recordRepo.create(
          personId: _selectedPersonId!,
          visitTime: _visitTime,
          location: _locationController.text.trim(),
          hospital: _hospitalController.text.trim(),
          visitType: _visitType,
          symptoms: _symptomsController.text.trim().isEmpty ? null : _symptomsController.text.trim(),
          diagnosis: _diagnosisController.text.trim().isEmpty ? null : _diagnosisController.text.trim(),
          doctorName: _doctorController.text.trim().isEmpty ? null : _doctorController.text.trim(),
          admissionDate: _admissionDate,
          dischargeDate: _dischargeDate,
          hospitalDays: _hospitalDaysController.text.trim().isEmpty ? null : int.tryParse(_hospitalDaysController.text.trim()),
          focusOn: _focusOnController.text.trim().isEmpty ? null : _focusOnController.text.trim(),
          result: _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          cost: cost,
        );
      }

      // Save tags
      await tagRepo.setRecordTags(record.id, _selectedTagIds);

      // Save new attachments
      for (final entry in _attachmentDrafts.entries) {
        for (final draft in entry.value) {
          await attRepo.create(
            recordId: record.id,
            type: entry.key,
            filePath: draft.filePath,
            thumbnailPath: draft.thumbnailPath,
            fileType: draft.fileType,
          );
        }
      }

      // Prompt for medication reminder if prescription attached
      if (_hasPrescriptionAttachments() && mounted) {
        final createReminder = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('添加用药提醒？'),
            content: const Text('检测到已上传处方附件，是否为本次就诊添加用药提醒？'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('暂不')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
            ],
          ),
        );

        if (createReminder == true && mounted) {
          ref.invalidate(recordsForSelectedPersonProvider);
          ref.invalidate(allRecordsProvider);
          context.push('/reminder/edit?personId=$_selectedPersonId&recordId=${record.id}');
          return;
        }
      }

      ref.invalidate(recordsForSelectedPersonProvider);
      ref.invalidate(allRecordsProvider);
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final isHuman = true; // Simplified; could check person type
    final showOutpatientFields = _visitType == VisitType.outpatient || _visitType == VisitType.emergency;
    final showInpatientFields = _visitType == VisitType.inpatient;
    final showSimpleFields = _visitType == VisitType.checkup || _visitType == VisitType.vaccination;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑就诊记录' : '添加就诊记录'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Person selector
            _buildPersonSelector(context),
            const SizedBox(height: 16),

            // Visit type
            Text('就诊类型', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: VisitType.values.map((vt) {
                final selected = _visitType == vt;
                return ChoiceChip(
                  label: Text(vt.label),
                  selected: selected,
                  onSelected: (_) => setState(() => _visitType = vt),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Date/time
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time),
              title: const Text('就诊时间'),
              subtitle: Text(_dateTimeFmt.format(_visitTime)),
              onTap: _pickDateTime,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: theme.colorScheme.outline),
              ),
            ),
            const SizedBox(height: 12),

            // Hospital with autocomplete
            _buildHospitalField(),
            const SizedBox(height: 12),

            // Location
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: '地点',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),

            // Dynamic fields based on visit type
            if (showOutpatientFields) ..._buildOutpatientFields(),
            if (showInpatientFields) ..._buildInpatientFields(),
            if (showSimpleFields) ..._buildSimpleFields(),

            // Cost
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: '花费金额（可选）',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
                prefixText: '¥ ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: '备注',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Tags
            _buildTagSection(context),
            const SizedBox(height: 16),

            // Attachments
            _buildAttachmentSection(context),
            const SizedBox(height: 16),

            // Save button
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('保存就诊记录'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonSelector(BuildContext context) {
    final theme = Theme.of(context);
    final personsAsync = ref.watch(personsProvider);

    return personsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (persons) {
        final selected = persons.where((p) => p.id == _selectedPersonId).firstOrNull;
        return Card(
          child: ListTile(
            leading: selected != null
                ? PersonAvatar(
                    avatarPath: selected.avatarPath,
                    name: selected.name,
                    type: selected.personType,
                    radius: 20,
                  )
                : const Icon(Icons.person),
            title: Text(selected?.name ?? '选择人员'),
            subtitle: selected != null ? Text('${selected.personRelationship.label} · ${selected.personType.label}') : null,
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: () async {
              final chosen = await showModalBottomSheet<String>(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('选择人员', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                      ),
                      ...persons.map((p) => ListTile(
                            leading: PersonAvatar(
                              avatarPath: p.avatarPath,
                              name: p.name,
                              type: p.personType,
                              radius: 20,
                            ),
                            title: Text(p.name),
                            subtitle: Text('${p.personRelationship.label} · ${p.personType.label}'),
                            selected: p.id == _selectedPersonId,
                            onTap: () => Navigator.pop(ctx, p.id),
                          )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              );
              if (chosen != null) setState(() => _selectedPersonId = chosen);
            },
          ),
        );
      },
    );
  }

  Widget _buildHospitalField() {
    final hospitalsAsync = ref.watch(hospitalsProvider);

    return hospitalsAsync.when(
      loading: () => TextFormField(
        controller: _hospitalController,
        decoration: const InputDecoration(
          labelText: '医院名称',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.local_hospital_outlined),
        ),
      ),
      error: (_, __) => TextFormField(
        controller: _hospitalController,
        decoration: const InputDecoration(
          labelText: '医院名称',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.local_hospital_outlined),
        ),
      ),
      data: (hospitals) {
        return Autocomplete<String>(
          initialValue: TextEditingValue(text: _hospitalController.text),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return hospitals;
            return hospitals.where((h) => h.contains(textEditingValue.text));
          },
          onSelected: (value) => _hospitalController.text = value,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            // Sync controllers
            _hospitalController.text = controller.text;
            controller.addListener(() {
              _hospitalController.text = controller.text;
            });
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: '医院名称',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildOutpatientFields() {
    return [
      TextFormField(
        controller: _symptomsController,
        decoration: const InputDecoration(
          labelText: '症状',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.sick_outlined),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _diagnosisController,
        decoration: const InputDecoration(
          labelText: '诊断',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.medical_services_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildInpatientFields() {
    return [
      Row(
        children: [
          Expanded(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              dense: true,
              title: const Text('入院日期'),
              subtitle: Text(_admissionDate != null ? _dateFmt.format(_admissionDate!) : '请选择'),
              onTap: () => _pickDate(isAdmission: true),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              dense: true,
              title: const Text('出院日期'),
              subtitle: Text(_dischargeDate != null ? _dateFmt.format(_dischargeDate!) : '请选择'),
              onTap: () => _pickDate(isAdmission: false),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _hospitalDaysController,
        decoration: const InputDecoration(
          labelText: '住院天数',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.calendar_month_outlined),
        ),
        keyboardType: TextInputType.number,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _diagnosisController,
        decoration: const InputDecoration(
          labelText: '诊断',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.medical_services_outlined),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '主治医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildSimpleFields() {
    final isVaccine = _visitType == VisitType.vaccination;
    return [
      TextFormField(
        controller: _focusOnController,
        decoration: InputDecoration(
          labelText: isVaccine ? '疫苗名称' : '重点关注',
          border: const OutlineInputBorder(),
          prefixIcon: Icon(isVaccine ? Icons.vaccines_outlined : Icons.info_outline),
        ),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _resultController,
        decoration: const InputDecoration(
          labelText: '结果摘要',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.summarize_outlined),
        ),
        maxLines: 2,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildTagSection(BuildContext context) {
    final theme = Theme.of(context);
    final tagsAsync = ref.watch(allTagsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('标签', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: _showTagPicker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('选择标签'),
            ),
          ],
        ),
        if (_selectedTagIds.isNotEmpty)
          tagsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (allTags) {
              final selected = allTags.where((t) => _selectedTagIds.contains(t.id)).toList();
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: selected.map((t) => Chip(
                  label: Text(t.name),
                  onDeleted: () => setState(() => _selectedTagIds.remove(t.id)),
                )).toList(),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAttachmentSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('附件', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        ...AttachmentType.values.map((type) => _buildAttachmentTypeSection(context, type)),
      ],
    );
  }

  Widget _buildAttachmentTypeSection(BuildContext context, AttachmentType type) {
    final theme = Theme.of(context);
    final newDrafts = _attachmentDrafts[type] ?? [];
    final existing = _existingAttachments.where((a) => a.type == type.code).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Text(type.label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.camera_alt, size: 20),
                tooltip: '拍照',
                onPressed: () => _addImageAttachment(type, ImageSource.camera),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.photo, size: 20),
                tooltip: '相册',
                onPressed: () => _addImageAttachment(type, ImageSource.gallery),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                tooltip: 'PDF',
                onPressed: () => _addPdfAttachment(type),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        if (existing.isNotEmpty || newDrafts.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: existing.length + newDrafts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index < existing.length) {
                  final att = existing[index];
                  return _buildExistingAttachmentThumb(att);
                }
                final draft = newDrafts[index - existing.length];
                return _buildDraftThumb(type, index - existing.length, draft);
              },
            ),
          ),
        const Divider(height: 16),
      ],
    );
  }

  Widget _buildExistingAttachmentThumb(AttachmentRow att) {
    final theme = Theme.of(context);
    final isPdf = att.attachmentFileType == FileType.pdf;
    return Stack(
      children: [
        Container(
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
                    Text('PDF', style: theme.textTheme.labelSmall),
                  ],
                )
              : Image.file(
                  File(att.thumbnailPath ?? att.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.file(File(att.filePath), fit: BoxFit.cover),
                ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => _removeExistingAttachment(att),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDraftThumb(AttachmentType type, int index, _AttachmentDraft draft) {
    final theme = Theme.of(context);
    final isPdf = draft.fileType == FileType.pdf;
    return Stack(
      children: [
        Container(
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
                    Text('PDF', style: theme.textTheme.labelSmall),
                  ],
                )
              : Image.file(File(draft.filePath), fit: BoxFit.cover),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: GestureDetector(
            onTap: () => _removeDraft(type, index),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(2),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentDraft {
  _AttachmentDraft({
    required this.filePath,
    this.thumbnailPath,
    required this.fileType,
  });

  final String filePath;
  final String? thumbnailPath;
  final FileType fileType;
}

class _TagPickerSheet extends StatefulWidget {
  const _TagPickerSheet({required this.allTags, required this.selectedIds});
  final List<TagRow> allTags;
  final List<String> selectedIds;

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late List<String> _selected;
  final _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Group tags by category
    final hospitalTags = widget.allTags.where((t) => t.category == TagCategory.hospital.code).toList();
    final conditionTags = widget.allTags.where((t) => t.category == TagCategory.condition.code).toList();
    final customTags = widget.allTags.where((t) => t.category == TagCategory.custom.code).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('选择标签', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context, _selected),
                  child: const Text('确定'),
                ),
              ],
            ),
          ),
          // Add new custom tag
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTagController,
                    decoration: const InputDecoration(
                      hintText: '新建自定义标签',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFF2A9D8F)),
                onPressed: () async {
                    final name = _newTagController.text.trim();
                    if (name.isEmpty) return;
                    final container = ProviderScope.containerOf(context);
                    final tagRepo = await container.read(tagRepositoryProvider.future);
                    final tag = await tagRepo.getOrCreate(name: name, category: TagCategory.custom);
                    setState(() {
                      if (!_selected.contains(tag.id)) _selected.add(tag.id);
                      _newTagController.clear();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                if (conditionTags.isNotEmpty) ...[
                  Text('病情类别', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: conditionTags.map((t) => FilterChip(
                      label: Text(t.name),
                      selected: _selected.contains(t.id),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selected.add(t.id);
                          } else {
                            _selected.remove(t.id);
                          }
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (hospitalTags.isNotEmpty) ...[
                  Text('医院', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: hospitalTags.map((t) => FilterChip(
                      label: Text(t.name),
                      selected: _selected.contains(t.id),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selected.add(t.id);
                          } else {
                            _selected.remove(t.id);
                          }
                        });
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                if (customTags.isNotEmpty) ...[
                  Text('自定义', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: customTags.map((t) => FilterChip(
                      label: Text(t.name),
                      selected: _selected.contains(t.id),
                      onSelected: (sel) {
                        setState(() {
                          if (sel) {
                            _selected.add(t.id);
                          } else {
                            _selected.remove(t.id);
                          }
                        });
                      },
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
