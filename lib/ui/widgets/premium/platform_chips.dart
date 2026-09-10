// ui/widgets/premium/platform_chips.dart
// Supported Platforms as Chips

import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class PlatformChips extends StatelessWidget {
  const PlatformChips({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Supported Platforms',
            style: AppTypography.titleLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _PlatformChip(
              label: 'TikTok',
              icon: Icons.music_note_rounded,
              color: AppColors.tiktok,
            ),
            _PlatformChip(
              label: 'Instagram',
              icon: Icons.camera_alt_rounded,
              color: AppColors.instagram,
            ),
            _PlatformChip(
              label: 'Facebook',
              icon: Icons.facebook,
              color: AppColors.facebook,
            ),
            _PlatformChip(
              label: 'Twitter/X',
              icon: Icons.alternate_email,
              color: AppColors.twitter,
            ),
            _PlatformChip(
              label: 'Vimeo',
              icon: Icons.play_circle_rounded,
              color: AppColors.vimeo,
            ),
            _PlatformChip(
              label: 'LinkedIn',
              icon: Icons.business_rounded,
              color: AppColors.linkedin,
            ),
            _PlatformChip(
              label: 'Pinterest',
              icon: Icons.push_pin_rounded,
              color: AppColors.pinterest,
            ),
            _PlatformChip(
              label: 'Reddit',
              icon: Icons.reddit,
              color: AppColors.reddit,
            ),
            _PlatformChip(
              label: '+ More',
              icon: Icons.more_horiz_rounded,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ],
    );
  }
}

class _PlatformChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _PlatformChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
