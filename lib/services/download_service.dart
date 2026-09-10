// services/download_service.dart
// CHANGES:
//  • MediaStore API — saves files via saveToMediaStore in MainActivity
//    (no MANAGE_EXTERNAL_STORAGE needed — Google Play approved approach)
//  • preferHD param — premium users get highest quality
// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';
import 'cobalt_api_service.dart';

class DownloadService {
  final MediaExtractorService _extractor = MediaExtractorService();

  // Platform channel to MainActivity's saveToMediaStore method
  static const _nativeBridge =
      MethodChannel('com.yourapp.allsocialdownloader/native');

  // ─── Single video download ────────────────────────────────────────────────

  Future<DownloadItem> downloadFromUrl(
    String url, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    bool preferHD = false,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final platform = MediaExtractorService.detectPlatform(url);

    var item = DownloadItem(
      id: id,
      url: url,
      fileName: 'media_$id.mp4',
      thumbnailUrl: '',
      sourceApp: platform,
      dateAdded: DateTime.now(),
      status: DownloadStatus.downloading,
    );

    try {
      onStatus?.call('🔍 Finding download link...');

      final result = await _extractor.extract(url, preferHD: preferHD);

      if (!result.ok) {
        final msg = result.errorMessage ?? 'Could not extract media.';
        onStatus?.call('❌ $msg');
        return item.copyWith(status: DownloadStatus.failed, errorMessage: msg);
      }

      final downloadUrl = result.url!;
      final ext = _detectExtension(downloadUrl, result.filename);
      final fileName = result.filename != null && result.filename!.isNotEmpty
          ? _sanitize(result.filename!)
          : '${platform}_${DateTime.now().millisecondsSinceEpoch}$ext';

      item = item.copyWith(fileName: fileName);

      // Step 1: Download to private temp cache (no permission needed)
      final tempPath = await _getTempPath(fileName);
      onStatus?.call('⬇️ Downloading...');

      final downloadedPath = await MediaExtractorService.downloadFile(
        downloadUrl,
        tempPath,
        onProgress: onProgress,
        onError: (e) {
          print('DL error: $e');
          onStatus?.call('❌ $e');
        },
      );

      if (downloadedPath == null) {
        return item.copyWith(
          status: DownloadStatus.failed,
          errorMessage: 'Download failed. Check your internet connection.',
        );
      }

      // Step 2: Move from temp cache → Download/ClipVaults/[Platform]/ via MediaStore
      // This is Google Play's approved method (no MANAGE_EXTERNAL_STORAGE)
      onStatus?.call('💾 Saving...');
      final finalPath = await _moveToMediaStore(
          downloadedPath, fileName, platform, _mimeType(fileName));

      onStatus?.call('✅ Saved!');
      return item.copyWith(
        localPath: finalPath,
        status: DownloadStatus.completed,
        progress: 1.0,
        fileName: fileName,
      );
    } catch (e) {
      print('Unexpected error: $e');
      return item.copyWith(
        status: DownloadStatus.failed,
        errorMessage:
            'Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e}',
      );
    }
  }

  // ─── MediaStore helpers ───────────────────────────────────────────────────

  // Save to app's private temp folder first (zero permissions needed)
  Future<String> _getTempPath(String fileName) async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}/clipvaults_temp');
    await dir.create(recursive: true);
    return '${dir.path}/$fileName';
  }

  // Move completed file from temp to Download/ClipVaults/[Platform]/ via MediaStore.
  // Uses MainActivity.saveToMediaStore which calls Android's MediaStore API.
  // This is the Google Play approved method — no MANAGE_EXTERNAL_STORAGE needed.
  Future<String> _moveToMediaStore(
      String tempPath, String fileName, String platform, String mimeType) async {
    try {
      final result = await _nativeBridge.invokeMethod<Map>('saveToMediaStore', {
        'sourcePath': tempPath,
        'fileName': fileName,
        'platform': platform,
        'mimeType': mimeType,
      });
      final success = result?['success'] as bool? ?? false;
      if (success) {
        final path = result?['path'] as String?;
        print('✅ MediaStore saved: $path');
        return path ?? tempPath;
      } else {
        print('MediaStore failed: ${result?['error']} — keeping temp file');
      }
    } catch (e) {
      print('MediaStore channel error: $e');
    }
    // Fallback: return temp path so the download isn't lost
    return tempPath;
  }

  String _mimeType(String fileName) {
    final lo = fileName.toLowerCase();
    if (lo.endsWith('.mp4'))  return 'video/mp4';
    if (lo.endsWith('.webm')) return 'video/webm';
    if (lo.endsWith('.mov'))  return 'video/quicktime';
    if (lo.endsWith('.mp3'))  return 'audio/mpeg';
    if (lo.endsWith('.m4a'))  return 'audio/mp4';
    if (lo.endsWith('.jpg') || lo.endsWith('.jpeg')) return 'image/jpeg';
    if (lo.endsWith('.png'))  return 'image/png';
    if (lo.endsWith('.gif'))  return 'image/gif';
    return 'video/mp4';
  }

  // ─── General helpers ──────────────────────────────────────────────────────

  String _detectExtension(String url, String? filename) {
    if (filename != null) {
      for (final ext in ['.mp4', '.webm', '.mov', '.mp3', '.m4a', '.jpg', '.png', '.gif']) {
        if (filename.toLowerCase().endsWith(ext)) return ext;
      }
    }
    final cleanUrl = url.split('?').first.toLowerCase();
    for (final ext in ['.mp4', '.webm', '.mov', '.mp3', '.m4a', '.jpg', '.png', '.gif']) {
      if (cleanUrl.endsWith(ext)) return ext;
    }
    return '.mp4';
  }

  String _sanitize(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }
}

// Progress model for playlist downloads
class PlaylistProgress {
  final int current;
  final int total;
  final String message;
  final bool isError;
  final bool isWarning;
  final bool isDone;

  PlaylistProgress(this.current, this.total, this.message,
      {this.isError = false, this.isWarning = false, this.isDone = false});

  double get fraction => total == 0 ? 0 : current / total;
}