// services/floating_overlay_manager.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FloatingOverlayManager {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/floating_overlay');

  static FloatingOverlayManager? _instance;
  static FloatingOverlayManager get instance =>
      _instance ??= FloatingOverlayManager._();

  FloatingOverlayManager._();

  bool _isActive = false;
  bool _isInitialized = false;
  Map<String, dynamic>? _currentMediaInfo;
  Timer? _autoHideTimer;

  // Configuration
  double _overlaySize = 120.0;
  double _overlayOpacity = 0.9;
  bool _showAppIcon = true;
  bool _autoHide = true;
  int _autoHideDelay = 10; // seconds

  // Callbacks
  Function(Map<String, dynamic>)? _onDownloadRequested;
  Function()? _onOverlayDismissed;

  /// Initialize the floating overlay manager
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🖼️ Initializing FloatingOverlayManager...');

      // Set up method call handler for overlay interactions
      _channel.setMethodCallHandler(_handleOverlayMethodCall);

      // Check if overlay permission is granted
      final bool hasPermission = await hasOverlayPermission();
      if (!hasPermission) {
        print('⚠️ Overlay permission not granted');
        return;
      }

      // Initialize native overlay service
      await _channel.invokeMethod('initializeOverlay', {
        'size': _overlaySize,
        'opacity': _overlayOpacity,
        'showAppIcon': _showAppIcon,
      });

      _isInitialized = true;
      print('✅ FloatingOverlayManager initialized successfully');
    } catch (e) {
      print('❌ Error initializing FloatingOverlayManager: $e');
    }
  }

  /// Show download prompt for detected media
  Future<bool> showDownloadPrompt(Map<String, dynamic> mediaInfo) async {
    if (!_isInitialized) {
      print('⚠️ FloatingOverlayManager not initialized');
      return false;
    }

    try {
      print('🖼️ Showing download prompt for: ${mediaInfo['appName']}');

      _currentMediaInfo = mediaInfo;
      _isActive = true;

      // Prepare overlay data
      final overlayData = {
        'appName': mediaInfo['appName'] ?? 'Unknown App',
        'packageName': mediaInfo['packageName'] ?? '',
        'platform': mediaInfo['platform'] ?? 'unknown',
        'title': mediaInfo['title'] ?? '',
        'text': mediaInfo['text'] ?? '',
        'color': mediaInfo['color'] ?? '#2196F3',
        'timestamp':
            mediaInfo['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        'showDownloadButton': true,
        'showCancelButton': true,
      };

      // Show overlay via native Android
      final bool success =
          await _channel.invokeMethod('showDownloadPrompt', overlayData);

      if (success) {
        // Start auto-hide timer if enabled
        if (_autoHide) {
          _startAutoHideTimer();
        }
        print('✅ Download prompt shown successfully');
      } else {
        print('❌ Failed to show download prompt');
        _isActive = false;
      }

      return success;
    } catch (e) {
      print('❌ Error showing download prompt: $e');
      _isActive = false;
      return false;
    }
  }

  /// Hide the overlay
  Future<void> hideOverlay() async {
    if (!_isActive) return;

    try {
      print('🖼️ Hiding overlay...');

      await _channel.invokeMethod('hideOverlay');
      _isActive = false;
      _currentMediaInfo = null;

      // Cancel auto-hide timer
      _autoHideTimer?.cancel();
      _autoHideTimer = null;

      print('✅ Overlay hidden');
    } catch (e) {
      print('❌ Error hiding overlay: $e');
    }
  }

  /// Show download success message
  Future<void> showDownloadSuccess() async {
    try {
      print('🖼️ Showing download success...');

      await _channel.invokeMethod('showDownloadResult', {
        'isSuccess': true,
        'message': 'Download started successfully!',
        'autoHide': true,
        'hideDelay': 3000, // 3 seconds
      });

      // Hide main overlay after success
      await Future.delayed(const Duration(milliseconds: 500));
      await hideOverlay();
    } catch (e) {
      print('❌ Error showing download success: $e');
    }
  }

  /// Show download error message
  Future<void> showDownloadError(String errorMessage) async {
    try {
      print('🖼️ Showing download error: $errorMessage');

      await _channel.invokeMethod('showDownloadResult', {
        'isSuccess': false,
        'message': errorMessage,
        'autoHide': true,
        'hideDelay': 5000, // 5 seconds
      });

      // Keep main overlay visible for retry
    } catch (e) {
      print('❌ Error showing download error: $e');
    }
  }

  /// Update overlay with new media information
  Future<void> updateMediaInfo(Map<String, dynamic> mediaInfo) async {
    if (!_isActive) return;

    try {
      _currentMediaInfo = mediaInfo;

      await _channel.invokeMethod('updateOverlayMedia', {
        'appName': mediaInfo['appName'] ?? 'Unknown App',
        'title': mediaInfo['title'] ?? '',
        'text': mediaInfo['text'] ?? '',
      });

      print('✅ Overlay media info updated');
    } catch (e) {
      print('❌ Error updating overlay media info: $e');
    }
  }

  /// Show overlay with custom configuration
  Future<bool> showCustomOverlay({
    required String title,
    required String message,
    String? appName,
    String? iconUrl,
    List<Map<String, dynamic>>? buttons,
    Duration? autoHideAfter,
  }) async {
    try {
      final overlayData = {
        'title': title,
        'message': message,
        'appName': appName ?? 'AllSocialDownloader',
        'iconUrl': iconUrl,
        'buttons': buttons ??
            [
              {'text': 'OK', 'action': 'dismiss'},
            ],
        'autoHide': autoHideAfter != null,
        'hideDelay': autoHideAfter?.inMilliseconds ?? 0,
      };

      final bool success =
          await _channel.invokeMethod('showCustomOverlay', overlayData);

      if (success) {
        _isActive = true;
        if (autoHideAfter != null) {
          Timer(autoHideAfter, () => hideOverlay());
        }
      }

      return success;
    } catch (e) {
      print('❌ Error showing custom overlay: $e');
      return false;
    }
  }

  /// Configure overlay appearance and behavior
  Future<void> configure({
    double? size,
    double? opacity,
    bool? showAppIcon,
    bool? autoHide,
    int? autoHideDelay,
  }) async {
    try {
      if (size != null) _overlaySize = size;
      if (opacity != null) _overlayOpacity = opacity;
      if (showAppIcon != null) _showAppIcon = showAppIcon;
      if (autoHide != null) _autoHide = autoHide;
      if (autoHideDelay != null) _autoHideDelay = autoHideDelay;

      if (_isInitialized) {
        await _channel.invokeMethod('configureOverlay', {
          'size': _overlaySize,
          'opacity': _overlayOpacity,
          'showAppIcon': _showAppIcon,
          'autoHide': _autoHide,
          'autoHideDelay': _autoHideDelay,
        });
      }

      print('✅ Overlay configuration updated');
    } catch (e) {
      print('❌ Error configuring overlay: $e');
    }
  }

  /// Set callbacks for overlay interactions
  void setCallbacks({
    Function(Map<String, dynamic>)? onDownloadRequested,
    Function()? onOverlayDismissed,
  }) {
    _onDownloadRequested = onDownloadRequested;
    _onOverlayDismissed = onOverlayDismissed;
  }

  /// Check if overlay permission is granted
  Future<bool> hasOverlayPermission() async {
    try {
      final bool hasPermission =
          await _channel.invokeMethod('hasOverlayPermission');
      return hasPermission;
    } catch (e) {
      print('❌ Error checking overlay permission: $e');
      return false;
    }
  }

  /// Request overlay permission
  Future<bool> requestOverlayPermission() async {
    try {
      final bool granted =
          await _channel.invokeMethod('requestOverlayPermission');
      return granted;
    } catch (e) {
      print('❌ Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Test overlay functionality
  Future<void> testOverlay() async {
    try {
      print('🧪 Testing overlay functionality...');

      final testMediaInfo = {
        'appName': 'TikTok',
        'packageName': 'com.zhiliaoapp.musically',
        'platform': 'tiktok',
        'title': 'Funny Cat Video',
        'text': 'Testing overlay display',
        'color': '#000000',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final bool success = await showDownloadPrompt(testMediaInfo);

      if (success) {
        print('✅ Test overlay shown successfully');

        // Auto-hide after 5 seconds for testing
        Timer(const Duration(seconds: 5), () async {
          await hideOverlay();
          print('✅ Test overlay auto-hidden');
        });
      } else {
        print('❌ Test overlay failed to show');
      }
    } catch (e) {
      print('❌ Error testing overlay: $e');
    }
  }

  /// Get overlay statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final Map<dynamic, dynamic> stats =
          await _channel.invokeMethod('getOverlayStats');
      return stats.cast<String, dynamic>();
    } catch (e) {
      print('❌ Error getting overlay statistics: $e');
      return {
        'isActive': _isActive,
        'isInitialized': _isInitialized,
        'showCount': 0,
        'downloadCount': 0,
        'errorCount': 0,
      };
    }
  }

  /// Handle method calls from native Android overlay
  Future<dynamic> _handleOverlayMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onDownloadRequested':
          return await _handleDownloadRequested(call.arguments);

        case 'onOverlayDismissed':
          return await _handleOverlayDismissed(call.arguments);

        case 'onOverlayMoved':
          return await _handleOverlayMoved(call.arguments);

        case 'onOverlayError':
          return await _handleOverlayError(call.arguments);

        default:
          print('⚠️ Unknown overlay method call: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling overlay method call ${call.method}: $e');
      return false;
    }
  }

  /// Handle download request from overlay
  Future<bool> _handleDownloadRequested(dynamic arguments) async {
    try {
      print('⬇️ Download requested from overlay');

      if (_currentMediaInfo != null && _onDownloadRequested != null) {
        _onDownloadRequested!(_currentMediaInfo!);
        return true;
      } else {
        print('⚠️ No media info or callback available for download');
        return false;
      }
    } catch (e) {
      print('❌ Error handling download request: $e');
      return false;
    }
  }

  /// Handle overlay dismissed
  Future<bool> _handleOverlayDismissed(dynamic arguments) async {
    try {
      print('🖼️ Overlay dismissed by user');

      _isActive = false;
      _currentMediaInfo = null;
      _autoHideTimer?.cancel();
      _autoHideTimer = null;

      if (_onOverlayDismissed != null) {
        _onOverlayDismissed!();
      }

      return true;
    } catch (e) {
      print('❌ Error handling overlay dismissed: $e');
      return false;
    }
  }

  /// Handle overlay moved
  Future<bool> _handleOverlayMoved(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      final double? x = data['x'];
      final double? y = data['y'];

      print('🖼️ Overlay moved to: ($x, $y)');
      return true;
    } catch (e) {
      print('❌ Error handling overlay moved: $e');
      return false;
    }
  }

  /// Handle overlay error
  Future<bool> _handleOverlayError(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      final String error = data['error'] ?? 'Unknown error';

      print('❌ Overlay error: $error');
      _isActive = false;

      return true;
    } catch (e) {
      print('❌ Error handling overlay error: $e');
      return false;
    }
  }

  /// Start auto-hide timer
  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(Duration(seconds: _autoHideDelay), () async {
      if (_isActive) {
        print('⏰ Auto-hiding overlay after ${_autoHideDelay}s');
        await hideOverlay();
      }
    });
  }

  // Getters
  bool get isActive => _isActive;
  bool get isInitialized => _isInitialized;
  Map<String, dynamic>? get currentMediaInfo => _currentMediaInfo;

  /// Dispose resources
  void dispose() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
    _isActive = false;
    _currentMediaInfo = null;
    _onDownloadRequested = null;
    _onOverlayDismissed = null;
  }
}
