// models/media_file.dart
import 'dart:io';

class MediaFile {
  final String id;
  final String path;
  final String fileName;
  final int fileSize;
  final bool isVideo;
  final String sourceApp;
  final DateTime createdAt;
  final DateTime viewedAt;
  final bool isDownloaded;
  final String? thumbnailPath;
  final Duration? duration;
  final Map<String, dynamic>? metadata;

  const MediaFile({
    required this.id,
    required this.path,
    required this.fileName,
    required this.fileSize,
    required this.isVideo,
    required this.sourceApp,
    required this.createdAt,
    required this.viewedAt,
    this.isDownloaded = false,
    this.thumbnailPath,
    this.duration,
    this.metadata,
  });

  /// Create MediaFile from file path
  factory MediaFile.fromPath(String filePath) {
    final fileName = filePath.split('/').last;
    final isVideo = _isVideoFile(filePath);
    final sourceApp = _detectSourceApp(filePath);

    return MediaFile(
      id: filePath.hashCode.toString(),
      path: filePath,
      fileName: fileName,
      fileSize: 0, // Will be populated when file is accessed
      isVideo: isVideo,
      sourceApp: sourceApp,
      createdAt: DateTime.now(),
      viewedAt: DateTime.now(),
    );
  }

  /// Create MediaFile from Map (from native side)
  factory MediaFile.fromMap(Map<dynamic, dynamic> map) {
    return MediaFile(
      id: map['id']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      fileSize: map['fileSize'] as int? ?? 0,
      isVideo: map['isVideo'] as bool? ?? false,
      sourceApp: map['sourceApp']?.toString() ?? 'unknown',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      viewedAt: DateTime.fromMillisecondsSinceEpoch(
        map['viewedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      isDownloaded: map['isDownloaded'] as bool? ?? false,
      thumbnailPath: map['thumbnailPath']?.toString(),
      duration: map['duration'] != null
          ? Duration(milliseconds: map['duration'] as int)
          : null,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  /// Convert MediaFile to Map (for native side)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'fileName': fileName,
      'fileSize': fileSize,
      'isVideo': isVideo,
      'sourceApp': sourceApp,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'viewedAt': viewedAt.millisecondsSinceEpoch,
      'isDownloaded': isDownloaded,
      'thumbnailPath': thumbnailPath,
      'duration': duration?.inMilliseconds,
      'metadata': metadata,
    };
  }

  /// Copy with new values
  MediaFile copyWith({
    String? id,
    String? path,
    String? fileName,
    int? fileSize,
    bool? isVideo,
    String? sourceApp,
    DateTime? createdAt,
    DateTime? viewedAt,
    bool? isDownloaded,
    String? thumbnailPath,
    Duration? duration,
    Map<String, dynamic>? metadata,
  }) {
    return MediaFile(
      id: id ?? this.id,
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      isVideo: isVideo ?? this.isVideo,
      sourceApp: sourceApp ?? this.sourceApp,
      createdAt: createdAt ?? this.createdAt,
      viewedAt: viewedAt ?? this.viewedAt,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      duration: duration ?? this.duration,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Get file extension
  String get extension {
    return fileName.split('.').last.toLowerCase();
  }

  /// Get formatted file size
  String get formattedSize {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// Get formatted duration for videos
  String get formattedDuration {
    if (duration == null) return '';

    final minutes = duration!.inMinutes;
    final seconds = duration!.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Get source app display name
  String get sourceAppDisplayName {
    switch (sourceApp) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'whatsapp_business':
        return 'WhatsApp Business';
      case 'instagram':
        return 'Instagram';
      case 'facebook':
        return 'Facebook';
      case 'tiktok':
        return 'TikTok';
      case 'twitter':
        return 'Twitter';
      
      default:
        return 'Unknown';
    }
  }

  /// Check if file was viewed today
  bool get isViewedToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final viewedDay = DateTime(viewedAt.year, viewedAt.month, viewedAt.day);
    return viewedDay.isAtSameMomentAs(today);
  }

  /// Check if file was viewed in last 24 hours
  bool get isViewedInLast24Hours {
    final twentyFourHoursAgo =
        DateTime.now().subtract(const Duration(hours: 24));
    return viewedAt.isAfter(twentyFourHoursAgo);
  }

  /// Check if file still exists on device
  bool get exists {
    try {
      return File(path).existsSync();
    } catch (e) {
      return false;
    }
  }

  /// Get file age in hours
  int get ageInHours {
    return DateTime.now().difference(createdAt).inHours;
  }

  /// Check if this is a WhatsApp status file
  bool get isWhatsAppStatus {
    return sourceApp.contains('whatsapp') && path.contains('.Statuses');
  }

  /// Check if this is a cached file (temporary)
  bool get isCachedFile {
    return path.contains('/cache/') || path.contains('/tmp/');
  }

  /// Get relative path for display
  String get relativePath {
    final segments = path.split('/');
    if (segments.length > 3) {
      return '.../${segments.sublist(segments.length - 3).join('/')}';
    }
    return path;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaFile &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          path == other.path;

  @override
  int get hashCode => id.hashCode ^ path.hashCode;

  @override
  String toString() {
    return 'MediaFile{id: $id, fileName: $fileName, sourceApp: $sourceApp, isVideo: $isVideo, size: $formattedSize}';
  }

  /// Helper method to detect if file is video
  static bool _isVideoFile(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    return videoExtensions.contains(extension);
  }

  /// Helper method to detect source app from path
  static String _detectSourceApp(String filePath) {
    if (filePath.contains('whatsapp')) {
      return filePath.contains('w4b') ? 'whatsapp_business' : 'whatsapp';
    } else if (filePath.contains('instagram')) {
      return 'instagram';
    } else if (filePath.contains('musically')) {
      return 'tiktok';
    } else if (filePath.contains('facebook')) {
      return 'facebook';
    } else if (filePath.contains('twitter')) {
      return 'twitter';
    }
    return 'unknown';
  }
}
