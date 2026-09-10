// services/file_monitor_service.dart - FIXED for Real File Access
// ignore_for_file: avoid_print, unused_import

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_file.dart';
import '../utils/native_file_manager.dart';
import 'native_bridge.dart';

class FileMonitorService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/file_monitor');

  // Stream controllers for real-time file updates
  final StreamController<List<MediaFile>> _mediaController =
      StreamController<List<MediaFile>>.broadcast();
  final StreamController<MediaFile> _newMediaController =
      StreamController<MediaFile>.broadcast();

  // Public streams
  Stream<List<MediaFile>> get mediaStream => _mediaController.stream;
  Stream<MediaFile> get newMediaStream => _newMediaController.stream;

  // Internal state
  bool _isMonitoring = false;
  Timer? _refreshTimer;
  List<MediaFile> _currentMediaFiles = [];

  // REAL WhatsApp paths (prioritized by accessibility)
  static const List<String> whatsappPaths = [
    '/storage/emulated/0/WhatsApp/Media/.Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    '/sdcard/WhatsApp/Media/.Statuses',
    '/sdcard/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
  ];

  static const List<String> whatsappBusinessPaths = [
    '/storage/emulated/0/WhatsApp Business/Media/.Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
    '/sdcard/WhatsApp Business/Media/.Statuses',
    '/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
  ];

  // Real Instagram cache paths
  static const List<String> instagramCachePaths = [
    '/storage/emulated/0/Android/data/com.instagram.android/cache',
    '/storage/emulated/0/Android/data/com.instagram.android/files',
    '/storage/emulated/0/Android/data/com.instagram.android/cache/tmp',
    '/sdcard/Android/data/com.instagram.android/cache',
  ];

  // Real TikTok cache paths
  static const List<String> tiktokCachePaths = [
    '/storage/emulated/0/Android/data/com.zhiliaoapp.musically/cache',
    '/storage/emulated/0/Android/data/com.zhiliaoapp.musically/files',
    '/sdcard/Android/data/com.zhiliaoapp.musically/cache',
  ];

  /// Initialize the file monitoring service
  Future<void> initialize() async {
    await NativeBridge.initialize();

    // Set up method call handler for native file updates
    _channel.setMethodCallHandler(_handleNativeMethodCall);

    // Listen to native bridge media stream
    NativeBridge.viewedMediaStream.listen((filePaths) {
      _updateMediaFromPaths(filePaths);
    });

    print('✅ FileMonitorService initialized');
  }

  /// Handle method calls from native Android code
  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onFileCreated':
        final String filePath = call.arguments as String;
        await _handleNewFile(filePath);
        break;
      case 'onFileDeleted':
        final String filePath = call.arguments as String;
        await _handleDeletedFile(filePath);
        break;
      case 'onFileModified':
        final String filePath = call.arguments as String;
        await _handleModifiedFile(filePath);
        break;
      case 'onDirectoryScanned':
        final List<dynamic> filePaths = call.arguments;
        await _handleDirectoryScan(filePaths.cast<String>());
        break;
      default:
        throw MissingPluginException('Method ${call.method} not implemented');
    }
  }

  /// Start monitoring all social media directories
  Future<bool> startMonitoring() async {
    if (_isMonitoring) return true;

    try {
      print('🔄 Starting file monitoring with REAL file access...');

      // Start native file monitoring
      await NativeBridge.startFileMonitoring();

      // Initial scan of all directories with REAL file access
      await _performRealInitialScan();

      // Start periodic refresh timer every 30 seconds
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        _refreshMediaFiles();
      });

      _isMonitoring = true;
      print('✅ File monitoring started successfully');
      return true;
    } catch (e) {
      print('❌ Error starting file monitoring: $e');
      return false;
    }
  }

  /// Stop file monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      await NativeBridge.stopFileMonitoring();
      _refreshTimer?.cancel();
      _isMonitoring = false;
      print('⏹️ File monitoring stopped');
    } catch (e) {
      print('❌ Error stopping file monitoring: $e');
    }
  }

  /// Perform REAL initial scan of all media directories
  Future<void> _performRealInitialScan() async {
    final List<MediaFile> allMedia = [];

    print('🔍 Starting REAL file scan...');

    // Scan WhatsApp statuses with REAL file access
    final whatsappMedia = await _scanWhatsAppStatusesReal();
    allMedia.addAll(whatsappMedia);
    print('📱 WhatsApp scan found: ${whatsappMedia.length} files');

    // Scan Instagram cache with REAL file access
    final instagramMedia = await _scanInstagramCacheReal();
    allMedia.addAll(instagramMedia);
    print('📸 Instagram scan found: ${instagramMedia.length} files');

    // Scan TikTok cache with REAL file access
    final tiktokMedia = await _scanTikTokCacheReal();
    allMedia.addAll(tiktokMedia);
    print('🎵 TikTok scan found: ${tiktokMedia.length} files');

    // Scan other social media apps
    final otherMedia = await _scanOtherSocialMediaReal();
    allMedia.addAll(otherMedia);
    print('🌐 Other platforms scan found: ${otherMedia.length} files');

    // Update current media list
    _currentMediaFiles = allMedia;
    _mediaController.add(_currentMediaFiles);

    print('✅ REAL scan completed: ${allMedia.length} total media files found');
  }

  /// Scan WhatsApp status directories for REAL files
  Future<List<MediaFile>> _scanWhatsAppStatusesReal() async {
    final List<MediaFile> mediaFiles = [];

    // Check regular WhatsApp
    for (final path in whatsappPaths) {
      try {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          print('📁 Found WhatsApp directory: $path');
          final files = await _scanDirectoryReal(path, 'whatsapp');
          mediaFiles.addAll(files);
          if (files.isNotEmpty) {
            print('✅ WhatsApp path $path: ${files.length} files');
            break; // Use first working path
          }
        } else {
          print('📁 WhatsApp directory not found: $path');
        }
      } catch (e) {
        print('❌ Error accessing WhatsApp path $path: $e');
      }
    }

    // Check WhatsApp Business
    for (final path in whatsappBusinessPaths) {
      try {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          print('📁 Found WhatsApp Business directory: $path');
          final files = await _scanDirectoryReal(path, 'whatsapp_business');
          mediaFiles.addAll(files);
          if (files.isNotEmpty) {
            print('✅ WhatsApp Business path $path: ${files.length} files');
            break; // Use first working path
          }
        }
      } catch (e) {
        print('❌ Error accessing WhatsApp Business path $path: $e');
      }
    }

    return mediaFiles;
  }

  /// Scan Instagram cache directories for REAL files
  Future<List<MediaFile>> _scanInstagramCacheReal() async {
    final List<MediaFile> mediaFiles = [];

    for (final path in instagramCachePaths) {
      try {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          print('📁 Found Instagram directory: $path');
          final files = await _scanDirectoryReal(path, 'instagram');
          mediaFiles.addAll(files);
          print('📸 Instagram path $path: ${files.length} files');
        }
      } catch (e) {
        print('❌ Error accessing Instagram path $path: $e');
      }
    }

    return mediaFiles;
  }

  /// Scan TikTok cache directories for REAL files
  Future<List<MediaFile>> _scanTikTokCacheReal() async {
    final List<MediaFile> mediaFiles = [];

    for (final path in tiktokCachePaths) {
      try {
        final Directory dir = Directory(path);
        if (await dir.exists()) {
          print('📁 Found TikTok directory: $path');
          final files = await _scanDirectoryReal(path, 'tiktok');
          mediaFiles.addAll(files);
          print('🎵 TikTok path $path: ${files.length} files');
        }
      } catch (e) {
        print('❌ Error accessing TikTok path $path: $e');
      }
    }

    return mediaFiles;
  }

  /// Scan other social media app directories with REAL file access
  Future<List<MediaFile>> _scanOtherSocialMediaReal() async {
    final List<MediaFile> mediaFiles = [];

    // Facebook cache
    final facebookPaths = [
      '/storage/emulated/0/Android/data/com.facebook.katana/cache',
      '/sdcard/Android/data/com.facebook.katana/cache',
    ];

    for (final path in facebookPaths) {
      try {
        final files = await _scanDirectoryReal(path, 'facebook');
        mediaFiles.addAll(files);
        if (files.isNotEmpty) {
          print('📘 Facebook path $path: ${files.length} files');
        }
      } catch (e) {
        print('❌ Error accessing Facebook path $path: $e');
      }
    }

    // Twitter cache
    final twitterPaths = [
      '/storage/emulated/0/Android/data/com.twitter.android/cache',
      '/sdcard/Android/data/com.twitter.android/cache',
    ];

    for (final path in twitterPaths) {
      try {
        final files = await _scanDirectoryReal(path, 'twitter');
        mediaFiles.addAll(files);
        if (files.isNotEmpty) {
          print('🐦 Twitter path $path: ${files.length} files');
        }
      } catch (e) {
        print('❌ Error accessing Twitter path $path: $e');
      }
    }

    return mediaFiles;
  }

  /// Scan a specific directory for REAL media files
  Future<List<MediaFile>> _scanDirectoryReal(
      String directoryPath, String sourceApp) async {
    final List<MediaFile> mediaFiles = [];

    try {
      final Directory directory = Directory(directoryPath);

      if (!await directory.exists()) {
        print('📁 Directory does not exist: $directoryPath');
        return mediaFiles;
      }

      // Try to access the directory
      List<FileSystemEntity> entities;
      try {
        entities = directory.listSync(recursive: true);
        print(
            '📁 Successfully accessed directory: $directoryPath (${entities.length} entities)');
      } catch (e) {
        print('❌ Permission denied for directory: $directoryPath - $e');
        return mediaFiles;
      }

      int validFiles = 0;
      for (final entity in entities) {
        if (entity is File) {
          final String filePath = entity.path;

          // Check if it's a supported media file
          if (_isMediaFile(filePath)) {
            try {
              final FileStat stat = entity.statSync();

              // Skip very small files (likely thumbnails)
              if (stat.size < 10000) continue;

              final MediaFile mediaFile = MediaFile(
                id: _generateFileId(filePath),
                path: filePath,
                fileName: _getFileName(filePath),
                fileSize: stat.size,
                isVideo: _isVideoFile(filePath),
                sourceApp: sourceApp,
                createdAt: stat.modified,
                viewedAt: stat.accessed,
                isDownloaded: false,
              );

              mediaFiles.add(mediaFile);
              validFiles++;
            } catch (e) {
              print('❌ Error processing file $filePath: $e');
            }
          }
        }
      }

      print('✅ Found $validFiles valid media files in $directoryPath');
    } catch (e) {
      print('❌ Error scanning directory $directoryPath: $e');
    }

    return mediaFiles;
  }

  /// Check if file is a supported media file
  bool _isMediaFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const supportedExtensions = [
      'jpg', 'jpeg', 'png', 'gif', 'webp', // Images
      'mp4', 'mov', 'avi', 'mkv', 'webm', // Videos
    ];
    return supportedExtensions.contains(extension);
  }

  /// Check if file is a video file
  bool _isVideoFile(String filePath) {
    final String extension = filePath.toLowerCase().split('.').last;
    const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm'];
    return videoExtensions.contains(extension);
  }

  /// Generate unique ID for file
  String _generateFileId(String filePath) {
    return filePath.hashCode.toString();
  }

  /// Get file name from path
  String _getFileName(String filePath) {
    return filePath.split('/').last;
  }

  /// Handle new file detected
  Future<void> _handleNewFile(String filePath) async {
    if (_isMediaFile(filePath)) {
      try {
        final File file = File(filePath);
        if (!await file.exists()) return;

        final FileStat stat = file.statSync();

        final MediaFile mediaFile = MediaFile(
          id: _generateFileId(filePath),
          path: filePath,
          fileName: _getFileName(filePath),
          fileSize: stat.size,
          isVideo: _isVideoFile(filePath),
          sourceApp: _detectSourceApp(filePath),
          createdAt: stat.modified,
          viewedAt: DateTime.now(),
          isDownloaded: false,
        );

        _currentMediaFiles.add(mediaFile);
        _mediaController.add(_currentMediaFiles);
        _newMediaController.add(mediaFile);

        print('📱 New media file detected: ${mediaFile.fileName}');
      } catch (e) {
        print('❌ Error handling new file $filePath: $e');
      }
    }
  }

  /// Handle deleted file
  Future<void> _handleDeletedFile(String filePath) async {
    _currentMediaFiles.removeWhere((file) => file.path == filePath);
    _mediaController.add(_currentMediaFiles);
    print('🗑️ Media file deleted: $filePath');
  }

  /// Handle modified file
  Future<void> _handleModifiedFile(String filePath) async {
    final index =
        _currentMediaFiles.indexWhere((file) => file.path == filePath);
    if (index != -1) {
      try {
        final File file = File(filePath);
        final FileStat stat = file.statSync();

        _currentMediaFiles[index] = _currentMediaFiles[index].copyWith(
          fileSize: stat.size,
          viewedAt: DateTime.now(),
        );

        _mediaController.add(_currentMediaFiles);
        print('📝 Media file modified: $filePath');
      } catch (e) {
        print('❌ Error handling modified file $filePath: $e');
      }
    }
  }

  /// Handle directory scan results from native
  Future<void> _handleDirectoryScan(List<String> filePaths) async {
    final List<MediaFile> newMediaFiles = [];

    for (final filePath in filePaths) {
      if (_isMediaFile(filePath)) {
        try {
          final File file = File(filePath);
          if (!await file.exists()) continue;

          final FileStat stat = file.statSync();

          final MediaFile mediaFile = MediaFile(
            id: _generateFileId(filePath),
            path: filePath,
            fileName: _getFileName(filePath),
            fileSize: stat.size,
            isVideo: _isVideoFile(filePath),
            sourceApp: _detectSourceApp(filePath),
            createdAt: stat.modified,
            viewedAt: stat.accessed,
            isDownloaded: false,
          );

          newMediaFiles.add(mediaFile);
        } catch (e) {
          print('❌ Error processing scanned file $filePath: $e');
        }
      }
    }

    _currentMediaFiles = newMediaFiles;
    _mediaController.add(_currentMediaFiles);
    print('🔄 Directory scan completed: ${newMediaFiles.length} files found');
  }

  /// Detect source app from file path
  String _detectSourceApp(String filePath) {
    if (filePath.contains('whatsapp')) {
      return filePath.contains('w4b') ? 'whatsapp_business' : 'whatsapp';
    } else if (filePath.contains('instagram')) {
      return 'instagram';
    } else if (filePath.contains('musically')) {
      return 'tiktok';
    } else if (filePath.contains('facebook')) {
      return 'facebook';
    } else if (filePath.contains('twitter')) {
      return 'twitter';
    }
    return 'unknown';
  }

  /// Update media files from file paths
  void _updateMediaFromPaths(List<String> filePaths) {
    final List<MediaFile> updatedMedia = [];

    for (final filePath in filePaths) {
      if (_isMediaFile(filePath)) {
        try {
          final File file = File(filePath);
          if (file.existsSync()) {
            final FileStat stat = file.statSync();

            final MediaFile mediaFile = MediaFile(
              id: _generateFileId(filePath),
              path: filePath,
              fileName: _getFileName(filePath),
              fileSize: stat.size,
              isVideo: _isVideoFile(filePath),
              sourceApp: _detectSourceApp(filePath),
              createdAt: stat.modified,
              viewedAt: DateTime.now(),
              isDownloaded: false,
            );

            updatedMedia.add(mediaFile);
          }
        } catch (e) {
          print('❌ Error updating media from path $filePath: $e');
        }
      }
    }

    if (updatedMedia.isNotEmpty) {
      _currentMediaFiles = updatedMedia;
      _mediaController.add(_currentMediaFiles);
      print('🔄 Updated media from paths: ${updatedMedia.length} files');
    }
  }

  /// Refresh media files periodically
  Future<void> _refreshMediaFiles() async {
    if (!_isMonitoring) return;

    try {
      print('🔄 Refreshing media files...');
      await _performRealInitialScan();
    } catch (e) {
      print('❌ Error refreshing media files: $e');
    }
  }

  /// Get media files viewed in the last 24 hours
  List<MediaFile> getViewedToday() {
    final DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
    return _currentMediaFiles
        .where((file) => file.viewedAt.isAfter(yesterday))
        .toList()
      ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
  }

  /// Get WhatsApp status files only
  List<MediaFile> getWhatsAppStatuses() {
    return _currentMediaFiles
        .where((file) => file.sourceApp.contains('whatsapp'))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Get files from specific social media app
  List<MediaFile> getMediaFromApp(String appName) {
    return _currentMediaFiles
        .where((file) => file.sourceApp == appName)
        .toList()
      ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
  }

  /// Download media file to permanent location
  Future<bool> downloadMedia(MediaFile mediaFile) async {
    try {
      final bool result =
          await NativeBridge.downloadDetectedMedia(mediaFile.path);

      if (result) {
        // Update the media file as downloaded
        final index =
            _currentMediaFiles.indexWhere((file) => file.id == mediaFile.id);
        if (index != -1) {
          _currentMediaFiles[index] = _currentMediaFiles[index].copyWith(
            isDownloaded: true,
          );
          _mediaController.add(_currentMediaFiles);
        }
        print('✅ Media downloaded successfully: ${mediaFile.fileName}');
      }

      return result;
    } catch (e) {
      print('❌ Error downloading media: $e');
      return false;
    }
  }

  /// Force refresh all directories NOW
  Future<void> forceRefreshAll() async {
    print('🔄 Force refreshing all directories...');
    await _performRealInitialScan();
  }

  /// Dispose of all resources
  void dispose() {
    stopMonitoring();
    _mediaController.close();
    _newMediaController.close();
    _refreshTimer?.cancel();
  }
}
