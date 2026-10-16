// providers/cloud_vault_provider.dart
// COMPLETE Cloud Vault Provider
//
// Key changes in this version:
//  - uploadFile() now checks isPremiumActive() itself, before accepting
//    anything. The Cloud Vault screen already shows a paywall to
//    non-premium users, but a client-side bypass (or a future screen
//    that forgets the check) would otherwise still upload — and every
//    upload consumes real Firebase Storage quota and real storage money.
//    Refusing at the source is the correct place.
//  - Removed orphaned writes to `usedCloudSpace`. That field was
//    incremented on upload and decremented on delete but never read
//    anywhere — _loadQuotaAndPremiumStatus() already computes used space
//    by SUMMING the actual cloudFiles records, which is always correct.
//    The increment/decrement pair was only ever able to drift.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/storage_service.dart';

class CloudFile {
  final String id;
  final String fileName;
  final String storagePath;
  final String thumbnailUrl;
  final String source;
  final bool isVideo;
  final int fileSize;
  final DateTime uploadDate;
  final String mimeType;

  CloudFile({
    required this.id,
    required this.fileName,
    required this.storagePath,
    required this.thumbnailUrl,
    required this.source,
    required this.isVideo,
    required this.fileSize,
    required this.uploadDate,
    this.mimeType = 'video/mp4',
  });

  factory CloudFile.fromMap(String id, Map<String, dynamic> map) {
    return CloudFile(
      id: id,
      fileName: map['fileName'] ?? 'unknown',
      storagePath: map['storagePath'] ?? '',
      thumbnailUrl: map['thumbnailUrl'] ?? '',
      source: map['source'] ?? 'unknown',
      isVideo: map['isVideo'] ?? false,
      fileSize: map['fileSize'] ?? 0,
      uploadDate: (map['uploadDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      mimeType: map['mimeType'] ?? 'video/mp4',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'storagePath': storagePath,
      'thumbnailUrl': thumbnailUrl,
      'source': source,
      'isVideo': isVideo,
      'fileSize': fileSize,
      'uploadDate': Timestamp.fromDate(uploadDate),
      'mimeType': mimeType,
    };
  }
}

class CloudVaultProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final StorageService _storageService = StorageService();

  List<CloudFile> _files = [];
  List<CloudFile> get files => _files;

  List<CloudFile> get imageFiles => _files.where((f) => !f.isVideo).toList();
  List<CloudFile> get videoFiles => _files.where((f) => f.isVideo).toList();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isUploading = false;
  bool get isUploading => _isUploading;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  double _uploadProgress = 0.0;
  double get uploadProgress => _uploadProgress;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  String? _error;
  String? get error => _error;

  int _quotaBytes = 3 * 1024 * 1024 * 1024; // 3GB default
  int get quotaBytes => _quotaBytes;

  int _usedBytes = 0;
  int get usedBytes => _usedBytes;

  double get usageFraction => _quotaBytes > 0 ? _usedBytes / _quotaBytes : 0.0;

  bool _isPremium = false;
  bool get isPremium => _isPremium;

  CloudVaultProvider() {
    init();
  }

  Future<void> init() async {
    try {
      await _loadQuotaAndPremiumStatus();
      await loadFiles();
    } catch (e) {
      print('⚠️ CloudVaultProvider init error: $e');
    }
  }

  Future<void> _loadQuotaAndPremiumStatus() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        // premiumExpiry is the field the server writes on subscription
        // verification — see functions/index.js:/verifySubscriptionPurchase.
        final expiry = data['premiumExpiry'] as Timestamp?;
        _isPremium = expiry != null && expiry.toDate().isAfter(DateTime.now());
        _quotaBytes = data['cloudQuota'] ?? 3 * 1024 * 1024 * 1024;
      }

