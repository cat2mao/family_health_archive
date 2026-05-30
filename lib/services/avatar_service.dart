import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class AvatarService {
  static const _uuid = Uuid();

  static Future<String?> saveAvatarFromFile(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(p.join(dir.path, 'avatars'));
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }
    final ext = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final dest = File(p.join(avatarsDir.path, '${_uuid.v4()}$ext'));
    await source.copy(dest.path);
    return dest.path;
  }

  static Future<void> deleteAvatarIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
