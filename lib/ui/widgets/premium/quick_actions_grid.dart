// ui/widgets/premium/quick_actions_grid.dart
// Quick Action Cards for the Home Screen

import 'package:flutter/material.dart';
import '../../themes/app_theme.dart';

class QuickActionsGrid extends StatelessWidget {
  final VoidCallback onWhatsAppTap;
  final VoidCallback onSavedTap;
  final VoidCallback onCloudTap;

  const QuickActionsGrid({
    Key? key,
    required this.onWhatsAppTap,
    required this.onSavedTap,
    required this.onCloudTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Quick Actions',
            style: AppTypography.titleLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Row(
          children: [
            _ActionCard(
              icon: Icons.chat_bubble_rounded,
              label: 'WhatsApp Status',
              color: AppColors.whatsapp,
              onTap: onWhatsAppTap,
            ),
            const SizedBox(width: AppSpacing.sm),
            _ActionCard(
              icon: Icons.folder_rounded,
              label: 'My Library',
              color: AppColors.primary,
              onTap: onSavedTap,
            ),
            const SizedBox(width: AppSpacing.sm),
            _ActionCard(
              icon: Icons.cloud_rounded,
              label: 'Cloud Vault',
              color: AppColors.secondary,
              onTap: onCloudTap,
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.soft,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
