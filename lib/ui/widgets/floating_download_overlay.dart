// ui/widgets/advanced_floating_download_overlay.dart - System overlay for video download prompts
// ignore_for_file: avoid_print, use_build_context_synchronously, unused_field

import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/video_downloader_service.dart';
import '../../services/clipboard_monitor.dart';

class AdvancedFloatingDownloadOverlay extends StatefulWidget {
  final Map<String, dynamic> mediaInfo;
  final VoidCallback? onDownloadStarted;
  final VoidCallback? onDismissed;
  final VoidCallback? onDownloadCompleted;

  const AdvancedFloatingDownloadOverlay({
    Key? key,
    required this.mediaInfo,
    this.onDownloadStarted,
    this.onDismissed,
    this.onDownloadCompleted,
  }) : super(key: key);

  @override
  State<AdvancedFloatingDownloadOverlay> createState() =>
      _AdvancedFloatingDownloadOverlayState();
}

class _AdvancedFloatingDownloadOverlayState
    extends State<AdvancedFloatingDownloadOverlay>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _progressController;

  // Animations
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  // State management
  OverlayState _overlayState = OverlayState.initial;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  String? _detectedUrl;
  bool _isSearchingForUrl = false;
  Timer? _urlSearchTimer;
  Timer? _autoHideTimer;

  // Services
  final VideoDownloaderService _downloaderService =
      VideoDownloaderService.instance;
  final AdvancedClipboardMonitor _clipboardMonitor =
      AdvancedClipboardMonitor.instance;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startUrlDetection();
    _setupAutoHide();
  }

  void _initializeAnimations() {
    // Slide in animation
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    // Pulse animation for attention
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Scale animation for interactions
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Progress animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Start animations
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  void _startUrlDetection() {
    setState(() {
      _overlayState = OverlayState.searchingUrl;
      _isSearchingForUrl = true;
      _statusMessage = 'Looking for video URL...';
    });

    // Set media context for better detection
    _clipboardMonitor.setMediaContext(widget.mediaInfo);

    // Check clipboard immediately
    _checkClipboardForUrl();

    // Start periodic checking
    _urlSearchTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      _checkClipboardForUrl();
    });

    // Timeout after 15 seconds
    Timer(const Duration(seconds: 15), () {
      if (_isSearchingForUrl && mounted) {
        _handleUrlSearchTimeout();
      }
    });
  }

  Future<void> _checkClipboardForUrl() async {
    try {
      final urlInfo =
          _clipboardMonitor.getLatestVideoUrlInfo(timeoutSeconds: 20);

      if (urlInfo != null) {
        final url = urlInfo['url'] as String;
        final platform = urlInfo['platform'] as String;
        final contextMatch = urlInfo['contextMatch'] as bool? ?? false;

        print('🔗 Found URL: $url (platform: $platform, match: $contextMatch)');

        if (_detectedUrl != url) {
          _detectedUrl = url;

          setState(() {
            _overlayState = OverlayState.urlFound;
            _isSearchingForUrl = false;
            _statusMessage = contextMatch
                ? 'Video URL found! Ready to download.'
                : 'URL found (${platform.toUpperCase()})';
          });

          _urlSearchTimer?.cancel();

          // Show URL found animation
          _pulseController.stop();
          _pulseController.reset();

          // Auto-start download if high confidence match
          if (contextMatch && urlInfo['confidence'] > 0.8) {
            Timer(const Duration(seconds: 1), () {
              if (mounted) _startDownload();
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error checking clipboard: $e');
    }
  }

  void _handleUrlSearchTimeout() {
    setState(() {
      _overlayState = OverlayState.urlNotFound;
      _isSearchingForUrl = false;
      _statusMessage = 'No video URL found in clipboard';
    });

    _urlSearchTimer?.cancel();

    // Auto-dismiss after timeout
    Timer(const Duration(seconds: 3), () {
      if (mounted) _dismissOverlay();
    });
  }

  void _setupAutoHide() {
    // Auto-hide after 30 seconds if no interaction
    _autoHideTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _overlayState != OverlayState.downloading) {
        _dismissOverlay();
      }
    });
  }

  Future<void> _startDownload() async {
    if (_detectedUrl == null) {
      _showError('No video URL available');
      return;
    }

    setState(() {
      _overlayState = OverlayState.downloading;
      _downloadProgress = 0.0;
      _statusMessage = 'Starting download...';
    });

    _autoHideTimer?.cancel();
    widget.onDownloadStarted?.call();

    // Haptic feedback
    HapticFeedback.mediumImpact();

    try {
      final success = await _downloaderService.downloadFromUrl(
        _detectedUrl!,
        widget.mediaInfo,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
        onStatusUpdate: (status) {
          if (mounted) {
            setState(() {
              _statusMessage = status;
            });
          }
        },
      );

      if (mounted) {
        if (success) {
          setState(() {
            _overlayState = OverlayState.completed;
            _statusMessage = 'Download completed!';
          });

          HapticFeedback.lightImpact();
          widget.onDownloadCompleted?.call();

          // Auto-dismiss after success
          Timer(const Duration(seconds: 3), () {
            if (mounted) _dismissOverlay();
          });
        } else {
          _showError('Download failed');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Download error: $e');
      }
    }
  }

  void _showError(String message) {
    setState(() {
      _overlayState = OverlayState.error;
      _statusMessage = message;
    });

    HapticFeedback.heavyImpact();

    // Auto-dismiss after error
    Timer(const Duration(seconds: 4), () {
      if (mounted) _dismissOverlay();
    });
  }

  void _dismissOverlay() {
    _urlSearchTimer?.cancel();
    _autoHideTimer?.cancel();
    _clipboardMonitor.clearMediaContext();

    widget.onDismissed?.call();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _urlSearchTimer?.cancel();
    _autoHideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.all(16),
        child: Material(
          color: Colors.transparent,
          child: _buildOverlayContent(),
        ),
      ),
    );
  }

  Widget _buildOverlayContent() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _overlayState == OverlayState.initial
              ? _pulseAnimation.value
              : 1.0,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: 320,
              maxWidth: 380,
              minHeight: 120,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _getStateColor().withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getStateColor().withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: _buildOverlayBody(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayBody() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildContent(),
          const SizedBox(height: 16),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getStateColor(),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getStateIcon(),
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.mediaInfo['appName'] ?? 'Unknown App',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _getStateTitle(),
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (_overlayState != OverlayState.downloading)
          GestureDetector(
            onTap: _dismissOverlay,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.close,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_overlayState) {
      case OverlayState.searchingUrl:
        return _buildSearchingContent();
      case OverlayState.urlFound:
        return _buildUrlFoundContent();
      case OverlayState.downloading:
        return _buildDownloadingContent();
      case OverlayState.completed:
        return _buildCompletedContent();
      case OverlayState.error:
      case OverlayState.urlNotFound:
        return _buildErrorContent();
      default:
        return _buildInitialContent();
    }
  }

  Widget _buildSearchingContent() {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(_getStateColor()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Copy a video link to your clipboard...',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlFoundContent() {
    return Column(
      children: [
        Row(
          children: [
            Icon(
              Icons.link,
              color: _getStateColor(),
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        if (_detectedUrl != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _detectedUrl!.length > 50
                  ? '${_detectedUrl!.substring(0, 50)}...'
                  : _detectedUrl!,
              style: TextStyle(
                color: Colors.grey[300],
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDownloadingContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(_getStateColor()),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(_downloadProgress * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompletedContent() {
    return Row(
      children: [
        Icon(
          Icons.check_circle,
          color: _getStateColor(),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent() {
    return Row(
      children: [
        Icon(
          Icons.error_outline,
          color: _getStateColor(),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialContent() {
    return Text(
      'Looking for video to download...',
      style: TextStyle(
        color: Colors.grey[300],
        fontSize: 14,
      ),
    );
  }

  Widget _buildActions() {
    switch (_overlayState) {
      case OverlayState.urlFound:
        return Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Download',
                Icons.download,
                _getStateColor(),
                _startDownload,
              ),
            ),
            const SizedBox(width: 12),
            _buildActionButton(
              'Cancel',
              Icons.close,
              Colors.grey[600]!,
              _dismissOverlay,
              isSecondary: true,
            ),
          ],
        );
      case OverlayState.downloading:
        return _buildActionButton(
          'Cancel',
          Icons.stop,
          Colors.red,
          _dismissOverlay,
          isSecondary: true,
        );
      case OverlayState.completed:
        return _buildActionButton(
          'Done',
          Icons.check,
          _getStateColor(),
          _dismissOverlay,
        );
      case OverlayState.searchingUrl:
        return _buildActionButton(
          'Cancel',
          Icons.close,
          Colors.grey[600]!,
          _dismissOverlay,
          isSecondary: true,
        );
      default:
        return _buildActionButton(
          'Dismiss',
          Icons.close,
          Colors.grey[600]!,
          _dismissOverlay,
          isSecondary: true,
        );
    }
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed, {
    bool isSecondary = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSecondary ? color.withValues(alpha: 0.2) : color,
          borderRadius: BorderRadius.circular(8),
          border: isSecondary
              ? Border.all(color: color.withValues(alpha: 0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSecondary ? color : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: isSecondary ? color : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStateColor() {
    switch (_overlayState) {
      case OverlayState.searchingUrl:
        return Colors.blue;
      case OverlayState.urlFound:
        return Colors.green;
      case OverlayState.downloading:
        return Colors.orange;
      case OverlayState.completed:
        return Colors.green;
      case OverlayState.error:
      case OverlayState.urlNotFound:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getStateIcon() {
    switch (_overlayState) {
      case OverlayState.searchingUrl:
        return Icons.search;
      case OverlayState.urlFound:
        return Icons.link;
      case OverlayState.downloading:
        return Icons.download;
      case OverlayState.completed:
        return Icons.check_circle;
      case OverlayState.error:
      case OverlayState.urlNotFound:
        return Icons.error_outline;
      default:
        return Icons.video_library;
    }
  }

  String _getStateTitle() {
    switch (_overlayState) {
      case OverlayState.searchingUrl:
        return 'Searching for video URL...';
      case OverlayState.urlFound:
        return 'Video URL detected';
      case OverlayState.downloading:
        return 'Downloading video...';
      case OverlayState.completed:
        return 'Download complete';
      case OverlayState.error:
        return 'Download failed';
      case OverlayState.urlNotFound:
        return 'No video URL found';
      default:
        return 'Video detected';
    }
  }
}

enum OverlayState {
  initial,
  searchingUrl,
  urlFound,
  downloading,
  completed,
  error,
  urlNotFound,
}

// System overlay manager for showing floating prompts over other apps
class FloatingOverlayManager {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/floating_overlay');

  static FloatingOverlayManager? _instance;
  static FloatingOverlayManager get instance =>
      _instance ??= FloatingOverlayManager._();

  FloatingOverlayManager._();

  bool _isOverlayActive = false;
  OverlayEntry? _currentOverlay;
  Map<String, dynamic>? _currentMediaInfo;

  /// Initialize the floating overlay manager
  Future<void> initialize() async {
    try {
      print('🖼️ Initializing FloatingOverlayManager...');

      // Set up method call handler
      _channel.setMethodCallHandler(_handleMethodCall);

      // Check overlay permission
      final hasPermission = await hasOverlayPermission();
      if (!hasPermission) {
        print('⚠️ Overlay permission not granted');
        return;
      }

      print('✅ FloatingOverlayManager initialized');
    } catch (e) {
      print('❌ Error initializing FloatingOverlayManager: $e');
    }
  }

  /// Show floating download prompt for detected media
  Future<bool> showVideoDownloadPrompt(Map<String, dynamic> mediaInfo) async {
    try {
      if (_isOverlayActive) {
        print('⚠️ Overlay already active, dismissing previous');
        await hideOverlay();
      }

      print('🖼️ Showing video download prompt for: ${mediaInfo['appName']}');

      // Check overlay permission
      final hasPermission = await hasOverlayPermission();
      if (!hasPermission) {
        print('❌ No overlay permission');
        return false;
      }

      _currentMediaInfo = mediaInfo;
      _isOverlayActive = true;

      // Show using Flutter overlay (for in-app testing)
      _showFlutterOverlay(mediaInfo);

      // Also trigger native overlay if available
      try {
        await _channel.invokeMethod('showVideoDownloadPrompt', mediaInfo);
      } catch (e) {
        print('⚠️ Native overlay failed, using Flutter overlay: $e');
      }

      return true;
    } catch (e) {
      print('❌ Error showing video download prompt: $e');
      _isOverlayActive = false;
      return false;
    }
  }

  /// Show Flutter overlay (for testing and fallback)
  void _showFlutterOverlay(Map<String, dynamic> mediaInfo) {
    final overlay = OverlayEntry(
      builder: (context) => Positioned(
        top: 100,
        right: 16,
        left: 16,
        child: AdvancedFloatingDownloadOverlay(
          mediaInfo: mediaInfo,
          onDownloadStarted: () {
            print('📥 Download started from overlay');
          },
          onDownloadCompleted: () {
            print('✅ Download completed from overlay');
            hideOverlay();
          },
          onDismissed: () {
            print('❌ Overlay dismissed');
            hideOverlay();
          },
        ),
      ),
    );

    // Get overlay state from navigator
    try {
      final navigatorState = _getNavigatorState();
      if (navigatorState != null) {
        navigatorState.overlay!.insert(overlay);
        _currentOverlay = overlay;
        print('✅ Flutter overlay shown');
      }
    } catch (e) {
      print('❌ Error showing Flutter overlay: $e');
    }
  }

  /// Hide overlay
  Future<void> hideOverlay() async {
    try {
      if (!_isOverlayActive) return;

      print('🖼️ Hiding overlay...');

      // Hide Flutter overlay
      _currentOverlay?.remove();
      _currentOverlay = null;

      // Hide native overlay
      try {
        await _channel.invokeMethod('hideOverlay');
      } catch (e) {
        print('⚠️ Native overlay hide failed: $e');
      }

      _isOverlayActive = false;
      _currentMediaInfo = null;

      print('✅ Overlay hidden');
    } catch (e) {
      print('❌ Error hiding overlay: $e');
    }
  }

  /// Handle method calls from native overlay
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onOverlayDismissed':
          return await _handleOverlayDismissed();
        case 'onDownloadRequested':
          return await _handleDownloadRequested(call.arguments);
        case 'onOverlayError':
          return await _handleOverlayError(call.arguments);
        default:
          print('⚠️ Unknown overlay method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling overlay method call: $e');
      return false;
    }
  }

  /// Handle overlay dismissed
  Future<bool> _handleOverlayDismissed() async {
    try {
      _isOverlayActive = false;
      _currentMediaInfo = null;
      _currentOverlay?.remove();
      _currentOverlay = null;
      return true;
    } catch (e) {
      print('❌ Error handling overlay dismissed: $e');
      return false;
    }
  }

  /// Handle download requested from native overlay
  Future<bool> _handleDownloadRequested(dynamic arguments) async {
    try {
      if (_currentMediaInfo == null) return false;

      // Start download using video downloader service
      final downloaderService = VideoDownloaderService.instance;
      final clipboardMonitor = AdvancedClipboardMonitor.instance;

      // Get URL from clipboard
      final urlInfo = clipboardMonitor.getLatestVideoUrlInfo();
      if (urlInfo == null) {
        print('❌ No video URL found for download');
        return false;
      }

      final url = urlInfo['url'] as String;
      print('⬇️ Starting download from native overlay: $url');

      final success = await downloaderService.downloadFromUrl(
        url,
        _currentMediaInfo!,
      );

      if (success) {
        print('✅ Download completed from native overlay');
        await hideOverlay();
      }

      return success;
    } catch (e) {
      print('❌ Error handling download request: $e');
      return false;
    }
  }

  /// Handle overlay error
  Future<bool> _handleOverlayError(dynamic arguments) async {
    try {
      final error = arguments['error'] ?? 'Unknown error';
      print('❌ Overlay error: $error');
      await hideOverlay();
      return true;
    } catch (e) {
      print('❌ Error handling overlay error: $e');
      return false;
    }
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

  /// Test overlay with sample media info
  Future<void> testOverlay() async {
    final testMediaInfo = {
      'appName': 'TikTok',
      'packageName': 'com.zhiliaoapp.musically',
      'platform': 'tiktok',
      'title': 'Test Video',
      'text': 'Testing overlay display',
      'isVideoApp': true,
      'downloadPriority': 'HIGH',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await showVideoDownloadPrompt(testMediaInfo);
  }

  /// Get navigator state for overlay
  NavigatorState? _getNavigatorState() {
    try {
      // This is a simplified approach - in a real app you'd have better navigator access
      return null; // Return actual navigator state
    } catch (e) {
      print('❌ Error getting navigator state: $e');
      return null;
    }
  }

  // Getters
  bool get isOverlayActive => _isOverlayActive;
  Map<String, dynamic>? get currentMediaInfo => _currentMediaInfo;

  /// Get overlay statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isOverlayActive': _isOverlayActive,
      'hasCurrentMedia': _currentMediaInfo != null,
      'currentApp': _currentMediaInfo?['appName'],
      'currentPlatform': _currentMediaInfo?['platform'],
    };
  }

  /// Dispose resources
  void dispose() {
    hideOverlay();
  }
}

// Media detection coordinator that ties everything together
class MediaDetectionCoordinator {
  static MediaDetectionCoordinator? _instance;
  static MediaDetectionCoordinator get instance =>
      _instance ??= MediaDetectionCoordinator._();

  MediaDetectionCoordinator._();

  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/media_detection');

  final FloatingOverlayManager _overlayManager =
      FloatingOverlayManager.instance;
  final AdvancedClipboardMonitor _clipboardMonitor =
      AdvancedClipboardMonitor.instance;
  final VideoDownloaderService _downloaderService =
      VideoDownloaderService.instance;

  bool _isInitialized = false;
  bool _isListening = false;

  /// Initialize the media detection system
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('🎬 Initializing MediaDetectionCoordinator...');

      // Initialize all services
      await _overlayManager.initialize();
      await _clipboardMonitor.initialize();
      await _downloaderService.initialize();

      // Set up method call handler for media detection events
      _channel.setMethodCallHandler(_handleMediaDetectionEvent);

      _isInitialized = true;
      print('✅ MediaDetectionCoordinator initialized');
    } catch (e) {
      print('❌ Error initializing MediaDetectionCoordinator: $e');
    }
  }

  /// Start listening for media detection events
  Future<void> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isListening) return;

    try {
      print('🔄 Starting media detection listening...');

      // Start clipboard monitoring
      await _clipboardMonitor.startMonitoring();

      // Start listening for video detection events from native service
      await _channel.invokeMethod('startListening');

      _isListening = true;
      print('✅ Media detection listening started');
    } catch (e) {
      print('❌ Error starting media detection listening: $e');
    }
  }

  /// Stop listening for media detection events
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      print('⏹️ Stopping media detection listening...');

      // Stop clipboard monitoring
      await _clipboardMonitor.stopMonitoring();

      // Stop native listening
      await _channel.invokeMethod('stopListening');

      // Hide any active overlays
      await _overlayManager.hideOverlay();

      _isListening = false;
      print('✅ Media detection listening stopped');
    } catch (e) {
      print('❌ Error stopping media detection listening: $e');
    }
  }

  /// Handle media detection events from native service
  Future<dynamic> _handleMediaDetectionEvent(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onVideoDetected':
          return await _handleVideoDetected(call.arguments);
        case 'onVideoFocusedAppDetected':
          return await _handleVideoFocusedAppDetected(call.arguments);
        case 'onVideoStopped':
          return await _handleVideoStopped(call.arguments);
        default:
          print('⚠️ Unknown media detection method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Error handling media detection event: $e');
      return false;
    }
  }

  /// Handle video detected event
  Future<bool> _handleVideoDetected(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);

      print(
          '🎬 Video detected: ${mediaInfo['appName']} - ${mediaInfo['title']}');

      // Set clipboard context for better URL detection
      _clipboardMonitor.setMediaContext(mediaInfo);

      // Show floating download prompt
      final success = await _overlayManager.showVideoDownloadPrompt(mediaInfo);

      return success;
    } catch (e) {
      print('❌ Error handling video detected: $e');
      return false;
    }
  }

  /// Handle video focused app detected (high priority apps like TikTok)
  Future<bool> _handleVideoFocusedAppDetected(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);

      print('🎯 High-priority video detected: ${mediaInfo['appName']}');

      // Immediate action for video-focused apps
      _clipboardMonitor.setMediaContext(mediaInfo);

      // Show overlay with higher priority
      final success = await _overlayManager.showVideoDownloadPrompt(mediaInfo);

      return success;
    } catch (e) {
      print('❌ Error handling video focused app detected: $e');
      return false;
    }
  }

  /// Handle video stopped event
  Future<bool> _handleVideoStopped(dynamic arguments) async {
    try {
      final mediaInfo = Map<String, dynamic>.from(arguments);

      print('🔇 Video stopped: ${mediaInfo['appName']}');

      // Clear clipboard context
      _clipboardMonitor.clearMediaContext();

      // Auto-hide overlay after a delay
      Timer(const Duration(seconds: 3), () {
        _overlayManager.hideOverlay();
      });

      return true;
    } catch (e) {
      print('❌ Error handling video stopped: $e');
      return false;
    }
  }

  /// Manually trigger video detection (for testing)
  Future<void> triggerTestDetection() async {
    final testMediaInfo = {
      'appName': 'TikTok',
      'packageName': 'com.zhiliaoapp.musically',
      'platform': 'tiktok',
      'title': 'Test Video Detection',
      'text': 'Testing media detection system',
      'isVideoApp': true,
      'downloadPriority': 'HIGH',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    await _handleVideoDetected(testMediaInfo);
  }

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// Get system statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isInitialized': _isInitialized,
      'isListening': _isListening,
      'overlayManager': _overlayManager.getStatistics(),
      'clipboardMonitor': _clipboardMonitor.getStatistics(),
      'downloaderService': _downloaderService.getStatistics(),
    };
  }

  /// Dispose all resources
  void dispose() {
    stopListening();
    _overlayManager.dispose();
    _clipboardMonitor.dispose();
    _downloaderService.dispose();
  }
}
