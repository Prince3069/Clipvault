// services/storage_service.dart
// COMPLETE - All methods defined including getSavedEdits, deleteSavedEdit, saveEditedFile

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/native');

  // ─── Get Download Path ──────────────────────────────────────────────────

  Future<String> getPlatformDownloadPath(String subFolder) async {
    try {
      if (Platform.isAndroid) {
        final dir =
            Directory('/storage/emulated/0/Download/ClipVaults/$subFolder');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        return dir.path;
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final folder = Directory('${dir.path}/ClipVaults/$subFolder');
        if (!await folder.exists()) {
          await folder.create(recursive: true);
        }
        return folder.path;
      }
    } catch (e) {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/ClipVaults/$subFolder');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }
      return folder.path;
    }
  }

  Future<String> get publicDownloadsDirectory async {
    const String publicPath = '/storage/emulated/0/Download/ClipVaults';
    final Directory dir = Directory(publicPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return publicPath;
  }

  // ─── Scan Media File ──────────────────────────────────────────────────

  Future<void> scanMediaFile(String path) async {
    try {
      await _channel.invokeMethod('scanMediaFile', path);
      print('✅ Scanned: $path');
    } catch (e) {
      print('⚠️ Could not scan media file: $e');
    }
  }

  // ─── SAVE EDITED FILE WITH TRACKING ──────────────────────────────────

  Future<String?> saveEditedFile({
    required String sourcePath,
    required String fileName,
    required String editType,
    required String mimeType,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return null;
      }

      final editsPath = await getPlatformDownloadPath('Edits');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final extension = sourcePath.split('.').last;
      final newFileName = '${editType}_${timestamp}_$safeName.$extension';
      final fullPath = '$editsPath/$newFileName';

      await sourceFile.copy(fullPath);
      await scanMediaFile(fullPath);
      await _trackEdit(fullPath, fileName, editType);

      print('✅ Saved edit: $fullPath');
      return fullPath;
    } catch (e) {
      print('❌ Error saving edited file: $e');
      return null;
    }
  }

  // ─── TRACK EDITS ──────────────────────────────────────────────────────

  Future<void> _trackEdit(
      String path, String originalName, String editType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final edits = prefs.getStringList('saved_edits') ?? [];

      final editInfo =
          '$path|$originalName|$editType|${DateTime.now().millisecondsSinceEpoch}';
      edits.add(editInfo);

      if (edits.length > 500) {
        edits.removeRange(0, edits.length - 500);
      }

      await prefs.setStringList('saved_edits', edits);
    } catch (e) {
      print('⚠️ Could not track edit: $e');
    }
  }

  // ─── GET SAVED EDITS ──────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSavedEdits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final edits = prefs.getStringList('saved_edits') ?? [];

      final result = <Map<String, dynamic>>[];
      for (final edit in edits) {
        try {
          final parts = edit.split('|');
          if (parts.length >= 4) {
            final path = parts[0];
            final file = File(path);
            if (await file.exists()) {
              result.add({
                'path': path,
                'originalName': parts[1],
                'editType': parts[2],
                'timestamp': int.tryParse(parts[3]) ?? 0,
                'size': await file.length(),
              });
            }
          }
        } catch (e) {
          // Skip invalid entries
        }
      }

      result.sort(
          (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
      return result;
    } catch (e) {
      print('⚠️ Could not get saved edits: $e');
      return [];
    }
  }

  // ─── DELETE SAVED EDIT ───────────────────────────────────────────────

  Future<bool> deleteSavedEdit(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      final edits = prefs.getStringList('saved_edits') ?? [];
      edits.removeWhere((edit) => edit.startsWith(path));
      await prefs.setStringList('saved_edits', edits);

      return true;
    } catch (e) {
      print('⚠️ Could not delete edit: $e');
      return false;
    }
  }

  // ─── DOWNLOAD FILE WITH PROGRESS ─────────────────────────────────────

  Future<bool> downloadFileWithProgress(
    String url,
    String filePath, {
    required void Function(double progress) onProgress,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        client.close(force: true);
        return false;
      }

      final file = File(filePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();

      final totalBytes = response.contentLength;
      var downloadedBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          onProgress(downloadedBytes / totalBytes);
        } else {
          onProgress(0.0);
        }
      }

      await sink.flush();
      await sink.close();
      client.close(force: true);
      onProgress(1.0);
      return true;
    } catch (e) {
      print('Download error: $e');
      return false;
    }
  }

  // ─── GET FILE SIZE ────────────────────────────────────────────────────

  Future<int> getFileSize(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // ─── CHECK IF FILE EXISTS ────────────────────────────────────────────

  Future<bool> fileExists(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // ─── DELETE FILE ──────────────────────────────────────────────────────

  Future<bool> deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ─── GET ALL FILES IN FOLDER ─────────────────────────────────────────

  Future<List<String>> getFilesInFolder(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) {
        return [];
      }
      final files = await dir.list().toList();
      return files
          .where((entity) => entity is File)
          .map((entity) => entity.path)
          .toList();
    } catch (e) {
      return [];
    }
  }

  // ─── SAVE MEDIA FILE ──────────────────────────────────────────────────

  Future<String> saveMediaFile(
      String sourcePath, String fileName, String platform) async {
    try {
      final sourceFile = File(sourcePath);
      final directory = await publicDownloadsDirectory;

      final platformDir = '$directory/${_getPlatformFolderName(platform)}';
      await Directory(platformDir).create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = fileName.split('.').last;
      final baseName = fileName.split('.').first;
      final uniqueFileName = '${platform}_${baseName}_$timestamp.$extension';

      final destinationPath = '$platformDir/$uniqueFileName';

      await sourceFile.copy(destinationPath);
      await scanMediaFile(destinationPath);

      return destinationPath;
    } catch (e) {
      print('❌ Error saving media file: $e');
      rethrow;
    }
  }

  String _getPlatformFolderName(String platform) {
    switch (platform.toLowerCase()) {
      case 'whatsapp':
      case 'whatsapp_business':
        return 'WhatsApp';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'tiktok':
        return 'TikTok';
      case 'twitter':
        return 'Twitter';
      case 'telegram':
        return 'Telegram';
      default:
        return 'Other';
    }
  }

  // ─── GET DOWNLOADED FILES ────────────────────────────────────────────

  Future<List<FileSystemEntity>> getDownloadedFiles() async {
    try {
      final directory = await publicDownloadsDirectory;
      final dir = Directory(directory);

      if (!await dir.exists()) {
        return [];
      }

      final List<FileSystemEntity> files = [];
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && _isMediaFile(entity.path)) {
          files.add(entity);
        }
      }

      files.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      return files;
    } catch (e) {
      print('❌ Error getting downloaded files: $e');
      return [];
    }
  }

  bool _isMediaFile(String filePath) {
    const mediaExtensions = [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.webm',
      '.3gp'
    ];
    return mediaExtensions.any((ext) => filePath.toLowerCase().endsWith(ext));
  }

  // ─── GET STORAGE INFO ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStorageInfo() async {
    try {
      final directory = await publicDownloadsDirectory;
      final dir = Directory(directory);

      if (!await dir.exists()) {
        return {
          'totalFiles': 0,
          'totalSize': 0,
          'path': directory,
        };
      }

      int totalFiles = 0;
      int totalSize = 0;
      Map<String, int> platformCounts = {};

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalFiles++;
          try {
            final stat = entity.statSync();
            totalSize += stat.size;

            final pathSegments = entity.path.split('/');
            final platformFolder = pathSegments.length > 1
                ? pathSegments[pathSegments.length - 2]
                : 'Other';
            platformCounts[platformFolder] =
                (platformCounts[platformFolder] ?? 0) + 1;
          } catch (e) {
            // Skip files we can't access
          }
        }
      }

      return {
        'totalFiles': totalFiles,
        'totalSize': totalSize,
        'formattedSize': _formatFileSize(totalSize),
        'path': directory,
        'platformCounts': platformCounts,
        'isPermanent': true,
      };
    } catch (e) {
      return {
        'totalFiles': 0,
        'totalSize': 0,
        'path': 'Error accessing storage',
        'isPermanent': false,
      };
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // ─── SAVE WHATSAPP STATUS ────────────────────────────────────────────

  Future<String> saveStatus(StatusItem status) async {
    try {
      final sourceFile = File(status.path);
      final directory = await publicDownloadsDirectory;
      final fileName = status.path.split('/').last;

      final whatsappDir = '$directory/WhatsApp';
      await Directory(whatsappDir).create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final extension = fileName.split('.').last;
      final baseName = fileName.split('.').first;
      final uniqueFileName = '${baseName}_$timestamp.$extension';

      final destinationPath = '$whatsappDir/$uniqueFileName';
      await sourceFile.copy(destinationPath);
      await scanMediaFile(destinationPath);

      return destinationPath;
    } catch (e) {
      print('❌ Error saving WhatsApp status: $e');
      rethrow;
    }
  }
}

// ─── StatusItem Model ──────────────────────────────────────────────────────

class StatusItem {
  final String id;
  final String path;
  final bool isVideo;
  final DateTime createdAt;

  StatusItem({
    required this.id,
    required this.path,
    required this.isVideo,
    required this.createdAt,
  });
}
