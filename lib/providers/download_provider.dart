// providers/download_provider.dart
// ADDED: Auto-sync to Cloud Vault after successful download
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download_item.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../services/cloud_vault_service.dart';

class DownloadProvider extends ChangeNotifier {
  final List<DownloadItem> _downloads = [];
  final DownloadService _downloadService = DownloadService();
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
      // showDownloadProgress is a STATIC method on NotificationService —
      // must be called on the class itself, not an instance. The old fake
      // extension took `progress` as a 0.0–1.0 fraction; the real method
      // takes a 0–100 int, hence the *100 conversion below.
      NotificationService.showDownloadProgress(
          title: 'Downloading...', message: 'Starting…', progress: 0);

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

      // showDownloadComplete is also static, and doesn't take an id at
      // all (it always uses notification id 0) — matching the real
      // method's actual parameters (title/message), not the old fake
      // extension's made-up ones (id/body/isComplete).
      NotificationService.showDownloadComplete(
        title: result.status == DownloadStatus.completed
            ? 'Download Complete ✅'
            : 'Download Failed',
        message: result.fileName,
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

  /// Registers a download that already completed OUTSIDE the normal
  /// downloadFromUrl() flow — specifically, BrowserDownloadScreen's
  /// webview-based fallback (used when direct extraction fails and the
  /// user downloads via the in-app browser instead). That screen was
  /// saving files to disk and showing its own "✅ Saved!" toast, but
  /// never told THIS provider anything happened — so the file genuinely
  /// saved (it played fine, size shown correctly) while being completely
  /// invisible to saved_screen.dart, which reads exclusively from this
  /// provider's `downloads` list to build its platform folders. This is
  /// the bridge that was missing between "a file got saved somewhere"
  /// and "the app's own download list knows about it."
  void registerCompletedDownload({
    required String url,
    required String localPath,
    required String fileName,
    required String sourceApp,
  }) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    _downloads.add(DownloadItem(
      id: id,
      url: url,
      fileName: fileName,
      thumbnailUrl: '',
      sourceApp: sourceApp,
      dateAdded: DateTime.now(),
      localPath: localPath,
      status: DownloadStatus.completed,
      progress: 1.0,
    ));
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
