// ui/widgets/social_media_card.dart
import 'package:flutter/material.dart';
import '../../models/social_media_platform.dart';

class SocialMediaCard extends StatelessWidget {
  final SocialMediaPlatform platform;
  final VoidCallback onTap;

  const SocialMediaCard({
    Key? key,
    required this.platform,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon would be loaded from assets in a real app
              Icon(
                _getPlatformIcon(platform.id),
                size: 36,
                color: _getPlatformColor(platform.id),
              ),
              const SizedBox(height: 8),
              Text(
                platform.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platformId) {
    switch (platformId) {
      case 'instagram':
        return Icons.camera_alt;
      case 'facebook':
        return Icons.facebook;
      case 'tiktok':
        return Icons.music_note;
      case 'twitter':
        return Icons.tag;
      default:
        return Icons.public;
    }
  }

  Color _getPlatformColor(String platformId) {
    switch (platformId) {
      case 'instagram':
        return Colors.pink;
      case 'facebook':
        return Colors.blue;
      case 'tiktok':
        return const Color.fromARGB(255, 230, 202, 202);
      case 'twitter':
        return Colors.lightBlue;
      default:
        return Colors.grey;
    }
  }
}
