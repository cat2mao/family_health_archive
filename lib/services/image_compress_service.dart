import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImageCompressService {
  static const _uuid = Uuid();
  static const int _maxLongEdge = 1080;
  static const int _quality = 80;

  /// Compress image to max 1080px long edge, <= 500KB target
  static Future<File?> compressImage(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!await attachmentsDir.exists()) {
      await attachmentsDir.create(recursive: true);
    }

    final ext = p.extension(source.path).toLowerCase();
    final targetPath = p.join(attachmentsDir.path, '${_uuid.v4()}$ext');

    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      quality: _quality,
      minWidth: _maxLongEdge,
      minHeight: _maxLongEdge,
      keepExif: false,
    );

    if (result == null) return null;

    // If still too large (>500KB), compress again with lower quality
    final file = File(result.path);
    if (await file.length() > 500 * 1024) {
      final targetPath2 = p.join(attachmentsDir.path, '${_uuid.v4()}$ext');
      final result2 = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath2,
        quality: 60,
        minWidth: _maxLongEdge,
        minHeight: _maxLongEdge,
        keepExif: false,
      );
      if (result2 != null) {
        await file.delete();
        return File(result2.path);
      }
    }
    return file;
  }

  /// Generate thumbnail (200px long edge)
  static Future<String?> generateThumbnail(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final thumbDir = Directory(p.join(dir.path, 'attachments', 'thumbnails'));
    if (!await thumbDir.exists()) {
      await thumbDir.create(recursive: true);
    }

    final targetPath = p.join(thumbDir.path, '${_uuid.v4()}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      source.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 200,
      minHeight: 200,
    );
    return result?.path;
  }
}
