// services/platform_services/real_instagram_service.dart
// ignore_for_file: avoid_print, unused_element

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../models/media_file.dart';
import '../native_bridge.dart';

class InstagramService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/instagram');

  // Real Instagram cache paths - no mock data
  static const List<String> instagramCachePaths = [
    '/storage/emulated/0/Android/data/com.instagram.android/cache',
    '/storage/emulated/0/Android/data/com.instagram.android/files',
    '/storage/emulated/0/Android/data/com.instagram.android/cache/tmp',
    '/storage/emulated/0/Android/data/com.instagram.android/cache/video_cache',
    '/storage/emulated/0/Android/data/com.instagram.android/cache/image_cache',
    '/sdcard/Android/data/com.instagram.android/cache',
  ];

  // Real Instagram internal storage paths
  static const List<String> instagramInternalPaths = [
    '/data/data/com.instagram.android/cache',
    '/data/data/com.instagram.android/files',
  ];

  /// Get real cached media files from Instagram
  Future<List<MediaFile>> getCachedMedia() async {
    final List<MediaFile> cachedMedia = [];

    try {
      // Use native bridge to access Instagram cache with proper permissions
      final List<String> cachedFiles =
          await NativeBridge.getInstagramCachedMedia();

      for (final filePath in cachedFiles) {
        if (_isValidMediaFile(filePath)) {
          final mediaFile = await _createMediaFileFromPath(filePath);
          if (mediaFile != null) {
            cachedMedia.add(mediaFile);
          }
        }
      }

      print('Instagram cached media found: ${cachedMedia.length} files');
      return cachedMedia;
    } catch (e) {
      print('Error getting Instagram cached media: $e');
      return [];
    }
  }

  /// Get currently viewed Instagram media (using accessibility service)
  Future<MediaFile?> getCurrentViewedMedia() async {
    try {
      final String? currentMediaPath =
          await _channel.invokeMethod('getCurrentViewedMedia');

      if (currentMediaPath != null && currentMediaPath.isNotEmpty) {
        return await _createMediaFileFromPath(currentMediaPath);
      }

      return null;
    } catch (e) {
      print('Error getting current viewed Instagram media: $e');
      return null;
    }
  }

  /// Download Instagram media file to permanent location
  Future<bool> downloadMedia(MediaFile mediaFile) async {
    try {
      // Use native bridge to download with proper file operations
      final bool result =
          await NativeBridge.downloadDetectedMedia(mediaFile.path);

      if (result) {
        print('Instagram media downloaded successfully: ${mediaFile.fileName}');

        // Scan the downloaded file to make it visible in gallery
        final String downloadPath = await _getDownloadPath(mediaFile.fileName);
        await NativeBridge.scanMediaFile(downloadPath);
      }

      return result;
    } catch (e) {
      print('Error downloading Instagram media: $e');
      return false;
    }
  }

  /// Monitor Instagram app for new media
  Future<void> startMonitoring() async {
    try {
      await _channel.invokeMethod('startInstagramMonitoring');
      print('Instagram monitoring started');
    } catch (e) {
      print('Error starting Instagram monitoring: $e');
    }
  }

  /// Stop monitoring Instagram app
  Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopInstagramMonitoring');
      print('Instagram monitoring stopped');
    } catch (e) {
      print('Error stopping Instagram monitoring: $e');
    }
  }

  /// Get Instagram media info from real file
  Future<Map<String, dynamic>> getMediaInfo(String filePath) async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getMediaInfo', filePath);
      return result.cast<String, dynamic>();
    } catch (e) {
      print('Error getting Instagram media info: $e');
      return {
        'title': 'Instagram Media',
        'thumbnail': '',
        'isVideo': _isVideoFile(filePath),
        'duration': 0,
        'size': 0,
      };
    }
  }

  /// Scan Instagram cache directories manually
  Future<List<MediaFile>> scanCacheDirectories() async {
    final List<MediaFile> foundMedia = [];

    for (final cachePath in instagramCachePaths) {
      try {
        final Directory cacheDir = Directory(cachePath);

        if (await cacheDir.exists()) {
          final List<FileSystemEntity> entities =
              cacheDir.listSync(recursive: true);

          for (final entity in entities) {
            if (entity is File && _isValidMediaFile(entity.path)) {
              final mediaFile = await _createMediaFileFromPath(entity.path);
              if (mediaFile != null) {
                foundMedia.add(mediaFile);
              }
            }
          }
        }
      } catch (e) {
        print('Error scanning Instagram cache directory $cachePath: $e');
      }
    }

    // Sort by most recently accessed
    foundMedia.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));

    print('Manual Instagram cache scan found: ${foundMedia.length} files');
    return foundMedia;
  }

  /// Get Instagram stories cache (if accessible)
  Future<List<MediaFile>> getStoriesCache() async {
    final List<MediaFile> stories = [];

    try {
      const String storiesPath =
          '/storage/emulated/0/Android/data/com.instagram.android/cache/stories';
      final Directory storiesDir = Directory(storiesPath);

      if (await storiesDir.exists()) {
        final List<FileSystemEntity> entities = storiesDir.listSync();

        for (final entity in entities) {
          if (entity is File && _isValidMediaFile(entity.path)) {
            final mediaFile = await _createMediaFileFromPath(entity.path);
            if (mediaFile != null) {
              stories.add(mediaFile);
            }
          }
        }
      }
    } catch (e) {
      print('Error getting Instagram stories cache: $e');
    }

    return stories;
  }

  /// Get Instagram reels cache (if accessible)
  Future<List<MediaFile>> getReelsCache() async {
    final List<MediaFile> reels = [];

    try {
      const String reelsPath =
          '/storage/emulated/0/Android/data/com.instagram.android/cache/reels';
      final Directory reelsDir = Directory(reelsPath);

      if (await reelsDir.exists()) {
        final List<FileSystemEntity> entities = reelsDir.listSync();

        for (final entity in entities) {
          if (entity is File && _isValidMediaFile(entity.path)) {
            final mediaFile = await _createMediaFileFromPath(entity.path);
            if (mediaFile != null) {
              reels.add(mediaFile);
            }
          }
        }
      }
    } catch (e) {
      print('Error getting Instagram reels cache: $e');
    }

    return reels;
  }

  /// Check if Instagram app is currently active
  Future<bool> isInstagramActive() async {
    try {
      final bool result = await _channel.invokeMethod('isInstagramActive');
      return result;
    } catch (e) {
      print('Error checking Instagram active status: $e');
      return false;
    }
  }

  /// Get recently viewed Instagram media (last 24 hours)
  Future<List<MediaFile>> getRecentlyViewedMedia() async {
    final List<MediaFile> recentMedia = [];

    try {
      final List<String> recentPaths =
          await _channel.invokeMethod('getRecentlyViewedMedia');

      for (final path in recentPaths) {
        if (_isValidMediaFile(path)) {
          final mediaFile = await _createMediaFileFromPath(path);
          if (mediaFile != null && mediaFile.isViewedInLast24Hours) {
            recentMedia.add(mediaFile);
          }
        }
      }

      // Sort by most recently viewed
      recentMedia.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    } catch (e) {
      print('Error getting recently viewed Instagram media: $e');
    }

    return recentMedia;
  }

  /// Clear Instagram cache (requires user permission)
  Future<bool> clearCache() async {
    try {
      final bool result = await _channel.invokeMethod('clearInstagramCache');
      print('Instagram cache cleared: $result');
      return result;
    } catch (e) {
      print('Error clearing Instagram cache: $e');
      return false;
    }
  }

  /// Get Instagram app cache size
  Future<int> getCacheSize() async {
    try {
      final int size = await _channel.invokeMethod('getInstagramCacheSize');
      return size;
    } catch (e) {
      print('Error getting Instagram cache size: $e');
      return 0;
    }
  }

  /// Extract Instagram media metadata
  Future<Map<String, dynamic>> extractMetadata(String filePath) async {
    try {
      final Map<dynamic, dynamic> metadata =
          await _channel.invokeMethod('extractMetadata', filePath);
      return metadata.cast<String, dynamic>();
    } catch (e) {
      print('Error extracting Instagram metadata: $e');
      return {};
    }
  }

  /// Create MediaFile object from real file path
  Future<MediaFile?> _createMediaFileFromPath(String filePath) async {
    try {
      final File file = File(filePath);

      if (!await file.exists()) {
        return null;
      }

      final FileStat stat = await file.stat();
      final String fileName = filePath.split('/').last;
      final bool isVideo = _isVideoFile(filePath);

      // Get additional metadata if available
      final Map<String, dynamic> metadata = await extractMetadata(filePath);

      return MediaFile(
        id: filePath.hashCode.toString(),
        path: filePath,
        fileName: fileName,
        fileSize: stat.size,
        isVideo: isVideo,
        sourceApp: 'instagram',
        createdAt: stat.modified,
        viewedAt: stat.accessed,
        isDownloaded: false,
        duration: metadata['duration'] != null
            ? Duration(milliseconds: metadata['duration'] as int)
            : null,
        metadata: metadata,
      );
    } catch (e) {
      print('Error creating MediaFile from path $filePath: $e');
      return null;
    }
  }

  /// Check if file is valid media file
  bool _isValidMediaFile(String filePath) {
    // Check file extension
    if (!_isMediaFile(filePath)) {
      return false;
    }

    // Check file size (ignore very small files, likely thumbnails)
    try {
      final File file = File(filePath);
      if (file.existsSync()) {
        final int size = file.lengthSync();
        // Ignore files smaller than 10KB (likely thumbnails or corrupted)
        if (size < 10240) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }

    // Check if file is not a temporary or system file
    final String fileName = filePath.split('/').last;
    if (fileName.startsWith('.') ||
        fileName.contains('tmp') ||
        fileName.contains('temp')) {
      return false;
    }

    return true;
  }

  /// Check if file is media file by extension
  bool _isMediaFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const supportedExtensions = [
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', // Images
      'mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', // Videos
    ];
    return supportedExtensions.contains(extension);
  }

  /// Check if file is video file
  bool _isVideoFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    return videoExtensions.contains(extension);
  }

  /// Get download path for Instagram media
  Future<String> _getDownloadPath(String fileName) async {
    try {
      final String? externalPath = await NativeBridge.getExternalStoragePath();
      final String downloadDir =
          '$externalPath/Download/AllSocialDownloader/Instagram';

      // Ensure directory exists
      final Directory dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      return '$downloadDir/$fileName';
    } catch (e) {
      print('Error getting download path: $e');
      return '/storage/emulated/0/Download/$fileName';
    }
  }

  /// Generate unique filename to avoid conflicts
  String _generateUniqueFileName(
      String originalName, List<String> existingFiles) {
    if (!existingFiles.contains(originalName)) {
      return originalName;
    }

    final String nameWithoutExt = originalName.split('.').first;
    final String extension = originalName.split('.').last;

    int counter = 1;
    String newName;

    do {
      newName = '${nameWithoutExt}_$counter.$extension';
      counter++;
    } while (existingFiles.contains(newName));

    return newName;
  }

  /// Listen for Instagram media detection events
  Stream<MediaFile> get mediaDetectionStream {
    return NativeBridge.mediaDetectionStream
        .where((path) => path != null && path.contains('instagram'))
        .asyncMap((path) => _createMediaFileFromPath(path!))
        .where((mediaFile) => mediaFile != null)
        .cast<MediaFile>();
  }

  /// Get Instagram app installation status
  Future<bool> isInstagramInstalled() async {
    try {
      final bool result = await _channel.invokeMethod('isInstagramInstalled');
      return result;
    } catch (e) {
      print('Error checking Instagram installation: $e');
      return false;
    }
  }

  /// Get Instagram app version
  Future<String?> getInstagramVersion() async {
    try {
      final String? version =
          await _channel.invokeMethod('getInstagramVersion');
      return version;
    } catch (e) {
      print('Error getting Instagram version: $e');
      return null;
    }
  }

  /// Get Instagram data directory size
  Future<int> getDataDirectorySize() async {
    try {
      final int size = await _channel.invokeMethod('getDataDirectorySize');
      return size;
    } catch (e) {
      print('Error getting Instagram data directory size: $e');
      return 0;
    }
  }

  /// Cleanup old cached files (older than specified days)
  Future<int> cleanupOldCache({int olderThanDays = 7}) async {
    int deletedCount = 0;
    final DateTime cutoffDate =
        DateTime.now().subtract(Duration(days: olderThanDays));

    try {
      for (final cachePath in instagramCachePaths) {
        final Directory cacheDir = Directory(cachePath);

        if (await cacheDir.exists()) {
          final List<FileSystemEntity> entities =
              cacheDir.listSync(recursive: true);

          for (final entity in entities) {
            if (entity is File) {
              try {
                final FileStat stat = await entity.stat();
                if (stat.modified.isBefore(cutoffDate)) {
                  await entity.delete();
                  deletedCount++;
                }
              } catch (e) {
                print('Error deleting old cache file ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error cleaning up Instagram cache: $e');
    }

    print('Instagram cache cleanup: $deletedCount files deleted');
    return deletedCount;
  }

  /// Get statistics about Instagram cache
  Future<Map<String, dynamic>> getCacheStatistics() async {
    int totalFiles = 0;
    int totalSize = 0;
    int videoFiles = 0;
    int imageFiles = 0;

    try {
      for (final cachePath in instagramCachePaths) {
        final Directory cacheDir = Directory(cachePath);

        if (await cacheDir.exists()) {
          final List<FileSystemEntity> entities =
              cacheDir.listSync(recursive: true);

          for (final entity in entities) {
            if (entity is File && _isValidMediaFile(entity.path)) {
              try {
                final FileStat stat = await entity.stat();
                totalFiles++;
                totalSize += stat.size;

                if (_isVideoFile(entity.path)) {
                  videoFiles++;
                } else {
                  imageFiles++;
                }
              } catch (e) {
                print('Error getting file stats for ${entity.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error getting Instagram cache statistics: $e');
    }

    return {
      'totalFiles': totalFiles,
      'totalSize': totalSize,
      'videoFiles': videoFiles,
      'imageFiles': imageFiles,
      'averageFileSize': totalFiles > 0 ? totalSize / totalFiles : 0,
    };
  }
}
