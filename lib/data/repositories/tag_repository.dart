import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../database/app_database.dart';

class TagRepository {
  TagRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<TagRow>> getAll() => _db.getAllTags();

  Future<List<TagRow>> getByCategory(String category) =>
      _db.getTagsByCategory(category);

  Future<TagRow?> getByName(String name) => _db.getTagByName(name);

  Future<TagRow> create({
    required String name,
    required TagCategory category,
  }) async {
    final row = TagRow(
      id: _uuid.v4(),
      name: name,
      category: category.code,
      createdAt: DateTime.now(),
    );
    await _db.insertTag(row);
    return row;
  }

  Future<TagRow> getOrCreate({
    required String name,
    required TagCategory category,
  }) async {
    final existing = await getByName(name);
    if (existing != null) return existing;
    return create(name: name, category: category);
  }

  Future<void> delete(String id) => _db.deleteTag(id);

  Future<void> setRecordTags(String recordId, List<String> tagIds) =>
      _db.setRecordTags(recordId, tagIds);

  Future<List<TagRow>> getTagsForRecord(String recordId) =>
      _db.getTagsForRecord(recordId);

  Future<Map<String, int>> getTagDistribution() => _db.getTagDistribution();

  /// Seed preset condition tags
  Future<void> seedPresetTags() async {
    final presets = [
      '感冒', '过敏', '肠胃', '皮肤', '口腔',
      '眼科', '耳鼻喉', '骨科', '心血管', '呼吸',
      '妇科', '泌尿', '精神心理', '体检', '疫苗',
      '外伤', '手术', '其他',
    ];
    for (final name in presets) {
      await getOrCreate(name: name, category: TagCategory.condition);
    }
  }
}
