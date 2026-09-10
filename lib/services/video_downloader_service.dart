// services/video_downloader_service.dart - Advanced video downloader with URL extraction
// ignore_for_file: avoid_print, unused_import

import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/media_file.dart';
import '../models/download_item.dart';
import 'storage_service.dart';
import 'native_bridge.dart';
import 'download_service.dart';

class VideoDownloaderService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/video_downloader');

  static VideoDownloaderService? _instance;
  static VideoDownloaderService get instance =>
      _instance ??= VideoDownloaderService._();

  VideoDownloaderService._();

  final Dio _dio = Dio();
  final StorageService _storageService = StorageService();
  final DownloadService _workingDownloader = DownloadService();
  final Map<String, CancelToken> _activeDownloads = {};

  // URL patterns for different platforms
  static const Map<String, List<String>> _urlPatterns = {
    'tiktok': [
      r'https?://(?:www\.)?tiktok\.com/@[\w.-]+/video/\d+',
      r'https?://(?:m\.)?tiktok\.com/v/\d+',
      r'https?://vm\.tiktok\.com/[\w]+',
      r'https?://(?:www\.)?tiktok\.com/t/[\w]+',
    ],
    'instagram': [
      r'https?://(?:www\.)?instagram\.com/p/[\w-]+',
      r'https?://(?:www\.)?instagram\.com/reel/[\w-]+',
      r'https?://(?:www\.)?instagram\.com/stories/[\w.-]+/\d+',
      r'https?://(?:www\.)?instagram\.com/tv/[\w-]+',
    ],
    'facebook': [
      r'https?://(?:www\.)?facebook\.com/watch/?\?v=\d+',
      r'https?://(?:www\.)?facebook\.com/[\w.-]+/videos/\d+',
      r'https?://(?:www\.)?facebook\.com/reel/\d+',
      r'https?://fb\.watch/[\w-]+',
    ],
    'twitter': [
      r'https?://(?:www\.)?twitter\.com/[\w]+/status/\d+',
      r'https?://(?:www\.)?x\.com/[\w]+/status/\d+',
      r'https?://t\.co/[\w]+',
    ],
  };

  /// Initialize the video downloader service
  Future<void> initialize() async {
    try {
      print('🎬 Initializing VideoDownloaderService...');

      // Configure Dio
      _dio.options.headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
      };

      _dio.options.connectTimeout = const Duration(seconds: 30);
      _dio.options.receiveTimeout = const Duration(minutes: 5);

      print('✅ VideoDownloaderService initialized');
    } catch (e) {
      print('❌ Error initializing VideoDownloaderService: $e');
    }
  }

  /// Download through the canonical extractor used by the main download flow.
  /// The older implementation below is retained only for backwards-compatible
  /// helper methods; routing never uses its placeholder endpoints now.
  Future<bool> downloadFromUrl(
    String url,
    Map<String, dynamic> mediaInfo, {
    Function(double)? onProgress,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      onStatusUpdate?.call('Finding download link...');
      final result = await _workingDownloader.downloadFromUrl(
        url,
        onProgress: onProgress,
        onStatus: onStatusUpdate,
      );
      final success = result.status == DownloadStatus.completed;
      onStatusUpdate?.call(success ? 'Download completed' : 'Download failed');
      return success;
    } catch (e) {
      print('❌ Error downloading from URL: $e');
      onStatusUpdate?.call('Download error');
      return false;
    }
  }

  /// Extract download URL from various platforms
  Future<Map<String, dynamic>?> _extractDownloadUrl(
      String url, String platform) async {
    try {
      switch (platform) {
        case 'tiktok':
          return await _extractTikTokUrl(url);
        case 'instagram':
          return await _extractInstagramUrl(url);
        case 'facebook':
          return await _extractFacebookUrl(url);
        case 'twitter':
          return await _extractTwitterUrl(url);
        default:
          return null;
      }
    } catch (e) {
      print('❌ Error extracting download URL for $platform: $e');
      return null;
    }
  }

  /// Extract TikTok video URL using public API
  Future<Map<String, dynamic>?> _extractTikTokUrl(String url) async {
    try {
      print('🎵 Extracting TikTok URL...');

      // Method 1: Try snaptik.app API
      try {
        final snapTikResult = await _trySnapTikAPI(url);
        if (snapTikResult != null) return snapTikResult;
      } catch (e) {
        print('⚠️ SnapTik API failed: $e');
      }

      // Method 2: Try ssstik.io API
      try {
        final sssTikResult = await _trySssTikAPI(url);
        if (sssTikResult != null) return sssTikResult;
      } catch (e) {
        print('⚠️ SssTik API failed: $e');
      }

      // Method 3: Try tikmate.app API
      try {
        final tikMateResult = await _tryTikMateAPI(url);
        if (tikMateResult != null) return tikMateResult;
      } catch (e) {
        print('⚠️ TikMate API failed: $e');
      }

      // Method 4: Fallback - try direct extraction (placeholder)
      return await _tryDirectTikTokExtraction(url);
    } catch (e) {
      print('❌ Error extracting TikTok URL: $e');
      return null;
    }
  }

  /// Try SnapTik API for TikTok download
  Future<Map<String, dynamic>?> _trySnapTikAPI(String url) async {
    try {
      // This is a placeholder - replace with actual SnapTik API implementation
      print('🔧 Trying SnapTik API...');

      final response = await _dio.post(
        'https://snaptik.app/api',
        data: {'url': url},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Referer': 'https://snaptik.app/',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        // Parse the response and extract download URL
        // This is a placeholder structure
        if (data['success'] == true && data['data'] != null) {
          return {
            'downloadUrl': data['data']['download_url'],
            'fileName': data['data']['title'] + '.mp4',
            'title': data['data']['title'],
            'thumbnail': data['data']['thumbnail'],
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ SnapTik API error: $e');
      return null;
    }
  }

  /// Try SssTik API for TikTok download
  Future<Map<String, dynamic>?> _trySssTikAPI(String url) async {
    try {
      print('🔧 Trying SssTik API...');

      // This is a placeholder - replace with actual SssTik API implementation
      final response = await _dio.post(
        'https://ssstik.io/abc',
        data: {
          'id': url,
          'locale': 'en',
          'tt': 'placeholder_token', // You'll need to get this from their site
        },
        options: Options(
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'Referer': 'https://ssstik.io/',
          },
        ),
      );

      if (response.statusCode == 200) {
        // Parse HTML response and extract download links
        final htmlContent = response.data as String;

        // Use regex to extract download URL from HTML
        final urlMatch =
            RegExp(r'href="([^"]*)" download').firstMatch(htmlContent);
        if (urlMatch != null) {
          final downloadUrl = urlMatch.group(1);
          return {
            'downloadUrl': downloadUrl,
            'fileName': 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4',
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ SssTik API error: $e');
      return null;
    }
  }

  /// Try TikMate API for TikTok download
  Future<Map<String, dynamic>?> _tryTikMateAPI(String url) async {
    try {
      print('🔧 Trying TikMate API...');

      // Placeholder for TikMate API implementation
      // You can implement this similar to the above methods

      return null;
    } catch (e) {
      print('❌ TikMate API error: $e');
      return null;
    }
  }

  /// Direct TikTok extraction (fallback method)
  Future<Map<String, dynamic>?> _tryDirectTikTokExtraction(String url) async {
    try {
      print('🔧 Trying direct TikTok extraction...');

      // This is where you'd implement your own server-side scraping
      // For now, return a placeholder

      // TODO: Replace with your own server endpoint
      final response = await _dio.post(
        'https://your-server.com/api/extract-tiktok',
        data: {'url': url},
        options: Options(
          headers: {'Content-Type': 'application/json'},
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return {
          'downloadUrl': data['download_url'],
          'fileName': data['filename'],
          'title': data['title'],
        };
      }

      return null;
    } catch (e) {
      print('❌ Direct TikTok extraction error: $e');
      // Return a mock response for testing
      return {
        'downloadUrl': 'https://example.com/mock_tiktok_video.mp4',
        'fileName': 'tiktok_mock_${DateTime.now().millisecondsSinceEpoch}.mp4',
        'title': 'Mock TikTok Video',
      };
    }
  }

  /// Extract Instagram video URL
  Future<Map<String, dynamic>?> _extractInstagramUrl(String url) async {
    try {
      print('📸 Extracting Instagram URL...');

      // Instagram is more complex due to authentication requirements
      // You'll need to implement server-side extraction

      // TODO: Implement Instagram extraction via your server
      final response = await _dio.post(
        'https://your-server.com/api/extract-instagram',
        data: {'url': url},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return {
          'downloadUrl': data['download_url'],
          'fileName': data['filename'],
        };
      }

      // Mock response for testing
      return {
        'downloadUrl': 'https://example.com/mock_instagram_video.mp4',
        'fileName':
            'instagram_mock_${DateTime.now().millisecondsSinceEpoch}.mp4',
      };
    } catch (e) {
      print('❌ Instagram extraction error: $e');
      return null;
    }
  }

  /// Extract Facebook video URL
  Future<Map<String, dynamic>?> _extractFacebookUrl(String url) async {
    try {
      print('📘 Extracting Facebook URL...');

      // Facebook videos are often protected, server-side extraction needed
      // Mock response for now
      return {
        'downloadUrl': 'https://example.com/mock_facebook_video.mp4',
        'fileName':
            'facebook_mock_${DateTime.now().millisecondsSinceEpoch}.mp4',
      };
    } catch (e) {
      print('❌ Facebook extraction error: $e');
      return null;
    }
  }

  /// Extract Twitter/X video URL
  Future<Map<String, dynamic>?> _extractTwitterUrl(String url) async {
    try {
      print('🐦 Extracting Twitter URL...');

      // Twitter/X videos can be extracted from API or direct parsing
      // Mock response for now
      return {
        'downloadUrl': 'https://example.com/mock_twitter_video.mp4',
        'fileName': 'twitter_mock_${DateTime.now().millisecondsSinceEpoch}.mp4',
      };
    } catch (e) {
      print('❌ Twitter extraction error: $e');
      return null;
    }
  }

  /// Download file from direct URL
  Future<bool> _downloadFile(
    String url,
    String fileName,
    String platform, {
    Function(double)? onProgress,
    Function(String)? onStatusUpdate,
  }) async {
    try {
      // Get download directory
      final downloadDir =
          await _storageService.getPlatformDownloadPath(platform);
      final filePath = '$downloadDir/$fileName';

      print('📁 Downloading to: $filePath');

      // Create cancel token for this download
      final cancelToken = CancelToken();
      _activeDownloads[fileName] = cancelToken;

      onStatusUpdate?.call('Downloading...');

      // Download with progress tracking
      await _dio.download(
        url,
        filePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            onProgress?.call(progress);

            final receivedMB = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMB = (total / 1024 / 1024).toStringAsFixed(1);
            onStatusUpdate?.call('Downloading... $receivedMB MB / $totalMB MB');
          }
        },
      );

      // Remove from active downloads
      _activeDownloads.remove(fileName);

      // Verify file was downloaded
      final file = File(filePath);
      if (await file.exists() && await file.length() > 0) {
        // Make file visible in gallery
        await _storageService.scanMediaFile(filePath);

        print('✅ File downloaded successfully: $filePath');
        onStatusUpdate?.call('Download completed');
        return true;
      } else {
        print('❌ Downloaded file is empty or doesn\'t exist');
        onStatusUpdate?.call('Download failed - file is empty');
        return false;
      }
    } catch (e) {
      _activeDownloads.remove(fileName);
      print('❌ Error downloading file: $e');
      onStatusUpdate?.call('Download error: $e');
      return false;
    }
  }

  /// Detect platform from URL
  String _detectPlatformFromUrl(String url) {
    final cleanUrl = url.toLowerCase();

    for (final platform in _urlPatterns.keys) {
      final patterns = _urlPatterns[platform]!;
      for (final pattern in patterns) {
        if (RegExp(pattern, caseSensitive: false).hasMatch(cleanUrl)) {
          return platform;
        }
      }
    }

    return 'unknown';
  }

  /// Check if URL is supported
  bool isSupportedUrl(String url) {
    return _detectPlatformFromUrl(url) != 'unknown';
  }

  /// Get supported platforms
  List<String> getSupportedPlatforms() {
    return _urlPatterns.keys.toList();
  }

  /// Cancel active download
  Future<void> cancelDownload(String fileName) async {
    try {
      final cancelToken = _activeDownloads[fileName];
      if (cancelToken != null) {
        cancelToken.cancel('Download cancelled by user');
        _activeDownloads.remove(fileName);
        print('🚫 Download cancelled: $fileName');
      }
    } catch (e) {
      print('❌ Error cancelling download: $e');
    }
  }

  /// Get active downloads count
  int get activeDownloadsCount => _activeDownloads.length;

  /// Get active download file names
  List<String> get activeDownloadFiles => _activeDownloads.keys.toList();

  /// Test URL extraction without downloading
  Future<Map<String, dynamic>?> testUrlExtraction(String url) async {
    try {
      final platform = _detectPlatformFromUrl(url);
      if (platform == 'unknown') return null;

      return await _extractDownloadUrl(url, platform);
    } catch (e) {
      print('❌ Error testing URL extraction: $e');
      return null;
    }
  }

  /// Get download statistics
  Map<String, dynamic> getStatistics() {
    return {
      'activeDownloads': activeDownloadsCount,
      'supportedPlatforms': getSupportedPlatforms(),
      'downloadPaths': _urlPatterns.keys.map((platform) async {
        return {
          platform: await _storageService.getPlatformDownloadPath(platform)
        };
      }).toList(),
    };
  }

  /// Dispose resources
  void dispose() {
    // Cancel all active downloads
    for (final cancelToken in _activeDownloads.values) {
      cancelToken.cancel('Service disposed');
    }
    _activeDownloads.clear();
    _dio.close();
  }
}
