import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../database/app_database.dart';

class ReminderRepository {
  ReminderRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<ReminderRow>> getAll() => _db.getAllReminders();

  Future<List<ReminderRow>> getActive() => _db.getActiveReminders();

  Future<List<ReminderRow>> getArchived() => _db.getArchivedReminders();

  Future<List<ReminderRow>> getByPerson(String personId) =>
      _db.getRemindersForPerson(personId);

  Future<ReminderRow?> getById(String id) => _db.getReminderById(id);

  Future<List<ReminderRow>> getDue() => _db.getDueReminders();

  Future<ReminderRow> create({
    required String personId,
    String? recordId,
    required String title,
    required ReminderType type,
    required DateTime remindTime,
    RepeatType repeatType = RepeatType.once,
    String? medicineName,
    String? dailyTimes,
    int? durationDays,
    String? dosage,
  }) async {
    final row = ReminderRow(
      id: _uuid.v4(),
      personId: personId,
      recordId: recordId,
      title: title,
      type: type.code,
      remindTime: remindTime,
      repeatType: repeatType.code,
      medicineName: medicineName,
      dailyTimes: dailyTimes,
      durationDays: durationDays,
      dosage: dosage,
      createdAt: DateTime.now(),
    );
    await _db.insertReminder(row);
    return row;
  }

  Future<void> update(ReminderRow row) => _db.updateReminder(row);

  Future<void> markCompleted(String id) async {
    final row = await getById(id);
    if (row != null) {
      await update(row.copyWith(isCompleted: true, archived: true));
    }
  }

  Future<void> archive(String id) async {
    final row = await getById(id);
    if (row != null) {
      await update(row.copyWith(archived: true));
    }
  }

  Future<void> delete(String id) => _db.deleteReminder(id);
}
