import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/enums.dart';

/// 本地 SQLite 数据库
class AppDatabase {
  AppDatabase._();
  static AppDatabase? _instance;
  static Database? _db;

  static Future<AppDatabase> instance() async {
    if (_instance != null) return _instance!;
    _instance = AppDatabase._();
    _db = await _open();
    return _instance!;
  }

  static Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'family_health_archive.sqlite');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await _createAllTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createV2Tables(db);
        }
        if (oldVersion < 3) {
          // Add treatment column to medical_records
          await db.execute('ALTER TABLE medical_records ADD COLUMN treatment TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE medical_records ADD COLUMN medicine TEXT');
        }
      },
    );
  }

  static Future<void> _createAllTables(Database db) async {
    await db.execute('''
      CREATE TABLE persons (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        avatar_path TEXT,
        type TEXT NOT NULL,
        relationship TEXT NOT NULL,
        gender TEXT,
        birth_date TEXT,
        blood_type TEXT,
        allergies TEXT,
        chronic_diseases TEXT,
        long_term_meds TEXT,
        breed TEXT,
        neutered INTEGER,
        chip_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE medical_records (
        id TEXT PRIMARY KEY,
        person_id TEXT NOT NULL,
        visit_time INTEGER NOT NULL,
        location TEXT NOT NULL DEFAULT '',
        hospital TEXT NOT NULL DEFAULT '',
        visit_type TEXT NOT NULL,
        symptoms TEXT,
        diagnosis TEXT,
        doctor_name TEXT,
        admission_date INTEGER,
        discharge_date INTEGER,
        hospital_days INTEGER,
        focus_on TEXT,
        result TEXT,
        treatment TEXT,
        notes TEXT,
        medicine TEXT,
        cost REAL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_records_person ON medical_records(person_id)',
    );
    await _createV2Tables(db);
  }

  static Future<void> _createV2Tables(Database db) async {
    // 附件表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY,
        record_id TEXT NOT NULL,
        type TEXT NOT NULL,
        file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        file_type TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (record_id) REFERENCES medical_records(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_attachments_record ON attachments(record_id)');

    // 标签表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // 病例-标签关联表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS record_tags (
        record_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (record_id, tag_id),
        FOREIGN KEY (record_id) REFERENCES medical_records(id) ON DELETE CASCADE,
        FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');

    // 提醒表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id TEXT PRIMARY KEY,
        person_id TEXT NOT NULL,
        record_id TEXT,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        remind_time INTEGER NOT NULL,
        repeat_type TEXT NOT NULL DEFAULT 'once',
        is_completed INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0,
        medicine_name TEXT,
        daily_times TEXT,
        duration_days INTEGER,
        dosage TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE,
        FOREIGN KEY (record_id) REFERENCES medical_records(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_reminders_person ON reminders(person_id)');

    // 体重记录表
    await db.execute('''
      CREATE TABLE IF NOT EXISTS weight_records (
        id TEXT PRIMARY KEY,
        person_id TEXT NOT NULL,
        weight REAL NOT NULL,
        record_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (person_id) REFERENCES persons(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_weight_person ON weight_records(person_id)');
  }

  Database get db => _db!;

  // ========== Persons ==========

  Future<List<PersonRow>> getAllPersons() async {
    final rows = await db.query('persons', orderBy: 'created_at ASC');
    return rows.map(PersonRow.fromMap).toList();
  }

  Future<PersonRow?> getPersonById(String id) async {
    final rows = await db.query('persons', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return PersonRow.fromMap(rows.first);
  }

  Future<void> insertPerson(PersonRow row) async {
    await db.insert('persons', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePerson(PersonRow row) async {
    await db.update('persons', row.toMap(), where: 'id = ?', whereArgs: [row.id]);
  }

  Future<void> deletePerson(String id) async {
    await db.delete('medical_records', where: 'person_id = ?', whereArgs: [id]);
    await db.delete('persons', where: 'id = ?', whereArgs: [id]);
  }

  // ========== Medical Records ==========

  Future<List<MedicalRecordRow>> getRecordsForPerson(String personId) async {
    final rows = await db.query(
      'medical_records',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'visit_time DESC',
    );
    return rows.map(MedicalRecordRow.fromMap).toList();
  }

  Future<MedicalRecordRow?> getRecordById(String id) async {
    final rows = await db.query('medical_records', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return MedicalRecordRow.fromMap(rows.first);
  }

  Future<void> insertMedicalRecord(MedicalRecordRow row) async {
    await db.insert('medical_records', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateMedicalRecord(MedicalRecordRow row) async {
    await db.update('medical_records', row.toMap(), where: 'id = ?', whereArgs: [row.id]);
  }

  Future<void> deleteMedicalRecord(String id) async {
    await db.delete('medical_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MedicalRecordRow>> getAllRecords() async {
    final rows = await db.query('medical_records', orderBy: 'visit_time DESC');
    return rows.map(MedicalRecordRow.fromMap).toList();
  }

  Future<List<MedicalRecordRow>> searchRecords({
    String? personId,
    String? hospital,
    String? visitType,
    String? keyword,
    int? startTime,
    int? endTime,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (personId != null) {
      where.add('person_id = ?');
      args.add(personId);
    }
    if (hospital != null && hospital.isNotEmpty) {
      where.add('hospital LIKE ?');
      args.add('%$hospital%');
    }
    if (visitType != null) {
      where.add('visit_type = ?');
      args.add(visitType);
    }
    if (keyword != null && keyword.isNotEmpty) {
      where.add('(symptoms LIKE ? OR diagnosis LIKE ? OR hospital LIKE ? OR notes LIKE ?)');
      args.addAll(['%$keyword%', '%$keyword%', '%$keyword%', '%$keyword%']);
    }
    if (startTime != null) {
      where.add('visit_time >= ?');
      args.add(startTime);
    }
    if (endTime != null) {
      where.add('visit_time <= ?');
      args.add(endTime);
    }
    final whereStr = where.isEmpty ? null : where.join(' AND ');
    final rows = await db.query(
      'medical_records',
      where: whereStr,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'visit_time DESC',
    );
    return rows.map(MedicalRecordRow.fromMap).toList();
  }

  Future<List<String>> getAllHospitals() async {
    final rows = await db.rawQuery(
      "SELECT DISTINCT hospital FROM medical_records WHERE hospital != '' ORDER BY hospital",
    );
    return rows.map((r) => r['hospital'] as String).toList();
  }

  // ========== Attachments ==========

  Future<List<AttachmentRow>> getAttachmentsForRecord(String recordId) async {
    final rows = await db.query(
      'attachments',
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'created_at ASC',
    );
    return rows.map(AttachmentRow.fromMap).toList();
  }

  Future<void> insertAttachment(AttachmentRow row) async {
    await db.insert('attachments', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<AttachmentRow?> getAttachment(String id) async {
    final rows = await db.query(
      'attachments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return AttachmentRow.fromMap(rows.first);
  }

  Future<void> deleteAttachment(String id) async {
    await db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAttachmentsForRecord(String recordId) async {
    await db.delete('attachments', where: 'record_id = ?', whereArgs: [recordId]);
  }

  // ========== Tags ==========

  Future<List<TagRow>> getAllTags() async {
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows.map(TagRow.fromMap).toList();
  }

  Future<List<TagRow>> getTagsByCategory(String category) async {
    final rows = await db.query('tags', where: 'category = ?', whereArgs: [category], orderBy: 'name ASC');
    return rows.map(TagRow.fromMap).toList();
  }

  Future<TagRow?> getTagById(String id) async {
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TagRow.fromMap(rows.first);
  }

  Future<TagRow?> getTagByName(String name) async {
    final rows = await db.query('tags', where: 'name = ?', whereArgs: [name]);
    if (rows.isEmpty) return null;
    return TagRow.fromMap(rows.first);
  }

  Future<void> insertTag(TagRow row) async {
    await db.insert('tags', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTag(String id) async {
    await db.delete('record_tags', where: 'tag_id = ?', whereArgs: [id]);
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  // ========== Record-Tags ==========

  Future<void> setRecordTags(String recordId, List<String> tagIds) async {
    await db.delete('record_tags', where: 'record_id = ?', whereArgs: [recordId]);
    for (final tagId in tagIds) {
      await db.insert('record_tags', {'record_id': recordId, 'tag_id': tagId});
    }
  }

  Future<List<TagRow>> getTagsForRecord(String recordId) async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN record_tags rt ON t.id = rt.tag_id
      WHERE rt.record_id = ?
      ORDER BY t.name ASC
    ''', [recordId]);
    return rows.map(TagRow.fromMap).toList();
  }

  Future<List<MedicalRecordRow>> getRecordsWithTag(String tagId) async {
    final rows = await db.rawQuery('''
      SELECT mr.* FROM medical_records mr
      INNER JOIN record_tags rt ON mr.id = rt.record_id
      WHERE rt.tag_id = ?
      ORDER BY mr.visit_time DESC
    ''', [tagId]);
    return rows.map(MedicalRecordRow.fromMap).toList();
  }

  Future<Map<String, int>> getTagDistribution() async {
    final rows = await db.rawQuery('''
      SELECT t.name, COUNT(rt.record_id) as cnt
      FROM tags t
      INNER JOIN record_tags rt ON t.id = rt.tag_id
      GROUP BY t.id
      ORDER BY cnt DESC
    ''');
    return {for (final r in rows) r['name'] as String: r['cnt'] as int};
  }

  // ========== Reminders ==========

  Future<List<ReminderRow>> getAllReminders() async {
    final rows = await db.query('reminders', orderBy: 'remind_time ASC');
    return rows.map(ReminderRow.fromMap).toList();
  }

  Future<List<ReminderRow>> getActiveReminders() async {
    final rows = await db.query(
      'reminders',
      where: 'archived = 0',
      orderBy: 'remind_time ASC',
    );
    return rows.map(ReminderRow.fromMap).toList();
  }

  Future<List<ReminderRow>> getArchivedReminders() async {
    final rows = await db.query(
      'reminders',
      where: 'archived = 1',
      orderBy: 'remind_time DESC',
    );
    return rows.map(ReminderRow.fromMap).toList();
  }

  Future<List<ReminderRow>> getRemindersForPerson(String personId) async {
    final rows = await db.query(
      'reminders',
      where: 'person_id = ? AND archived = 0',
      whereArgs: [personId],
      orderBy: 'remind_time ASC',
    );
    return rows.map(ReminderRow.fromMap).toList();
  }

  Future<List<ReminderRow>> getUncompletedReminders() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'reminders',
      where: 'is_completed = 0 AND archived = 0 AND remind_time <= ?',
      whereArgs: [now],
      orderBy: 'remind_time ASC',
    );
    return rows.map(ReminderRow.fromMap).toList();
  }

  Future<ReminderRow?> getReminderById(String id) async {
    final rows = await db.query('reminders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ReminderRow.fromMap(rows.first);
  }

  Future<void> insertReminder(ReminderRow row) async {
    await db.insert('reminders', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateReminder(ReminderRow row) async {
    await db.update('reminders', row.toMap(), where: 'id = ?', whereArgs: [row.id]);
  }

  Future<void> deleteReminder(String id) async {
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ReminderRow>> getDueReminders() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await db.query(
      'reminders',
      where: 'is_completed = 0 AND archived = 0 AND remind_time <= ?',
      whereArgs: [now],
      orderBy: 'remind_time ASC',
    );
    return rows.map(ReminderRow.fromMap).toList();
  }

  // ========== Weight Records ==========

  Future<List<WeightRecordRow>> getWeightRecords(String personId) async {
    final rows = await db.query(
      'weight_records',
      where: 'person_id = ?',
      whereArgs: [personId],
      orderBy: 'record_date ASC',
    );
    return rows.map(WeightRecordRow.fromMap).toList();
  }

  Future<void> insertWeightRecord(WeightRecordRow row) async {
    await db.insert('weight_records', row.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWeightRecord(String id) async {
    await db.delete('weight_records', where: 'id = ?', whereArgs: [id]);
  }

  // ========== Export / Import ==========

  Future<Map<String, dynamic>> exportAllData() async {
    final persons = await getAllPersons();
    final records = await getAllRecords();
    final tags = await getAllTags();
    final reminders = await getAllReminders();

    List<Map<String, dynamic>> attachments = [];
    for (final r in records) {
      final atts = await getAttachmentsForRecord(r.id);
      attachments.addAll(atts.map((a) => a.toMap()));
    }

    List<Map<String, dynamic>> recordTags = [];
    for (final r in records) {
      final ts = await getTagsForRecord(r.id);
      for (final t in ts) {
        recordTags.add({'record_id': r.id, 'tag_id': t.id});
      }
    }

    List<Map<String, dynamic>> weights = [];
    for (final p in persons) {
      final ws = await getWeightRecords(p.id);
      weights.addAll(ws.map((w) => w.toMap()));
    }

    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'persons': persons.map((p) => p.toMap()).toList(),
      'medical_records': records.map((r) => r.toMap()).toList(),
      'attachments': attachments,
      'tags': tags.map((t) => t.toMap()).toList(),
      'record_tags': recordTags,
      'reminders': reminders.map((r) => r.toMap()).toList(),
      'weight_records': weights,
    };
  }

  Future<void> importAllData(Map<String, dynamic> data) async {
    await db.transaction((txn) async {
      // Clear all tables
      await txn.delete('record_tags');
      await txn.delete('attachments');
      await txn.delete('reminders');
      await txn.delete('weight_records');
      await txn.delete('medical_records');
      await txn.delete('tags');
      await txn.delete('persons');

      // Insert persons
      final persons = data['persons'] as List<dynamic>? ?? [];
      for (final p in persons) {
        await txn.insert('persons', Map<String, Object?>.from(p as Map));
      }

      // Insert tags
      final tags = data['tags'] as List<dynamic>? ?? [];
      for (final t in tags) {
        await txn.insert('tags', Map<String, Object?>.from(t as Map));
      }

      // Insert medical records
      final records = data['medical_records'] as List<dynamic>? ?? [];
      for (final r in records) {
        await txn.insert('medical_records', Map<String, Object?>.from(r as Map));
      }

      // Insert attachments
      final attachments = data['attachments'] as List<dynamic>? ?? [];
      for (final a in attachments) {
        await txn.insert('attachments', Map<String, Object?>.from(a as Map));
      }

      // Insert record_tags
      final recordTags = data['record_tags'] as List<dynamic>? ?? [];
      for (final rt in recordTags) {
        await txn.insert('record_tags', Map<String, Object?>.from(rt as Map));
      }

      // Insert reminders
      final reminders = data['reminders'] as List<dynamic>? ?? [];
      for (final r in reminders) {
        await txn.insert('reminders', Map<String, Object?>.from(r as Map));
      }

      // Insert weight records
      final weights = data['weight_records'] as List<dynamic>? ?? [];
      for (final w in weights) {
        await txn.insert('weight_records', Map<String, Object?>.from(w as Map));
      }
    });
  }
}

// ==================== Data Row Classes ====================

class PersonRow {
  PersonRow({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.type,
    required this.relationship,
    this.gender,
    this.birthDate,
    this.bloodType,
    this.allergies,
    this.chronicDiseases,
    this.longTermMeds,
    this.breed,
    this.neutered,
    this.chipId,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? avatarPath;
  final String type;
  final String relationship;
  final String? gender;
  final String? birthDate;
  final String? bloodType;
  final String? allergies;
  final String? chronicDiseases;
  final String? longTermMeds;
  final String? breed;
  final bool? neutered;
  final String? chipId;
  final DateTime createdAt;

  PersonType get personType => PersonType.fromCode(type);
  Relationship get personRelationship => Relationship.fromCode(relationship);
  Gender? get personGender => Gender.fromCode(gender);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'avatar_path': avatarPath,
        'type': type,
        'relationship': relationship,
        'gender': gender,
        'birth_date': birthDate,
        'blood_type': bloodType,
        'allergies': allergies,
        'chronic_diseases': chronicDiseases,
        'long_term_meds': longTermMeds,
        'breed': breed,
        'neutered': neutered == null ? null : (neutered! ? 1 : 0),
        'chip_id': chipId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory PersonRow.fromMap(Map<String, Object?> map) => PersonRow(
        id: map['id']! as String,
        name: map['name']! as String,
        avatarPath: map['avatar_path'] as String?,
        type: map['type']! as String,
        relationship: map['relationship']! as String,
        gender: map['gender'] as String?,
        birthDate: map['birth_date'] as String?,
        bloodType: map['blood_type'] as String?,
        allergies: map['allergies'] as String?,
        chronicDiseases: map['chronic_diseases'] as String?,
        longTermMeds: map['long_term_meds'] as String?,
        breed: map['breed'] as String?,
        neutered: map['neutered'] == null ? null : (map['neutered'] as int) == 1,
        chipId: map['chip_id'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );

  PersonRow copyWith({
    String? name,
    String? avatarPath,
    String? type,
    String? relationship,
    String? gender,
    String? birthDate,
    String? bloodType,
    String? allergies,
    String? chronicDiseases,
    String? longTermMeds,
    String? breed,
    bool? neutered,
    String? chipId,
  }) =>
      PersonRow(
        id: id,
        name: name ?? this.name,
        avatarPath: avatarPath ?? this.avatarPath,
        type: type ?? this.type,
        relationship: relationship ?? this.relationship,
        gender: gender ?? this.gender,
        birthDate: birthDate ?? this.birthDate,
        bloodType: bloodType ?? this.bloodType,
        allergies: allergies ?? this.allergies,
        chronicDiseases: chronicDiseases ?? this.chronicDiseases,
        longTermMeds: longTermMeds ?? this.longTermMeds,
        breed: breed ?? this.breed,
        neutered: neutered ?? this.neutered,
        chipId: chipId ?? this.chipId,
        createdAt: createdAt,
      );
}

class MedicalRecordRow {
  MedicalRecordRow({
    required this.id,
    required this.personId,
    required this.visitTime,
    this.location = '',
    this.hospital = '',
    required this.visitType,
    this.symptoms,
    this.diagnosis,
    this.doctorName,
    this.admissionDate,
    this.dischargeDate,
    this.hospitalDays,
    this.focusOn,
    this.result,
    this.treatment,
    this.medicine,
    this.notes,
    this.cost,
    required this.createdAt,
  });

  final String id;
  final String personId;
  final DateTime visitTime;
  final String location;
  final String hospital;
  final String visitType;
  final String? symptoms;
  final String? diagnosis;
  final String? doctorName;
  final DateTime? admissionDate;
  final DateTime? dischargeDate;
  final int? hospitalDays;
  final String? focusOn;
  final String? result;
  final String? treatment;
  final String? medicine;
  final String? notes;
  final double? cost;
  final DateTime createdAt;

  VisitType get recordVisitType => VisitType.fromCode(visitType);

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'visit_time': visitTime.millisecondsSinceEpoch,
        'location': location,
        'hospital': hospital,
        'visit_type': visitType,
        'symptoms': symptoms,
        'diagnosis': diagnosis,
        'doctor_name': doctorName,
        'admission_date': admissionDate?.millisecondsSinceEpoch,
        'discharge_date': dischargeDate?.millisecondsSinceEpoch,
        'hospital_days': hospitalDays,
        'focus_on': focusOn,
        'result': result,
        'treatment': treatment,
        'medicine': medicine,
        'notes': notes,
        'cost': cost,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory MedicalRecordRow.fromMap(Map<String, Object?> map) => MedicalRecordRow(
        id: map['id']! as String,
        personId: map['person_id']! as String,
        visitTime: DateTime.fromMillisecondsSinceEpoch(map['visit_time']! as int),
        location: map['location'] as String? ?? '',
        hospital: map['hospital'] as String? ?? '',
        visitType: map['visit_type']! as String,
        symptoms: map['symptoms'] as String?,
        diagnosis: map['diagnosis'] as String?,
        doctorName: map['doctor_name'] as String?,
        admissionDate: map['admission_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['admission_date']! as int),
        dischargeDate: map['discharge_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['discharge_date']! as int),
        hospitalDays: map['hospital_days'] as int?,
        focusOn: map['focus_on'] as String?,
        result: map['result'] as String?,
        treatment: map['treatment'] as String?,
        medicine: map['medicine'] as String?,
        notes: map['notes'] as String?,
        cost: (map['cost'] as num?)?.toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );

  String toJson() => jsonEncode(toMap());
}

class AttachmentRow {
  AttachmentRow({
    required this.id,
    required this.recordId,
    required this.type,
    required this.filePath,
    this.thumbnailPath,
    required this.fileType,
    required this.createdAt,
  });

  final String id;
  final String recordId;
  final String type;
  final String filePath;
  final String? thumbnailPath;
  final String fileType;
  final DateTime createdAt;

  AttachmentType get attachmentType => AttachmentType.fromCode(type);
  FileType get attachmentFileType => FileType.fromCode(fileType);

  Map<String, Object?> toMap() => {
        'id': id,
        'record_id': recordId,
        'type': type,
        'file_path': filePath,
        'thumbnail_path': thumbnailPath,
        'file_type': fileType,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory AttachmentRow.fromMap(Map<String, Object?> map) => AttachmentRow(
        id: map['id']! as String,
        recordId: map['record_id']! as String,
        type: map['type']! as String,
        filePath: map['file_path']! as String,
        thumbnailPath: map['thumbnail_path'] as String?,
        fileType: map['file_type']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
}

class TagRow {
  TagRow({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String category;
  final DateTime createdAt;

  TagCategory get tagCategory => TagCategory.fromCode(category);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TagRow.fromMap(Map<String, Object?> map) => TagRow(
        id: map['id']! as String,
        name: map['name']! as String,
        category: map['category']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
}

class ReminderRow {
  ReminderRow({
    required this.id,
    required this.personId,
    this.recordId,
    required this.title,
    required this.type,
    required this.remindTime,
    this.repeatType = 'once',
    this.isCompleted = false,
    this.archived = false,
    this.medicineName,
    this.dailyTimes,
    this.durationDays,
    this.dosage,
    required this.createdAt,
  });

  final String id;
  final String personId;
  final String? recordId;
  final String title;
  final String type;
  final DateTime remindTime;
  final String repeatType;
  final bool isCompleted;
  final bool archived;
  final String? medicineName;
  final String? dailyTimes;
  final int? durationDays;
  final String? dosage;
  final DateTime createdAt;

  ReminderType get reminderType => ReminderType.fromCode(type);
  RepeatType get repeat => RepeatType.fromCode(repeatType);

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'record_id': recordId,
        'title': title,
        'type': type,
        'remind_time': remindTime.millisecondsSinceEpoch,
        'repeat_type': repeatType,
        'is_completed': isCompleted ? 1 : 0,
        'archived': archived ? 1 : 0,
        'medicine_name': medicineName,
        'daily_times': dailyTimes,
        'duration_days': durationDays,
        'dosage': dosage,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ReminderRow.fromMap(Map<String, Object?> map) => ReminderRow(
        id: map['id']! as String,
        personId: map['person_id']! as String,
        recordId: map['record_id'] as String?,
        title: map['title']! as String,
        type: map['type']! as String,
        remindTime: DateTime.fromMillisecondsSinceEpoch(map['remind_time']! as int),
        repeatType: map['repeat_type'] as String? ?? 'once',
        isCompleted: (map['is_completed'] as int? ?? 0) == 1,
        archived: (map['archived'] as int? ?? 0) == 1,
        medicineName: map['medicine_name'] as String?,
        dailyTimes: map['daily_times'] as String?,
        durationDays: map['duration_days'] as int?,
        dosage: map['dosage'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );

  ReminderRow copyWith({
    String? title,
    String? type,
    DateTime? remindTime,
    String? repeatType,
    bool? isCompleted,
    bool? archived,
    String? medicineName,
    String? dailyTimes,
    int? durationDays,
    String? dosage,
  }) =>
      ReminderRow(
        id: id,
        personId: personId,
        recordId: recordId,
        title: title ?? this.title,
        type: type ?? this.type,
        remindTime: remindTime ?? this.remindTime,
        repeatType: repeatType ?? this.repeatType,
        isCompleted: isCompleted ?? this.isCompleted,
        archived: archived ?? this.archived,
        medicineName: medicineName ?? this.medicineName,
        dailyTimes: dailyTimes ?? this.dailyTimes,
        durationDays: durationDays ?? this.durationDays,
        dosage: dosage ?? this.dosage,
        createdAt: createdAt,
      );
}

class WeightRecordRow {
  WeightRecordRow({
    required this.id,
    required this.personId,
    required this.weight,
    required this.recordDate,
    required this.createdAt,
  });

  final String id;
  final String personId;
  final double weight;
  final String recordDate; // yyyy-MM-dd
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'person_id': personId,
        'weight': weight,
        'record_date': recordDate,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory WeightRecordRow.fromMap(Map<String, Object?> map) => WeightRecordRow(
        id: map['id']! as String,
        personId: map['person_id']! as String,
        weight: (map['weight'] as num).toDouble(),
        recordDate: map['record_date']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
}
