// ui/widgets/premium/repurpose_studio.dart - ENHANCED WITH FULL AI
// COMPLETE - One-Tap Repurpose Studio with Real AI Power

import 'dart:convert';
import 'dart:io';

import 'package:all_social_downloader/ui/screens/premium_screen.dart';
import 'package:all_social_downloader/ui/screens/buy_credits_screen.dart';
import 'package:all_social_downloader/ui/themes/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/ai_service.dart';
import '../../../providers/premium_provider.dart';
import '../../../services/storage_service.dart';
import '../../../services/native_bridge.dart';

class RepurposeStudio extends StatefulWidget {
  final String videoId;
  final String videoTitle;
  final String videoPath;
  final String platform;
  final VoidCallback? onComplete;

  const RepurposeStudio({
    Key? key,
    required this.videoId,
    required this.videoTitle,
    required this.videoPath,
    required this.platform,
    this.onComplete,
  }) : super(key: key);

  @override
  State<RepurposeStudio> createState() => _RepurposeStudioState();
}

class _RepurposeStudioState extends State<RepurposeStudio> {
  final AIService _ai = AIService();
  final StorageService _storage = StorageService();

  bool _isGenerating = false;
  Map<String, dynamic>? _results;
  String? _error;
  int _remainingCredits = 0;
  bool _isPremium = false;
  int _freePacksRemaining = 2;
  double _processingProgress = 0.0;
  String _processingMessage = '';

