import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../database/app_database.dart';

class PersonRepository {
  PersonRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<List<PersonRow>> getAll() => _db.getAllPersons();

  Future<PersonRow?> getById(String id) => _db.getPersonById(id);

  Future<PersonRow?> getSelf() async {
    final all = await getAll();
    try {
      return all.firstWhere((p) => p.relationship == Relationship.self.code);
    } catch (_) {
      return all.isNotEmpty ? all.first : null;
    }
  }

  Future<PersonRow> create({
    required String name,
    required PersonType type,
    required Relationship relationship,
    String? avatarPath,
    Gender? gender,
    String? birthDate,
    String? bloodType,
    String? allergies,
    String? chronicDiseases,
    String? longTermMeds,
    String? breed,
    bool? neutered,
    String? chipId,
  }) async {
    final row = PersonRow(
      id: _uuid.v4(),
      name: name,
      avatarPath: avatarPath,
      type: type.code,
      relationship: relationship.code,
      gender: gender?.code,
      birthDate: birthDate,
      bloodType: bloodType,
      allergies: allergies,
      chronicDiseases: chronicDiseases,
      longTermMeds: longTermMeds,
      breed: breed,
      neutered: neutered,
      chipId: chipId,
      createdAt: DateTime.now(),
    );
    await _db.insertPerson(row);
    return row;
  }

  Future<void> update(PersonRow row) => _db.updatePerson(row);

  Future<void> delete(String id) => _db.deletePerson(id);
}
