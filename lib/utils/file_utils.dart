// utils/file_utils.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class FileUtils {
  static Future<String> getUniqueFileName(
      String directory, String fileName) async {
    final File file = File(path.join(directory, fileName));
    if (!await file.exists()) {
      return fileName;
    }

    int counter = 1;
    String fileNameWithoutExtension = path.basenameWithoutExtension(fileName);
    String extension = path.extension(fileName);

    while (true) {
      final String newFileName =
          '$fileNameWithoutExtension ($counter)$extension';
      final File newFile = File(path.join(directory, newFileName));

      if (!await newFile.exists()) {
        return newFileName;
      }

      counter++;
    }
  }

  // utils/file_utils.dart (continued)
  static Future<String> getFileSize(String filePath) async {
    final File file = File(filePath);
    if (!await file.exists()) {
      return '0 B';
    }

    final int bytes = await file.length();
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  static Future<void> deleteFile(String filePath) async {
    final File file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> renameFile(String oldPath, String newPath) async {
    final File file = File(oldPath);
    if (await file.exists()) {
      await file.rename(newPath);
    }
  }

  static Future<bool> checkDiskSpace(int requiredBytes) async {
    try {
      final Directory? directory = await getExternalStorageDirectory();
      if (directory == null) return false;

      // This is a simplification - in production you'd use a plugin to check available disk space
      return true;
    } catch (e) {
      return false;
    }
  }
}
