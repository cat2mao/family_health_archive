import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/repositories/attachment_repository.dart';
import '../data/repositories/medical_record_repository.dart';
import '../data/repositories/person_repository.dart';
import '../data/repositories/reminder_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/weight_repository.dart';
import '../services/first_launch_service.dart';

// Database
final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  return AppDatabase.instance();
});

// Repositories
final personRepositoryProvider = FutureProvider<PersonRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return PersonRepository(db);
});

final medicalRecordRepositoryProvider =
    FutureProvider<MedicalRecordRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return MedicalRecordRepository(db);
});

final attachmentRepositoryProvider =
    FutureProvider<AttachmentRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return AttachmentRepository(db);
});

final tagRepositoryProvider = FutureProvider<TagRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return TagRepository(db);
});

final reminderRepositoryProvider = FutureProvider<ReminderRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return ReminderRepository(db);
});

final weightRepositoryProvider = FutureProvider<WeightRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return WeightRepository(db);
});

// Bootstrap
final bootstrapProvider = FutureProvider<String?>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  if (await FirstLaunchService.needsSeed()) {
    return FirstLaunchService(db).seedSampleData();
  }
  final repo = PersonRepository(db);
  // Seed preset tags
  final tagRepo = TagRepository(db);
  await tagRepo.seedPresetTags();
  return (await repo.getSelf())?.id;
});

// Persons
final personsProvider = FutureProvider<List<PersonRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(personRepositoryProvider.future);
  return repo.getAll();
});

final selectedPersonIdProvider = StateProvider<String?>((ref) => null);

// Records
final recordsForSelectedPersonProvider =
    FutureProvider<List<MedicalRecordRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final persons = await ref.watch(personsProvider.future);
  if (persons.isEmpty) return [];
  final selectedId = ref.watch(selectedPersonIdProvider);
  final personId = selectedId ??
      persons
          .where((p) => p.relationship == 'self')
          .map((p) => p.id)
          .firstOrNull ??
      persons.first.id;
  final repo = await ref.watch(medicalRecordRepositoryProvider.future);
  return repo.getByPerson(personId);
});

// All records (for search/statistics)
final allRecordsProvider = FutureProvider<List<MedicalRecordRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(medicalRecordRepositoryProvider.future);
  return repo.getAll();
});

// Tags
final allTagsProvider = FutureProvider<List<TagRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(tagRepositoryProvider.future);
  return repo.getAll();
});

// Reminders
final activeRemindersProvider = FutureProvider<List<ReminderRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(reminderRepositoryProvider.future);
  return repo.getActive();
});

final archivedRemindersProvider = FutureProvider<List<ReminderRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(reminderRepositoryProvider.future);
  return repo.getArchived();
});

// Search
final searchKeywordProvider = StateProvider<String>((ref) => '');
final searchPersonFilterProvider = StateProvider<String?>((ref) => null);
final searchHospitalFilterProvider = StateProvider<String?>((ref) => null);
final searchVisitTypeFilterProvider = StateProvider<String?>((ref) => null);

final searchResultsProvider = FutureProvider<List<MedicalRecordRow>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(medicalRecordRepositoryProvider.future);
  final keyword = ref.watch(searchKeywordProvider);
  final personId = ref.watch(searchPersonFilterProvider);
  final hospital = ref.watch(searchHospitalFilterProvider);
  final visitType = ref.watch(searchVisitTypeFilterProvider);

  if (keyword.isEmpty && personId == null && hospital == null && visitType == null) {
    return [];
  }

  return repo.search(
    personId: personId,
    hospital: hospital,
    visitType: visitType,
    keyword: keyword.isEmpty ? null : keyword,
  );
});

// Hospital autocomplete
final hospitalsProvider = FutureProvider<List<String>>((ref) async {
  await ref.watch(bootstrapProvider.future);
  final repo = await ref.watch(medicalRecordRepositoryProvider.future);
  return repo.getAllHospitals();
});
