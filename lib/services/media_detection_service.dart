// services/enhanced_media_detection_service.dart - FIXED AND ENHANCED
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/services.dart';
import 'clipboard_monitor.dart';
import 'floating_overlay_manager.dart';
import 'video_downloader_service.dart';
import 'native_bridge.dart';

class EnhancedMediaDetectionService {
  static const MethodChannel _mediaDetectionChannel =
      MethodChannel('com.yourapp.allsocialdownloader/media_detection');
  static const MethodChannel _floatingChannel =
      MethodChannel('com.yourapp.allsocialdownloader/floating_overlay');
  static const MethodChannel _clipboardChannel =
      MethodChannel('com.yourapp.allsocialdownloader/clipboard');
  static const MethodChannel _permissionsChannel =
      MethodChannel('com.yourapp.allsocialdownloader/permissions');

  static EnhancedMediaDetectionService? _instance;
  static EnhancedMediaDetectionService get instance =>
      _instance ??= EnhancedMediaDetectionService._();

  EnhancedMediaDetectionService._();

  bool _isActive = false;
  bool _hasNotificationAccess = false;
  String? _lastDetectedMedia;
  Timer? _statusCheckTimer;
  Map<String, dynamic>? _currentMediaContext;

  final AdvancedClipboardMonitor _clipboardMonitor =
      AdvancedClipboardMonitor.instance;
  final FloatingOverlayManager _overlayManager =
      FloatingOverlayManager.instance;
  final VideoDownloaderService _downloaderService =
      VideoDownloaderService.instance;

  /// Initialize the enhanced media detection service
  Future<void> initialize() async {
    try {
      print('🎬 Initializing Enhanced MediaDetectionService...');

      // Set up method call handlers for all channels
      _mediaDetectionChannel.setMethodCallHandler(_handleMediaDetectionCall);
      _floatingChannel.setMethodCallHandler(_handleFloatingOverlayCall);
      _clipboardChannel.setMethodCallHandler(_handleClipboardCall);

      // Initialize native bridge
      await NativeBridge.initialize();

      // Check initial status
      await _checkServiceStatus();

      // Initialize sub-services
      await _clipboardMonitor.initialize();
      await _overlayManager.initialize();
      await _downloaderService.initialize();

      // Set up overlay callbacks
      _overlayManager.setCallbacks(
        onDownloadRequested: _handleDownloadRequest,
        onOverlayDismissed: _handleOverlayDismissed,
      );

      print('✅ Enhanced MediaDetectionService initialized');
    } catch (e) {
      print('❌ Error initializing Enhanced MediaDetectionService: $e');
    }
  }

  /// Start enhanced media detection
  Future<bool> startDetection() async {
    try {
      print('🔄 Starting enhanced media detection...');

      // Check notification access first
      if (!await hasNotificationAccess()) {
        print('⚠️ No notification access permission');
        return false;
      }

      // Start the native media detection service
      final bool success =
          await _mediaDetectionChannel.invokeMethod('startMediaDetection');

      if (success) {
        _isActive = true;

        // Start clipboard monitoring for URL detection
        await _clipboardMonitor.startMonitoring();

        // Start periodic status checks
        _startStatusChecking();

        print('✅ Enhanced media detection started successfully');
      } else {
        print('❌ Failed to start enhanced media detection');
      }

      return success;
    } catch (e) {
      print('❌ Error starting enhanced media detection: $e');
      return false;
    }
  }

  /// Stop media detection
  Future<void> stopDetection() async {
    try {
      print('⏹️ Stopping enhanced media detection...');

      await _mediaDetectionChannel.invokeMethod('stopMediaDetection');
      _isActive = false;

      // Stop sub-services
      await _clipboardMonitor.stopMonitoring();
      await _overlayManager.hideOverlay();

      // Stop status checking
      _statusCheckTimer?.cancel();

      print('✅ Enhanced media detection stopped');
    } catch (e) {
      print('❌ Error stopping enhanced media detection: $e');
    }
  }

