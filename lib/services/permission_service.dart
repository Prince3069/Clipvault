// services/permission_service.dart
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionState {
  final bool storage;
  final bool manageStorage;
  final bool photos;
  final bool videos;
  final bool notifications;
  final bool overlay;
  final bool accessibility;
  final int sdkVersion;

  const PermissionState({
    this.storage = false,
    this.manageStorage = false,
    this.photos = false,
    this.videos = false,
    this.notifications = false,
    this.overlay = false,
    this.accessibility = false,
    this.sdkVersion = 29,
  });

  bool get isAndroid13Plus => sdkVersion >= 33;
  bool get isAndroid11Plus => sdkVersion >= 30;

  /// The app can save its own downloads through MediaStore and can read
  /// WhatsApp statuses through the separately persisted SAF tree grant.
  /// Broad media and All files permissions are not required on modern Android.
  bool get canAccessFiles {
    if (isAndroid11Plus) return true;
    return storage;
  }

  /// True when the minimum required permissions are granted
  bool get allCriticalGranted => canAccessFiles;
}

class PermissionService {
  static const MethodChannel _channel =
      MethodChannel('com.yourapp.allsocialdownloader/permissions');

  static int? _sdkCache;

  // ─── SDK Version ─────────────────────────────────────────────────────────

  Future<int> getSdkVersion() async {
    if (_sdkCache != null) return _sdkCache!;
    if (!Platform.isAndroid) { _sdkCache = 0; return 0; }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      _sdkCache = info.version.sdkInt;
      return _sdkCache!;
    } catch (_) {
      _sdkCache = 29;
      return 29;
    }
  }

  // ─── State ────────────────────────────────────────────────────────────────

  Future<PermissionState> getPermissionState() async {
    final sdk = await getSdkVersion();
    bool storage = false, manageStorage = false, photos = false,
        videos = false, notifications = false, overlay = false,
        accessibility = false;

    try {
      if (sdk >= 33) {
        // Downloads are written through MediaStore. WhatsApp access is handled
        // by its own persisted ACTION_OPEN_DOCUMENT_TREE grant.
        notifications = await ph.Permission.notification.isGranted;
      } else if (sdk >= 30) {
        // Android 10+ does not need legacy storage permission for MediaStore.
        notifications = true;
      } else {
        storage = await ph.Permission.storage.isGranted;
        notifications = true;
      }
      overlay = await _checkOverlay();
      accessibility = await _checkAccessibility();
    } catch (e) {
      print('Permission state error: $e');
    }

    return PermissionState(
      storage: storage,
      manageStorage: manageStorage,
      photos: photos,
      videos: videos,
      notifications: notifications,
      overlay: overlay,
      accessibility: accessibility,
      sdkVersion: sdk,
    );
  }

  // ─── Request Core ─────────────────────────────────────────────────────────

  Future<bool> requestCorePermissions() async {
    final sdk = await getSdkVersion();
    try {
      // Modern Android uses MediaStore for app-created downloads and SAF for
      // the user-selected WhatsApp status directory. Ask only for the legacy
      // permission on Android 9 and below.
      if (sdk >= 30) return true;
      return (await ph.Permission.storage.request()).isGranted;
    } catch (e) {
      print('Request core error: $e');
      return false;
    }
  }

  /// Notifications are optional and are requested only when the user enables
  /// download notifications, never during onboarding.
  Future<bool> requestNotificationPermission() async {
    try {
      final sdk = await getSdkVersion();
      if (sdk < 33) return true;
      return (await ph.Permission.notification.request()).isGranted;
    } catch (e) {
      print('Notification permission error: $e');
      return false;
    }
  }

  // ─── Overlay ──────────────────────────────────────────────────────────────

  Future<bool> hasOverlayPermission() => _checkOverlay();

  Future<bool> requestOverlayPermission() async {
    try {
      try {
        final r = await _channel.invokeMethod<bool>('requestSystemAlertWindow');
        if (r != null) return r;
      } catch (_) {}
      return (await ph.Permission.systemAlertWindow.request()).isGranted;
    } catch (e) {
      print('Overlay request error: $e');
      return false;
    }
  }

  // ─── Accessibility ────────────────────────────────────────────────────────

  Future<bool> isAccessibilityEnabled() => _checkAccessibility();

  /// Opens accessibility settings — on Android 12+, user must first enable
  /// "Allow restricted settings" in App Info → ⋮ → Allow restricted settings
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {
      try {
        await ph.openAppSettings();
      } catch (e) {
        print('Cannot open accessibility settings: $e');
      }
    }
  }

  /// Opens the App Info page for this app — user can then enable restricted settings
  Future<void> openAppInfoSettings() async {
    try {
      await _channel.invokeMethod('openAppInfo');
    } catch (_) {
      try {
        await ph.openAppSettings();
      } catch (e) {
        print('Cannot open app info: $e');
      }
    }
  }

  Future<void> launchAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (e) {
      print('Cannot open app settings: $e');
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<bool> _checkManageStorage() async {
    try {
      try {
        final r = await _channel.invokeMethod<bool>('hasManageExternalStorage');
        if (r != null) return r;
      } catch (_) {}
      return await ph.Permission.manageExternalStorage.isGranted;
    } catch (_) { return false; }
  }

  Future<bool> _requestManageStorage() async {
    try {
      try {
        final r = await _channel.invokeMethod<bool>('requestManageExternalStorage');
        if (r != null) return r;
      } catch (_) {}
      return (await ph.Permission.manageExternalStorage.request()).isGranted;
    } catch (_) { return false; }
  }

  Future<bool> _checkOverlay() async {
    try {
      try {
        final r = await _channel.invokeMethod<bool>('hasSystemAlertWindow');
        if (r != null) return r;
      } catch (_) {}
      return await ph.Permission.systemAlertWindow.isGranted;
    } catch (_) { return false; }
  }

  Future<bool> _checkAccessibility() async {
    try {
      final r = await _channel.invokeMethod<bool>('isAccessibilityServiceEnabled');
      return r ?? false;
    } catch (_) { return false; }
  }
}
