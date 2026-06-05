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
import '../../services/ai_ocr_service.dart';
import '../../services/image_compress_service.dart';
import '../../services/ocr_service.dart';
import '../../widgets/fullscreen_image_viewer.dart';
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
  final _treatmentController = TextEditingController();
  final _notesController = TextEditingController();
  final _costController = TextEditingController();
  final _hospitalDaysController = TextEditingController();
  final _medicineController = TextEditingController();

  // Track individual invoice costs for breakdown display
  final List<double> _invoiceCosts = [];

  VisitType _visitType = VisitType.outpatient;
  DateTime _visitTime = DateTime.now();
  DateTime? _admissionDate;
  DateTime? _dischargeDate;
  String? _selectedPersonId;

  // Tags
  List<String> _selectedTagIds = [];

  // Attachments - grouped by type
  final Map<AttachmentType, List<_AttachmentDraft>> _attachmentDrafts = {};

  // OCR state
  bool _ocrProcessing = false;
  int _ocrProcessingCount = 0; // Track how many OCR tasks are running

  // Existing attachments (for edit mode)
  List<AttachmentRow> _existingAttachments = [];

  bool _loading = true;
  bool _saving = false;
  MedicalRecordRow? _existing;
  bool _hasChanges = false;

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
        _treatmentController.text = row.treatment ?? '';
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
    _treatmentController.dispose();
    _notesController.dispose();
    _costController.dispose();
    _hospitalDaysController.dispose();
    _medicineController.dispose();
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
      _markChanged();
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
      _markChanged();
    });
  }

  /// Add image attachment and auto-OCR it
  Future<void> _addImageAttachment(AttachmentType type, ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      maxWidth: 2048,
      imageQuality: 92,
    );
    if (file == null) return;

    final original = File(file.path);

    // Run OCR on the higher-quality original before compression
    // (OCR service does its own resizing/preprocessing internally)
    _autoOcrOnImage(original.path);

    // Compress for storage
    final compressed = await ImageCompressService.compressImage(original);
    if (compressed == null) return;

    final thumb = await ImageCompressService.generateThumbnail(compressed);

    setState(() {
      _attachmentDrafts[type]!.add(_AttachmentDraft(
        filePath: compressed.path,
        thumbnailPath: thumb,
        fileType: FileType.image,
      ));
      _markChanged();
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
      _markChanged();
    });
    // PDF files are not OCR'd (only local image OCR for privacy)
  }

  /// Automatically run OCR on uploaded image and offer to fill form fields
  Future<void> _autoOcrOnImage(String imagePath) async {
    setState(() {
      _ocrProcessing = true;
      _ocrProcessingCount++;
    });

    try {
      var data = await OcrService.recognizeFromFile(imagePath);

      // Try vision model first if enabled (sends image directly to AI)
      bool visionTried = false;
      if (await AiOcrService.isVisionEnabled() && await AiOcrService.isEnabled()) {
        try {
          final visionData = await AiOcrService.analyzeImageWithVision(imagePath);
          if (visionData != null && visionData.hasAnyData) {
            data = visionData;
            visionTried = true;
            debugPrint('Vision model OCR successful');
          }
        } catch (e) {
          debugPrint('Vision model failed, falling back: $e');
        }
      }

      // Try text-based AI enhancement if vision wasn't used or failed
      if (!visionTried && data.rawText != null && data.rawText!.isNotEmpty) {
        try {
          final aiData = await AiOcrService.analyzeWithAi(data.rawText!);
          if (aiData != null) {
            data = aiData;
          }
        } catch (e) {
          debugPrint('AI enhancement failed, using local OCR: $e');
        }
      }

      if (!mounted || !data.hasAnyData) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('未识别到文字内容，请手动填写'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Show editable OCR result sheet and get edited data
      final editedData = await showModalBottomSheet<OcrExtractedData>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        builder: (ctx) => _OcrResultSheet(data: data),
      );

      if (editedData != null && mounted) {
        setState(() {
          if (editedData.hospital != null) {
            if (_hospitalController.text.trim().isEmpty) {
              _hospitalController.text = editedData.hospital!;
            }
          }
          if (editedData.diagnosis != null) {
            final existing = _diagnosisController.text.trim();
            if (existing.isEmpty) {
              _diagnosisController.text = editedData.diagnosis!;
            } else if (!existing.contains(editedData.diagnosis!)) {
              _diagnosisController.text = '$existing; ${editedData.diagnosis!}';
            }
          }
          if (editedData.doctorName != null && _doctorController.text.trim().isEmpty) {
            _doctorController.text = editedData.doctorName!;
          }
          if (editedData.symptoms != null) {
            final existing = _symptomsController.text.trim();
            if (existing.isEmpty) {
              _symptomsController.text = editedData.symptoms!;
            } else if (!existing.contains(editedData.symptoms!)) {
              _symptomsController.text = '$existing\n${editedData.symptoms!}';
            }
          }
          if (editedData.cost != null) {
            final newCost = double.tryParse(editedData.cost!);
            if (newCost != null) {
              _invoiceCosts.add(newCost);
              final existingCost = double.tryParse(_costController.text.trim());
              if (existingCost != null) {
                _costController.text = (existingCost + newCost).toStringAsFixed(2);
              } else {
                _costController.text = editedData.cost!;
              }
            }
          }
          if (editedData.result != null) {
            final existing = _resultController.text.trim();
            if (existing.isEmpty) {
              _resultController.text = editedData.result!;
            } else if (!existing.contains(editedData.result!)) {
              _resultController.text = '$existing; ${editedData.result!}';
            }
          }
          if (editedData.treatment != null) {
            final existing = _treatmentController.text.trim();
            if (existing.isEmpty) {
              _treatmentController.text = editedData.treatment!;
            } else if (!existing.contains(editedData.treatment!)) {
              _treatmentController.text = '$existing; ${editedData.treatment!}';
            }
          }
          if (editedData.medicineName != null) {
            final existing = _medicineController.text.trim();
            if (existing.isEmpty) {
              _medicineController.text = editedData.medicineName!;
            } else if (!existing.contains(editedData.medicineName!)) {
              _medicineController.text = '$existing; ${editedData.medicineName!}';
            }
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已自动填入识别信息')),
          );
        }
      }
    } catch (e) {
      debugPrint('Auto OCR failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OCR识别失败，请手动填写'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _ocrProcessingCount--;
          if (_ocrProcessingCount <= 0) {
            _ocrProcessing = false;
            _ocrProcessingCount = 0;
          }
        });
      }
    }
  }

  void _removeDraft(AttachmentType type, int index) {
    setState(() {
      _attachmentDrafts[type]!.removeAt(index);
      _markChanged();
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

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
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
          treatment: _treatmentController.text.trim().isEmpty ? null : _treatmentController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          medicine: _medicineController.text.trim().isEmpty ? null : _medicineController.text.trim(),
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
          treatment: _treatmentController.text.trim().isEmpty ? null : _treatmentController.text.trim(),
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          medicine: _medicineController.text.trim().isEmpty ? null : _medicineController.text.trim(),
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
    final showOutpatientFields = _visitType == VisitType.outpatient || _visitType == VisitType.emergency;
    final showInpatientFields = _visitType == VisitType.inpatient;
    final showSimpleFields = _visitType == VisitType.checkup || _visitType == VisitType.vaccination;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasChanges) {
          Navigator.of(context).pop();
          return;
        }
        final shouldLeave = await _confirmLeave();
        if (shouldLeave == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            if (!_hasChanges) {
              Navigator.of(context).pop();
              return;
            }
            final shouldLeave = await _confirmLeave();
            if (shouldLeave == true && context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(_isEdit ? '编辑就诊记录' : '添加就诊记录'),
        actions: [
          // Show OCR processing indicator
          if (_ocrProcessing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
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

            // Visit type dropdown
            DropdownButtonFormField<VisitType>(
              value: _visitType,
              decoration: const InputDecoration(
                labelText: '就诊类型',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_hospital_outlined),
              ),
              items: VisitType.values.map((vt) {
                return DropdownMenuItem<VisitType>(
                  value: vt,
                  child: Text(vt.label),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) setState(() { _visitType = value; _markChanged(); });
              },
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

            // Department
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: '就诊科室',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.meeting_room_outlined),
              ),
              onChanged: (_) => _markChanged(),
            ),
            const SizedBox(height: 12),

            // Dynamic fields based on visit type
            if (showOutpatientFields) ..._buildOutpatientFields(),
            if (showInpatientFields) ..._buildInpatientFields(),
            if (showSimpleFields) ..._buildSimpleFields(),

          // Treatment
          TextFormField(
            controller: _treatmentController,
            decoration: const InputDecoration(
              labelText: '处置',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.healing_outlined),
            ),
            maxLines: 2,
            onChanged: (_) => _markChanged(),
          ),
          const SizedBox(height: 12),

          // Medicine (prescription)
          TextFormField(
            controller: _medicineController,
            decoration: const InputDecoration(
              labelText: '药品（可选）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.medication_outlined),
            ),
            maxLines: 2,
            onChanged: (_) => _markChanged(),
          ),
          const SizedBox(height: 12),

          // Cost with breakdown
          _buildCostSection(theme),
          const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _notesController,
              onChanged: (_) => _markChanged(),
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
      ),
    );
  }

  Future<bool?> _confirmLeave() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认离开'),
        content: const Text('当前填写的信息尚未保存，确定要离开吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('离开')),
          FilledButton(onPressed: () async {
            await _save();
          }, child: const Text('保存')),
        ],
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
            // Sync OCR-set value into the autocomplete controller
            if (_hospitalController.text != controller.text) {
              controller.text = _hospitalController.text;
            }
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
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _diagnosisController,
        decoration: const InputDecoration(
          labelText: '诊断',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.medical_services_outlined),
        ),
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
        onChanged: (_) => _markChanged(),
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
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _diagnosisController,
        decoration: const InputDecoration(
          labelText: '诊断',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.medical_services_outlined),
        ),
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '主治医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
        onChanged: (_) => _markChanged(),
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
        onChanged: (_) => _markChanged(),
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
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _doctorController,
        decoration: const InputDecoration(
          labelText: '医生',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.person_outlined),
        ),
        onChanged: (_) => _markChanged(),
      ),
      const SizedBox(height: 12),
    ];
  }

  /// Build cost section with total and per-invoice breakdown
  Widget _buildCostSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _costController,
          decoration: const InputDecoration(
            labelText: '花费金额（总金额）',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.payments_outlined),
            prefixText: '¥ ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _markChanged(),
        ),
        // Show per-invoice cost breakdown if there are multiple invoice costs
        if (_invoiceCosts.length > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.receipt_long, size: 16, color: theme.colorScheme.outline),
                    const SizedBox(width: 8),
                    Text(
                      '发票明细',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_invoiceCosts.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          '发票 ${i + 1}:',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const Spacer(),
                        Text(
                          '¥${_invoiceCosts[i].toStringAsFixed(2)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(height: 8),
                Row(
                  children: [
                    Text(
                      '合计:',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      '¥${_invoiceCosts.reduce((a, b) => a + b).toStringAsFixed(2)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
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
        Row(
          children: [
            Text('附件', style: theme.textTheme.titleSmall),
            if (_ocrProcessing) ...[
              const SizedBox(width: 8),
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 4),
              Text('正在识别...', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '上传图片将自动识别内容并补全信息',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
        ),
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
                tooltip: '拍照（自动识别）',
                onPressed: () => _addImageAttachment(type, ImageSource.camera),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.photo, size: 20),
                tooltip: '相册（自动识别）',
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
        GestureDetector(
          onTap: isPdf ? null : () {
            FullscreenImageViewer.show(context, imagePath: att.filePath);
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
                      Text('PDF', style: theme.textTheme.labelSmall),
                    ],
                  )
                : Image.file(
                    File(att.thumbnailPath ?? att.filePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.file(File(att.filePath), fit: BoxFit.cover),
                  ),
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
        GestureDetector(
          onTap: isPdf ? null : () {
            FullscreenImageViewer.show(context, imagePath: draft.filePath);
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
                      Text('PDF', style: theme.textTheme.labelSmall),
                    ],
                  )
                : Image.file(File(draft.filePath), fit: BoxFit.cover),
          ),
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

/// Bottom sheet showing OCR results with option to edit and auto-fill
class _OcrResultSheet extends StatefulWidget {
  const _OcrResultSheet({required this.data});
  final OcrExtractedData data;

  @override
  State<_OcrResultSheet> createState() => _OcrResultSheetState();
}

class _OcrResultSheetState extends State<_OcrResultSheet> {
  late final TextEditingController _hospitalController;
  late final TextEditingController _diagnosisController;
  late final TextEditingController _doctorController;
  late final TextEditingController _symptomsController;
  late final TextEditingController _costController;
  late final TextEditingController _resultController;
  late final TextEditingController _dateController;
  late final TextEditingController _medicineController;

  @override
  void initState() {
    super.initState();
    _hospitalController = TextEditingController(text: widget.data.hospital ?? '');
    _diagnosisController = TextEditingController(text: widget.data.diagnosis ?? '');
    _doctorController = TextEditingController(text: widget.data.doctorName ?? '');
    _symptomsController = TextEditingController(text: widget.data.symptoms ?? '');
    _costController = TextEditingController(text: widget.data.cost ?? '');
    _resultController = TextEditingController(text: widget.data.result ?? '');
    _dateController = TextEditingController(text: widget.data.date ?? '');
    _medicineController = TextEditingController(text: widget.data.medicineName ?? '');
  }

  @override
  void dispose() {
    _hospitalController.dispose();
    _diagnosisController.dispose();
    _doctorController.dispose();
    _symptomsController.dispose();
    _costController.dispose();
    _resultController.dispose();
    _dateController.dispose();
    _medicineController.dispose();
    super.dispose();
  }

  /// Get the edited data as a new OcrExtractedData
  OcrExtractedData _getEditedData() {
    return OcrExtractedData(
      hospital: _hospitalController.text.trim().isEmpty ? null : _hospitalController.text.trim(),
      diagnosis: _diagnosisController.text.trim().isEmpty ? null : _diagnosisController.text.trim(),
      doctorName: _doctorController.text.trim().isEmpty ? null : _doctorController.text.trim(),
      symptoms: _symptomsController.text.trim().isEmpty ? null : _symptomsController.text.trim(),
      cost: _costController.text.trim().isEmpty ? null : _costController.text.trim(),
      result: _resultController.text.trim().isEmpty ? null : _resultController.text.trim(),
      medicineName: _medicineController.text.trim().isEmpty ? null : _medicineController.text.trim(),
      rawText: widget.data.rawText,
      documentType: widget.data.documentType,
    );
  }

  bool get _hasAnyData {
    return _hospitalController.text.trim().isNotEmpty ||
        _diagnosisController.text.trim().isNotEmpty ||
        _doctorController.text.trim().isNotEmpty ||
        _symptomsController.text.trim().isNotEmpty ||
        _costController.text.trim().isNotEmpty ||
        _resultController.text.trim().isNotEmpty ||
        _medicineController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.document_scanner, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '识别到${widget.data.documentTypeName}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '可编辑修改',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              children: [
                _buildEditableField(
                  theme,
                  label: '医院',
                  controller: _hospitalController,
                  icon: Icons.local_hospital_outlined,
                ),
                _buildEditableField(
                  theme,
                  label: '诊断',
                  controller: _diagnosisController,
                  icon: Icons.medical_services_outlined,
                ),
                _buildEditableField(
                  theme,
                  label: '医生',
                  controller: _doctorController,
                  icon: Icons.person_outlined,
                ),
                _buildEditableField(
                  theme,
                  label: '症状',
                  controller: _symptomsController,
                  icon: Icons.sick_outlined,
                  maxLines: 2,
                ),
                _buildEditableField(
                  theme,
                  label: '费用',
                  controller: _costController,
                  icon: Icons.payments_outlined,
                  keyboardType: TextInputType.number,
                ),
                _buildEditableField(
                  theme,
                  label: '药品',
                  controller: _medicineController,
                  icon: Icons.medication_outlined,
                ),
                _buildEditableField(
                  theme,
                  label: '结果',
                  controller: _resultController,
                  icon: Icons.summarize_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '点击可修改识别结果，仅填入当前为空的字段',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    child: const Text('忽略'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _hasAnyData
                        ? () => Navigator.pop(context, _getEditedData())
                        : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('确认填入'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField(
    ThemeData theme, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    setState(() {
                      controller.clear();
                    });
                  },
                )
              : null,
        ),
        onChanged: (_) => setState(() {}),
      ),
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
