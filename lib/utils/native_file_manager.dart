// utils/native_file_manager.dart
// ignore_for_file: avoid_print, unused_import

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_file.dart';

class NativeFileManager {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/file_manager');

  /// Check if app has access to specific directory
  static Future<bool> hasDirectoryAccess(String directoryPath) async {
    try {
      final bool result =
          await _channel.invokeMethod('hasDirectoryAccess', directoryPath);
      return result;
    } catch (e) {
      print('Error checking directory access for $directoryPath: $e');
      return false;
    }
  }

  /// Request access to specific directory (Android 11+ scoped storage)
  static Future<bool> requestDirectoryAccess(String directoryPath) async {
    try {
      final bool result =
          await _channel.invokeMethod('requestDirectoryAccess', directoryPath);
      return result;
    } catch (e) {
      print('Error requesting directory access for $directoryPath: $e');
      return false;
    }
  }

  /// Copy file from source to destination with progress callback
  static Future<bool> copyFileWithProgress(
    String sourcePath,
    String destinationPath,
    Function(double)? onProgress,
  ) async {
    try {
      final Map<String, dynamic> params = {
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
      };

      // Set up progress callback if provided
      if (onProgress != null) {
        _channel.setMethodCallHandler((call) async {
          if (call.method == 'onCopyProgress') {
            final double progress = call.arguments as double;
            onProgress(progress);
          }
        });
      }

      final bool result =
          await _channel.invokeMethod('copyFileWithProgress', params);
      return result;
    } catch (e) {
      print('Error copying file from $sourcePath to $destinationPath: $e');
      return false;
    }
  }

  /// Move file from source to destination
  static Future<bool> moveFile(
      String sourcePath, String destinationPath) async {
    try {
      final Map<String, dynamic> params = {
        'sourcePath': sourcePath,
        'destinationPath': destinationPath,
      };

      final bool result = await _channel.invokeMethod('moveFile', params);
      return result;
    } catch (e) {
      print('Error moving file from $sourcePath to $destinationPath: $e');
      return false;
    }
  }

  /// Delete file safely
  static Future<bool> deleteFile(String filePath) async {
    try {
      final bool result = await _channel.invokeMethod('deleteFile', filePath);
      return result;
    } catch (e) {
      print('Error deleting file $filePath: $e');
      return false;
    }
  }

