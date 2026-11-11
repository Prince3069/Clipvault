// providers/notification_provider.dart
// COMPLETE - FCM token management + foreground notification handling
//
// The app already had a NotificationService for LOCAL "download complete"
// alerts (see services/notification_service.dart). This is different: it's
// the FCM path for messages the SERVER pushes — streak reminders, and
// anything else you send from Firebase Console later.
//
// Token handling: FCM tokens can be rotated by Google at any time. This
// listens for refreshes and re-saves to Firestore, so a stale token never
// leaves you unable to reach a user.

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level handler for messages received while the app is fully
/// terminated or in background. Must be a top-level function (not a
/// class method) — Firebase calls it outside any Flutter app context.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('Background FCM: ${message.messageId} / ${message.data}');
  // Nothing to do here for now — FCM automatically displays the
  // notification when the app is backgrounded. Future: handle silent
  // data-only messages (e.g. background sync triggers).
}

class NotificationProvider extends ChangeNotifier {
  static const String _baseUrl =
      'https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  bool _initialized = false;
  String? _currentToken;
  bool _permissionGranted = false;
  String? _pendingDeepLink;

  bool get permissionGranted => _permissionGranted;
  String? get currentToken => _currentToken;

  /// Called once from main.dart before runApp. Sets up the background
  /// handler, requests permission, and registers the token.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // Background handler must be registered before any other FCM call.
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // iOS foreground presentation options (no-op on Android but safe).
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Permission: on iOS this shows the system prompt; on Android 13+
      // it shows the POST_NOTIFICATIONS prompt; on older Android it just
      // returns granted without any UI.
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      _permissionGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;

      // Register the token with the server. The token can rotate at any
      // point (app reinstall, Play Services update, etc.) — the refresh
      // listener below handles that.
      if (_permissionGranted) {
        await _registerToken();
        _messaging.onTokenRefresh.listen((newToken) {
          _currentToken = newToken;
          _saveToken(newToken);
        });
      }

      // Tap handling. When the user taps a notification while the app is
      // backgrounded (but not killed), onMessageOpenedApp fires.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // When the app was fully terminated and tapped to open, getInitialMessage
      // returns the message that launched it. Must be awaited ONCE at startup.
      final initial = await _messaging.getInitialMessage();
      if (initial != null) {
        _handleNotificationTap(initial);
      }

      // Foreground messages don't show a system notification by default on
      // Android — you'd need a local notification channel. Rather than
      // duplicating NotificationService's channel here, foreground FCM
      // messages are treated as silent (just for future in-app handling).
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('Foreground FCM: ${message.notification?.title}');
      });
    } catch (e) {
      debugPrint('NotificationProvider initialize error: $e');
    }
  }

  Future<void> _registerToken() async {
    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      _currentToken = token;
      await _saveToken(token);
    } catch (e) {
      debugPrint('FCM token registration error: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final idToken = await user.getIdToken();
      if (idToken == null) return;

      final response = await http
          .post(
            Uri.parse('$_baseUrl/registerFcmToken'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'token': token, 'platform': 'android'}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        debugPrint('FCM token registered with server');
      } else {
        debugPrint('FCM token registration failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('FCM token save error: $e');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    // The server sends a 'deeplink' data field when it wants to route the
    // user somewhere specific (e.g. 'coach' to open the AI Content Coach).
    // If a screen isn't ready to consume it yet, it stays pending here.
    final link = message.data['deeplink'] as String?;
    if (link != null && link.isNotEmpty) {
      _pendingDeepLink = link;
      notifyListeners();
    }
  }

  /// Called by a screen (e.g. MainNavigationScreen) to consume and clear
  /// the pending deeplink, then navigate accordingly.
  String? consumePendingDeepLink() {
    final link = _pendingDeepLink;
    _pendingDeepLink = null;
    return link;
  }

  /// Called when the account links or switches — re-registers the token
  /// so it's attached to the correct UID. Without this, a token saved
  /// while the user was anonymous would keep receiving pushes even after
  /// they signed into a different account on the same device.
  Future<void> reregisterForCurrentUser() async {
    if (!_permissionGranted) return;
    await _registerToken();
  }

  /// Whether the person has ever completed a download (used to decide
  /// whether the streak reminder is worth sending). Not currently used
  /// here — reserved for the server-side job.
  Future<bool> hasEverDownloaded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_ever_downloaded') ?? false;
  }
}
