// services/working_overlay_service.dart
// ignore_for_file: avoid_print, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'native_bridge.dart';

class WorkingOverlayService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/overlay');

  static bool _isOverlayActive = false;
  static String? _currentDetectedMedia;

  /// Show download overlay when media is detected
  static Future<bool> showDownloadOverlay({
    String? mediaPath,
    String? appName,
  }) async {
    try {
      _currentDetectedMedia = mediaPath;

      final Map<String, dynamic> params = {
        'mediaPath': mediaPath ?? '',
        'appName': appName ?? 'Unknown',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final bool result =
          await _channel.invokeMethod('showDownloadOverlay', params);
      _isOverlayActive = result;

      return result;
    } catch (e) {
      print('Error showing download overlay: $e');
      return false;
    }
  }

  /// Hide download overlay
  static Future<void> hideDownloadOverlay() async {
    try {
      await _channel.invokeMethod('hideDownloadOverlay');
      _isOverlayActive = false;
      _currentDetectedMedia = null;
    } catch (e) {
      print('Error hiding download overlay: $e');
    }
  }

  /// Check if overlay is currently active
  static bool get isOverlayActive => _isOverlayActive;

  /// Get currently detected media path
  static String? get currentDetectedMedia => _currentDetectedMedia;

  /// Initialize overlay service and set up listeners
  static Future<void> initialize() async {
    // Set up method call handler for overlay interactions
    _channel.setMethodCallHandler(_handleOverlayMethodCall);

    // Listen to media detection events
    NativeBridge.mediaDetectionStream.listen((mediaPath) {
      if (mediaPath != null) {
        _handleMediaDetected(mediaPath);
      }
    });

    // Listen to app changes
    _listenToAppChanges();
  }

  /// Handle method calls from native overlay
  static Future<dynamic> _handleOverlayMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDownloadButtonClicked':
        return await _handleDownloadButtonClicked(call.arguments);

      case 'onOverlayDismissed':
        _isOverlayActive = false;
        _currentDetectedMedia = null;
        return true;

      case 'onOverlayMoved':
        // Handle overlay position changes if needed
        return true;

      default:
        throw MissingPluginException('${call.method} not implemented');
    }
  }

  /// Handle media detection and show overlay
  static Future<void> _handleMediaDetected(String mediaPath) async {
    if (!_isOverlayActive && await _shouldShowOverlay()) {
      final String appName = _detectAppFromPath(mediaPath);
      await showDownloadOverlay(
        mediaPath: mediaPath,
        appName: appName,
      );
    }
  }

  /// Handle download button clicked from overlay
  static Future<bool> _handleDownloadButtonClicked(dynamic arguments) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(arguments);
      final String? mediaPath = data['mediaPath'];

      if (mediaPath != null) {
        // Download the media using native bridge
        final bool success =
            await NativeBridge.downloadDetectedMedia(mediaPath);

        if (success) {
          // Hide overlay after successful download
          await hideDownloadOverlay();

          // Show success notification
          await _showDownloadNotification(
            title: 'Download Complete',
            message: 'Media downloaded successfully',
            isSuccess: true,
          );
        } else {
          // Show error notification
          await _showDownloadNotification(
            title: 'Download Failed',
            message: 'Could not download media',
            isSuccess: false,
          );
        }

        return success;
      }

      return false;
    } catch (e) {
      print('Error handling download button click: $e');
      return false;
    }
  }

  /// Listen to app changes to show/hide overlay appropriately
  static void _listenToAppChanges() {
    // This would be implemented to listen to accessibility events
    // showing when user switches between supported social media apps
  }

  /// Check if overlay should be shown based on current app and settings
  static Future<bool> _shouldShowOverlay() async {
    try {
      // Check if overlay permission is granted
      final bool hasPermission = await NativeBridge.hasOverlayPermission();
      if (!hasPermission) return false;

      // Check if user has enabled overlay in settings
      // This would check user preferences
      return true;
    } catch (e) {
      print('Error checking overlay conditions: $e');
      return false;
    }
  }

  /// Detect app name from media path
  static String _detectAppFromPath(String path) {
    if (path.contains('whatsapp')) {
      return 'WhatsApp';
    } else if (path.contains('instagram')) {
      return 'Instagram';
    } else if (path.contains('facebook')) {
      return 'Facebook';
    } else if (path.contains('tiktok') || path.contains('musically')) {
      return 'TikTok';
    } else if (path.contains('twitter')) {
      return 'Twitter';
    }
    return 'Unknown';
  }

  /// Show download notification
  static Future<void> _showDownloadNotification({
    required String title,
    required String message,
    required bool isSuccess,
  }) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'message': message,
        'isSuccess': isSuccess,
      });
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  /// Update overlay with new media information
  static Future<void> updateOverlayMedia(
      String mediaPath, String appName) async {
    if (_isOverlayActive) {
      try {
        await _channel.invokeMethod('updateOverlayMedia', {
          'mediaPath': mediaPath,
          'appName': appName,
        });
        _currentDetectedMedia = mediaPath;
      } catch (e) {
        print('Error updating overlay media: $e');
      }
    }
  }

  /// Configure overlay appearance and behavior
  static Future<void> configureOverlay({
    int? overlaySize,
    double? overlayOpacity,
    bool? showAppIcon,
    bool? autoHide,
  }) async {
    try {
      final Map<String, dynamic> config = {};

      if (overlaySize != null) config['size'] = overlaySize;
      if (overlayOpacity != null) config['opacity'] = overlayOpacity;
      if (showAppIcon != null) config['showAppIcon'] = showAppIcon;
      if (autoHide != null) config['autoHide'] = autoHide;

      await _channel.invokeMethod('configureOverlay', config);
    } catch (e) {
      print('Error configuring overlay: $e');
    }
  }

  /// Get overlay statistics
  static Future<Map<String, dynamic>> getOverlayStats() async {
    try {
      final Map<dynamic, dynamic> result =
          await _channel.invokeMethod('getOverlayStats');
      return result.cast<String, dynamic>();
    } catch (e) {
      print('Error getting overlay stats: $e');
      return {};
    }
  }
}

/// Flutter widget for in-app overlay preview/testing
class OverlayPreviewWidget extends StatefulWidget {
  final String? mediaPath;
  final String appName;
  final VoidCallback? onDownload;
  final VoidCallback? onDismiss;

  const OverlayPreviewWidget({
    Key? key,
    this.mediaPath,
    required this.appName,
    this.onDownload,
    this.onDismiss,
  }) : super(key: key);

  @override
  State<OverlayPreviewWidget> createState() => _OverlayPreviewWidgetState();
}

class _OverlayPreviewWidgetState extends State<OverlayPreviewWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: _buildOverlayContent(),
          ),
        );
      },
    );
  }

  Widget _buildOverlayContent() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _animationController.reverse().then((_) {
              widget.onDownload?.call();
            });
          },
          customBorder: const CircleBorder(),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.download,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.appName.substring(0, 2).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 5,
                right: 5,
                child: GestureDetector(
                  onTap: () {
                    _animationController.reverse().then((_) {
                      widget.onDismiss?.call();
                    });
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
