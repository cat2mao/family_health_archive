import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

class WeightRepository {
  WeightRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<WeightRecordRow>> getByPerson(String personId) =>
      _db.getWeightRecords(personId);

  Future<WeightRecordRow> create({
    required String personId,
    required double weight,
    required String recordDate,
  }) async {
    final row = WeightRecordRow(
      id: _uuid.v4(),
      personId: personId,
      weight: weight,
      recordDate: recordDate,
      createdAt: DateTime.now(),
    );
    await _db.insertWeightRecord(row);
    return row;
  }

  Future<void> delete(String id) => _db.deleteWeightRecord(id);
}
