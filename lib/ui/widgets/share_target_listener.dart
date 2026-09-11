// ui/widgets/share_target_listener.dart
// Web safe version

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/share_target_service.dart';
import '../../services/cobalt_api_service.dart';
import '../../providers/download_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/premium_provider.dart';
import '../themes/app_theme.dart';
import '../screens/browser_download_screen.dart';
import '../screens/premium_screen.dart';

class ShareTargetListener extends StatefulWidget {
  final Widget child;

  const ShareTargetListener({Key? key, required this.child}) : super(key: key);

  @override
  State<ShareTargetListener> createState() => _ShareTargetListenerState();
}

class _ShareTargetListenerState extends State<ShareTargetListener> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Only register on non-web platforms
    if (!kIsWeb) {
      ShareTargetService.instance.onShareReceived(_handleShare);
      ShareTargetService.instance.onSharedMedia(_handleSharedMedia);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pendingMedia = ShareTargetService.instance.getPendingSharedMediaPath();
        if (pendingMedia != null && pendingMedia.isNotEmpty) {
          _handleSharedMedia(pendingMedia);
        }
        final pending = ShareTargetService.instance.getPendingSharedText();
        if (pending != null && pending.isNotEmpty) {
          _handleShare(pending);
        }
      });
    }
  }

  Future<void> _handleSharedMedia(String path) async {
    if (!mounted || kIsWeb) return;
    final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
    final imported = await mediaProvider.importSharedMedia(path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(imported
            ? 'Shared media added to your MediaNest library.'
            : 'MediaNest could not import that shared media.'),
        backgroundColor: imported ? AppColors.primary : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleShare(String url) {
    if (_isProcessing || kIsWeb) return;
    if (!mounted) return;

    if (!CobaltApiService.isSupportedUrl(url)) {
      _showNotSupportedDialog(url);
      return;
    }

    _processSharedUrl(url);
  }

  Future<void> _processSharedUrl(String url) async {
    if (_isProcessing || kIsWeb) return;
    setState(() => _isProcessing = true);

    try {
      final premium = Provider.of<PremiumProvider>(context, listen: false);
      if (!premium.canDownload) {
        _showLimitReachedDialog(premium);
        setState(() => _isProcessing = false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.share_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '📤 Opening shared link: ${_truncateUrl(url)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BrowserDownloadScreen(url: url),
          ),
        );
      }
    } catch (e) {
      print('❌ Process shared URL error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error processing share: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showNotSupportedDialog(String url) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: const Text('Unsupported Link'),
        content: Text(
          'The shared link is not from a supported platform.\n\n'
          'Supported platforms: TikTok, Instagram, Facebook, Twitter, '
          'Vimeo, LinkedIn, Pinterest, Reddit, and more.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showLimitReachedDialog(PremiumProvider premium) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF9500)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Daily Limit Reached',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'ve used ${premium.downloadsToday} of ${PremiumProvider.kFreeDailyLimit} free downloads today.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PremiumScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_rounded),
                  label: const Text('Upgrade to Pro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Maybe Later'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _truncateUrl(String url) {
    if (url.length <= 40) return url;
    return '${url.substring(0, 40)}...';
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
