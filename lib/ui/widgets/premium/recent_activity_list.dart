// ui/widgets/premium/recent_activity_list.dart
// Recent Downloads Activity List

import 'package:all_social_downloader/models/download_item.dart';
import 'package:all_social_downloader/providers/download_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import '../../models/download_item.dart';
// import '../../providers/download_provider.dart';
import '../../themes/app_theme.dart';

class RecentActivityList extends StatelessWidget {
  const RecentActivityList({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadProvider>(
      builder: (_, provider, __) {
        final recent = provider.downloads
            .where((d) =>
                d.status == DownloadStatus.completed ||
                d.status == DownloadStatus.downloading)
            .take(3)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: AppTypography.titleLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (provider.downloads.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      // Navigate to full downloads list
                    },
                    child: Text(
                      'See All',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (recent.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.download_outlined,
                        size: 32,
                        color: AppColors.textMuted,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'No recent downloads',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        'Download your first video to get started',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...recent.map((item) => _RecentItem(item: item)),
          ],
        );
      },
    );
  }
}

class _RecentItem extends StatelessWidget {
  final DownloadItem item;

  const _RecentItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDownloading = item.status == DownloadStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _getPlatformColor(item.sourceApp).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              _getPlatformIcon(item.sourceApp),
              color: _getPlatformColor(item.sourceApp),
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.fileName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Text(
                      _formatDate(item.dateAdded),
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: AppColors.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (isDownloading)
                      Text(
                        '${(item.progress * 100).toInt()}%',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else
                      Text(
                        'Completed',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                if (isDownloading) const SizedBox(height: 4),
                if (isDownloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 2,
                      backgroundColor: AppColors.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Icon(
            isDownloading
                ? Icons.more_horiz_rounded
                : Icons.check_circle_rounded,
            color: isDownloading ? AppColors.textMuted : AppColors.success,
            size: 20,
          ),
        ],
      ),
    );
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return AppColors.tiktok;
      case 'instagram':
        return AppColors.instagram;
      case 'facebook':
        return AppColors.facebook;
      case 'twitter':
        return AppColors.twitter;
      case 'whatsapp':
        return AppColors.whatsapp;
      case 'vimeo':
        return AppColors.vimeo;
      default:
        return AppColors.primary;
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'tiktok':
        return Icons.music_note_rounded;
      case 'instagram':
        return Icons.camera_alt_rounded;
      case 'facebook':
        return Icons.facebook;
      case 'twitter':
        return Icons.alternate_email;
      case 'whatsapp':
        return Icons.chat_bubble_rounded;
      case 'vimeo':
        return Icons.play_circle_rounded;
      default:
        return Icons.link_rounded;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}
