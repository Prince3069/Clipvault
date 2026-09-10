// ui/widgets/recently_viewed_section.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/media_provider.dart';
import '../../models/media_file.dart';

class RecentlyViewedSection extends StatelessWidget {
  const RecentlyViewedSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaProvider>(
      builder: (context, mediaProvider, child) {
        final recentMedia = mediaProvider.recentlyViewed.take(5).toList();

        if (recentMedia.isEmpty) {
          return Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history,
                    size: 32,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No recent media',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: recentMedia.length,
            itemBuilder: (context, index) {
              final mediaFile = recentMedia[index];
              return Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                child: _buildRecentMediaItem(context, mediaFile),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildRecentMediaItem(BuildContext context, MediaFile mediaFile) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _openMediaViewer(context, mediaFile),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(8)),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.grey[300],
                      child: Icon(
                        mediaFile.isVideo ? Icons.movie : Icons.image,
                        size: 24,
                        color: Colors.grey[600],
                      ),
                    ),
                    if (mediaFile.isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 24,
                          color: Colors.white,
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: _getPlatformColor(mediaFile.sourceApp),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          _getPlatformIcon(mediaFile.sourceApp),
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                mediaFile.fileName,
                style: const TextStyle(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMediaViewer(BuildContext context, MediaFile mediaFile) {
    // Navigate to media viewer
    Navigator.pushNamed(
      context,
      '/media_viewer',
      arguments: mediaFile,
    );
  }

  Color _getPlatformColor(String sourceApp) {
    switch (sourceApp) {
      case 'whatsapp':
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

  IconData _getPlatformIcon(String sourceApp) {
    switch (sourceApp) {
      case 'whatsapp':
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
}
