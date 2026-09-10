// models/download_item.dart
class DownloadItem {
  final String id;
  final String url;
  final String fileName;
  final String thumbnailUrl;
  final String sourceApp;
  final DateTime dateAdded;
  final String localPath;
  final DownloadStatus status;
  final double progress;
  final String? errorMessage;

  const DownloadItem({
    required this.id,
    required this.url,
    required this.fileName,
    required this.thumbnailUrl,
    required this.sourceApp,
    required this.dateAdded,
    this.localPath = '',
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
  });

  DownloadItem copyWith({
    String? id,
    String? url,
    String? fileName,
    String? thumbnailUrl,
    String? sourceApp,
    DateTime? dateAdded,
    String? localPath,
    DownloadStatus? status,
    double? progress,
    String? errorMessage,
  }) {
    return DownloadItem(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      sourceApp: sourceApp ?? this.sourceApp,
      dateAdded: dateAdded ?? this.dateAdded,
      localPath: localPath ?? this.localPath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

enum DownloadStatus { pending, downloading, completed, failed, canceled }
