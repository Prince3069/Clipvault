// services/share_target_service.dart
// COMPLETE - Universal Share Target Handler

import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/download_provider.dart';
import '../providers/premium_provider.dart';
import '../services/cobalt_api_service.dart';
import '../ui/screens/browser_download_screen.dart';

class ShareTargetService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/share_target');

  static ShareTargetService? _instance;
  static ShareTargetService get instance =>
      _instance ??= ShareTargetService._();

  ShareTargetService._();

  bool _isInitialized = false;
  String? _pendingSharedText;
  String? _pendingSharedMediaPath;
  bool _isProcessing = false;

  /// Initialize the share target service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _channel.setMethodCallHandler(_handleMethodCall);
      _isInitialized = true;
      print('📤 ShareTargetService initialized');
    } catch (e) {
      print('❌ ShareTargetService init error: $e');
    }
  }

  /// Handle method calls from native Android
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onShareReceived':
          final args = call.arguments as Map<dynamic, dynamic>;
          final text = args['text'] as String? ?? '';
          final mediaPath = args['uri'] as String? ?? '';
          print('📤 Share received: ${text.isNotEmpty ? text : mediaPath}');
          if (text.trim().isNotEmpty) {
            _handleSharedText(text);
          } else if (mediaPath.trim().isNotEmpty) {
            _handleSharedMedia(mediaPath);
          }
          return true;

        case 'onMultipleShareReceived':
          final args = call.arguments as Map<dynamic, dynamic>;
          final texts = args['texts'] as List<dynamic>? ?? [];
          final mediaPaths = args['uris'] as List<dynamic>? ?? [];
          print('📤 Multiple shares received: ${texts.length + mediaPaths.length} items');
          if (texts.isNotEmpty) {
            _handleSharedText(texts.first as String);
          } else if (mediaPaths.isNotEmpty) {
            _handleSharedMedia(mediaPaths.first as String);
          }
          return true;

        default:
          print('⚠️ Unknown share target method: ${call.method}');
          return false;
      }
    } catch (e) {
      print('❌ Share target handler error: $e');
      return false;
    }
  }

  /// Handle shared text (URL)
  void _handleSharedText(String text) {
    if (_isProcessing) return;
    if (text.trim().isEmpty) return;

    _pendingSharedText = text.trim();

    // Check if it's a supported URL
    if (CobaltApiService.isSupportedUrl(text)) {
      _processSharedUrl(text);
    } else {
      print('⚠️ Shared text is not a supported URL: $text');
    }
  }

  void _handleSharedMedia(String path) {
    if (path.trim().isEmpty) return;
    _pendingSharedMediaPath = path.trim();
    _onSharedMedia?.call(path.trim());
  }

  /// Process a shared URL
  Future<void> _processSharedUrl(String url) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      print('📤 Processing shared URL: $url');

      // Get the current context (requires a BuildContext)
      // We'll use a different approach - send to the home screen via event
      _notifyFlutter(url);
    } catch (e) {
      print('❌ Process shared URL error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Notify Flutter UI about the shared URL
  void _notifyFlutter(String url) {
    // This will be handled by the ShareTargetListener in the app
    // We'll use a simple callback approach
    _onShareReceived?.call(url);
  }

  /// Callback for when a share is received
  Function(String)? _onShareReceived;
  Function(String)? _onSharedMedia;

  /// Register a callback to handle shared URLs
  void onShareReceived(Function(String) callback) {
    _onShareReceived = callback;
  }

  /// Register a callback to handle a copied incoming media path.
  void onSharedMedia(Function(String) callback) {
    _onSharedMedia = callback;
  }

  /// Get the pending shared text (clears it after reading)
  String? getPendingSharedText() {
    final text = _pendingSharedText;
    _pendingSharedText = null;
    return text;
  }

  /// Get a pending shared local media path, if any.
  String? getPendingSharedMediaPath() {
    final path = _pendingSharedMediaPath;
    _pendingSharedMediaPath = null;
    return path;
  }

  /// Check if there's a pending share
  bool get hasPendingShare =>
      _pendingSharedText != null || _pendingSharedMediaPath != null;

  /// Clear the pending share
  void clearPendingShare() {
    _pendingSharedText = null;
    _pendingSharedMediaPath = null;
  }

  /// Dispose the service
  void dispose() {
    _isInitialized = false;
    _onShareReceived = null;
    _onSharedMedia = null;
  }
}
