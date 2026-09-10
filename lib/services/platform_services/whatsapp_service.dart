// WhatsApp status loader with Android-version-aware path and native fallbacks.
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/services.dart';
import '../../models/status_item.dart';

class WhatsAppService {
  static bool _activeBusiness = false;

  static const MethodChannel _nativeChannel =
      MethodChannel('com.yourapp.allsocialdownloader/whatsapp');

  static const List<String> _normalPaths = [
    '/storage/emulated/0/WhatsApp/Media/.Statuses',
    '/sdcard/WhatsApp/Media/.Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    '/sdcard/Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    '/storage/emulated/0/WhatsApp/Media/Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/Statuses',
  ];

  static const List<String> _businessPaths = [
    '/storage/emulated/0/WhatsApp Business/Media/.Statuses',
    '/sdcard/WhatsApp Business/Media/.Statuses',
    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
    '/sdcard/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses',
  ];

  Future<bool> hasStatusFolderAccess({
    bool isBusinessWhatsApp = false,
  }) async {
    try {
      final result = await _nativeChannel.invokeMethod<bool>(
        'hasWhatsAppStatusAccess',
        <String, dynamic>{'business': isBusinessWhatsApp},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestStatusFolderAccess({
    bool isBusinessWhatsApp = false,
  }) async {
    try {
      final result = await _nativeChannel.invokeMethod<bool>(
        'requestWhatsAppStatusAccess',
        <String, dynamic>{'business': isBusinessWhatsApp},
      );
      return result ?? false;
    } catch (e) {
      print('Could not open WhatsApp folder picker: $e');
      return false;
    }
  }

  Future<List<StatusItem>> getStatuses({
    bool isBusinessWhatsApp = false,
  }) async {
    _activeBusiness = isBusinessWhatsApp;
    final cutoff = DateTime.now().subtract(const Duration(hours: 48));
    final preferred = isBusinessWhatsApp ? _businessPaths : _normalPaths;
    final fallback = isBusinessWhatsApp ? _normalPaths : _businessPaths;
    final paths = <String>[...preferred, ...fallback];

    print('Scanning WhatsApp status paths: ${paths.length} candidates');

    // First use the persisted SAF tree. This is the modern, permission-light
    // path and is the same one the user approved with “Use this folder”.
    final grantedStatuses = await _getStatusesViaNative(null)
        .timeout(const Duration(seconds: 22), onTimeout: () => null);
    // A non-null result means the persisted tree was read successfully. An
    // empty list is a valid “no recent statuses” result and must not trigger
    // repeated scans of unrelated fallback locations.
    if (grantedStatuses != null) {
      return grantedStatuses
          .where((item) => item.createdAt.isAfter(cutoff))
          .take(200)
          .toList();
    }

    // Legacy direct filesystem fallback for Android versions that expose the
    // WhatsApp status directory directly.
    for (final path in paths) {
      try {
        final directory = Directory(path);
        if (!await directory.exists()) continue;

        final statuses = (await _scanDirectory(directory))
            .where((item) => item.createdAt.isAfter(cutoff))
            .take(200)
            .toList();
        if (statuses.isNotEmpty) {
          print('Found ${statuses.length} statuses at $path');
          return statuses;
        }
      } catch (e) {
        print('Direct scan failed for $path: $e');
      }
    }

    // Scoped-storage devices may expose the directory only through native code.
    for (final path in paths) {
      final statuses = await _getStatusesViaNative(path);
      if (statuses != null && statuses.isNotEmpty) {
        return statuses.where((item) => item.createdAt.isAfter(cutoff)).take(200).toList();
      }
    }

    // Let the Android side auto-detect any alternative WhatsApp location.
    final nativeStatuses = await _getStatusesViaNative(null);
    if (nativeStatuses != null && nativeStatuses.isNotEmpty) {
      return nativeStatuses.where((item) => item.createdAt.isAfter(cutoff)).take(200).toList();
    }

    print('No WhatsApp statuses found. Open a status in WhatsApp first, then refresh.');
    return <StatusItem>[];
  }

  Future<List<StatusItem>> _scanDirectory(Directory directory) async {
    final statuses = <StatusItem>[];

    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;

        final path = entity.path;
        final lower = path.toLowerCase();
        final isVideo = _isVideoPath(lower);
        final isImage = _isImagePath(lower);
        if (!isVideo && !isImage) continue;

        try {
          final stat = await entity.stat();
          if (stat.size < 1000) continue;

          statuses.add(StatusItem(
            id: path,
            path: path,
            isVideo: isVideo,
            createdAt: stat.modified,
            isDownloaded: false,
          ));
        } catch (e) {
          print('Could not read WhatsApp file $path: $e');
        }
      }
    } catch (e) {
      print('Could not list WhatsApp directory ${directory.path}: $e');
    }

    statuses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return statuses.take(200).toList();
  }

  Future<List<StatusItem>?> _getStatusesViaNative(String? path) async {
    try {
      final raw = await _nativeChannel.invokeMethod<dynamic>(
        'getWhatsAppStatuses',
        <String, dynamic>{
          'path': path,
          'business': _activeBusiness,
        },
      );
      if (raw is! Map) return null;

      final rawPaths = raw['paths'];
      if (rawPaths is! List) return null;

      final statuses = <StatusItem>[];
      for (final value in rawPaths) {
        if (value is! String || value.isEmpty) continue;

        final file = File(value);
        try {
          if (!await file.exists()) continue;
          final stat = await file.stat();
          if (stat.size < 1000) continue;

          final lower = value.toLowerCase();
          final isVideo = _isVideoPath(lower);
          if (!isVideo && !_isImagePath(lower)) continue;

          statuses.add(StatusItem(
            id: value,
            path: value,
            isVideo: isVideo,
            createdAt: stat.modified,
            isDownloaded: false,
          ));
        } catch (_) {
          // Skip files that disappear or cannot be read during the scan.
        }
      }

      statuses.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return statuses.take(200).toList();
    } catch (e) {
      print('Native WhatsApp status fetch failed: $e');
      return null;
    }
  }

  bool _isVideoPath(String path) =>
      path.endsWith('.mp4') ||
      path.endsWith('.mov') ||
      path.endsWith('.3gp') ||
      path.endsWith('.mkv') ||
      path.endsWith('.avi') ||
      path.endsWith('.webm');

  bool _isImagePath(String path) =>
      path.endsWith('.jpg') ||
      path.endsWith('.jpeg') ||
      path.endsWith('.png') ||
      path.endsWith('.gif') ||
      path.endsWith('.webp');

  Future<String?> saveStatus(StatusItem status) async {
    try {
      final sourceFile = File(status.path);
      if (!await sourceFile.exists()) return null;

      final originalName = status.path.split('/').last;
      final dot = originalName.lastIndexOf('.');
      final base = dot > 0 ? originalName.substring(0, dot) : originalName;
      final extension = dot > 0
          ? originalName.substring(dot + 1)
          : (status.isVideo ? 'mp4' : 'jpg');
      final fileName =
          'whatsapp_${base}_${DateTime.now().millisecondsSinceEpoch}.$extension';

      final result = await _nativeChannel.invokeMethod<dynamic>(
        'saveToMediaStore',
        <String, dynamic>{
          'sourcePath': status.path,
          'fileName': fileName,
          'platform': 'whatsapp',
          'mimeType': status.isVideo ? 'video/mp4' : 'image/jpeg',
        },
      );

      if (result is Map && result['success'] == true) {
        return result['path'] as String?;
      }

      final destination =
          Directory('/storage/emulated/0/Download/ClipVaults/WhatsApp');
      await destination.create(recursive: true);
      final savedPath = '${destination.path}/$fileName';
      await sourceFile.copy(savedPath);
      try {
        await _nativeChannel.invokeMethod<void>('scanMediaFile', savedPath);
      } catch (_) {}
      return savedPath;
    } catch (e) {
      print('Error saving WhatsApp status: $e');
      return null;
    }
  }

  Future<bool> isWhatsAppInstalled() async {
    try {
      final result =
          await _nativeChannel.invokeMethod<bool>('isWhatsAppInstalled');
      if (result != null) return result;
    } catch (_) {}

    for (final path in [..._normalPaths, ..._businessPaths]) {
      try {
        if (await Directory(path).exists()) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<String?> getWhatsAppVersion() async {
    try {
      return await _nativeChannel.invokeMethod<String>('getWhatsAppVersion');
    } catch (_) {
      return null;
    }
  }
}