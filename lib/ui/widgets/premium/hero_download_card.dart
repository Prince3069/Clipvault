// ui/widgets/premium/hero_download_card.dart
// Premium Hero Download Card - The centerpiece of the home screen

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../themes/app_theme.dart';

class HeroDownloadCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isProcessing;
  final String? clipboardUrl;
  final VoidCallback onDownload;
  final VoidCallback onClearClipboard;

  const HeroDownloadCard({
    Key? key,
    required this.controller,
    required this.focusNode,
    required this.isProcessing,
    this.clipboardUrl,
    required this.onDownload,
    required this.onClearClipboard,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isFocused = focusNode.hasFocus;
    final hasText = controller.text.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: AppShadows.primary,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.link_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paste a Link',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Download from any supported platform',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Input Field
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isFocused
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.2),
                  width: isFocused ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'https://www.tiktok.com/@...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      onSubmitted: (_) => onDownload(),
                    ),
                  ),
                  if (hasText)
                    IconButton(
                      onPressed: () {
                        controller.clear();
                      },
                      icon: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 18,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // Action Row
            Row(
              children: [
                // Download Button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : onDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download_rounded, size: 18),
                              SizedBox(width: AppSpacing.sm),
                              Text(
                                'Download',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(width: AppSpacing.sm),

                // Paste Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing
                        ? null
                        : () async {
                            final data =
                                await Clipboard.getData(Clipboard.kTextPlain);
                            final text = data?.text?.trim() ?? '';
                            if (text.isNotEmpty) {
                              controller.text = text;
                            }
                          },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: const Icon(Icons.content_paste_rounded, size: 18),
                  ),
                ),
              ],
            ),

            // Clipboard Banner
            if (clipboardUrl != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.content_paste_rounded,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 16,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Link detected in clipboard',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClearClipboard,
                      child: Icon(
                        Icons.close_rounded,
                        color: Colors.white.withValues(alpha: 0.4),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
