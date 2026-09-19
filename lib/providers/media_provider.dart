// providers/media_provider.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/media_file.dart';
import '../services/permission_service.dart';
import '../services/platform_services/whatsapp_service.dart';
import '../services/native_bridge.dart';

class MediaProvider extends ChangeNotifier {
  final List<MediaFile> _allMedia = [];
  final List<MediaFile> _whatsappImages = [];
  final List<MediaFile> _whatsappVideos = [];
  bool _hasPermissions = false;
  bool _isLoading = false;
  String? _whatsappError;
  String? _lastDownloadError;

  List<MediaFile> get allMedia => List.unmodifiable(_allMedia);

  /// Recently viewed = last 10 media files sorted by viewedAt
  List<MediaFile> get recentlyViewed {
    final all = [..._allMedia, ..._whatsappImages, ..._whatsappVideos];
    all.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return all.take(10).toList();
  }

  List<MediaFile> get whatsappImages => List.unmodifiable(_whatsappImages);
  List<MediaFile> get whatsappVideos => List.unmodifiable(_whatsappVideos);
  bool get hasPermissions => _hasPermissions;
  bool get isLoading => _isLoading;
  String? get whatsappError => _whatsappError;
  String? get lastDownloadError => _lastDownloadError;

  MediaProvider() {
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      final ps = PermissionService();
      final state = await ps.getPermissionState();
      final statusFolderAccess =
          await WhatsAppService().hasStatusFolderAccess();
      // Allow if normal storage, all-files, or the persisted WhatsApp SAF tree is available.
      _hasPermissions =
          state.canAccessFiles || state.manageStorage || statusFolderAccess;
    } catch (e) {
      _hasPermissions = false;
    }
    notifyListeners();
  }

  /// Refresh all media (WhatsApp + downloaded files)
  Future<void> refreshAllMedia() async {
    await _checkPermissions();

    _isLoading = true;
    notifyListeners();

    try {
      final hasStatusAccess = await WhatsAppService().hasStatusFolderAccess();
      if (hasStatusAccess) {
        await refreshWhatsAppStatuses();
      } else {
        _whatsappImages.clear();
        _whatsappVideos.clear();
        _whatsappError = null;
      }
      // MediaStore indexing remains available without a WhatsApp SAF grant.
      await _loadDownloadedFiles();
    } catch (e) {
      print('Error refreshing media: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load WhatsApp statuses
  Future<void> refreshWhatsAppStatuses({bool isBusiness = false}) async {
    _whatsappError = null;
    notifyListeners();
    try {
      final service = WhatsAppService();
      final statuses = await service
          .getStatuses(isBusinessWhatsApp: isBusiness)
          .timeout(const Duration(seconds: 25));

      _whatsappImages.clear();
      _whatsappVideos.clear();

      for (final status in statuses) {
        final mediaFile = MediaFile(
          id: status.id,
          path: status.path,
          fileName: status.id,
          fileSize: _getFileSize(status.path),
          isVideo: status.isVideo,
          sourceApp: 'whatsapp',
          createdAt: status.createdAt,
          viewedAt: status.createdAt,
          isDownloaded: false,
        );

        if (status.isVideo) {
          _whatsappVideos.add(mediaFile);
        } else {
          _whatsappImages.add(mediaFile);
        }
      }

      // Sort newest first
      _whatsappImages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _whatsappVideos.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      notifyListeners();
    } on TimeoutException {
      _whatsappImages.clear();
      _whatsappVideos.clear();
      _whatsappError = 'The WhatsApp folder scan took too long. Tap Retry.';
      notifyListeners();
    } catch (e) {
      print('Error loading WhatsApp statuses: $e');
      _whatsappImages.clear();
      _whatsappVideos.clear();
      _whatsappError =
          'Could not read the selected WhatsApp folder. Tap Retry.';
      notifyListeners();
    }
  }

  /// Load previously downloaded files
  Future<void> _loadDownloadedFiles() async {
    try {
      // Modern Android owns public downloads through MediaStore. Query those
      // rows first so the Library survives process restarts and does not depend
      // on raw directory traversal or broad storage permission.
      final indexedRows = await NativeBridge.queryClipVaultMedia();
      if (indexedRows.isNotEmpty) {
        final indexed = indexedRows
            .map((row) {
              final path = (row['path'] as String?) ?? '';
              final fileName = (row['fileName'] as String?) ?? 'media';
              final createdMillis = (row['createdAt'] as num?)?.toInt() ?? 0;
              return MediaFile(
                id: (row['id'] as String?) ?? path.hashCode.toString(),
                path: path,
                fileName: fileName,
                fileSize: (row['fileSize'] as num?)?.toInt() ?? 0,
                isVideo: row['isVideo'] == true,
                sourceApp: (row['sourceApp'] as String?) ??
                    _detectPlatformFromPath(path),
                createdAt: createdMillis > 0
                    ? DateTime.fromMillisecondsSinceEpoch(createdMillis)
                    : DateTime.now(),
                viewedAt: createdMillis > 0
                    ? DateTime.fromMillisecondsSinceEpoch(createdMillis)
                    : DateTime.now(),
                isDownloaded: true,
              );
            })
            .where((item) => item.path.isNotEmpty)
            .toList();
        indexed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _allMedia
          ..clear()
          ..addAll(indexed);
        notifyListeners();
        return;
      }

      const downloadBases = [
        '/storage/emulated/0/Download/ClipVaults',
        // Backward compatibility for files saved by older ClipVault builds.
        '/storage/emulated/0/Download/SaveIt',
      ];
      final entities = <FileSystemEntity>[];
      for (final base in downloadBases) {
        final dir = Directory(base);
        if (await dir.exists()) {
          entities.addAll(dir.listSync(recursive: true));
        }
      }
      if (entities.isEmpty) return;
      final downloaded = <MediaFile>[];

      for (final entity in entities) {
        if (entity is File && _isMediaFile(entity.path)) {
          final stat = entity.statSync();
          final name = entity.path.split('/').last;
          downloaded.add(MediaFile(
            id: entity.path.hashCode.toString(),
            path: entity.path,
            fileName: name,
            fileSize: stat.size,
            isVideo: _isVideoFile(entity.path),
            sourceApp: _detectPlatformFromPath(entity.path),
            createdAt: stat.modified,
            viewedAt: stat.accessed,
            isDownloaded: true,
          ));
        }
      }

      downloaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _allMedia.clear();
      _allMedia.addAll(downloaded);
      notifyListeners();
    } catch (e) {
      print('Error loading downloaded files: $e');
    }
  }

  /// Import a video or image received from Android’s Sharesheet.
  Future<bool> importSharedMedia(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return false;
      final stat = await source.stat();
      final name = source.path.split('/').last;
      final isVideo = _isVideoFile(source.path);
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      final mimeType = isVideo
          ? (ext == 'webm' ? 'video/webm' : 'video/mp4')
          : (ext == 'png' ? 'image/png' : 'image/jpeg');
      final publicPath = await NativeBridge.saveToMediaStore(
        sourcePath: source.path,
        fileName:
            'shared_${DateTime.now().millisecondsSinceEpoch}_${name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}',
        platform: 'Shared',
        mimeType: mimeType,
      );
      final finalPath = publicPath ?? source.path;
      _allMedia.removeWhere((item) => item.path == finalPath);
      _allMedia.insert(
        0,
        MediaFile(
          id: finalPath.hashCode.toString(),
          path: finalPath,
          fileName: name,
          fileSize: stat.size,
          isVideo: isVideo,
          sourceApp: 'shared',
          createdAt: DateTime.now(),
          viewedAt: DateTime.now(),
          isDownloaded: true,
        ),
      );
      notifyListeners();
      return true;
    } catch (e) {
      print('Error importing shared media: $e');
      return false;
    }
  }

  /// Download a media file (copy to Downloads/ClipVaults via MediaStore).
  ///
  /// Idempotent: WhatsApp status items are backed by a cached copy of the
  /// status file that the native side deletes once it's been permanently
  /// saved. Previously this method only ever updated `_allMedia`, so a
  /// WhatsApp item's `isDownloaded` flag never actually flipped to true —
  /// the grid kept showing the download button, a repeat tap tried to copy
  /// a source file that had already been deleted on the first successful
  /// save, and that repeat tap is what showed up as "Save failed".
  Future<bool> downloadMedia(MediaFile mediaFile) async {
    _lastDownloadError = null;

    // Already saved — don't re-touch a source file that may have already
    // been deleted after its first successful save.
    if (mediaFile.isDownloaded) return true;

    try {
      final sourceFile = File(mediaFile.path);
      if (!await sourceFile.exists()) {
        _lastDownloadError = 'Source file no longer exists — it may have '
            'already been saved.';
        return false;
      }

      final platform = mediaFile.sourceApp.isEmpty
          ? 'WhatsApp'
          : mediaFile.sourceApp[0].toUpperCase() +
              mediaFile.sourceApp.substring(1);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = mediaFile.path.contains('.')
          ? '.${mediaFile.path.split('.').last.toLowerCase()}'
          : (mediaFile.isVideo ? '.mp4' : '.jpg');
      final safeName = '${platform.toLowerCase()}_$timestamp$ext';
      final mimeType = _mimeTypeForExtension(ext, mediaFile.isVideo);

      final destPath = await NativeBridge.saveToMediaStore(
        sourcePath: sourceFile.path,
        fileName: safeName,
        platform: platform,
        mimeType: mimeType,
      );

      if (destPath == null || destPath.isEmpty) {
        _lastDownloadError =
            NativeBridge.lastMediaStoreError ?? 'Unknown error';
        return false;
      }

      _markDownloaded(mediaFile.id);

      // allMedia (what saved_screen.dart's folder counts read) is only
      // ever populated by this native query — flipping isDownloaded above
      // only updates the WhatsApp browse list, a completely separate list
      // the Saved screen never looks at. Without this call, a real,
      // successful save would sit invisible to the Saved tab until
      // something else forced a fresh query (a pull-to-refresh, or the
      // screen happening to remount) — which is exactly the bug reported.
      await _loadDownloadedFiles();
      notifyListeners();
      return true;
    } catch (e) {
      print('Error downloading media: $e');
      _lastDownloadError = e.toString();
      return false;
    }
  }

  /// Update the isDownloaded flag on an item wherever it actually lives —
  /// _allMedia, _whatsappImages, or _whatsappVideos.
  void _markDownloaded(String id) {
    final allIdx = _allMedia.indexWhere((m) => m.id == id);
    if (allIdx >= 0) {
      _allMedia[allIdx] = _allMedia[allIdx].copyWith(isDownloaded: true);
      return;
    }
    final imgIdx = _whatsappImages.indexWhere((m) => m.id == id);
    if (imgIdx >= 0) {
      _whatsappImages[imgIdx] =
          _whatsappImages[imgIdx].copyWith(isDownloaded: true);
      return;
    }
    final vidIdx = _whatsappVideos.indexWhere((m) => m.id == id);
    if (vidIdx >= 0) {
      _whatsappVideos[vidIdx] =
          _whatsappVideos[vidIdx].copyWith(isDownloaded: true);
    }
  }

  String _mimeTypeForExtension(String dotExt, bool isVideo) {
    switch (dotExt.toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.mov':
        return 'video/quicktime';
      case '.3gp':
        return 'video/3gpp';
      case '.mkv':
        return 'video/x-matroska';
      case '.webm':
        return 'video/webm';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.mp4':
        return 'video/mp4';
      default:
        return isVideo ? 'video/mp4' : 'image/jpeg';
    }
  }

  int getMediaCountByPlatform(String platform) {
    if (platform == 'whatsapp') {
      return _whatsappImages.length + _whatsappVideos.length;
    }
    return _allMedia
        .where((m) => m.sourceApp.toLowerCase() == platform.toLowerCase())
        .length;
  }

  // Helpers

  int _getFileSize(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
    }
  }

  bool _isMediaFile(String path) {
    const exts = [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      '3gp',
      'mp3',
      'm4a',
    ];
    final ext = path.toLowerCase().split('.').last;
    return exts.contains(ext);
  }

  bool _isVideoFile(String path) {
    const exts = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    final ext = path.toLowerCase().split('.').last;
    return exts.contains(ext);
  }

  String _detectPlatformFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('tiktok')) return 'tiktok';
    if (lower.contains('instagram')) return 'instagram';
    if (lower.contains('facebook')) return 'facebook';
    if (lower.contains('twitter') || lower.contains('/x/')) return 'twitter';
    if (lower.contains('whatsapp')) return 'whatsapp';
    return 'unknown';
  }
}
