// ui/widgets/platform_filter_chips.dart
import 'package:flutter/material.dart';

class PlatformFilterChips extends StatelessWidget {
  final String selectedPlatform;
  final Function(String) onPlatformSelected;

  const PlatformFilterChips({
    Key? key,
    required this.selectedPlatform,
    required this.onPlatformSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final platforms = [
      {'id': 'all', 'name': 'All', 'icon': Icons.apps, 'color': Colors.grey},
      {
        'id': 'whatsapp',
        'name': 'WhatsApp',
        'icon': Icons.message,
        'color': Colors.green
      },
      {
        'id': 'instagram',
        'name': 'Instagram',
        'icon': Icons.camera_alt,
        'color': Colors.purple
      },
      {
        'id': 'facebook',
        'name': 'Facebook',
        'icon': Icons.facebook,
        'color': Colors.blue
      },
      {
        'id': 'tiktok',
        'name': 'TikTok',
        'icon': Icons.music_note,
        'color': Colors.black
      },
      {
        'id': 'twitter',
        'name': 'Twitter',
        'icon': Icons.alternate_email,
        'color': Colors.lightBlue
      },
    ];

    return Wrap(
      spacing: 8,
      children: platforms.map((platform) {
        final isSelected = selectedPlatform == platform['id'];
        return FilterChip(
          selected: isSelected,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                platform['icon'] as IconData,
                size: 16,
                color: isSelected ? Colors.white : platform['color'] as Color,
              ),
              const SizedBox(width: 4),
              Text(platform['name'] as String),
            ],
          ),
          onSelected: (selected) {
            onPlatformSelected(platform['id'] as String);
          },
          selectedColor: platform['color'] as Color,
          checkmarkColor: Colors.white,
        );
      }).toList(),
    );
  }
}