  /// Get file metadata (size, dates, permissions)
  static Future<Map<String, dynamic>?> getFileMetadata(String filePath) async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getFileMetadata', filePath);
      return result.cast<String, dynamic>();
    } catch (e) {
      print('Error getting file metadata for $filePath: $e');
      return null;
    }
  }

  /// Scan file to make it visible in gallery
  static Future<bool> scanMediaFile(String filePath) async {
    try {
      final bool result =
          await _channel.invokeMethod('scanMediaFile', filePath);
      return result;
    } catch (e) {
      print('Error scanning media file $filePath: $e');
      return false;
    }
  }

  /// Get all files in directory with filter
  static Future<List<String>> getFilesInDirectory(
    String directoryPath, {
    List<String>? extensions,
    bool recursive = false,
    int? maxAge, // in hours
  }) async {
    try {
      final Map<String, dynamic> params = {
        'directoryPath': directoryPath,
        'extensions': extensions,
        'recursive': recursive,
        'maxAge': maxAge,
      };

      final List<dynamic> result =
          await _channel.invokeMethod('getFilesInDirectory', params);
      return result.cast<String>();
    } catch (e) {
      print('Error getting files in directory $directoryPath: $e');
      return [];
    }
  }

  /// Get directory size
  static Future<int> getDirectorySize(String directoryPath) async {
    try {
      final int result =
          await _channel.invokeMethod('getDirectorySize', directoryPath);
      return result;
    } catch (e) {
      print('Error getting directory size for $directoryPath: $e');
      return 0;
    }
  }

  /// Create directory if it doesn't exist
  static Future<bool> createDirectory(String directoryPath) async {
    try {
      final bool result =
          await _channel.invokeMethod('createDirectory', directoryPath);
      return result;
    } catch (e) {
      print('Error creating directory $directoryPath: $e');
      return false;
    }
  }

  /// Get external storage path
  static Future<String?> getExternalStoragePath() async {
    try {
      final String? result =
          await _channel.invokeMethod('getExternalStoragePath');
      return result;
    } catch (e) {
      print('Error getting external storage path: $e');
      return null;
    }
  }

  /// Get app-specific external storage path
  static Future<String?> getAppExternalStoragePath() async {
    try {
      final String? result =
          await _channel.invokeMethod('getAppExternalStoragePath');
      return result;
    } catch (e) {
      print('Error getting app external storage path: $e');
      return null;
    }
  }

  /// Check if file exists
  static Future<bool> fileExists(String filePath) async {
    try {
      final bool result = await _channel.invokeMethod('fileExists', filePath);
      return result;
    } catch (e) {
      print('Error checking if file exists $filePath: $e');
      return false;
    }
  }

  /// Get available storage space
  static Future<int> getAvailableStorageSpace() async {
    try {
      final int result =
          await _channel.invokeMethod('getAvailableStorageSpace');
      return result;
    } catch (e) {
      print('Error getting available storage space: $e');
      return 0;
    }
  }

  /// Generate unique filename in directory
  static Future<String> generateUniqueFileName(
      String directoryPath, String fileName) async {
    try {
      final Map<String, dynamic> params = {
        'directoryPath': directoryPath,
        'fileName': fileName,
      };

      final String result =
          await _channel.invokeMethod('generateUniqueFileName', params);
      return result;
    } catch (e) {
      print('Error generating unique filename: $e');
      return fileName;
    }
  }

  /// Get recently accessed files
  static Future<List<String>> getRecentlyAccessedFiles({
    int maxCount = 50,
    int maxAgeHours = 24,
  }) async {
    try {
      final Map<String, dynamic> params = {
        'maxCount': maxCount,
        'maxAgeHours': maxAgeHours,
      };

      final List<dynamic> result =
          await _channel.invokeMethod('getRecentlyAccessedFiles', params);
      return result.cast<String>();
    } catch (e) {
      print('Error getting recently accessed files: $e');
      return [];
    }
  }

  /// Watch directory for changes
  static Future<bool> watchDirectory(String directoryPath) async {
    try {
      final bool result =
          await _channel.invokeMethod('watchDirectory', directoryPath);
      return result;
    } catch (e) {
      print('Error watching directory $directoryPath: $e');
      return false;
    }
  }

  /// Stop watching directory
  static Future<bool> stopWatchingDirectory(String directoryPath) async {
    try {
      final bool result =
          await _channel.invokeMethod('stopWatchingDirectory', directoryPath);
      return result;
    } catch (e) {
      print('Error stopping directory watch $directoryPath: $e');
      return false;
    }
  }

  /// Get file hash (for duplicate detection)
  static Future<String?> getFileHash(String filePath) async {
    try {
      final String? result =
          await _channel.invokeMethod('getFileHash', filePath);
      return result;
    } catch (e) {
      print('Error getting file hash for $filePath: $e');
      return null;
    }
  }

  /// Find duplicate files
  static Future<List<List<String>>> findDuplicateFiles(
      List<String> filePaths) async {
    try {
      final List<dynamic> result =
          await _channel.invokeMethod('findDuplicateFiles', filePaths);
      return result.map((group) => (group as List).cast<String>()).toList();
    } catch (e) {
      print('Error finding duplicate files: $e');
      return [];
    }
  }

  /// Compress file (if supported)
  static Future<String?> compressFile(String filePath,
      {int quality = 80}) async {
    try {
      final Map<String, dynamic> params = {
        'filePath': filePath,
        'quality': quality,
      };

      final String? result =
          await _channel.invokeMethod('compressFile', params);
      return result;
    } catch (e) {
      print('Error compressing file $filePath: $e');
      return null;
    }
  }

  /// Extract thumbnail from video file
  static Future<String?> extractVideoThumbnail(String videoPath) async {
    try {
      final String? result =
          await _channel.invokeMethod('extractVideoThumbnail', videoPath);
      return result;
    } catch (e) {
      print('Error extracting thumbnail from $videoPath: $e');
      return null;
    }
  }

  /// Get video duration
  static Future<int?> getVideoDuration(String videoPath) async {
    try {
      final int? result =
          await _channel.invokeMethod('getVideoDuration', videoPath);
      return result;
    } catch (e) {
      print('Error getting video duration for $videoPath: $e');
      return null;
    }
  }

  /// Get image dimensions
  static Future<Map<String, int>?> getImageDimensions(String imagePath) async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getImageDimensions', imagePath);
      return result.cast<String, int>();
    } catch (e) {
      print('Error getting image dimensions for $imagePath: $e');
      return null;
    }
  }

  /// Create download folder structure
  static Future<bool> createDownloadFolders() async {
    try {
      final String? externalPath = await getExternalStoragePath();
      if (externalPath == null) return false;

      const List<String> folders = [
        'AllSocialDownloader',
        'AllSocialDownloader/WhatsApp',
        'AllSocialDownloader/Instagram',
        'AllSocialDownloader/TikTok',
        'AllSocialDownloader/Facebook',
        'AllSocialDownloader/Twitter',
      ];

      for (final folder in folders) {
        final String fullPath = '$externalPath/Download/$folder';
        await createDirectory(fullPath);
      }

      return true;
    } catch (e) {
      print('Error creating download folders: $e');
      return false;
    }
  }

  /// Get download folder for specific app
  static Future<String?> getDownloadFolder(String appName) async {
    try {
      final String? externalPath = await getExternalStoragePath();
      if (externalPath == null) return null;

      final String folderName = _getAppFolderName(appName);
      final String fullPath =
          '$externalPath/Download/AllSocialDownloader/$folderName';

      // Ensure folder exists
      await createDirectory(fullPath);

      return fullPath;
    } catch (e) {
      print('Error getting download folder for $appName: $e');
      return null;
    }
  }

  /// Get appropriate folder name for app
  static String _getAppFolderName(String appName) {
    switch (appName.toLowerCase()) {
      case 'whatsapp':
      case 'whatsapp_business':
        return 'WhatsApp';
      case 'instagram':
        return 'Instagram';
      case 'tiktok':
        return 'TikTok';
      case 'facebook':
        return 'Facebook';
      case 'twitter':
        return 'Twitter';
      default:
        return 'Other';
    }
  }

  /// Clean up temporary files
  static Future<int> cleanupTempFiles() async {
    try {
      final int result = await _channel.invokeMethod('cleanupTempFiles');
      return result;
    } catch (e) {
      print('Error cleaning up temp files: $e');
      return 0;
    }
  }

  /// Get storage usage statistics
  static Future<Map<String, dynamic>> getStorageUsageStats() async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getStorageUsageStats');
      return result.cast<String, dynamic>();
    } catch (e) {
      print('Error getting storage usage stats: $e');
      return {};
    }
  }
}
