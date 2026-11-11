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

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../services/native_bridge.dart';
import '../services/storage_service.dart';
import 'premium_provider.dart';

const Set<String> _kVideoExts = {
  'mp4', 'webm', 'mov', 'mkv', 'avi', '3gp', 'm4v', 'ts', 'flv', //
};
const Set<String> _kImageExts = {
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif', 'bmp', //
};

String _extOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return '';
  final ext = fileName.substring(dot + 1).toLowerCase();
  return ext.length <= 5 ? ext : '';
}

class CloudFile {
  final String id;
  final String fileName;
  final String storagePath;
  final String thumbnailUrl;
  // Storage path of the separately-uploaded thumbnail ('' when the
  // thumbnail is the file itself, or for older records).
  final String thumbnailPath;
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
    this.thumbnailPath = '',
    this.mimeType = 'video/mp4',
  });

  /// True when [thumbnailUrl] points at a real picture that can be shown.
  /// Older video records stored the VIDEO's own URL here, which can never
  /// render as an image.
  bool get hasImageThumbnail {
    if (thumbnailUrl.isEmpty) return false;
    if (!isVideo) return true;
    return thumbnailPath.isNotEmpty || thumbnailUrl.contains('thumb');
  }

  factory CloudFile.fromMap(String id, Map<String, dynamic> map) {
    final fileName = (map['fileName'] ?? 'unknown').toString();
    final rawMime = map['mimeType']?.toString() ?? '';
    final storagePath = (map['storagePath'] ?? '').toString();
    final ext = _extOf(fileName).isNotEmpty ? _extOf(fileName) : _extOf(storagePath);

    // Older records could carry a wrong isVideo flag (a video saved as an
    // "image" when the picker gave no file type). Work the truth out from
    // everything we know rather than trusting the single stored flag.
    bool isVideo = map['isVideo'] == true;
    if (rawMime.startsWith('video') || _kVideoExts.contains(ext)) {
      isVideo = true;
    } else if (rawMime.startsWith('image') && _kImageExts.contains(ext)) {
      isVideo = false;
    }

    return CloudFile(
      id: id,
      fileName: fileName,
      storagePath: storagePath,
      thumbnailUrl: (map['thumbnailUrl'] ?? '').toString(),
      thumbnailPath: (map['thumbnailPath'] ?? '').toString(),
      source: (map['source'] ?? 'unknown').toString(),
      isVideo: isVideo,
      fileSize: (map['fileSize'] as num?)?.toInt() ?? 0,
      uploadDate: (map['uploadDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      mimeType: rawMime.isNotEmpty
          ? rawMime
          : (isVideo ? 'video/mp4' : 'image/jpeg'),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'storagePath': storagePath,
      'thumbnailUrl': thumbnailUrl,
      'thumbnailPath': thumbnailPath,
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
  StreamSubscription<User?>? _authSub;
  String? _loadedForUid;

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
    // The provider is created at app start, often before sign-in has
    // finished. Re-load whenever the signed-in account changes so the
    // vault isn't stuck empty (or showing the previous account's files).
    _authSub = _auth.authStateChanges().listen((user) {
      if (user?.uid == _loadedForUid) return;
      _loadedForUid = user?.uid;
      _files = [];
      _usedBytes = 0;
      _isPremium = false;
      _graceCheck = null;
      if (user == null) {
        notifyListeners();
      } else {
        init();
      }
    });
  }

  Future<void> init() async {
    try {
      await _loadQuotaAndPremiumStatus();
      await loadFiles();
    } catch (e) {
      print('⚠️ CloudVaultProvider init error: $e');
    }
  }

  /// Owner/producer accounts are always Pro (same list the server and the
  /// security rules use).
  bool _isOwner(User user) {
    final email = (user.email ?? '').trim().toLowerCase();
    if (email.isEmpty || !PremiumProvider.ownerEmails.contains(email)) {
      return false;
    }
    return user.emailVerified ||
        user.providerData.any((p) => p.providerId == 'google.com');
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
        _quotaBytes =
            (data['cloudQuota'] as num?)?.toInt() ?? 3 * 1024 * 1024 * 1024;
      }
      if (_isOwner(user)) _isPremium = true;

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
    if (_isOwner(user)) return true;
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
          .where((f) => f.storagePath.isNotEmpty)
          .toList();
      _usedBytes = _files.fold<int>(0, (sum, f) => sum + f.fileSize);

      _error = null;
    } catch (e) {
      _error = 'Failed to load cloud files: $e';
      _files = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── File type detection ──────────────────────────────────────────────

  /// Looks at the file's first bytes to tell what it REALLY is. Returns
  /// (isVideo, extension, mimeType), or null when the signature isn't one
  /// we know. This is what stops a video with no file extension (many
  /// Android pickers hand those back) being stored as an "image".
  Future<(bool, String, String)?> _sniffFileType(File file) async {
    try {
      final raf = await file.open();
      final Uint8List h = await raf.read(16).whenComplete(() => raf.close());
      if (h.length < 12) return null;
      String ascii(int from, int to) =>
          String.fromCharCodes(h.sublist(from, to));

      if (h[0] == 0xFF && h[1] == 0xD8) return (false, 'jpg', 'image/jpeg');
      if (h[0] == 0x89 && ascii(1, 4) == 'PNG') {
        return (false, 'png', 'image/png');
      }
      if (ascii(0, 4) == 'GIF8') return (false, 'gif', 'image/gif');
      if (ascii(0, 4) == 'RIFF') {
        final kind = ascii(8, 12);
        if (kind == 'WEBP') return (false, 'webp', 'image/webp');
        if (kind == 'AVI ') return (true, 'avi', 'video/x-msvideo');
      }
      if (h[0] == 0x1A && h[1] == 0x45 && h[2] == 0xDF && h[3] == 0xA3) {
        return (true, 'webm', 'video/webm');
      }
      if (ascii(4, 8) == 'ftyp') {
        final brand = ascii(8, 12).toLowerCase();
        const imageBrands = {'heic', 'heix', 'hevc', 'mif1', 'msf1', 'avif'};
        if (imageBrands.contains(brand)) {
          return (false, brand == 'avif' ? 'avif' : 'heic',
              brand == 'avif' ? 'image/avif' : 'image/heic');
        }
        if (brand.startsWith('qt')) return (true, 'mov', 'video/quicktime');
        if (brand.startsWith('3gp')) return (true, '3gp', 'video/3gpp');
        return (true, 'mp4', 'video/mp4');
      }
    } catch (e) {
      print('File type sniff failed: $e');
    }
    return null;
  }

  String _safeName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty || cleaned == '_') return 'file';
    return cleaned.length > 80 ? cleaned.substring(cleaned.length - 80) : cleaned;
  }

  Future<Uint8List?> _videoThumbnail(String videoPath) async {
    try {
      return await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360,
        quality: 70,
        timeMs: 800,
      );
    } catch (e) {
      print('Video thumbnail error: $e');
      return null;
    }
  }

  /// Uploads a file to the cloud vault.
  ///
  /// [expectVideo] says which picker the file came from (true = video
  /// picker, false = image picker). The file's real bytes still win when
  /// they are recognisable.
  Future<bool> uploadFile({
    required String localPath,
    required String fileName,
    required String source,
    String? mimeType,
    bool? expectVideo,
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

    _isUploading = true;
    _uploadProgress = 0.0;
    _error = null;
    _statusMessage = 'Starting upload...';
    notifyListeners();

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        throw 'File not found';
      }

      final fileSize = await file.length();
      if (fileSize <= 0) {
        throw 'The selected file is empty';
      }
      if (_usedBytes + fileSize > _quotaBytes) {
        throw 'Not enough cloud space left for this file. Delete some '
            'files first.';
      }

      // ── What is this file, really? ──────────────────────────────────
      final sniffed = await _sniffFileType(file);
      final nameExt = _extOf(fileName);
      final bool isVideo;
      String ext;
      String contentType;
      if (sniffed != null) {
        isVideo = sniffed.$1;
        // Keep the original extension when it agrees with the content.
        final agrees = isVideo
            ? _kVideoExts.contains(nameExt)
            : _kImageExts.contains(nameExt);
        ext = agrees ? nameExt : sniffed.$2;
        contentType = sniffed.$3;
      } else {
        isVideo = expectVideo ??
            ((mimeType?.startsWith('video') ?? false) ||
                _kVideoExts.contains(nameExt));
        ext = nameExt.isNotEmpty ? nameExt : (isVideo ? 'mp4' : 'jpg');
        contentType = (mimeType != null &&
                mimeType.startsWith(isVideo ? 'video' : 'image'))
            ? mimeType
            : (isVideo ? 'video/mp4' : 'image/jpeg');
      }

      // A display name that always carries the right extension, so the
      // file opens correctly after it is downloaded again.
      final baseName = nameExt.isNotEmpty
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      final displayName =
          '${baseName.trim().isEmpty ? 'file' : baseName.trim()}.$ext';

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath =
          'users/${user.uid}/cloud_vault/${timestamp}_${_safeName(displayName)}';

      _statusMessage = 'Uploading to cloud...';
      notifyListeners();

      final ref = _storage.ref(storagePath);
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(
          contentType: contentType,
          customMetadata: {'kind': isVideo ? 'video' : 'image'},
        ),
      );

      final progressSub = uploadTask.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes <= 0) return;
        _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        _statusMessage = 'Uploading... ${(_uploadProgress * 100).toInt()}%';
        notifyListeners();
      }, onError: (_) {});

      final TaskSnapshot snapshot =
          await uploadTask.whenComplete(() => progressSub.cancel());
      final downloadUrl = await snapshot.ref.getDownloadURL();

      // ── Thumbnail ───────────────────────────────────────────────────
      // Videos get a real JPEG frame (a video URL can't be shown as a
      // picture). Images are their own thumbnail.
      String thumbnailUrl = isVideo ? '' : downloadUrl;
      String thumbnailPath = '';
      if (isVideo) {
        _statusMessage = 'Creating preview...';
        notifyListeners();
        final thumb = await _videoThumbnail(localPath);
        if (thumb != null && thumb.isNotEmpty) {
          try {
            final path =
                'users/${user.uid}/cloud_vault/thumbs/${timestamp}_thumb.jpg';
            final thumbRef = _storage.ref(path);
            await thumbRef.putData(
                thumb, SettableMetadata(contentType: 'image/jpeg'));
            thumbnailUrl = await thumbRef.getDownloadURL();
            thumbnailPath = path;
          } catch (e) {
            // A missing preview must never fail the upload itself.
            print('Thumbnail upload failed (non-fatal): $e');
          }
        }
      }

      final cloudFile = CloudFile(
        id: '$timestamp',
        fileName: displayName,
        storagePath: storagePath,
        thumbnailUrl: thumbnailUrl,
        thumbnailPath: thumbnailPath,
        source: source,
        isVideo: isVideo,
        fileSize: fileSize,
        uploadDate: DateTime.now(),
        mimeType: contentType,
      );

      try {
        await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('cloudFiles')
            .doc('$timestamp')
            .set(cloudFile.toMap());
      } catch (e) {
        // Don't leave an invisible, quota-eating file behind.
        try {
          await ref.delete();
        } catch (_) {}
        rethrow;
      }

      _files.insert(0, cloudFile);
      _usedBytes += fileSize;

      _statusMessage = 'Upload complete!';
      _uploadProgress = 1.0;
      _isUploading = false;
      notifyListeners();

      return true;
    } catch (e) {
      _error = _friendlyError(e, uploading: true);
      _statusMessage = 'Upload failed';
      _isUploading = false;
      notifyListeners();
      return false;
    }
  }

  String _friendlyError(Object e, {required bool uploading}) {
    if (e is String) return e;
    if (e is FirebaseException) {
      switch (e.code) {
        case 'unauthorized':
        case 'permission-denied':
          return uploading
              ? 'Cloud Vault refused the upload. Make sure your Pro '
                  'subscription is active and you are signed in.'
              : 'Cloud Vault refused access to this file. Make sure you '
                  'are signed in to the account that uploaded it.';
        case 'object-not-found':
          return 'This file no longer exists in the cloud.';
        case 'canceled':
          return 'Cancelled.';
        case 'retry-limit-exceeded':
        case 'unavailable':
          return 'Network problem — check your connection and try again.';
        case 'quota-exceeded':
          return 'Cloud storage is full right now. Please try again later.';
      }
      return e.message ?? e.code;
    }
    return e.toString();
  }

  // ─── Download ─────────────────────────────────────────────────────────

  /// Brings a cloud file onto the phone's private cache so it can be
  /// played / viewed. Nothing is written to the public gallery, so this
  /// works on every Android version without storage permissions. A file
  /// already in the cache is reused (no second download).
  Future<String?> fetchForViewing(CloudFile file) async {
    if (_isDownloading) return null;

    final user = _auth.currentUser;
    if (user == null) {
      _error = 'Please sign in to open cloud files';
      notifyListeners();
      return null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Opening...';
    _error = null;
    notifyListeners();

    try {
      final path = await _fetchToCache(file);
      _statusMessage = '';
      _downloadProgress = 1.0;
      _isDownloading = false;
      notifyListeners();
      return path;
    } catch (e) {
      _error = _friendlyError(e, uploading: false);
      _statusMessage = 'Could not open file';
      _isDownloading = false;
      notifyListeners();
      return null;
    }
  }

  Future<String> _fetchToCache(CloudFile file) async {
    final tempDir = await getTemporaryDirectory();
    final dir = Directory('${tempDir.path}/cloud_vault_cache');
    if (!await dir.exists()) await dir.create(recursive: true);

    // The local copy must end in the right extension or the player /
    // image viewer can't tell what it is.
    var name = _safeName(file.fileName);
    final ext = _extOf(name);
    final okExt =
        file.isVideo ? _kVideoExts.contains(ext) : _kImageExts.contains(ext);
    if (!okExt) name = '$name.${file.isVideo ? 'mp4' : 'jpg'}';

    final local = File('${dir.path}/${_safeName(file.id)}_$name');
    if (await local.exists()) {
      final size = await local.length();
      if (size > 0 && (file.fileSize <= 0 || size == file.fileSize)) {
        return local.path;
      }
      await local.delete();
    }

    final task = _storage.ref(file.storagePath).writeToFile(local);
    final sub = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes <= 0) return;
      _downloadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
      _statusMessage = 'Downloading... ${(_downloadProgress * 100).toInt()}%';
      notifyListeners();
    }, onError: (_) {});
    try {
      await task;
    } catch (e) {
      try {
        if (await local.exists()) await local.delete();
      } catch (_) {}
      rethrow;
    } finally {
      await sub.cancel();
    }
    if (!await local.exists() || await local.length() == 0) {
      throw 'The download came back empty. Please try again.';
    }
    return local.path;
  }

  /// Saves a cloud file into the phone's gallery / Downloads so it shows
  /// up in other apps. Returns the saved path, or null on failure (see
  /// [error]).
  Future<String?> downloadFile(CloudFile file) async {
    if (_isDownloading) return null;

    final user = _auth.currentUser;
    if (user == null) {
      _error = 'Please sign in to download files';
      notifyListeners();
      return null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _statusMessage = 'Starting download...';
    _error = null;
    notifyListeners();

    try {
      final cachedPath = await _fetchToCache(file);

      _statusMessage = 'Saving to your phone...';
      notifyListeners();

      final cachedName = cachedPath.split('/').last;
      final ext = _extOf(cachedName);
      final hasExt = _extOf(file.fileName).isNotEmpty;
      final saveName = hasExt ? file.fileName : '${file.fileName}.$ext';

      // MediaStore is the supported way to write into shared storage on
      // every modern Android version.
      String? savedPath = await NativeBridge.saveToMediaStore(
        sourcePath: cachedPath,
        fileName: saveName,
        platform: 'cloud',
        mimeType: file.mimeType,
      );

      // Older devices / anything MediaStore refused: plain file copy into
      // the app's Download folder.
      if (savedPath == null || savedPath.isEmpty) {
        try {
          final folder = await _storageService.getPlatformDownloadPath('Cloud');
          final target = '$folder/${_safeName(saveName)}';
          await File(cachedPath).copy(target);
          await _storageService.scanMediaFile(target);
          savedPath = target;
        } catch (e) {
          throw 'Could not save to your phone: '
              '${NativeBridge.lastMediaStoreError ?? e}';
        }
      }

      _statusMessage = 'Saved to your phone';
      _downloadProgress = 1.0;
      _isDownloading = false;
      notifyListeners();
      return savedPath;
    } catch (e) {
      _error = _friendlyError(e, uploading: false);
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
      // An object that is already gone must not block removing its
      // record — otherwise the entry could never be deleted.
      try {
        await _storage.ref(file.storagePath).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
      if (file.thumbnailPath.isNotEmpty) {
        try {
          await _storage.ref(file.thumbnailPath).delete();
        } catch (_) {}
      }

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
      _error = 'Delete failed: ${_friendlyError(e, uploading: false)}';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshQuota() async {
    await _loadQuotaAndPremiumStatus();
  }

  Future<bool>? _graceCheck;

  /// True when the subscription lapsed less than 24 hours ago. The answer
  /// is cached for the session so screens can call this from build()
  /// without re-reading Firestore on every rebuild.
  Future<bool> checkGracePeriod({bool refresh = false}) {
    if (refresh) _graceCheck = null;
    return _graceCheck ??= _readGracePeriod();
  }

  Future<bool> _readGracePeriod() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      if (_isOwner(user)) return false;

      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data() ?? {};
        final expiryDate = data['premiumExpiry'] as Timestamp?;
        if (expiryDate != null) {
          final expiry = expiryDate.toDate();
          final now = DateTime.now();
          final diff = expiry.difference(now);
          // Grace period of 24 hours — matches the "renew within 24h or
          // files are permanently deleted" copy in cloud_vault_screen.dart.
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

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
