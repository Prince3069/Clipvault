// providers/download_provider.dart
// ADDED: Auto-sync to Cloud Vault after successful download
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_item.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../services/cloud_vault_service.dart';

extension NotificationServiceProgressExtension on NotificationService {
  void showDownloadNotification({
    required int id,
    required String title,
    required String body,
    required bool isComplete,
  }) {
    // NotificationService implementation is provided elsewhere in the app.
    // This compatibility method keeps the download provider compiling when
    // the underlying service does not expose a native method with this name.
    print('Notification[$id]: $title - $body');
  }

  void showDownloadProgressNotification({
    required int id,
    required String title,
    required double progress,
  }) {
    final percent = (progress * 100).clamp(0.0, 100.0).toStringAsFixed(0);
    showDownloadNotification(
      id: id,
      title: title,
      body: '$percent%',
      isComplete: false,
    );
  }
}

class DownloadProvider extends ChangeNotifier {
  final List<DownloadItem> _downloads = [];
  final DownloadService _downloadService = DownloadService();
  final NotificationService _notificationService = NotificationService();
  final CloudVaultService _cloudVaultService = CloudVaultService();

  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  List<DownloadItem> get activeDownloads =>
      _downloads.where((d) => d.status == DownloadStatus.downloading).toList();

  Future<void> downloadFromUrl(
    String url, {
    void Function(double progress)? onProgress,
    void Function(String status)? onStatus,
    // Called after a SUCCESSFUL download — reduces free-user counter.
    // Pass () => premiumProvider.recordDownload() from the calling widget.
    Future<void> Function()? onRecordDownload,
    // true for premium users → DownloadService requests highest quality
    bool preferHD = false,
  }) async {
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();
    final tempItem = DownloadItem(
      id: uniqueId,
      url: url,
      fileName: 'Preparing...',
      thumbnailUrl: '',
      sourceApp: '',
      dateAdded: DateTime.now(),
      status: DownloadStatus.downloading,
    );

    _downloads.add(tempItem);
    notifyListeners();

    try {
      final notifId = int.parse(uniqueId.substring(uniqueId.length - 7));
      _notificationService.showDownloadProgressNotification(
          id: notifId, title: 'Downloading...', progress: 0.0);

      final result = await _downloadService.downloadFromUrl(
        url,
        preferHD: preferHD,
        onProgress: (p) {
          final idx = _downloads.indexWhere((d) => d.id == uniqueId);
          if (idx >= 0) {
            _downloads[idx] = _downloads[idx].copyWith(progress: p);
            notifyListeners();
          }
          onProgress?.call(p);
        },
        onStatus: onStatus,
      );

      final idx = _downloads.indexWhere((d) => d.id == uniqueId);
      if (idx >= 0) {
        _downloads[idx] = result.copyWith(id: uniqueId);
        notifyListeners();
      }

      // ── Record against free-user daily limit ────────────────────────────
      // Only fires on successful completion — failed/cancelled don't count.
      if (result.status == DownloadStatus.completed) {
        await onRecordDownload?.call();

        // ── Auto-sync to Cloud Vault ──────────────────────────────────────
        // Check if auto-sync is enabled in settings
        try {
          final prefs = await SharedPreferences.getInstance();
          final autoSync = prefs.getBool('autoSyncToCloud') ?? false;
          if (autoSync && result.localPath.isNotEmpty) {
            // Check if user is premium
            final isPremium = await _cloudVaultService.isPremiumActive();
            if (isPremium) {
              print('☁️ Auto-syncing to cloud: ${result.fileName}');
              await _cloudVaultService.uploadFile(
                localPath: result.localPath,
                fileName: result.fileName,
                source:
                    result.sourceApp.isNotEmpty ? result.sourceApp : 'download',
                onProgress: (p) {
                  // Optional: update notification with upload progress
                },
                onStatus: (msg) {
                  print('☁️ Cloud upload: $msg');
                },
              );
            }
          }
        } catch (e) {
          print('Auto-sync error: $e');
          // Non-critical - don't fail the download
        }
      }

      _notificationService.showDownloadNotification(
        id: notifId,
        title: result.status == DownloadStatus.completed
            ? 'Download Complete ✅'
            : 'Download Failed',
        body: result.fileName,
        isComplete: result.status == DownloadStatus.completed,
      );
    } catch (e) {
      print('Download error: $e');
      final idx = _downloads.indexWhere((d) => d.id == uniqueId);
      if (idx >= 0) {
        _downloads[idx] =
            _downloads[idx].copyWith(status: DownloadStatus.failed);
        notifyListeners();
      }
    }
  }

  void cancelDownload(String id) {
    final idx = _downloads.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      _downloads[idx] =
          _downloads[idx].copyWith(status: DownloadStatus.canceled);
      notifyListeners();
    }
  }

  void removeDownload(String id) {
    _downloads.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  Future<void> retryDownload(String id) async {
    final idx = _downloads.indexWhere((d) => d.id == id);
    if (idx >= 0) {
      final url = _downloads[idx].url;
      _downloads.removeAt(idx);
      notifyListeners();
      await downloadFromUrl(url);
    }
  }

  void clearCompleted() {
    _downloads.removeWhere((d) =>
        d.status == DownloadStatus.completed ||
        d.status == DownloadStatus.failed ||
        d.status == DownloadStatus.canceled);
    notifyListeners();
  }
}
