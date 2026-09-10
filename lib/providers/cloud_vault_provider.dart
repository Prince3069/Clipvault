// providers/cloud_vault_provider.dart
// COMPLETE Cloud Vault Provider

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Initialize the provider
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
        // NOTE: premium grants write `premiumExpiry` (a Timestamp) — see
        // PremiumProvider.grantPremium() -> CloudVaultService.updatePremiumExpiry().
        // This used to check a field called `isPremium` that nothing in the
        // app ever wrote, so the Cloud Vault screen could never see a paying
        // user as premium even right after a successful purchase.
        final expiry = data['premiumExpiry'] as Timestamp?;
        _isPremium = expiry != null && expiry.toDate().isAfter(DateTime.now());
        _quotaBytes = data['cloudQuota'] ?? 3 * 1024 * 1024 * 1024;
      }
      // Used space is computed live from the actual cloudFiles records
      // rather than trusting a separately-incremented counter — a file
      // added via the auto-sync path (CloudVaultService.uploadFile, used by
      // DownloadProvider) never touched a counter field, so the counter
      // could silently drift below what's really stored (and billed) in
      // Firebase. Summing the real records is always correct.
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

    // Check quota
    if (_usedBytes >= _quotaBytes) {
      _error = 'Storage quota exceeded. Please upgrade to Pro.';
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
      final isVideo = mimeType?.startsWith('video') ?? false;
      final ext = localPath.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath =
          'users/${user.uid}/cloud_vault/${timestamp}_$fileName';

      _statusMessage = 'Uploading to cloud...';
      notifyListeners();

      // Upload to Firebase Storage with progress
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

      // Create thumbnail URL (for videos we use the video URL as thumbnail)
      final thumbnailUrl = isVideo ? downloadUrl : downloadUrl;

      // Save to Firestore
      final cloudFile = CloudFile(
        id: '$timestamp',
        fileName: fileName,
        storagePath: storagePath,
        thumbnailUrl: thumbnailUrl,
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

      // Update user's used space
      await _firestore.collection('users').doc(user.uid).update({
        'usedCloudSpace': FieldValue.increment(fileSize),
      });

      _usedBytes += fileSize;

      // Add to local list
      _files.insert(0, cloudFile);

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

      final ref = _storage.ref(file.storagePath);
      final downloadUrl = await ref.getDownloadURL();

      _statusMessage = 'Downloading...';
      notifyListeners();

      // Download to device
      final folder = file.isVideo ? 'Videos' : 'Pictures';
      final downloadDir = '/storage/emulated/0/$folder/ClipVaults/Cloud';
      final localPath = '$downloadDir/${file.fileName}';

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
      // Delete from Storage
      final ref = _storage.ref(file.storagePath);
      await ref.delete();

      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('cloudFiles')
          .doc(file.id)
          .delete();

      // Update used space
      await _firestore.collection('users').doc(user.uid).update({
        'usedCloudSpace': FieldValue.increment(-file.fileSize),
      });

      _usedBytes -= file.fileSize;

      // Remove from local list
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
          // Grace period of 24 hours
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
    // Clean up
  }
}
