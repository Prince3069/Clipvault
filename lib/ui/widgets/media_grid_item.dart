// ui/widgets/media_grid_item.dart
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/media_file.dart';

class MediaGridItem extends StatelessWidget {
  final MediaFile mediaFile;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const MediaGridItem({
    Key? key,
    required this.mediaFile,
    required this.onTap,
    required this.onDownload,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Media Preview
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    // Background image/video preview
                    _buildMediaPreview(),

                    // Platform badge
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getPlatformColor().withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getPlatformIcon(),
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              mediaFile.sourceAppDisplayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Video play indicator
                    if (mediaFile.isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),

                    // Duration for videos
                    if (mediaFile.isVideo && mediaFile.duration != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            mediaFile.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Download status indicator
                    if (mediaFile.isDownloaded)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Media Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // File name
                  Text(
                    mediaFile.fileName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 4),

                  // File info row
                  Row(
                    children: [
                      Icon(
                        mediaFile.isVideo ? Icons.videocam : Icons.image,
                        size: 14,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          mediaFile.formattedSize,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      Text(
                        _getTimeAgo(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onDownload,
                          icon: Icon(
                            mediaFile.isDownloaded
                                ? Icons.download_done
                                : Icons.download,
                            size: 16,
                          ),
                          label: Text(
                            mediaFile.isDownloaded ? 'Downloaded' : 'Download',
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            backgroundColor: mediaFile.isDownloaded
                                ? Colors.green
                                : Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _showMoreOptions(context),
                        icon: const Icon(Icons.more_vert),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (mediaFile.exists && !mediaFile.isCachedFile) {
      // Show actual file preview
      return mediaFile.isVideo
          ? _buildVideoThumbnail()
          : Image.file(
              File(mediaFile.path),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
            );
    } else {
      // Show placeholder for cached or non-existent files
      return _buildPlaceholder();
    }
  }

  Widget _buildVideoThumbnail() {
    // For videos, show a dark background with play icon
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black87,
      child: const Center(
        child: Icon(
          Icons.movie,
          size: 40,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[300],
      child: Center(
        child: Icon(
          mediaFile.isVideo ? Icons.movie : Icons.image,
          size: 40,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Color _getPlatformColor() {
    switch (mediaFile.sourceApp) {
      case 'whatsapp':
      case 'whatsapp_business':
        return Colors.green;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue;
      case 'tiktok':
        return Colors.black;
      case 'twitter':
        return Colors.lightBlue;
      default:
        return Colors.grey;
    }
  }

  IconData _getPlatformIcon() {
    switch (mediaFile.sourceApp) {
      case 'whatsapp':
      case 'whatsapp_business':
        return Icons.message;
      case 'instagram':
        return Icons.camera_alt;
      case 'facebook':
        return Icons.facebook;
      case 'tiktok':
        return Icons.music_note;
      case 'twitter':
        return Icons.alternate_email;
      default:
        return Icons.apps;
    }
  }

  String _getTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(mediaFile.viewedAt);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.info),
            title: const Text('File Info'),
            onTap: () {
              Navigator.pop(context);
              _showFileInfo(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.share),
            title: const Text('Share'),
            onTap: () {
              Navigator.pop(context);
              // Implement share functionality
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Show in Folder'),
            onTap: () {
              Navigator.pop(context);
              // Implement show in folder functionality
            },
          ),
          if (!mediaFile.isDownloaded)
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(context);
                onDownload();
              },
            ),
        ],
      ),
    );
  }

  void _showFileInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Name', mediaFile.fileName),
            _buildInfoRow('Size', mediaFile.formattedSize),
            _buildInfoRow('Source', mediaFile.sourceAppDisplayName),
            _buildInfoRow('Type', mediaFile.isVideo ? 'Video' : 'Image'),
            if (mediaFile.isVideo && mediaFile.duration != null)
              _buildInfoRow('Duration', mediaFile.formattedDuration),
            _buildInfoRow('Created', _formatDate(mediaFile.createdAt)),
            _buildInfoRow('Viewed', _formatDate(mediaFile.viewedAt)),
            _buildInfoRow('Path', mediaFile.relativePath),
            _buildInfoRow('Downloaded', mediaFile.isDownloaded ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
