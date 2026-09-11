// services/cloud_vault_service.dart
// Complete Cloud Vault Service with Firebase Integration
// Handles: Upload, Download, Delete, Quota Management, Thumbnails
// ignore_for_file: avoid_print, constant_identifier_names

import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'dart:math';

class CloudVaultService {
  static const double QUOTA_GB = 3.0;
  static const int QUOTA_BYTES = 3 * 1024 * 1024 * 1024;
  static const int GRACE_PERIOD_HOURS = 24;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Native bridge for MediaStore save (reuse from download_service)
  static const _nativeBridge =
      MethodChannel('com.yourapp.allsocialdownloader/native');

  String get _uid => _auth.currentUser?.uid ?? '';

  String _safeFileName(String value) {
    final cleaned = value
        .replaceAll('\\', '_')
        .replaceAll('/', '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return cleaned.isEmpty ? 'media.bin' : cleaned;
  }

  /// Check if user has valid premium subscription
  Future<bool> isPremiumActive() async {
    if (_uid.isEmpty) return false;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (!doc.exists) return false;
      final expiry = doc.data()?['premiumExpiry'] as Timestamp?;
      if (expiry == null) return false;
      return expiry.toDate().isAfter(DateTime.now());
    } catch (e) {
      print('Premium check error: $e');
      return false;
    }
  }

