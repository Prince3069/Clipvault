// services/advanced_clipboard_monitor.dart - Enhanced clipboard monitoring for video URLs
// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/services.dart';

class AdvancedClipboardMonitor {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/clipboard');

  static AdvancedClipboardMonitor? _instance;
  static AdvancedClipboardMonitor get instance =>
      _instance ??= AdvancedClipboardMonitor._();

  AdvancedClipboardMonitor._();

  bool _isMonitoring = false;
  Timer? _clipboardTimer;
  String _lastClipboardContent = '';
  String? _latestVideoUrl;
  DateTime? _lastUrlDetection;
  Map<String, dynamic>? _currentMediaContext;

  // Enhanced video URL patterns for comprehensive detection
  static const Map<String, List<String>> _enhancedUrlPatterns = {
    'tiktok': [
      r'https?://(?:www\.)?tiktok\.com/@[\w.-]+/video/\d+',
      r'https?://(?:m\.)?tiktok\.com/v/\d+',
      r'https?://vm\.tiktok\.com/[\w\-_]+',
      r'https?://(?:www\.)?tiktok\.com/t/[\w\-_]+',
      r'https?://(?:www\.)?tiktok\.com/share/video/\d+',
      r'https?://vt\.tiktok\.com/[\w\-_]+',
    ],
    'instagram': [
      r'https?://(?:www\.)?instagram\.com/p/[\w\-_]+',
      r'https?://(?:www\.)?instagram\.com/reel/[\w\-_]+',
      r'https?://(?:www\.)?instagram\.com/stories/[\w.-]+/\d+',
      r'https?://(?:www\.)?instagram\.com/tv/[\w\-_]+',
      r'https?://(?:www\.)?instagram\.com/[\w.-]+/p/[\w\-_]+',
      r'https?://instagr\.am/p/[\w\-_]+',
    ],
    'facebook': [
      r'https?://(?:www\.)?facebook\.com/watch/?\?v=\d+',
      r'https?://(?:www\.)?facebook\.com/[\w.-]+/videos/\d+',
      r'https?://(?:www\.)?facebook\.com/reel/\d+',
      r'https?://fb\.watch/[\w\-_]+',
      r'https?://(?:www\.)?facebook\.com/video\.php\?v=\d+',
      r'https?://(?:m\.)?facebook\.com/story\.php\?story_fbid=\d+',
    ],
    'twitter': [
      r'https?://(?:www\.)?twitter\.com/[\w]+/status/\d+',
      r'https?://(?:www\.)?x\.com/[\w]+/status/\d+',
      r'https?://t\.co/[\w\-_]+',
      r'https?://mobile\.twitter\.com/[\w]+/status/\d+',
    ],
    'snapchat': [
      r'https?://(?:www\.)?snapchat\.com/t/[\w\-_]+',
      r'https?://t\.snapchat\.com/[\w\-_]+',
      r'https?://(?:www\.)?snapchat\.com/spotlight/[\w\-_]+',
    ],
    'telegram': [
      r'https?://t\.me/[\w\-_]+/\d+',
      r'https?://telegram\.me/[\w\-_]+/\d+',
      r'https?://telegram\.dog/[\w\-_]+/\d+',
    ],
    'pinterest': [
      r'https?://(?:www\.)?pinterest\.com/pin/\d+',
      r'https?://pin\.it/[\w\-_]+',
      r'https?://(?:www\.)?pinterest\.[\w]+/pin/\d+',
    ],
    'reddit': [
      r'https?://(?:www\.)?reddit\.com/r/[\w\-_]+/comments/[\w\-_]+',
      r'https?://redd\.it/[\w\-_]+',
      r'https?://(?:v\.)?redd\.it/[\w\-_]+',
    ],
    'linkedin': [
      r'https?://(?:www\.)?linkedin\.com/posts/[\w\-_]+',
      r'https?://(?:www\.)?linkedin\.com/feed/update/urn:li:activity:\d+',
    ],
    'vimeo': [
      r'https?://(?:www\.)?vimeo\.com/\d+',
      r'https?://player\.vimeo\.com/video/\d+',
    ],
    'dailymotion': [
      r'https?://(?:www\.)?dailymotion\.com/video/[\w\-_]+',
      r'https?://dai\.ly/[\w\-_]+',
    ],
    'twitch': [
      r'https?://(?:www\.)?twitch\.tv/[\w\-_]+',
      r'https?://(?:www\.)?twitch\.tv/videos/\d+',
      r'https?://clips\.twitch\.tv/[\w\-_]+',
    ],
  };

