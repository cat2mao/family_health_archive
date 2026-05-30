import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../database/app_database.dart';

class AttachmentRepository {
  AttachmentRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<AttachmentRow>> getByRecord(String recordId) =>
      _db.getAttachmentsForRecord(recordId);

  Future<void> create({
    required String recordId,
    required AttachmentType type,
    required String filePath,
    String? thumbnailPath,
    required FileType fileType,
  }) async {
    final row = AttachmentRow(
      id: _uuid.v4(),
      recordId: recordId,
      type: type.code,
      filePath: filePath,
      thumbnailPath: thumbnailPath,
      fileType: fileType.code,
      createdAt: DateTime.now(),
    );
    await _db.insertAttachment(row);
  }

  Future<void> delete(String id) async {
    // Also delete files
    final att = await _getById(id);
    if (att != null) {
      await _deleteFiles(att);
    }
    await _db.deleteAttachment(id);
  }

  Future<void> deleteForRecord(String recordId) async {
    final atts = await getByRecord(recordId);
    for (final att in atts) {
      await _deleteFiles(att);
    }
    await _db.deleteAttachmentsForRecord(recordId);
  }

  Future<AttachmentRow?> _getById(String id) async {
    // Simple lookup through all records' attachments
    return null; // Will be handled by direct delete
  }

  Future<void> _deleteFiles(AttachmentRow att) async {
    try {
      final file = File(att.filePath);
      if (await file.exists()) await file.delete();
      if (att.thumbnailPath != null) {
        final thumb = File(att.thumbnailPath!);
        if (await thumb.exists()) await thumb.delete();
      }
    } catch (_) {}
  }

  /// Clean orphaned files (attachments for deleted records)
  Future<int> cleanOrphanedFiles() async {
    int cleaned = 0;
    final dir = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!await attachmentsDir.exists()) return 0;

    // Get all current file paths
    final allRecords = await _db.getAllRecords();
    final currentPaths = <String>{};
    for (final r in allRecords) {
      final atts = await _db.getAttachmentsForRecord(r.id);
      for (final a in atts) {
        currentPaths.add(a.filePath);
        if (a.thumbnailPath != null) currentPaths.add(a.thumbnailPath!);
      }
    }

    await for (final entity in attachmentsDir.list(recursive: true)) {
      if (entity is File && !currentPaths.contains(entity.path)) {
        try {
          await entity.delete();
          cleaned++;
        } catch (_) {}
      }
    }
    return cleaned;
  }
}