  /// Handle method calls from native media detection service
  Future<dynamic> _handleMediaDetectionCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onVideoDetected':
          return await _handleVideoDetected(call.arguments);
        case 'onVideoFocusedAppDetected':
          return await _handleVideoFocusedAppDetected(call.arguments);
        case 'onMediaPlaying':
          return await _handleMediaPlaying(call.arguments);
        case 'onMediaStopped':
          return await _handleMediaStopped(call.arguments);
        case 'onServiceConnected':
          return await _handleServiceConnected(call.arguments);
        case 'onServiceDisconnected':
          return await _handleServiceDisconnected(call.arguments);
        case 'onListenerConnected':
          return await _handleListenerConnected(call.arguments);
        case 'onListenerDisconnected':
          return await _handleListenerDisconnected(call.arguments);
        default:
          print('⚠️ Unknown media detection method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling media detection call ${call.method}: $e');
      return false;
    }
  }

  /// Handle floating overlay method calls
  Future<dynamic> _handleFloatingOverlayCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onDownloadRequested':
          return await _handleDownloadRequest(call.arguments);
        case 'onOverlayDismissed':
          return await _handleOverlayDismissed();
        case 'onOverlayError':
          return await _handleOverlayError(call.arguments);
        default:
          print('⚠️ Unknown floating overlay method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling floating overlay call ${call.method}: $e');
      return false;
    }
  }

  /// Handle clipboard method calls - FIXED METHOD
  Future<dynamic> _handleClipboardCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onClipboardChanged':
          final String content = call.arguments['content'] ?? '';
          final int timestamp = call.arguments['timestamp'] ?? 0;
          return await _handleClipboardChanged(content, timestamp);
        case 'onVideoUrlDetected':
          final Map<String, dynamic> urlInfo =
              Map<String, dynamic>.from(call.arguments);
          return await _handleVideoUrlDetected(urlInfo);
        case 'onClipboardCleared':
          return await _handleClipboardCleared();
        default:
          print('⚠️ Unknown clipboard method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling clipboard call ${call.method}: $e');
      return false;
    }
  }

  /// Handle video detected from native service
  Future<bool> _handleVideoDetected(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);

      print('🎬 Video detected:');
      print('   📱 App: ${mediaInfo['appName']}');
      print('   📋 Title: ${mediaInfo['title']}');
      print('   🔖 Platform: ${mediaInfo['platform']}');
      print('   🎯 Priority: ${mediaInfo['downloadPriority']}');

      // Store current media context
      _currentMediaContext = mediaInfo;
      _lastDetectedMedia = mediaInfo['title'] ?? '';

      // Set clipboard context for better URL detection
      _clipboardMonitor.setMediaContext(mediaInfo);

      // Show floating download prompt immediately
      await _overlayManager.showDownloadPrompt(mediaInfo);

      return true;
    } catch (e) {
      print('❌ Error handling video detected: $e');
      return false;
    }
  }

  /// Handle video detected from high-priority apps (TikTok, Instagram, etc.)
  Future<bool> _handleVideoFocusedAppDetected(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);
      print('🎯 High-priority video detected: ${mediaInfo['appName']}');

      // Same as regular detection but with higher priority
      _currentMediaContext = mediaInfo;
      _clipboardMonitor.setMediaContext(mediaInfo);

      // Show overlay with immediate attention
      await _overlayManager.showDownloadPrompt(mediaInfo);

      return true;
    } catch (e) {
      print('❌ Error handling video focused app detected: $e');
      return false;
    }
  }

  /// Handle media playing detected
  Future<bool> _handleMediaPlaying(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);
      print('▶️ Media playing: ${mediaInfo['appName']}');

      // Update current context
      _currentMediaContext = mediaInfo;
      _clipboardMonitor.setMediaContext(mediaInfo);

      // Show or update floating prompt
      await _overlayManager.showDownloadPrompt(mediaInfo);

      return true;
    } catch (e) {
      print('❌ Error handling media playing: $e');
      return false;
    }
  }

  /// Handle media stopped
  Future<bool> _handleMediaStopped(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);
      print('🔇 Media stopped: ${mediaInfo['appName']}');

      // Clear context
      _currentMediaContext = null;
      _clipboardMonitor.clearMediaContext();

      // Hide overlay after a delay to allow user to click download
      Timer(const Duration(seconds: 5), () {
        _overlayManager.hideOverlay();
      });

      return true;
    } catch (e) {
      print('❌ Error handling media stopped: $e');
      return false;
    }
  }

  /// Handle clipboard content changed
  Future<bool> _handleClipboardChanged(String content, int timestamp) async {
    try {
      print('📋 Clipboard changed: ${content.length} characters');

      // Let the clipboard monitor handle URL detection
      return true;
    } catch (e) {
      print('❌ Error handling clipboard changed: $e');
      return false;
    }
  }

  /// Handle video URL detected in clipboard - FIXED METHOD
  Future<bool> _handleVideoUrlDetected(Map<String, dynamic> urlInfo) async {
    try {
      final String url = urlInfo['url'] ?? '';
      final String platform = urlInfo['platform'] ?? '';
      final double confidence = urlInfo['confidence'] ?? 0.0;
      final bool isHighConfidence = urlInfo['isHighConfidence'] ?? false;

      print('🔗 Video URL detected:');
      print('   🌐 URL detected (value redacted)');
      print('   📱 Platform: $platform');
      print('   🎯 Confidence: $confidence');
      print('   ⚡ High Confidence: $isHighConfidence');

      // If we have an active overlay, update it with URL found status
      if (_overlayManager.isActive) {
        await _overlayManager.updateMediaInfo({
          ...(_currentMediaContext ?? {}),
          'detectedUrl': url,
          'urlPlatform': platform,
          'urlConfidence': confidence,
        });

        // Auto-start download for high confidence matches
        if (isHighConfidence && confidence > 0.8) {
          print('🚀 Auto-starting download for high confidence URL');
          Timer(const Duration(seconds: 1), () {
            _handleDownloadRequest({'url': url});
          });
        }
      }

      return true;
    } catch (e) {
      print('❌ Error handling video URL detected: $e');
      return false;
    }
  }

  /// Handle clipboard cleared
  Future<bool> _handleClipboardCleared() async {
    try {
      print('🧹 Clipboard cleared');
      return true;
    } catch (e) {
      print('❌ Error handling clipboard cleared: $e');
      return false;
    }
  }

  /// Handle download request from overlay
  Future<void> _handleDownloadRequest(dynamic arguments) async {
    try {
      print('⬇️ Download request received');

      // Get URL from arguments or clipboard
      String? downloadUrl;

      if (arguments is Map && arguments.containsKey('url')) {
        downloadUrl = arguments['url'] as String?;
      } else {
        // Try to get the latest URL from clipboard monitor
        downloadUrl = _clipboardMonitor.getLatestVideoUrl(timeoutSeconds: 30);
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        print('❌ No download URL available');
        await _overlayManager
            .showDownloadError('No video URL found. Copy a video link first.');
        return;
      }

      if (_currentMediaContext == null) {
        print('❌ No media context available');
        await _overlayManager
            .showDownloadError('No media context. Please try again.');
        return;
      }

      print('⬇️ Starting detected media download');

      // Start download using the video downloader service
      final success = await _downloaderService.downloadFromUrl(
        downloadUrl,
        _currentMediaContext!,
        onProgress: (progress) {
          // _overlayManager.updateDownloadProgress(progress);
        },
        onStatusUpdate: (status) {
          print('📊 Download status: $status');
        },
      );

      if (success) {
        print('✅ Download completed successfully');
        await _overlayManager.showDownloadSuccess();
      } else {
        print('❌ Download failed');
        await _overlayManager.showDownloadError('Download failed');
      }
    } catch (e) {
      print('❌ Error handling download request: $e');
      await _overlayManager.showDownloadError('Download error: $e');
    }
  }

  /// Handle overlay dismissed
  Future<void> _handleOverlayDismissed() async {
    try {
      print('❌ Overlay dismissed by user');
      _currentMediaContext = null;
      _clipboardMonitor.clearMediaContext();
    } catch (e) {
      print('❌ Error handling overlay dismissed: $e');
    }
  }

  /// Handle overlay error
  Future<bool> _handleOverlayError(dynamic arguments) async {
    try {
      final String error = arguments['error'] ?? 'Unknown error';
      print('❌ Overlay error: $error');
      return true;
    } catch (e) {
      print('❌ Error handling overlay error: $e');
      return false;
    }
  }

  /// Handle service connected
  Future<bool> _handleServiceConnected(dynamic arguments) async {
    try {
      print('✅ Native media detection service connected');
      _isActive = true;
      return true;
    } catch (e) {
      print('❌ Error handling service connected: $e');
      return false;
    }
  }

  /// Handle service disconnected
  Future<bool> _handleServiceDisconnected(dynamic arguments) async {
    try {
      print('⚠️ Native media detection service disconnected');
      _isActive = false;

      // Try to restart after a delay
      Timer(const Duration(seconds: 5), () {
        if (!_isActive) {
          print('🔄 Attempting to restart media detection...');
          startDetection();
        }
      });

      return true;
    } catch (e) {
      print('❌ Error handling service disconnected: $e');
      return false;
    }
  }

  /// Handle notification listener connected
  Future<bool> _handleListenerConnected(dynamic arguments) async {
    try {
      print('🔗 Notification listener connected');
      _hasNotificationAccess = true;
      return true;
    } catch (e) {
      print('❌ Error handling listener connected: $e');
      return false;
    }
  }

  /// Handle notification listener disconnected
  Future<bool> _handleListenerDisconnected(dynamic arguments) async {
    try {
      print('🔌 Notification listener disconnected');
      _hasNotificationAccess = false;

      // Try to restart if possible
      Timer(const Duration(seconds: 5), () {
        if (_isActive) {
          print('🔄 Attempting to restart notification listener...');
          startDetection();
        }
      });

      return true;
    } catch (e) {
      print('❌ Error handling listener disconnected: $e');
      return false;
    }
  }

  /// Check if service is active
  bool get isActive => _isActive;

  /// Check if has notification access
  Future<bool> hasNotificationAccess() async {
    try {
      _hasNotificationAccess =
          await _mediaDetectionChannel.invokeMethod('hasNotificationAccess');
      return _hasNotificationAccess;
    } catch (e) {
      print('❌ Error checking notification access: $e');
      return false;
    }
  }

  /// Request notification access
  Future<void> requestNotificationAccess() async {
    try {
      await _permissionsChannel.invokeMethod('requestNotificationAccess');
    } catch (e) {
      print('❌ Error requesting notification access: $e');
    }
  }

  /// Check current service status
  Future<void> _checkServiceStatus() async {
    try {
      final bool isDetectionActive =
          await _mediaDetectionChannel.invokeMethod('isMediaDetectionActive');
      final bool hasAccess = await hasNotificationAccess();

      if (_isActive != isDetectionActive) {
        _isActive = isDetectionActive;
        print('📊 Media detection status updated: $_isActive');
      }

      if (_hasNotificationAccess != hasAccess) {
        _hasNotificationAccess = hasAccess;
        print('📊 Notification access status updated: $_hasNotificationAccess');
      }
    } catch (e) {
      print('❌ Error checking service status: $e');
    }
  }

  /// Start periodic status checking
  void _startStatusChecking() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _checkServiceStatus();
    });
  }

  /// Get current media detection statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isActive': _isActive,
      'hasNotificationAccess': _hasNotificationAccess,
      'lastDetectedMedia': _lastDetectedMedia,
      'hasCurrentContext': _currentMediaContext != null,
      'currentApp': _currentMediaContext?['appName'],
      'currentPlatform': _currentMediaContext?['platform'],
      'clipboardMonitorActive': _clipboardMonitor.isMonitoring,
      'overlayManagerActive': _overlayManager.isActive,
      'downloaderServiceActive': true,
    };
  }

  /// Test the enhanced media detection system
  Future<void> testSystem() async {
    try {
      print('🧪 Testing enhanced media detection system...');

      // Test 1: Check permissions
      final hasAccess = await hasNotificationAccess();
      print('📋 Notification access: ${hasAccess ? '✅' : '❌'}');

      // Test 2: Check if service is active
      final isActive =
          await _mediaDetectionChannel.invokeMethod('isMediaDetectionActive');
      print('📋 Detection active: ${isActive ? '✅' : '❌'}');

      // Test 3: Get active notifications
      final activeNotifications = await _mediaDetectionChannel
          .invokeMethod('getActiveMediaNotifications');
      print('📋 Active notifications: ${activeNotifications.length}');

      // Test 4: Test clipboard monitoring
      await _clipboardMonitor.testClipboardDetection();

      // Test 5: Test overlay
      await _overlayManager.testOverlay();

      print('🧪 Enhanced system test completed');
    } catch (e) {
      print('❌ Error testing enhanced system: $e');
    }
  }

  /// Manually trigger download prompt for testing
  Future<void> triggerTestPrompt() async {
    final testMediaInfo = {
      'appName': 'TikTok',
      'packageName': 'com.zhiliaoapp.musically',
      'platform': 'tiktok',
      'title': 'Test Video Detection',
      'text': 'Testing enhanced media detection system',
      'color': '#000000',
      'isVideoApp': true,
      'downloadPriority': 'HIGH',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _handleVideoDetected(testMediaInfo);
  }

  /// Get supported platforms
  List<String> getSupportedPlatforms() {
    return [
      'tiktok',
      'instagram',
      'facebook',
      'twitter',
      'snapchat',
      'telegram',
    ];
  }

  /// Check if platform is supported
  bool isPlatformSupported(String platform) {
    return getSupportedPlatforms().contains(platform.toLowerCase());
  }

  /// Get current media context
  Map<String, dynamic>? getCurrentMediaContext() {
    return _currentMediaContext;
  }

  /// Force refresh service status
  Future<void> refreshServiceStatus() async {
    await _checkServiceStatus();
  }

  /// Dispose of all resources
  void dispose() {
    stopDetection();
    _statusCheckTimer?.cancel();
    _clipboardMonitor.dispose();
    _overlayManager.dispose();
    _downloaderService.dispose();
  }
}

/// Extension methods for easier access
extension EnhancedMediaDetectionServiceExtension
    on EnhancedMediaDetectionService {
  /// Quick check if system is ready
  Future<bool> isSystemReady() async {
    return _isActive &&
        _hasNotificationAccess &&
        _clipboardMonitor.isMonitoring &&
        _overlayManager.isInitialized;
  }

  /// Get health status
  Future<Map<String, bool>> getHealthStatus() async {
    return {
      'mediaDetectionActive': _isActive,
      'notificationAccess': _hasNotificationAccess,
      'clipboardMonitoring': _clipboardMonitor.isMonitoring,
      'overlayReady': _overlayManager.isInitialized,
      'downloaderReady': true,
    };
  }

  /// Quick start everything
  Future<bool> quickStart() async {
    try {
      await initialize();
      return await startDetection();
    } catch (e) {
      print('❌ Error in quick start: $e');
      return false;
    }
  }
}