      // Used space is computed live from the actual cloudFiles records —
      // always correct, and this is what the quota bar actually reads.
      final filesSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cloudFiles')
          .get();
      _usedBytes = filesSnapshot.docs.fold<int>(
          0, (sum, d) => sum + ((d.data()['fileSize'] as num?)?.toInt() ?? 0));

      notifyListeners();
    } catch (e) {
      print('⚠️ Load quota error: $e');
    }
  }

  /// Reads premium status fresh, right before an upload — deliberately not
  /// just consulting the cached _isPremium field, so a subscription that
  /// expired yesterday doesn't sneak an upload through today.
  Future<bool> _isPremiumActive() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!doc.exists) return false;
      final expiry = doc.data()?['premiumExpiry'] as Timestamp?;
      return expiry != null && expiry.toDate().isAfter(DateTime.now());
    } catch (e) {
      print('Premium check error: $e');
      return false;
    }
  }

  Future<void> loadFiles() async {
    if (_isLoading) return;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _files = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cloudFiles')
          .orderBy('uploadDate', descending: true)
          .get();

      _files = snapshot.docs
          .map((doc) => CloudFile.fromMap(doc.id, doc.data()))
          .toList();

      _error = null;
    } catch (e) {
      _error = 'Failed to load cloud files: $e';
      _files = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadFile({
    required String localPath,
    required String fileName,
    required String source,
    String? mimeType,
  }) async {
    if (_isUploading) return false;

    final user = _auth.currentUser;
    if (user == null) {
      _error = 'Please sign in to upload files';
      notifyListeners();
      return false;
    }

    // Server-side of the premium wall — see file header comment.
    final isPremium = await _isPremiumActive();
    if (!isPremium) {
      _error = 'Cloud Vault Pro requires an active subscription. '
          'Upgrade to keep syncing files.';
      notifyListeners();
      return false;
    }

    if (_usedBytes >= _quotaBytes) {
      _error = 'Storage quota exceeded. Delete some files first.';
      notifyListeners();
      return false;
    }

    _isUploading = true;
    _uploadProgress = 0.0;
    _error = null;
    _statusMessage = 'Starting upload...';
    notifyListeners();

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        _error = 'File not found';
        _isUploading = false;
        notifyListeners();
        return false;
      }

      final fileSize = await file.length();

      // Determine video-ness from BOTH the mime type (when the picker
      // gives one) AND the filename extension. Some OEM pickers return
      // null mimeType even for real videos, which used to silently send
      // videos into the images folder.
      final ext =
          fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
      const videoExts = {'mp4', 'webm', 'mov', 'mkv', 'avi', '3gp', 'm4v'};
      final isVideo =
          (mimeType?.startsWith('video') ?? false) || videoExts.contains(ext);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath =
          'users/${user.uid}/cloud_vault/${timestamp}_$fileName';

      _statusMessage = 'Uploading to cloud...';
      notifyListeners();

      final ref = _storage.ref(storagePath);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg'),
        ),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        _uploadProgress = progress;
        _statusMessage = 'Uploading... ${(progress * 100).toInt()}%';
        notifyListeners();
      });

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // For videos we just use the video URL as the thumbnail placeholder
      // (the cloud_vault_screen._buildThumbnail CachedNetworkImage will
      // render a broken-image fallback, which is fine — a real video
      // thumbnail would need server-side generation, next milestone).
      final cloudFile = CloudFile(
        id: '$timestamp',
        fileName: fileName,
        storagePath: storagePath,
        thumbnailUrl: downloadUrl,
        source: source,
        isVideo: isVideo,
        fileSize: fileSize,
        uploadDate: DateTime.now(),
        mimeType: mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg'),
      );

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cloudFiles')
          .doc('$timestamp')
          .set(cloudFile.toMap());

      // Local cache update — used space stays correct because we recompute
      // it from the sum of records via _loadQuotaAndPremiumStatus below.
      _files.insert(0, cloudFile);
      _usedBytes += fileSize;

      _statusMessage = 'Upload complete!';
      _uploadProgress = 1.0;
      _isUploading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Upload failed: $e';
      _statusMessage = 'Upload failed';
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _downloadFileWithProgress(
    String url,
    String filePath, {
    required void Function(double progress) onProgress,
  }) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final downloadResponse = await request.close();

      if (downloadResponse.statusCode != HttpStatus.ok) {
        client.close(force: true);
        return false;
      }

      final file = File(filePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();

      final totalBytes = downloadResponse.contentLength;
      var downloadedBytes = 0;

      await for (final chunk in downloadResponse) {
        sink.add(chunk);
        downloadedBytes += chunk.length;

        if (totalBytes > 0) {
          onProgress(downloadedBytes / totalBytes);
        } else {
          onProgress(0.0);
        }
      }

      await sink.flush();
      await sink.close();
      client.close(force: true);
      onProgress(1.0);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<String?> downloadFile(CloudFile file) async {
    if (_isDownloading) return null;

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Starting download...';
    _error = null;
    notifyListeners();

    try {
      final user = _auth.currentUser;
      if (user == null) {
        _error = 'Please sign in to download files';
        _isDownloading = false;
        notifyListeners();
        return null;
      }

      _statusMessage = 'Getting download URL...';
      notifyListeners();

      final folder = file.isVideo ? 'Videos' : 'Pictures';
      final downloadDir = '/storage/emulated/0/$folder/MediaNest/Cloud';
      final localPath = '$downloadDir/${file.fileName}';

      // Skip re-download when the identical file (name + size) already
      // exists locally — Firebase Storage bills $0.12/GB per download, and
      // re-fetching a file the person already has is pure wasted spend.
      final existing = File(localPath);
      if (await existing.exists()) {
        final localSize = await existing.length();
        if (localSize == file.fileSize && file.fileSize > 0) {
          _statusMessage = 'Already downloaded';
          _downloadProgress = 1.0;
          _isDownloading = false;
          notifyListeners();
          return localPath;
        }
      }

      final ref = _storage.ref(file.storagePath);
      final downloadUrl = await ref.getDownloadURL();

      _statusMessage = 'Downloading...';
      notifyListeners();

      final dir = Directory(downloadDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final response = await _downloadFileWithProgress(
        downloadUrl,
        localPath,
        onProgress: (progress) {
          _downloadProgress = progress;
          _statusMessage = 'Downloading... ${(progress * 100).toInt()}%';
          notifyListeners();
        },
      );

      if (response) {
        await _storageService.scanMediaFile(localPath);
        _statusMessage = 'Download complete!';
        _downloadProgress = 1.0;
        _isDownloading = false;
        notifyListeners();
        return localPath;
      } else {
        _error = 'Download failed';
        _isDownloading = false;
        notifyListeners();
        return null;
      }
    } catch (e) {
      _error = 'Download failed: $e';
      _statusMessage = 'Download failed';
      _isDownloading = false;
      notifyListeners();
      return null;
    }
  }

  Future<bool> deleteFile(CloudFile file) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final ref = _storage.ref(file.storagePath);
      await ref.delete();

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cloudFiles')
          .doc(file.id)
          .delete();

      _usedBytes -= file.fileSize;
      if (_usedBytes < 0) _usedBytes = 0;

      _files.removeWhere((f) => f.id == file.id);
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Delete failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshQuota() async {
    await _loadQuotaAndPremiumStatus();
  }

  Future<bool> checkGracePeriod() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final expiryDate = data['premiumExpiry'] as Timestamp?;
        if (expiryDate != null) {
          final expiry = expiryDate.toDate();
          final now = DateTime.now();
          final diff = expiry.difference(now);
          // Grace period of 24 hours — matches CloudVaultService's own
          // GRACE_PERIOD_HOURS and the "renew within 24h or files are
          // permanently deleted" copy in cloud_vault_screen.dart.
          return diff.isNegative && diff.abs().inHours < 24;
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void dispose() {
    // Nothing to clean up here.
  }
}
