// ui/widgets/premium/creator_stats_card.dart
// Statistics Card showing downloads, storage, etc.

// import 'package:all_social_downloader/models/download_item.dart';
// import 'package:all_social_downloader/providers/download_provider.dart';
// import 'package:all_social_downloader/providers/media_provider.dart';
// import 'package:all_social_downloader/providers/premium_provider.dart';
import 'package:flutter/material.dart';
import 'package:medianest/models/download_item.dart';
import 'package:medianest/providers/download_provider.dart';
import 'package:medianest/providers/media_provider.dart';
import 'package:medianest/providers/premium_provider.dart';
import 'package:provider/provider.dart';

import '../../themes/app_theme.dart';

class CreatorStatsCard extends StatelessWidget {
  const CreatorStatsCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer3<DownloadProvider, MediaProvider, PremiumProvider>(
      builder: (_, downloadProvider, mediaProvider, premium, __) {
        final completedDownloads = downloadProvider.downloads
            .where((d) => d.status == DownloadStatus.completed)
            .length;

        final totalMedia = mediaProvider.allMedia.length +
            mediaProvider.whatsappImages.length +
            mediaProvider.whatsappVideos.length;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(
                value: '$completedDownloads',
                label: 'Downloads',
                icon: Icons.download_rounded,
                color: AppColors.primary,
              ),
              _StatItem(
                value: '$totalMedia',
                label: 'Media Files',
                icon: Icons.folder_rounded,
                color: AppColors.secondary,
              ),
              _StatItem(
                value: premium.isPremium ? 'Pro' : 'Free',
                label: 'Plan',
                icon: premium.isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.star_rounded,
                color:
                    premium.isPremium ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.titleMedium.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