  final List<RepurposeActionItem> _actions = [
    const RepurposeActionItem(
      id: 'quick_pack',
      icon: Icons.auto_awesome_rounded,
      label: 'Quick Pack',
      description: 'Free: Caption + Checklist',
      color: Color(0xFF6C63FF),
    ),
    const RepurposeActionItem(
      id: 'caption',
      icon: Icons.text_fields_rounded,
      label: 'Smart Caption',
      description: 'AI writes engaging captions',
      color: Color(0xFF6C63FF),
    ),
    const RepurposeActionItem(
      id: 'hashtags',
      icon: Icons.tag_rounded,
      label: 'Smart Hashtags',
      description: 'Trending & niche hashtags',
      color: Color(0xFF00C2FF),
    ),
    const RepurposeActionItem(
      id: 'subtitle',
      icon: Icons.closed_caption_rounded,
      label: 'Subtitles',
      description: 'Auto-generate SRT file',
      color: Color(0xFF22C55E),
    ),
    const RepurposeActionItem(
      id: 'translate',
      icon: Icons.translate_rounded,
      label: 'Translate',
      description: 'Translate captions/speech',
      color: Color(0xFFF59E0B),
    ),
    const RepurposeActionItem(
      id: 'summarize',
      icon: Icons.auto_awesome_rounded,
      label: 'Summarize',
      description: 'Key points and takeaways',
      color: Color(0xFFEC4899),
    ),
    const RepurposeActionItem(
      id: 'script',
      icon: Icons.description_rounded,
      label: 'Script',
      description: 'Full video script',
      color: Color(0xFF8B5CF6),
    ),
    const RepurposeActionItem(
      id: 'tweet_thread',
      icon: Icons.chat_rounded,
      label: 'Tweet Thread',
      description: 'Twitter/X thread',
      color: Color(0xFF1DA1F2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadCreditsAndPremium();
  }

  Future<void> _loadCreditsAndPremium() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().split('T').first;
    final storedDay = prefs.getString('repurpose_free_day');
    if (storedDay != today) {
      await prefs.setString('repurpose_free_day', today);
      await prefs.setInt('repurpose_free_remaining', 2);
    }
    final premium = await _ai.verifyPremium();
    final isPremium = premium['isPremium'] ?? false;

    // The real /getAICredits shape has no field called "credits" — that
    // never existed server-side, so this used to silently read 0 for
    // everyone. Premium users get a real remainingCredits number; free
    // users don't need one here since every AI action except Quick Pack
    // is fully premium-gated regardless of credits.
    int remaining = 0;
    if (isPremium) {
      final credits = await _ai.getAICredits();
      remaining = credits['remainingCredits'] as int? ?? 0;
    }

    if (mounted) {
      setState(() {
        _remainingCredits = remaining;
        _isPremium = isPremium;
        _freePacksRemaining = prefs.getInt('repurpose_free_remaining') ?? 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.05),
            AppColors.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: AppSpacing.md),
          _buildCreditsBar(),
          const SizedBox(height: AppSpacing.md),
          _buildActionsGrid(),
          const SizedBox(height: AppSpacing.md),
          if (_results != null) _buildResults(),
          if (_isGenerating) _buildLoading(),
          if (_error != null) _buildError(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(Icons.auto_awesome_rounded,
              color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Repurpose Studio', style: AppTypography.titleMedium),
              Text(
                'AI-powered tools for your content',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (!_isPremium)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.workspace_premium_rounded,
                    color: AppColors.warning, size: 14),
                const SizedBox(width: 4),
                Text('Pro',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.warning, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCreditsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, color: AppColors.warning, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _isPremium
                ? '$_remainingCredits AI credits remaining'
                : '$_freePacksRemaining free packs · $_remainingCredits AI credits',
            style:
                AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (!_isPremium)
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const PremiumScreen(),
                ));
              },
              child: Text(
                'Get More',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.1,
      ),
      itemCount: _actions.length,
      itemBuilder: (context, index) {
        final action = _actions[index];
        final isLocked = action.id != 'quick_pack' && !_isPremium;

        return GestureDetector(
          onTap: () {
            if (isLocked) {
              _showPremiumDialog();
            } else {
              _handleAction(action.id);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: isLocked ? AppColors.surfaceAlt : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isLocked
                    ? AppColors.border
                    : action.color.withValues(alpha: 0.2),
              ),
              boxShadow: isLocked ? null : AppShadows.soft,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? AppColors.border
                            : action.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        isLocked ? Icons.lock_rounded : action.icon,
                        color: isLocked ? AppColors.textMuted : action.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.label,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isLocked
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.id == 'quick_pack' ? 'FREE' : 'PRO',
                      style: AppTypography.caption.copyWith(
                        color:
                            !isLocked ? AppColors.success : AppColors.textMuted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
                if (_results != null && _results!.containsKey(action.id))
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ),
                if (isLocked)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.workspace_premium_rounded,
                          color: AppColors.warning, size: 10),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildResults() {
    if (_results == null || _results!.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 16),
              const SizedBox(width: AppSpacing.sm),
              const Text('AI Results', style: AppTypography.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _results = null),
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._results!.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _ResultItem(
                  actionId: entry.key,
                  label: _actions.firstWhere((a) => a.id == entry.key).label,
                  result: entry.value,
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  _processingMessage.isNotEmpty
                      ? _processingMessage
                      : 'AI is working its magic...',
                  style: AppTypography.bodyMedium,
                ),
              ),
              if (_processingProgress > 0)
                Text(
                  '${(_processingProgress * 100).toInt()}%',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (_processingProgress > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _processingProgress.clamp(0.0, 1.0),
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 16),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAction(String actionId) async {
    // Quick Pack - Free deterministic action
    if (actionId == 'quick_pack') {
      if (!_isPremium && _freePacksRemaining <= 0) {
        _showPremiumDialog();
        return;
      }

      setState(() {
        _isGenerating = true;
        _processingMessage = 'Creating your Quick Pack...';
        _processingProgress = 0.0;
        _error = null;
      });

      // Simulate progress for better UX
      for (int i = 0; i <= 100; i += 10) {
        await Future.delayed(Duration(milliseconds: 100));
        if (mounted) {
          setState(() => _processingProgress = i / 100);
        }
      }

      if (!_isPremium) {
        final prefs = await SharedPreferences.getInstance();
        final remaining = (_freePacksRemaining - 1).clamp(0, 2);
        await prefs.setInt('repurpose_free_remaining', remaining);
        if (mounted) {
          setState(() => _freePacksRemaining = remaining);
        }
      }

      final result = {
        'title': 'Quick Creator Pack',
        'caption': _generateQuickCaption(),
        'checklist': [
          '📹 Hook: Open with your strongest visual or statement',
          '📝 Context: Add your unique perspective or story',
          '🎯 Call to Action: End with one clear next step',
          '🏷️ Tags: #${widget.platform} #ContentCreator #Viral',
          '⏰ Timing: Post when your audience is most active',
        ],
        'script': _generateQuickScript(),
      };

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _results = {...?_results, 'quick_pack': result};
        });
        widget.onComplete?.call();
        _showSuccessSnackbar('Quick Pack ready!');
      }
      return;
    }

    // AI Actions - Use the AI service
    setState(() {
      _isGenerating = true;
      _processingMessage = 'Starting AI processing...';
      _processingProgress = 0.0;
      _error = null;
    });

    try {
      // Update progress
      setState(() => _processingProgress = 0.2);
      _processingMessage = 'Analyzing your content...';
      await Future.delayed(const Duration(milliseconds: 300));

      setState(() => _processingProgress = 0.5);
      _processingMessage = 'Generating with AI...';
      await Future.delayed(const Duration(milliseconds: 300));

      final result = await _ai.processAction(
        actionId: actionId,
        videoId: widget.videoId,
        videoTitle: widget.videoTitle,
        videoPath: widget.videoPath,
        platform: widget.platform,
      );

      setState(() => _processingProgress = 0.9);
      _processingMessage = 'Finalizing...';
      await Future.delayed(const Duration(milliseconds: 200));

      if (!mounted) return;

      // The server always says success:true/false — this used to default
      // straight to a hardcoded "Generated successfully!" without ever
      // checking that flag, so a 402 (not premium) or 429 (budget used up)
      // response looked identical to a real result. Checking it is what
      // actually makes the premium gate mean anything.
      if (result['success'] == true) {
        setState(() {
          _isGenerating = false;
          _processingProgress = 1.0;
          _remainingCredits = result['remainingCredits'] ?? _remainingCredits;
          if (_results == null) _results = {};
          _results![actionId] = result['result'] ?? 'Generated successfully!';
        });
        _showSuccessSnackbar('${_getActionLabel(actionId)} generated!');
        widget.onComplete?.call();
        return;
      }

      // Real failure — show the server's actual reason, not a fabricated
      // result that looks like it worked.
      final serverError =
          (result['error'] as String?) ?? 'Something went wrong';
      setState(() {
        _isGenerating = false;
        _processingProgress = 0;
      });
      if (serverError.toLowerCase().contains('upgrade') ||
          serverError.toLowerCase().contains('premium')) {
        _showPremiumDialog();
      } else if (serverError.toLowerCase().contains('budget')) {
        _showBudgetExhaustedDialog(serverError);
      } else {
        setState(() => _error = serverError);
      }
    } catch (e) {
      // A genuine network/parsing failure — say so plainly. No fabricated
      // "offline mode" result; that's exactly what let free users get a
      // real-looking output for free with zero indication anything failed.
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _processingProgress = 0;
          _error =
              'Could not reach the server. Check your connection and try again.';
        });
      }
    }
  }

