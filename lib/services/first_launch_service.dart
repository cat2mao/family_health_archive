import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../data/repositories/tag_repository.dart';

const _keySeeded = 'first_launch_seeded';

class FirstLaunchService {
  FirstLaunchService(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  static Future<bool> needsSeed() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_keySeeded) ?? false);
  }

  static Future<void> markSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySeeded, true);
  }

  Future<String> seedSampleData() async {
    final selfId = _uuid.v4();
    final now = DateTime.now();
    final self = PersonRow(
      id: selfId,
      name: '本人',
      type: PersonType.human.code,
      relationship: Relationship.self.code,
      gender: Gender.unknown.code,
      createdAt: now,
    );
    await _db.insertPerson(self);

    final record = MedicalRecordRow(
      id: _uuid.v4(),
      personId: selfId,
      visitTime: now.subtract(const Duration(days: 7)),
      hospital: '示例社区医院',
      location: '示例市',
      visitType: VisitType.outpatient.code,
      symptoms: '示例：轻微咳嗽',
      diagnosis: '上呼吸道感染',
      doctorName: '张医生',
      notes: '这是示例就诊记录。点击底部 + 添加您的真实记录；长按顶部头像可编辑档案。',
      cost: 128.5,
      createdAt: now,
    );
    await _db.insertMedicalRecord(record);

    // Seed preset tags
    final tagRepo = TagRepository(_db);
    await tagRepo.seedPresetTags();

    await markSeeded();
    return selfId;
  }
}