  /// Get user's quota usage
  Future<Map<String, dynamic>> getQuotaInfo() async {
    if (_uid.isEmpty) {
      return {
        'usedBytes': 0,
        'usedGB': 0,
        'quotaBytes': QUOTA_BYTES,
        'quotaGB': QUOTA_GB,
        'fileCount': 0,
        'remainingBytes': QUOTA_BYTES,
        'isPremium': false,
      };
    }
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('cloudFiles')
          .get();

      int totalBytes = 0;
      int fileCount = 0;
      for (final doc in snapshot.docs) {
        final size = doc.data()['fileSize'] as int? ?? 0;
        totalBytes += size;
        fileCount++;
      }

      return {
        'usedBytes': totalBytes,
        'usedGB': totalBytes / (1024 * 1024 * 1024),
        'quotaBytes': QUOTA_BYTES,
        'quotaGB': QUOTA_GB,
        'fileCount': fileCount,
        'remainingBytes': QUOTA_BYTES - totalBytes,
        'isPremium': await isPremiumActive(),
      };
    } catch (e) {
      print('Quota info error: $e');
      return {
        'usedBytes': 0,
        'usedGB': 0,
        'quotaBytes': QUOTA_BYTES,
        'quotaGB': QUOTA_GB,
        'fileCount': 0,
        'remainingBytes': QUOTA_BYTES,
        'isPremium': false,
      };
    }
  }

  /// Get list of user's cloud files
  Stream<List<CloudFile>> getUserFiles() {
    if (_uid.isEmpty) return Stream.value(const <CloudFile>[]);
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('cloudFiles')
        .orderBy('uploadDate', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return CloudFile(
          id: doc.id,
          fileName: data['fileName'] ?? 'unknown',
          fileSize: data['fileSize'] ?? 0,
          mimeType: data['mimeType'] ?? 'video/mp4',
          storagePath: data['storagePath'] ?? '',
          thumbnailUrl: data['thumbnailUrl'] ?? '',
          uploadDate: (data['uploadDate'] as Timestamp).toDate(),
          source: data['source'] ?? 'manual',
          isVideo: data['isVideo'] ?? false,
        );
      }).toList();
    });
  }

  /// Upload a file to cloud vault
  Future<CloudFile?> uploadFile({
    required String localPath,
    required String fileName,
    required String source,
    String? mimeType,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    try {
      if (_uid.isEmpty) {
        onStatus?.call('❌ Sign in to use Cloud Vault Pro');
        return null;
      }
      // Check quota first
      final quota = await getQuotaInfo();
      if (!quota['isPremium']) {
        onStatus?.call('❌ Premium subscription required');
        return null;
      }

      final file = File(localPath);
      if (!await file.exists()) {
        onStatus?.call('❌ File not found');
        return null;
      }

      final fileSize = await file.length();
      if (fileSize <= 0) {
        onStatus?.call('❌ The selected file is empty');
        return null;
      }
      if (fileSize > quota['remainingBytes']) {
        onStatus?.call('❌ Quota exceeded. Delete some files first.');
        return null;
      }

      // Determine file type
      final isVideo = _isVideoFile(fileName);
      final effectiveMimeType = mimeType ?? _mimeType(fileName);

      // Generate unique path
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeName = _safeFileName(fileName);
      final ext = safeName.contains('.') ? safeName.split('.').last : '';
      final storageFileName =
          '${timestamp}_${_uid.substring(0, min(8, _uid.length))}.${ext.isNotEmpty ? ext : (isVideo ? 'mp4' : 'jpg')}';
      final storagePath =
          'users/$_uid/${isVideo ? 'videos' : 'images'}/$storageFileName';

      onStatus?.call('⬆️ Uploading...');

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child(storagePath);
      final uploadTask = storageRef.putFile(
        file,
        SettableMetadata(
          contentType: effectiveMimeType,
          customMetadata: {
            'fileName': fileName,
            'uploadedBy': _uid,
            'uploadDate': DateTime.now().toIso8601String(),
          },
        ),
      );

      // Track progress
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // Generate thumbnail for faster loading
      String? thumbnailUrl;
      onStatus?.call('🖼️ Generating thumbnail...');
      try {
        if (isVideo) {
          final thumbData = await _generateVideoThumbnail(localPath);
          if (thumbData != null) {
            final thumbPath = 'users/$_uid/thumbnails/${timestamp}_thumb.jpg';
            final thumbRef = _storage.ref().child(thumbPath);
            await thumbRef.putData(
              thumbData,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            thumbnailUrl = await thumbRef.getDownloadURL();
          }
        } else {
          // For images, use the image itself as thumbnail (smaller size)
          final thumbData = await _generateImageThumbnail(localPath);
          if (thumbData != null) {
            final thumbPath = 'users/$_uid/thumbnails/${timestamp}_thumb.jpg';
            final thumbRef = _storage.ref().child(thumbPath);
            await thumbRef.putData(
              thumbData,
              SettableMetadata(contentType: 'image/jpeg'),
            );
            thumbnailUrl = await thumbRef.getDownloadURL();
          }
        }
      } catch (e) {
        print('Thumbnail generation error: $e');
        // Use the original URL as fallback
        thumbnailUrl = downloadUrl;
      }

      // Save metadata to Firestore
      onStatus?.call('💾 Saving metadata...');
      final docRef = _firestore
          .collection('users')
          .doc(_uid)
          .collection('cloudFiles')
          .doc();

      final cloudFile = CloudFile(
        id: docRef.id,
        fileName: fileName,
        fileSize: fileSize,
        mimeType: effectiveMimeType,
        storagePath: storagePath,
        thumbnailUrl: thumbnailUrl ?? downloadUrl,
        uploadDate: DateTime.now(),
        source: source,
        isVideo: isVideo,
      );

      await docRef.set({
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': effectiveMimeType,
        'storagePath': storagePath,
        'downloadUrl': downloadUrl,
        'thumbnailUrl': thumbnailUrl ?? downloadUrl,
        'uploadDate': Timestamp.now(),
        'source': source,
        'isVideo': isVideo,
      });

      onStatus?.call('✅ Uploaded successfully!');
      onProgress?.call(1.0);

      return cloudFile;
    } catch (e) {
      print('Upload error: $e');
      onStatus?.call('❌ Upload failed: $e');
      return null;
    }
  }

  /// Download a file from cloud to device
  Future<String?> downloadFile(
    CloudFile file, {
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    try {
      if (_uid.isEmpty) {
        onStatus?.call('❌ Sign in to use Cloud Vault Pro');
        return null;
      }
      if (!await isPremiumActive()) {
        onStatus?.call('❌ Cloud Vault Pro subscription required');
        return null;
      }
      onStatus?.call('⬇️ Downloading...');

      // Get download URL from Firestore or Storage
      String downloadUrl;
      final doc = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('cloudFiles')
          .doc(file.id)
          .get();

      if (doc.exists) {
        downloadUrl = doc.data()?['downloadUrl'] as String? ?? '';
        if (downloadUrl.isEmpty) {
          final ref = _storage.ref().child(file.storagePath);
          downloadUrl = await ref.getDownloadURL();
        }
      } else {
        final ref = _storage.ref().child(file.storagePath);
        downloadUrl = await ref.getDownloadURL();
      }

      // Download to temp first
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${_safeFileName(file.fileName)}';
      final tempFile = File(tempPath);

      // Download using Firebase Storage
      final ref = _storage.ref().child(file.storagePath);
      final downloadTask = ref.writeToFile(tempFile);

      downloadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });

      await downloadTask.whenComplete(() => null);

      // Move to MediaStore (Download/MediaNest/Cloud)
      onStatus?.call('💾 Saving to device...');
      final platform = 'cloud';
      final finalPath = await _moveToMediaStore(
        tempPath,
        file.fileName,
        platform,
        file.mimeType,
      );

      onStatus?.call('✅ Saved to device!');
      onProgress?.call(1.0);

      return finalPath;
    } catch (e) {
      print('Download error: $e');
      onStatus?.call('❌ Download failed: $e');
      return null;
    }
  }

  /// Delete a file from cloud
  Future<bool> deleteFile(CloudFile file) async {
    if (_uid.isEmpty) return false;
    try {
      // Delete from Storage
      try {
        final ref = _storage.ref().child(file.storagePath);
        await ref.delete();
      } catch (e) {
        print('Storage delete error (may already be deleted): $e');
      }

      // Delete thumbnail if exists
      if (file.thumbnailUrl.isNotEmpty) {
        try {
          // Extract path from URL
          final uri = Uri.parse(file.thumbnailUrl);
          final segments = uri.pathSegments;
          if (segments.length >= 4) {
            final thumbPath = segments.sublist(2).join('/');
            final thumbRef = _storage.ref().child(thumbPath);
            await thumbRef.delete();
          }
        } catch (_) {}
      }

      // Delete from Firestore
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('cloudFiles')
          .doc(file.id)
          .delete();

      print('✅ Deleted: ${file.fileName}');
      return true;
    } catch (e) {
      print('Delete error: $e');
      return false;
    }
  }

  /// Delete ALL user files (when premium expires after grace period)
  Future<void> deleteAllUserFiles() async {
    if (_uid.isEmpty) return;
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('cloudFiles')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final storagePath = data['storagePath'] as String?;
        if (storagePath != null) {
          try {
            await _storage.ref().child(storagePath).delete();
          } catch (_) {}
        }
        await doc.reference.delete();
      }

      print('✅ All user files deleted');
    } catch (e) {
      print('Delete all error: $e');
    }
  }

  /// Check if user is in grace period
  Future<bool> isInGracePeriod() async {
    if (_uid.isEmpty) return false;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (!doc.exists) return false;
      final expiry = doc.data()?['premiumExpiry'] as Timestamp?;
      if (expiry == null) return false;

      final expiryDate = expiry.toDate();
      final now = DateTime.now();
      final diff = now.difference(expiryDate);

      return diff.isNegative == false && diff.inHours < GRACE_PERIOD_HOURS;
    } catch (e) {
      return false;
    }
  }

  // NOTE: updatePremiumExpiry() used to live here, letting the client write
  // premiumExpiry/planId straight to Firestore based on its own local
  // purchase callback. That was a real security hole — a modified client
  // (or a Frida/Xposed hook faking a successful purchase) could grant
  // itself premium forever without ever paying. It's been removed. The
  // ONLY place premiumExpiry/planId get written now is server-side, in
  // functions/index.js's /verifySubscriptionPurchase, after Google Play
  // itself has confirmed the purchase is real. If you're tempted to bring
  // this back for convenience, don't — go through the server endpoint.

  // ─── Helper methods ──────────────────────────────────────────────────────

  bool _isVideoFile(String fileName) {
    const videoExts = ['.mp4', '.webm', '.mov', '.mkv', '.avi', '.3gp'];
    final lo = fileName.toLowerCase();
    return videoExts.any((ext) => lo.endsWith(ext));
  }

  String _mimeType(String fileName) {
    final lo = fileName.toLowerCase();
    if (lo.endsWith('.mp4')) return 'video/mp4';
    if (lo.endsWith('.webm')) return 'video/webm';
    if (lo.endsWith('.mov')) return 'video/quicktime';
    if (lo.endsWith('.mkv')) return 'video/x-matroska';
    if (lo.endsWith('.jpg') || lo.endsWith('.jpeg')) return 'image/jpeg';
    if (lo.endsWith('.png')) return 'image/png';
    if (lo.endsWith('.gif')) return 'image/gif';
    if (lo.endsWith('.webp')) return 'image/webp';
    return 'video/mp4';
  }

  Future<Uint8List?> _generateVideoThumbnail(String videoPath) async {
    try {
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) return null;
      if (await videoFile.length() < 1024) return null;

      final videoUri =
          videoPath.startsWith('file://') ? videoPath : 'file://$videoPath';

      final data = await VideoThumbnail.thumbnailData(
        video: videoUri,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 70,
        timeMs: 500,
      );

      return data;
    } catch (e) {
      print('Video thumbnail error: $e');
      return null;
    }
  }

  Future<Uint8List?> _generateImageThumbnail(String imagePath) async {
    try {
      final imageFile = File(imagePath);
      if (!await imageFile.exists()) return null;

      // For images, we'll resize using a simple approach
      // Since we can't easily resize images in pure Dart without a package,
      // we'll just read the file and return it
      // For production, consider using image package for resizing
      return await imageFile.readAsBytes();
    } catch (e) {
      print('Image thumbnail error: $e');
      return null;
    }
  }

  Future<String> _moveToMediaStore(
    String tempPath,
    String fileName,
    String platform,
    String mimeType,
  ) async {
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
      }
    } catch (e) {
      print('MediaStore error: $e');
    }
    return tempPath;
  }
}

// ─── CloudFile Model ─────────────────────────────────────────────────────────

class CloudFile {
  final String id;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final String storagePath;
  final String thumbnailUrl;
  final DateTime uploadDate;
  final String source;
  final bool isVideo;

  CloudFile({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.storagePath,
    required this.thumbnailUrl,
    required this.uploadDate,
    required this.source,
    required this.isVideo,
  });

  String get sizeLabel {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1048576) return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    if (fileSize < 1073741824) {
      return '${(fileSize / 1048576).toStringAsFixed(1)}MB';
    }
    return '${(fileSize / 1073741824).toStringAsFixed(2)}GB';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(uploadDate);
    if (diff.inDays > 30) {
      return '${uploadDate.day}/${uploadDate.month}/${uploadDate.year}';
    }
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'storagePath': storagePath,
        'thumbnailUrl': thumbnailUrl,
        'uploadDate': uploadDate.toIso8601String(),
        'source': source,
        'isVideo': isVideo,
      };
}
