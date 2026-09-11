// services/native_bridge.dart - FIXED VERSION
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBridge {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/native');
  static const MethodChannel _fileChannel =
      MethodChannel('com.yourapp.allsocialdownloader/file_monitor');
  static const MethodChannel _overlayChannel =
      MethodChannel('com.yourapp.allsocialdownloader/overlay');

  // Stream controllers for real-time updates
  static final StreamController<String?> _mediaDetectionController =
      StreamController<String?>.broadcast();
  static final StreamController<List<String>> _viewedMediaController =
      StreamController<List<String>>.broadcast();

  // Public streams
  static Stream<String?> get mediaDetectionStream =>
      _mediaDetectionController.stream;
  static Stream<List<String>> get viewedMediaStream =>
      _viewedMediaController.stream;

  static bool _isInitialized = false;

  /// Initialize all native services and method call handlers
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🔄 Initializing NativeBridge...');

      // Set up method call handlers for receiving data from native side
      _channel.setMethodCallHandler(_handleMethodCall);
      _fileChannel.setMethodCallHandler(_handleFileMethodCall);
      _overlayChannel.setMethodCallHandler(_handleOverlayMethodCall);

      // Try to initialize native side
      try {
        await _channel.invokeMethod('initialize');
        print('✅ Native bridge initialized successfully');
      } catch (e) {
        print(
            '⚠️ Native initialization failed (this is OK if native code not implemented): $e');
      }

      _isInitialized = true;
    } catch (e) {
      print('❌ Error initializing NativeBridge: $e');
      // Don't throw error, allow app to continue without native features
    }
  }

  /// Handle method calls from native Android code
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onMediaDetected':
          final String? mediaPath = call.arguments as String?;
          print('📱 Media detected: $mediaPath');
          _mediaDetectionController.add(mediaPath);
          break;
        case 'onAccessibilityEvent':
          final Map<dynamic, dynamic> eventData = call.arguments;
          await _handleAccessibilityEvent(eventData);
          break;
        case 'onPermissionResult':
          final bool granted = call.arguments as bool;
          print('📱 Permission result: $granted');
          return granted;
        default:
          print('⚠️ Unknown method call: ${call.method}');
          throw MissingPluginException('${call.method} not implemented');
      }
    } catch (e) {
      print('❌ Error handling method call ${call.method}: $e');
    }
  }

  /// Handle file monitoring method calls
  static Future<dynamic> _handleFileMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onNewMediaFiles':
          final List<dynamic> filePaths = call.arguments;
          print('📱 New media files: ${filePaths.length}');
          _viewedMediaController.add(filePaths.cast<String>());
          break;
        case 'onFileDeleted':
          final String deletedPath = call.arguments;
          print('📱 File deleted: $deletedPath');
          break;
        default:
          print('⚠️ Unknown file method call: ${call.method}');
          throw MissingPluginException('${call.method} not implemented');
      }
    } catch (e) {
      print('❌ Error handling file method call ${call.method}: $e');
    }
  }

  /// Handle overlay method calls
  static Future<dynamic> _handleOverlayMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onOverlayTapped':
          final String? mediaPath = call.arguments as String?;
          if (mediaPath != null) {
            await downloadDetectedMedia(mediaPath);
          }
          break;
        default:
          print('⚠️ Unknown overlay method call: ${call.method}');
          throw MissingPluginException('${call.method} not implemented');
      }
    } catch (e) {
      print('❌ Error handling overlay method call ${call.method}: $e');
    }
  }

  /// Handle accessibility events from native side
  static Future<void> _handleAccessibilityEvent(
      Map<dynamic, dynamic> eventData) async {
    try {
      final String packageName = eventData['packageName'] ?? '';
      final String eventType = eventData['eventType'] ?? '';

      if (_isSocialMediaApp(packageName) &&
          eventType == 'TYPE_WINDOW_CONTENT_CHANGED') {
        // Request media detection for current screen
        await detectCurrentMedia();
      }
    } catch (e) {
      print('❌ Error handling accessibility event: $e');
    }
  }

  /// Check if package name belongs to supported social media app
  static bool _isSocialMediaApp(String packageName) {
    const supportedApps = [
      'com.whatsapp',
      'com.whatsapp.w4b',
      'com.instagram.android',
      'com.facebook.katana',
      'com.zhiliaoapp.musically',
      'com.twitter.android',
    ];
    return supportedApps.contains(packageName);
  }

  // ============================================================================
  // PUBLIC API METHODS WITH FALLBACKS
  // ============================================================================

  /// Start the accessibility service
  static Future<bool> startAccessibilityService() async {
    try {
      final bool result =
          await _channel.invokeMethod('startAccessibilityService');
      print('♿ Accessibility service start result: $result');
      return result;
    } catch (e) {
      print('❌ Error starting accessibility service: $e');
      return false;
    }
  }

  /// Check if accessibility service is enabled with fallback
  static Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final bool result =
          await _channel.invokeMethod('isAccessibilityServiceEnabled');
      print('♿ Accessibility service enabled: $result');
      return result;
    } catch (e) {
      print(
          '⚠️ Cannot check accessibility service (native not implemented): $e');
      // Return false but don't crash the app
      return false;
    }
  }

  /// Open accessibility settings
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
      print('♿ Opened accessibility settings');
    } catch (e) {
      print('❌ Error opening accessibility settings: $e');
      // Try alternative method
      try {
        await _channel.invokeMethod('openAppSettings');
      } catch (e2) {
        print('❌ Error opening app settings: $e2');
      }
    }
  }

  /// Start file monitoring services with fallback
  static Future<bool> startFileMonitoring() async {
    try {
      final bool result =
          await _fileChannel.invokeMethod('startFileMonitoring');
      print('📁 File monitoring start result: $result');
      return result;
    } catch (e) {
      print('⚠️ Cannot start file monitoring (native not implemented): $e');
      return false;
    }
  }

  /// Stop file monitoring services
  static Future<void> stopFileMonitoring() async {
    try {
      await _fileChannel.invokeMethod('stopFileMonitoring');
      print('📁 File monitoring stopped');
    } catch (e) {
      print('⚠️ Cannot stop file monitoring: $e');
    }
  }

  /// Get list of media viewed today. Returns an empty list when the optional
  /// native monitor is unavailable; it never fabricates media records.
  static Future<List<String>> getViewedMediaToday() async {
    try {
      final List<dynamic> result =
          await _fileChannel.invokeMethod('getViewedMediaToday');
      print('📱 Viewed media today: ${result.length} files');
      return result.cast<String>();
    } catch (e) {
      print('⚠️ Cannot get viewed media: $e');
      return const <String>[];
    }
  }

  /// Get WhatsApp status files from the optional legacy native bridge.
  static Future<List<String>> getWhatsAppStatuses() async {
    try {
      final List<dynamic> result =
          await _fileChannel.invokeMethod('getWhatsAppStatuses');
      print('💬 WhatsApp statuses: ${result.length} files');
      return result.cast<String>();
    } catch (e) {
      print('⚠️ Cannot get WhatsApp statuses: $e');
      return const <String>[];
    }
  }

  /// Get Instagram cached media from the optional legacy native bridge.
  static Future<List<String>> getInstagramCachedMedia() async {
    try {
      final List<dynamic> result =
          await _fileChannel.invokeMethod('getInstagramCachedMedia');
      print('📷 Instagram media: ${result.length} files');
      return result.cast<String>();
    } catch (e) {
      print('⚠️ Cannot get Instagram media: $e');
      return const <String>[];
    }
  }

  /// Show download overlay
  static Future<bool> showDownloadOverlay() async {
    try {
      final bool result = await _overlayChannel.invokeMethod('showOverlay');
      print('🖼️ Overlay shown: $result');
      return result;
    } catch (e) {
      print('⚠️ Cannot show overlay: $e');
      return false;
    }
  }

  /// Hide download overlay
  static Future<void> hideDownloadOverlay() async {
    try {
      await _overlayChannel.invokeMethod('hideOverlay');
      print('🖼️ Overlay hidden');
    } catch (e) {
      print('⚠️ Cannot hide overlay: $e');
    }
  }

  /// Detect media currently visible on screen
  static Future<String?> detectCurrentMedia() async {
    try {
      final String? result = await _channel.invokeMethod('detectCurrentMedia');
      print('🔍 Current media detected: $result');
      return result;
    } catch (e) {
      print('⚠️ Cannot detect current media: $e');
      return null;
    }
  }

  /// Set after every saveToMediaStore call — the native side's reported
  /// error message on failure (e.g. "Source file not found",
  /// "MediaStore insert failed"), or null after a success. Read this right
  /// after a failed saveToMediaStore call for a real reason instead of a
  /// generic "failed" message.
  static String? lastMediaStoreError;

  /// Save a local file through Android MediaStore and return its public path.
  static Future<String?> saveToMediaStore({
    required String sourcePath,
    required String fileName,
    required String platform,
    required String mimeType,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'saveToMediaStore',
        <String, dynamic>{
          'sourcePath': sourcePath,
          'fileName': fileName,
          'platform': platform,
          'mimeType': mimeType,
        },
      );
      if (result?['success'] == true) {
        lastMediaStoreError = null;
        return result?['path'] as String?;
      }
      lastMediaStoreError =
          result?['error'] as String? ?? 'Unknown native error';
    } catch (e) {
      print('❌ Error saving to MediaStore: $e');
      lastMediaStoreError = e.toString();
    }
    return null;
  }

  static Future<bool> trimVideo({
    required String sourcePath,
    required String outputPath,
    required int startUs,
    required int endUs,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('trimVideo', <String, dynamic>{
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'startUs': startUs,
        'endUs': endUs,
      });
      return result ?? false;
    } catch (e) {
      print('❌ Native trim failed: $e');
      return false;
    }
  }

  static Future<bool> extractFrame({
    required String sourcePath,
    required String outputPath,
    required int positionUs,
    required String format,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('extractFrame', <String, dynamic>{
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'positionUs': positionUs,
        'format': format,
      });
      return result ?? false;
    } catch (e) {
      print('❌ Native frame extraction failed: $e');
      return false;
    }
  }

  /// Rotate a video by writing container-level rotation metadata (0/90/180/270).
  /// No frame is decoded or re-encoded, so this is effectively instant.
  static Future<bool> rotateVideo({
    required String sourcePath,
    required String outputPath,
    required int degrees,
  }) async {
    try {
      final result =
          await _channel.invokeMethod<bool>('rotateVideo', <String, dynamic>{
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'degrees': degrees,
      });
      return result ?? false;
    } catch (e) {
      print('❌ Native rotate failed: $e');
      return false;
    }
  }

  /// Query durable MediaNest files indexed by Android MediaStore.
  static Future<List<Map<String, dynamic>>> queryMediaNestMedia() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'queryMediaNestMedia',
      );
      return (result ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (e) {
      print('❌ Error querying MediaNest MediaStore: $e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// Open Android's system document picker for one video and return a local
  /// cache path without requesting broad storage access.
  static Future<String?> pickVideoFile() async {
    try {
      return await _channel.invokeMethod<String>('pickMediaFile');
    } catch (e) {
      print('❌ Error picking video file: $e');
      return null;
    }
  }

  /// Download detected media file with fallback
  static Future<bool> downloadDetectedMedia(String sourcePath) async {
    try {
      final Map<String, dynamic> params = {
        'sourcePath': sourcePath,
        'destinationFolder': '/storage/emulated/0/Download/MediaNest',
      };
      final bool result =
          await _fileChannel.invokeMethod('downloadMedia', params);
      print('⬇️ Download result for $sourcePath: $result');
      return result;
    } catch (e) {
      print('❌ Error downloading media: $e');
      return false;
    }
  }

  /// Request system overlay permission with better detection
  static Future<bool> requestOverlayPermission() async {
    try {
      final bool result =
          await _channel.invokeMethod('requestOverlayPermission');
      print('🖼️ Overlay permission request result: $result');
      return result;
    } catch (e) {
      print('❌ Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Check if overlay permission is granted with better detection
  static Future<bool> hasOverlayPermission() async {
    try {
      final bool result = await _channel.invokeMethod('hasOverlayPermission');
      print('🖼️ Has overlay permission: $result');
      return result;
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Error checking overlay permission: $e');
      }
      return false;
    }
  }

  /// Get app cache directory for a specific social media app
  static Future<String?> getAppCacheDirectory(String packageName) async {
    try {
      final String? result =
          await _fileChannel.invokeMethod('getAppCacheDirectory', packageName);
      return result;
    } catch (e) {
      print('❌ Error getting app cache directory: $e');
      return null;
    }
  }

  /// Scan media file to make it visible in gallery
  static Future<void> scanMediaFile(String filePath) async {
    try {
      await _fileChannel.invokeMethod('scanMediaFile', filePath);
    } catch (e) {
      print('❌ Error scanning media file: $e');
    }
  }

  /// Get device external storage path
  static Future<String?> getExternalStoragePath() async {
    try {
      final String? result =
          await _fileChannel.invokeMethod('getExternalStoragePath');
      return result;
    } catch (e) {
      print('❌ Error getting external storage path: $e');
      return '/storage/emulated/0';
    }
  }

  /// Check if app has required permissions
  static Future<Map<String, bool>> checkAllPermissions() async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('checkAllPermissions');
      return result.cast<String, bool>();
    } catch (e) {
      print('❌ Error checking permissions: $e');
      return {};
    }
  }

  /// Request all required permissions
  static Future<bool> requestAllPermissions() async {
    try {
      final bool result = await _channel.invokeMethod('requestAllPermissions');
      return result;
    } catch (e) {
      print('❌ Error requesting permissions: $e');
      return false;
    }
  }

  /// Dispose of all controllers and cleanup
  static void dispose() {
    _mediaDetectionController.close();
    _viewedMediaController.close();
    _isInitialized = false;
  }
}