  // Context-aware URL validation
  static const Map<String, List<String>> _contextKeywords = {
    'tiktok': ['tiktok', 'fyp', 'for you', 'trending'],
    'instagram': ['instagram', 'insta', 'ig', 'reel', 'story'],
    'facebook': ['facebook', 'fb', 'meta'],
    'twitter': ['twitter', 'tweet', 'x.com'],
  };

  /// Initialize enhanced clipboard monitoring
  Future<void> initialize() async {
    try {
      print('📋 Initializing Advanced ClipboardMonitor...');

      // Set up method call handler for native clipboard events
      _channel.setMethodCallHandler(_handleNativeClipboardEvent);

      print('✅ Advanced ClipboardMonitor initialized');
    } catch (e) {
      print('❌ Error initializing Advanced ClipboardMonitor: $e');
    }
  }

// services/clipboard_monitor.dart - MISSING METHODS ADDED
// Add these methods to your existing AdvancedClipboardMonitor class

  /// Update download progress for overlay
  void updateDownloadProgress(double progress) {
    try {
      _channel.invokeMethod('onUpdateDownloadProgress', {
        'progress': progress,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Error updating download progress: $e');
    }
  }

  /// Show download success message
  Future<void> showDownloadSuccess() async {
    try {
      await _channel.invokeMethod('onDownloadSuccess', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Error showing download success: $e');
    }
  }

  /// Show download error message
  Future<void> showDownloadError(String error) async {
    try {
      await _channel.invokeMethod('onDownloadError', {
        'error': error,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Error showing download error: $e');
    }
  }

  /// Start video URL detection with context (FIXED METHOD)
  void startVideoUrlDetection(Map<String, dynamic> mediaInfo) {
    try {
      print('🔍 Starting video URL detection for: ${mediaInfo['appName']}');

      // Set the media context for better URL matching
      setMediaContext(mediaInfo);

      // Start monitoring clipboard for video URLs
      if (!_isMonitoring) {
        startMonitoring();
      }

      // Force check current clipboard content
      forceCheckClipboard();

      print('✅ Video URL detection started');
    } catch (e) {
      print('❌ Error starting video URL detection: $e');
    }
  }

  /// Check if overlay manager is initialized
  bool get isInitialized => true; // Add this getter to your class

  /// Update media info in overlay
  Future<void> updateMediaInfo(Map<String, dynamic> mediaInfo) async {
    try {
      _currentMediaContext = mediaInfo;

      await _channel.invokeMethod('onUpdateMediaInfo', {
        'mediaInfo': mediaInfo,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      print('❌ Error updating media info: $e');
    }
  }

  /// Handle native clipboard events
  Future<dynamic> _handleNativeClipboardEvent(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onClipboardChanged':
          final String content = call.arguments['content'] ?? '';
          final int timestamp = call.arguments['timestamp'] ?? 0;
          await _handleClipboardContent(content, timestamp);
          break;
        case 'onClipboardCleared':
          _clearDetectedUrl();
          break;
        default:
          print('⚠️ Unknown clipboard method: ${call.method}');
      }
    } catch (e) {
      print('❌ Error handling native clipboard event: $e');
    }
  }

  /// Start enhanced clipboard monitoring
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    try {
      print('🔄 Starting enhanced clipboard monitoring...');

      // Start native clipboard monitoring for real-time detection
      await _channel.invokeMethod('startClipboardMonitoring');

      _isMonitoring = true;

      // Get initial clipboard content
      _lastClipboardContent = await _getClipboardContent();

      // Start periodic checking as backup
      _clipboardTimer = Timer.periodic(
        const Duration(milliseconds: 1000), // Check every second
        (_) => _checkClipboard(),
      );

      print('✅ Enhanced clipboard monitoring started');
    } catch (e) {
      print('❌ Error starting clipboard monitoring: $e');
      _isMonitoring = false;
    }
  }

  /// Stop clipboard monitoring
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) return;

    try {
      print('⏹️ Stopping clipboard monitoring...');

      await _channel.invokeMethod('stopClipboardMonitoring');

      _isMonitoring = false;
      _clipboardTimer?.cancel();
      _clipboardTimer = null;

      print('✅ Clipboard monitoring stopped');
    } catch (e) {
      print('❌ Error stopping clipboard monitoring: $e');
    }
  }

  /// Set media context for better URL detection
  void setMediaContext(Map<String, dynamic> mediaInfo) {
    _currentMediaContext = mediaInfo;
    print(
        '🎬 Media context set: ${mediaInfo['appName']} - ${mediaInfo['platform']}');

    // Immediately check current clipboard for relevant URLs
    _checkClipboard();
  }

  /// Clear media context
  void clearMediaContext() {
    _currentMediaContext = null;
    _latestVideoUrl = null;
    _lastUrlDetection = null;
    print('🧹 Media context cleared');
  }

  /// Check clipboard periodically (backup method)
  Future<void> _checkClipboard() async {
    if (!_isMonitoring) return;

    try {
      final currentContent = await _getClipboardContent();

      if (currentContent != _lastClipboardContent &&
          currentContent.isNotEmpty) {
        _lastClipboardContent = currentContent;
        await _handleClipboardContent(
            currentContent, DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      print('❌ Error checking clipboard: $e');
    }
  }

  /// Handle clipboard content change with enhanced detection
  Future<void> _handleClipboardContent(String content, int timestamp) async {
    try {
      if (content.trim().isEmpty) return;

      print('📋 Clipboard content detected (${content.length} chars)');

      // Detect video URLs with enhanced patterns
      final detectedUrl = _detectEnhancedVideoUrl(content);

      if (detectedUrl != null) {
        _latestVideoUrl = detectedUrl['url'];
        _lastUrlDetection = DateTime.fromMillisecondsSinceEpoch(timestamp);

        print('🔗 Enhanced video URL detected!');
        print('   🌐 URL: $_latestVideoUrl');
        print('   📱 Platform: ${detectedUrl['platform']}');
        print('   🎯 Confidence: ${detectedUrl['confidence']}');

        // Context-aware validation
        if (_currentMediaContext != null) {
          final contextPlatform = _currentMediaContext!['platform'] as String?;
          final detectedPlatform = detectedUrl['platform'] as String;
          final confidence = detectedUrl['confidence'] as double;

          if (contextPlatform == detectedPlatform) {
            print(
                '✅ Platform match confirmed: $contextPlatform (confidence: $confidence)');

            // High confidence match - notify immediately
            _notifyUrlDetected(detectedUrl, isHighConfidence: confidence > 0.8);
          } else {
            print(
                '⚠️ Platform mismatch: $contextPlatform vs $detectedPlatform');

            // Still store the URL but with lower confidence
            detectedUrl['confidence'] = confidence * 0.7;
            _notifyUrlDetected(detectedUrl, isHighConfidence: false);
          }
        } else {
          // No context - just store the URL
          print('📝 No media context, storing URL for later use');
          _notifyUrlDetected(detectedUrl, isHighConfidence: false);
        }
      } else {
        print('❌ No video URL detected in clipboard content');
      }
    } catch (e) {
      print('❌ Error handling clipboard content: $e');
    }
  }

  /// Enhanced video URL detection with confidence scoring
  Map<String, dynamic>? _detectEnhancedVideoUrl(String content) {
    try {
      // Clean up the content
      final cleanContent = content.trim();

      // Extract all URLs from content
      final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
      final urls = urlRegex.allMatches(cleanContent);

      Map<String, dynamic>? bestMatch;
      double highestConfidence = 0.0;

      for (final urlMatch in urls) {
        final url = urlMatch.group(0)!;
        final urlInfo = _analyzeUrl(url, cleanContent);

        if (urlInfo != null && urlInfo['confidence'] > highestConfidence) {
          highestConfidence = urlInfo['confidence'];
          bestMatch = urlInfo;
        }
      }

      return bestMatch;
    } catch (e) {
      print('❌ Error detecting enhanced video URL: $e');
      return null;
    }
  }

  /// Analyze individual URL with confidence scoring
  Map<String, dynamic>? _analyzeUrl(String url, String fullContent) {
    try {
      String platform = 'unknown';
      double confidence = 0.0;

      // Check each platform's URL patterns
      for (final platformName in _enhancedUrlPatterns.keys) {
        final patterns = _enhancedUrlPatterns[platformName]!;

        for (final pattern in patterns) {
          final regex = RegExp(pattern, caseSensitive: false);
          final match = regex.firstMatch(url);

          if (match != null) {
            platform = platformName;
            confidence = 0.7; // Base confidence for pattern match
            break;
          }
        }

        if (platform != 'unknown') break;
      }

      if (platform == 'unknown') return null;

      // Boost confidence based on context keywords
      final contextWords = _contextKeywords[platform] ?? [];
      final lowerContent = fullContent.toLowerCase();

      for (final keyword in contextWords) {
        if (lowerContent.contains(keyword)) {
          confidence += 0.1;
        }
      }

      // Boost confidence if URL is clean (no extra parameters)
      if (!url.contains('?') || url.split('?').length <= 2) {
        confidence += 0.1;
      }

      // Boost confidence for video-specific indicators
      if (url.contains('video') ||
          url.contains('watch') ||
          url.contains('reel')) {
        confidence += 0.1;
      }

      // Cap confidence at 1.0
      confidence = confidence.clamp(0.0, 1.0);

      final cleanUrl = _cleanVideoUrl(url, platform);

      return {
        'url': cleanUrl,
        'platform': platform,
        'originalUrl': url,
        'confidence': confidence,
        'detectedAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error analyzing URL: $e');
      return null;
    }
  }

  /// Clean video URL by removing unnecessary parameters
  String _cleanVideoUrl(String url, String platform) {
    try {
      switch (platform) {
        case 'tiktok':
          // Remove TikTok tracking parameters but keep essential ones
          return url.replaceAll(
              RegExp(r'[?&](utm_[^&]*|fbclid=[^&]*|gclid=[^&]*)'), '');

        case 'instagram':
          // Keep Instagram URL as is, they're usually clean
          return url;


        case 'facebook':
          // Remove Facebook tracking parameters
          return url.replaceAll(RegExp(r'[?&]__[^&]*'), '');

        case 'twitter':
          // Keep Twitter URLs clean
          return url.replaceAll(RegExp(r'[?&](utm_[^&]*|ref_[^&]*)'), '');

        default:
          return url;
      }
    } catch (e) {
      print('❌ Error cleaning URL: $e');
      return url;
    }
  }

  /// Notify about detected URL
  void _notifyUrlDetected(Map<String, dynamic> urlInfo,
      {required bool isHighConfidence}) {
    try {
      // Store in instance variables
      _latestVideoUrl = urlInfo['url'];
      _lastUrlDetection = DateTime.now();

      // Notify via method channel
      _channel.invokeMethod('onVideoUrlDetected', {
        'url': urlInfo['url'],
        'platform': urlInfo['platform'],
        'confidence': urlInfo['confidence'],
        'isHighConfidence': isHighConfidence,
        'hasMediaContext': _currentMediaContext != null,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      print('📤 URL detection notification sent');
    } catch (e) {
      print('❌ Error notifying URL detection: $e');
    }
  }

  /// Get clipboard content
  Future<String> _getClipboardContent() async {
    try {
      return await _channel.invokeMethod('getClipboardContent') ?? '';
    } catch (e) {
      print('❌ Error getting clipboard content: $e');
      return '';
    }
  }

  /// Set clipboard content
  Future<void> setClipboardContent(String content) async {
    try {
      await _channel.invokeMethod('setClipboardContent', {'content': content});
    } catch (e) {
      print('❌ Error setting clipboard content: $e');
    }
  }

  /// Get latest detected video URL (with timeout)
  String? getLatestVideoUrl({int timeoutSeconds = 30}) {
    if (_lastUrlDetection != null && _latestVideoUrl != null) {
      final timeDiff = DateTime.now().difference(_lastUrlDetection!);
      if (timeDiff.inSeconds <= timeoutSeconds) {
        return _latestVideoUrl;
      }
    }
    return null;
  }

  /// Get latest video URL with platform information
  Map<String, dynamic>? getLatestVideoUrlInfo({int timeoutSeconds = 30}) {
    final url = getLatestVideoUrl(timeoutSeconds: timeoutSeconds);
    if (url != null) {
      final platform = _detectPlatformFromUrl(url);
      return {
        'url': url,
        'platform': platform,
        'detectedAt': _lastUrlDetection?.toIso8601String(),
        'hasContext': _currentMediaContext != null,
        'contextMatch': _currentMediaContext?['platform'] == platform,
      };
    }
    return null;
  }

  /// Detect platform from URL
  String _detectPlatformFromUrl(String url) {
    final cleanUrl = url.toLowerCase();

    for (final platform in _enhancedUrlPatterns.keys) {
      final patterns = _enhancedUrlPatterns[platform]!;
      for (final pattern in patterns) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(cleanUrl)) {
          return platform;
        }
      }
    }

    return 'unknown';
  }

  /// Clear stored video URL
  void _clearDetectedUrl() {
    _latestVideoUrl = null;
    _lastUrlDetection = null;
    print('🧹 Cleared detected video URL');
  }

  /// Force check current clipboard content
  Future<String?> forceCheckClipboard() async {
    try {
      final content = await _getClipboardContent();
      if (content.isNotEmpty) {
        await _handleClipboardContent(
            content, DateTime.now().millisecondsSinceEpoch);
        return getLatestVideoUrl();
      }
      return null;
    } catch (e) {
      print('❌ Error force checking clipboard: $e');
      return null;
    }
  }

  /// Check if URL is supported
  bool isSupportedUrl(String url) {
    return _detectPlatformFromUrl(url) != 'unknown';
  }

  /// Get URL information
  Map<String, dynamic>? getUrlInfo(String url) {
    return _analyzeUrl(url, url);
  }

  /// Validate URL with current context
  bool validateUrlWithContext(String url) {
    if (_currentMediaContext == null) return true;

    final platform = _detectPlatformFromUrl(url);
    final contextPlatform = _currentMediaContext!['platform'] as String?;

    return platform == contextPlatform;
  }

  /// Test clipboard detection with sample URLs
  Future<void> testClipboardDetection() async {
    try {
      print('🧪 Testing enhanced clipboard detection...');

      final testUrls = [
        'https://www.tiktok.com/@username/video/1234567890123456789',
        'https://vm.tiktok.com/ZMeMNpFoo/',
        'https://www.instagram.com/p/ABC123DEF/',
        'https://www.instagram.com/reel/XYZ789/',
        'https://twitter.com/user/status/1234567890',
        'https://www.facebook.com/watch/?v=1234567890',
        'https://fb.watch/abc123/',
      ];

      for (final url in testUrls) {
        print('🔗 Testing URL: $url');

        await setClipboardContent(url);
        await Future.delayed(const Duration(milliseconds: 200));

        final detected = await forceCheckClipboard();
        final platform = _detectPlatformFromUrl(url);

        print('   Platform: $platform');
        print('   Detected: ${detected != null ? '✅' : '❌'}');
        if (detected != null) {
          print('   Result: $detected');
        }
        print('');
      }

      print('🧪 Enhanced clipboard detection test completed');
    } catch (e) {
      print('❌ Error testing clipboard detection: $e');
    }
  }

  /// Get monitoring statistics
  Map<String, dynamic> getStatistics() {
    return {
      'isMonitoring': _isMonitoring,
      'lastClipboardLength': _lastClipboardContent.length,
      'latestVideoUrl': _latestVideoUrl,
      'lastUrlDetection': _lastUrlDetection?.toIso8601String(),
      'hasMediaContext': _currentMediaContext != null,
      'currentContextPlatform': _currentMediaContext?['platform'],
      'supportedPlatforms': _enhancedUrlPatterns.keys.toList(),
      'totalPatterns': _enhancedUrlPatterns.values
          .map((patterns) => patterns.length)
          .reduce((a, b) => a + b),
    };
  }

  /// Get detailed clipboard history (last 10 entries)
  List<Map<String, dynamic>> getClipboardHistory() {
    // This would require storing history, for now return current state
    return [
      {
        'content': _lastClipboardContent.length > 100
            ? '${_lastClipboardContent.substring(0, 100)}...'
            : _lastClipboardContent,
        'timestamp': DateTime.now().toIso8601String(),
        'containsUrl': _latestVideoUrl != null,
        'detectedPlatform': _latestVideoUrl != null
            ? _detectPlatformFromUrl(_latestVideoUrl!)
            : null,
      }
    ];
  }

  /// Advanced URL extraction from complex text
  List<Map<String, dynamic>> extractAllVideoUrls(String text) {
    final List<Map<String, dynamic>> foundUrls = [];

    try {
      // Extract all URLs
      final urlRegex = RegExp(r'https?://[^\s\n\r]+', caseSensitive: false);
      final urls = urlRegex.allMatches(text);

      for (final urlMatch in urls) {
        final url = urlMatch.group(0)!;
        final urlInfo = _analyzeUrl(url, text);

        if (urlInfo != null) {
          foundUrls.add(urlInfo);
        }
      }

      // Sort by confidence
      foundUrls.sort((a, b) =>
          (b['confidence'] as double).compareTo(a['confidence'] as double));
    } catch (e) {
      print('❌ Error extracting video URLs: $e');
    }

    return foundUrls;
  }

  /// Smart URL selection based on context and confidence
  String? selectBestUrl(List<Map<String, dynamic>> urls) {
    if (urls.isEmpty) return null;

    // If we have media context, prefer matching platform
    if (_currentMediaContext != null) {
      final contextPlatform = _currentMediaContext!['platform'] as String?;

      for (final urlInfo in urls) {
        if (urlInfo['platform'] == contextPlatform &&
            urlInfo['confidence'] > 0.6) {
          return urlInfo['url'];
        }
      }
    }

    // Otherwise, return highest confidence URL
    final bestUrl = urls.first;
    return bestUrl['confidence'] > 0.5 ? bestUrl['url'] : null;
  }

  /// Monitor clipboard for specific platform
  Future<void> monitorForPlatform(String platform,
      {Duration timeout = const Duration(minutes: 2)}) async {
    print('🎯 Monitoring clipboard for $platform URLs...');

    final startTime = DateTime.now();
    const checkInterval = Duration(milliseconds: 500);

    while (DateTime.now().difference(startTime) < timeout) {
      final content = await _getClipboardContent();
      final urls = extractAllVideoUrls(content);

      for (final urlInfo in urls) {
        if (urlInfo['platform'] == platform) {
          print('✅ Found $platform URL: ${urlInfo['url']}');
          _latestVideoUrl = urlInfo['url'];
          _lastUrlDetection = DateTime.now();
          return;
        }
      }

      await Future.delayed(checkInterval);
    }

    print('⏰ Timeout waiting for $platform URL');
  }

  /// Check if monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Get supported platforms list
  List<String> get supportedPlatforms => _enhancedUrlPatterns.keys.toList();

  /// Get current media context
  Map<String, dynamic>? get currentMediaContext => _currentMediaContext;

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _clearDetectedUrl();
    clearMediaContext();
  }
}