  String _generateQuickCaption() {
    final titles = [
      '🔥 This moment is too good not to share!',
      '💡 Save this for later - it\'s a game changer!',
      '✨ When creativity meets execution...',
      '🚀 The best content is the one you create!',
      '🎯 Stay focused, stay creative, stay you!',
    ];
    return titles[DateTime.now().millisecond % titles.length];
  }

  String _generateQuickScript() {
    return '''
🎬 QUICK SCRIPT

HOOK (0-3s):
Start with your most compelling visual or statement.

BODY (3-15s):
Share your unique perspective. What makes this content special?
Add value: insight, humor, or inspiration.

CLOSE (15-30s):
End with a clear call to action.
Ask viewers to like, comment, or share.

📝 TIP: Keep it authentic and engaging!
''';
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  void _showPremiumDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.primary, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text('Unlock All AI Tools',
                  style: AppTypography.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Get access to all repurpose tools including subtitles, translation, summarization, and more.',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PremiumScreen(),
                    ));
                  },
                  child: const Text('Upgrade to Pro'),
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

  void _showBudgetExhaustedDialog(String serverMessage) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              const Icon(Icons.bolt_rounded,
                  color: AppColors.warning, size: 48),
              const SizedBox(height: AppSpacing.md),
              const Text('AI allowance used up',
                  style: AppTypography.headlineMedium),
              const SizedBox(height: AppSpacing.sm),
              // The server's own message — it already says exactly what
              // happened and what to do (buy credits or wait for renewal),
              // no need to guess at different copy here.
              Text(
                serverMessage,
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const BuyCreditsScreen(),
                    ));
                  },
                  child: const Text('Buy Credits'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getActionLabel(String actionId) {
    return _actions.firstWhere((a) => a.id == actionId).label;
  }
}

// ─── Supporting Models ──────────────────────────────────────────────────────

class RepurposeActionItem {
  final String id;
  final IconData icon;
  final String label;
  final String description;
  final Color color;

  const RepurposeActionItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
  });
}

class _ResultItem extends StatelessWidget {
  final String actionId;
  final String label;
  final dynamic result;

  const _ResultItem({
    required this.actionId,
    required this.label,
    required this.result,
  });

  @override
  Widget build(BuildContext context) {
    String displayText = '';
    String fullText = '';

    if (result is String) {
      displayText = result;
      fullText = result;
    } else if (result is Map) {
      fullText = result['result'] ??
          result['text'] ??
          result['caption'] ??
          result['summary'] ??
          result['translation'] ??
          jsonEncode(result);
      displayText = fullText;

      // Show special content for different action types
      if (result.containsKey('caption')) {
        displayText = result['caption'];
        fullText = result['caption'];
      } else if (result.containsKey('checklist')) {
        displayText = (result['checklist'] as List).take(3).join(' • ');
        fullText = (result['checklist'] as List).join('\n');
      }
    } else if (result is List) {
      displayText = result.take(3).join(' • ');
      fullText = result.join('\n');
    } else {
      displayText = result.toString();
      fullText = result.toString();
    }

    if (displayText.length > 80) {
      displayText = '${displayText.substring(0, 80)}...';
    }

    return Row(
      children: [
        Container(
          width: 3,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
              Text(
                displayText,
                style: AppTypography.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: fullText));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard!'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded,
                  size: 16, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () {
                // Share the result
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Share feature coming soon!'),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.share_rounded,
                  size: 16, color: AppColors.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }
}
