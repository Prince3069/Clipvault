// models/status_item.dart
class StatusItem {
  final String id;
  final String path;
  final bool isVideo;
  final DateTime createdAt;
  final bool isDownloaded;

  StatusItem({
    required this.id,
    required this.path,
    required this.isVideo,
    required this.createdAt,
    this.isDownloaded = false,
  });
}
