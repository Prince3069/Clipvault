// services/platform_services/real_facebook_service.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../models/media_file.dart';
import '../native_bridge.dart';

class FacebookService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/facebook');

  // Real Facebook cache paths
  static const List<String> facebookCachePaths = [
    '/storage/emulated/0/Android/data/com.facebook.katana/cache',
    '/storage/emulated/0/Android/data/com.facebook.katana/files',
    '/storage/emulated/0/Android/data/com.facebook.katana/cache/image',
    '/storage/emulated/0/Android/data/com.facebook.katana/cache/video',
    '/sdcard/Android/data/com.facebook.katana/cache',
  ];

  // Facebook Lite paths
  static const List<String> facebookLiteCachePaths = [
    '/storage/emulated/0/Android/data/com.facebook.lite/cache',
    '/storage/emulated/0/Android/data/com.facebook.lite/files',
    '/sdcard/Android/data/com.facebook.lite/cache',
  ];

  /// Get cached media files from Facebook (limited success)
  Future<List<MediaFile>> getCachedMedia() async {
    final List<MediaFile> cachedMedia = [];

    try {
      print('🔍 Scanning Facebook cache directories...');

      // Scan Facebook main app cache
      for (final path in facebookCachePaths) {
        final files = await _scanCacheDirectory(path, 'facebook');
        cachedMedia.addAll(files);
      }

      // Scan Facebook Lite cache
      for (final path in facebookLiteCachePaths) {
        final files = await _scanCacheDirectory(path, 'facebook_lite');
        cachedMedia.addAll(files);
      }

      // Filter out non-media files and very small files (thumbnails)
      final validMedia = cachedMedia
          .where((file) =>
              file.fileSize > 50000 && // Larger than 50KB
              _isValidFacebookMedia(file.path))
          .toList();

      print('📱 Facebook cached media found: ${validMedia.length} files');
      return validMedia;
    } catch (e) {
      print('❌ Error getting Facebook cached media: $e');
      return [];
    }
  }

  /// Scan Facebook cache directory
  Future<List<MediaFile>> _scanCacheDirectory(
      String cachePath, String sourceApp) async {
    final List<MediaFile> mediaFiles = [];

    try {
      final Directory cacheDir = Directory(cachePath);

      if (!await cacheDir.exists()) {
        print('📁 Facebook cache directory not found: $cachePath');
        return mediaFiles;
      }

      // Check if we have permission to access this directory
      try {
        final List<FileSystemEntity> entities =
            cacheDir.listSync(recursive: true);

        for (final entity in entities) {
          if (entity is File && _isMediaFile(entity.path)) {
            try {
              final FileStat stat = await entity.stat();

              // Skip very small files (likely thumbnails or metadata)
              if (stat.size < 10000) continue;

              final MediaFile mediaFile = MediaFile(
                id: entity.path.hashCode.toString(),
                path: entity.path,
                fileName: entity.path.split('/').last,
                fileSize: stat.size,
                isVideo: _isVideoFile(entity.path),
                sourceApp: sourceApp,
                createdAt: stat.modified,
                viewedAt: stat.accessed,
                isDownloaded: false,
              );

              mediaFiles.add(mediaFile);
            } catch (e) {
              // Skip files we can't access
              continue;
            }
          }
        }
      } catch (e) {
        print('⚠️  No permission to access Facebook cache: $cachePath');
      }
    } catch (e) {
      print('❌ Error scanning Facebook cache directory $cachePath: $e');
    }

    return mediaFiles;
  }

  /// Detect currently viewed Facebook content (using accessibility)
  Future<Map<String, dynamic>?> detectCurrentContent() async {
    try {
      final Map<dynamic, dynamic>? result =
          await _channel.invokeMethod('detectCurrentContent');
      if (result != null) {
        return result.cast<String, dynamic>();
      }
      return null;
    } catch (e) {
      print('❌ Error detecting current Facebook content: $e');
      return null;
    }
  }

  /// Attempt to download Facebook media (limited success)
  Future<bool> downloadMedia(MediaFile mediaFile) async {
    try {
      print('⬬ Attempting to download Facebook media: ${mediaFile.fileName}');

      // For Facebook, we can only download cached files
      if (!mediaFile.path.contains('/cache/')) {
        print('❌ Cannot download non-cached Facebook content');
        return false;
      }

      // Check if source file still exists
      final File sourceFile = File(mediaFile.path);
      if (!await sourceFile.exists()) {
        print('❌ Facebook source file no longer exists');
        return false;
      }

      // Download using native bridge
      final bool result =
          await NativeBridge.downloadDetectedMedia(mediaFile.path);

      if (result) {
        print('✅ Facebook media downloaded successfully');
      } else {
        print('❌ Facebook media download failed');
      }

      return result;
    } catch (e) {
      print('❌ Error downloading Facebook media: $e');
      return false;
    }
  }

  /// Take screenshot of current Facebook content (alternative approach)
  Future<String?> captureCurrentScreen() async {
    try {
      final String? screenshotPath =
          await _channel.invokeMethod('captureScreen');

      if (screenshotPath != null) {
        print('📸 Facebook screen captured: $screenshotPath');
        return screenshotPath;
      }

      return null;
    } catch (e) {
      print('❌ Error capturing Facebook screen: $e');
      return null;
    }
  }

  /// Get Facebook app information
  Future<Map<String, dynamic>> getFacebookAppInfo() async {
    try {
      final Map<String, dynamic> info = {
        'isInstalled': await _isFacebookInstalled(),
        'version': await _getFacebookVersion(),
        'cacheSize': await _getCacheSize(),
        'canAccessCache': await _canAccessCache(),
      };

      return info;
    } catch (e) {
      print('❌ Error getting Facebook app info: $e');
      return {};
    }
  }

  /// Check if Facebook is installed
  Future<bool> _isFacebookInstalled() async {
    try {
      final bool result = await _channel.invokeMethod('isFacebookInstalled');
      return result;
    } catch (e) {
      return false;
    }
  }

  /// Get Facebook version
  Future<String?> _getFacebookVersion() async {
    try {
      final String? version = await _channel.invokeMethod('getFacebookVersion');
      return version;
    } catch (e) {
      return null;
    }
  }

  /// Get Facebook cache size
  Future<int> _getCacheSize() async {
    try {
      int totalSize = 0;

      for (final path in [...facebookCachePaths, ...facebookLiteCachePaths]) {
        try {
          final Directory dir = Directory(path);
          if (await dir.exists()) {
            final List<FileSystemEntity> entities =
                dir.listSync(recursive: true);
            for (final entity in entities) {
              if (entity is File) {
                try {
                  final FileStat stat = await entity.stat();
                  totalSize += stat.size;
                } catch (e) {
                  // Skip files we can't access
                }
              }
            }
          }
        } catch (e) {
          // Skip directories we can't access
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Check if we can access Facebook cache
  Future<bool> _canAccessCache() async {
    try {
      for (final path in facebookCachePaths) {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          try {
            dir.listSync(recursive: false);
            return true; // If we can list without error, we have access
          } catch (e) {
            continue;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Monitor Facebook app activity
  Stream<Map<String, dynamic>> get facebookActivityStream {
    return NativeBridge.mediaDetectionStream
        .where((path) => path != null && path.contains('facebook'))
        .asyncMap((path) async {
      return {
        'type': 'media_detected',
        'path': path,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    });
  }

  /// Get Facebook media limitations info
  Map<String, dynamic> getFacebookLimitations() {
    return {
      'videoDownloads': {
        'supported': false,
        'reason': 'Facebook uses encrypted streaming URLs and DRM protection',
        'alternative': 'Screen recording or screenshot capture',
      },
      'imageDownloads': {
        'supported': true,
        'limitation': 'Only cached images, not all photos',
        'success_rate': 'Low to Medium',
      },
      'storyDownloads': {
        'supported': false,
        'reason': 'Stories are heavily protected and encrypted',
        'alternative': 'Screen capture only',
      },
      'cacheAccess': {
        'supported': true,
        'limitation': 'Limited by Android permissions and Facebook security',
        'note': 'Facebook minimizes cacheable content',
      },
      'recommendations': [
        'Use screen capture for videos',
        'Focus on cached images only',
        'Consider Facebook as low-priority platform',
        'Inform users about limitations',
      ],
    };
  }

  /// Helper methods
  bool _isMediaFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const supportedExtensions = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      '3gp',
    ];
    return supportedExtensions.contains(extension);
  }

  bool _isVideoFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    return videoExtensions.contains(extension);
  }

  bool _isValidFacebookMedia(String filePath) {
    // Facebook-specific validation
    final String fileName = filePath.split('/').last;

    // Skip obvious non-media files
    if (fileName.startsWith('.') ||
        fileName.contains('temp') ||
        fileName.contains('tmp') ||
        fileName.contains('thumbnail') ||
        fileName.length < 5) {
      return false;
    }

    // Facebook cache files often have specific patterns
    return _isMediaFile(filePath);
  }

  /// Show Facebook limitations dialog to user
  static Map<String, String> getFacebookUserWarnings() {
    return {
      'title': 'Facebook Download Limitations',
      'message': '''
⚠️ Facebook has strict content protection:

✅ What Works:
• Cached images (limited)
• Profile photos
• Some post images
• Screenshot capture

❌ What Doesn't Work:
• Video downloads (encrypted)
• Facebook Stories (protected)
• Live videos (streaming only)
• Most recent content (not cached)

💡 Recommendation:
Use screen recording for Facebook videos instead of trying to download directly.
      ''',
    };
  }
}
