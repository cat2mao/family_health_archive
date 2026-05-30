import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../database/app_database.dart';

class MedicalRecordRepository {
  MedicalRecordRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<MedicalRecordRow>> getByPerson(String personId) =>
      _db.getRecordsForPerson(personId);

  Future<MedicalRecordRow?> getById(String id) => _db.getRecordById(id);

  Future<List<MedicalRecordRow>> getAll() => _db.getAllRecords();

  Future<MedicalRecordRow> create({
    required String personId,
    required DateTime visitTime,
    String location = '',
    String hospital = '',
    required VisitType visitType,
    String? symptoms,
    String? diagnosis,
    String? doctorName,
    DateTime? admissionDate,
    DateTime? dischargeDate,
    int? hospitalDays,
    String? focusOn,
    String? result,
    String? notes,
    double? cost,
  }) async {
    final row = MedicalRecordRow(
      id: _uuid.v4(),
      personId: personId,
      visitTime: visitTime,
      location: location,
      hospital: hospital,
      visitType: visitType.code,
      symptoms: symptoms,
      diagnosis: diagnosis,
      doctorName: doctorName,
      admissionDate: admissionDate,
      dischargeDate: dischargeDate,
      hospitalDays: hospitalDays,
      focusOn: focusOn,
      result: result,
      notes: notes,
      cost: cost,
      createdAt: DateTime.now(),
    );
    await _db.insertMedicalRecord(row);
    return row;
  }

  Future<void> update(MedicalRecordRow row) => _db.updateMedicalRecord(row);

  Future<void> delete(String id) => _db.deleteMedicalRecord(id);

  Future<List<MedicalRecordRow>> search({
    String? personId,
    String? hospital,
    String? visitType,
    String? keyword,
    DateTime? startTime,
    DateTime? endTime,
  }) =>
      _db.searchRecords(
        personId: personId,
        hospital: hospital,
        visitType: visitType,
        keyword: keyword,
        startTime: startTime?.millisecondsSinceEpoch,
        endTime: endTime?.millisecondsSinceEpoch,
      );

  Future<List<String>> getAllHospitals() => _db.getAllHospitals();
}
