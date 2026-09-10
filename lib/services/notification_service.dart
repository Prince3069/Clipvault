// services/notification_service.dart
// COMPLETE Notification Service

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  // Initialize the notification service
  static Future<void> init() async {
    if (_isInitialized || kIsWeb) return;

    try {
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _notifications.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      _isInitialized = true;
      print('✅ Notification Service initialized');
    } catch (e) {
      print('⚠️ Notification Service init error: $e');
    }
  }

  static void _onNotificationTap(NotificationResponse response) {
    // Handle notification tap
    print('Notification tapped: ${response.payload}');
  }

  // Show a download completion notification
  static Future<void> showDownloadComplete({
    required String title,
    required String message,
    String? payload,
  }) async {
    if (_isInitialized && !kIsWeb) {
      try {
        const AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          'download_channel',
          'Download Updates',
          channelDescription: 'Notifies when downloads are complete',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

        const DarwinNotificationDetails iosDetails =
            DarwinNotificationDetails();

        const NotificationDetails details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _notifications.show(
          0,
          title,
          message,
          details,
          payload: payload,
        );
      } catch (e) {
        print('⚠️ Failed to show notification: $e');
      }
    }
  }

  // Show a progress notification
  static Future<void> showDownloadProgress({
    required String title,
    required String message,
    required int progress,
    int maxProgress = 100,
  }) async {
    if (_isInitialized && !kIsWeb) {
      try {
        final AndroidNotificationDetails androidDetails =
            AndroidNotificationDetails(
          'download_channel',
          'Download Updates',
          channelDescription: 'Shows download progress',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          showProgress: true,
          progress: progress,
          maxProgress: maxProgress,
          icon: '@mipmap/ic_launcher',
        );

        const DarwinNotificationDetails iosDetails =
            DarwinNotificationDetails();

        final NotificationDetails details = NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        );

        await _notifications.show(
          1,
          title,
          message,
          details,
        );
      } catch (e) {
        print('⚠️ Failed to show progress notification: $e');
      }
    }
  }

  // Cancel all notifications
  static Future<void> cancelAll() async {
    if (_isInitialized && !kIsWeb) {
      await _notifications.cancelAll();
    }
  }

  // Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return false;
    try {
      final enabled = await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled ?? false;
    } catch (e) {
      return false;
    }
  }
}
