// ui/widgets/premium/repurpose_studio.dart
// Repurpose Studio — multi-variant + tone-aware.
//
// The previous version surfaced ONE result per action. This version
// requests THREE variants, shows them as selectable cards, and exposes a
// tone picker + per-variant Remix. The intent: give the user choices,
// not opinions.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medianest/ui/screens/buy_credits_screen.dart';
import 'package:medianest/ui/screens/premium_screen.dart';
import 'package:medianest/ui/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/ai_service.dart';
import '../../../services/repurpose_service.dart';
import '../../../providers/premium_provider.dart';

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
  final RepurposeService _repurpose = RepurposeService();

  bool _isGenerating = false;
  String? _error;
  String _processingMessage = '';
  double _processingProgress = 0.0;

  // Result storage: actionId → list of 3 variant strings.
  final Map<String, List<String>> _results = {};

  // Currently selected tone for the NEXT action. Defaults to 'default'.
  String _selectedTone = 'default';

  // Which action's result is expanded for viewing right now.
  String? _expandedAction;

  // Analysis key cache (see _ensureAnalysisKey).
  String? _analysisKey;

  bool _isPremium = false;

  static const List<(String, String, IconData)> _tones = [
    ('default', 'Default', Icons.auto_awesome_rounded),
    ('punchy', 'Punchy', Icons.bolt_rounded),
    ('funny', 'Funny', Icons.emoji_emotions_rounded),
    ('professional', 'Professional', Icons.work_outline_rounded),
    ('bold', 'Bold', Icons.local_fire_department_rounded),
    ('warm', 'Warm', Icons.favorite_border_rounded),
  ];

  static const List<_ActionItem> _actions = [
    _ActionItem(
      id: 'quick_pack',
      icon: Icons.auto_awesome_rounded,
      label: 'Quick Pack',
      color: Color(0xFF6C63FF),
    ),
    _ActionItem(
      id: 'caption',
      icon: Icons.text_fields_rounded,
      label: 'Captions',
      color: Color(0xFF6C63FF),
    ),
    _ActionItem(
      id: 'hashtags',
      icon: Icons.tag_rounded,
      label: 'Hashtags',
      color: Color(0xFF00C2FF),
    ),
    _ActionItem(
      id: 'subtitle',
      icon: Icons.closed_caption_rounded,
      label: 'Subtitles',
      color: Color(0xFF22C55E),
    ),
    _ActionItem(
      id: 'translate',
      icon: Icons.translate_rounded,
      label: 'Translate',
      color: Color(0xFFF59E0B),
    ),
    _ActionItem(
      id: 'summarize',
      icon: Icons.subject_rounded,
      label: 'Summarize',
      color: Color(0xFFEC4899),
    ),
    _ActionItem(
      id: 'script',
      icon: Icons.description_rounded,
      label: 'Script',
      color: Color(0xFF8B5CF6),
    ),
    _ActionItem(
      id: 'tweet_thread',
      icon: Icons.chat_rounded,
      label: 'Thread',
      color: Color(0xFF1DA1F2),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (mounted) setState(() => _isPremium = premium.isPremium);
  }

  /// Ensures the video has been analyzed once for this video file. The
  /// first AI action triggers the upload+transcribe; subsequent actions
  /// on the same video reuse the key, so the person pays the analysis
  /// cost exactly once regardless of how many actions they run.
  Future<String?> _ensureAnalysisKey() async {
    if (_analysisKey != null) return _analysisKey;
    try {
      final key = await _ai.analyzeVideoFile(widget.videoPath);
      _analysisKey = key;
      return key;
    } catch (e) {
      debugPrint('Analysis failed (proceeding title-only): $e');
      return null;
    }
  }

  // ─── Actions ───────────────────────────────────────────────────────

  Future<void> _handleAction(String actionId) async {
    if (actionId == 'quick_pack') {
      await _handleQuickPack();
      return;
    }

    if (!_isPremium) {
      _showPremiumDialog();
      return;
    }

    setState(() {
      _isGenerating = true;
      _processingMessage = 'Analyzing the video...';
      _processingProgress = 0.15;
      _error = null;
      _expandedAction = actionId;
    });

    try {
      final analysisKey = await _ensureAnalysisKey();

      if (mounted) {
        setState(() {
          _processingMessage = 'Writing three versions...';
          _processingProgress = 0.6;
        });
      }

      final result = await _repurpose.processActionVariants(
        actionId: actionId,
        videoTitle: widget.videoTitle,
        videoPath: widget.videoPath,
        platform: widget.platform,
        analysisKey: analysisKey,
        tone: _selectedTone,
      );

      if (!mounted) return;

      if (result.success) {
        setState(() {
          _results[actionId] = result.variants;
          _isGenerating = false;
          _processingProgress = 1.0;
          _expandedAction = actionId;
        });
        widget.onComplete?.call();
      } else {
        setState(() {
          _isGenerating = false;
          _processingProgress = 0;
          _error = result.error ?? 'Something went wrong.';
        });
        if (result.error != null &&
            result.error!.toLowerCase().contains('upgrade')) {
          _showPremiumDialog();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _processingProgress = 0;
        _error = 'Could not reach the server. Check your connection.';
      });
    }
  }

  Future<void> _handleQuickPack() async {
    setState(() {
      _isGenerating = true;
      _processingMessage = 'Building your free pack...';
      _processingProgress = 0.5;
      _error = null;
      _expandedAction = 'quick_pack';
    });

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    final quickPack = [
      '🔥 This moment is worth watching twice.',
      '💡 Save this one — it will change how you think about your next post.',
      '✨ Sometimes the right frame says more than a paragraph.',
    ];
    setState(() {
      _results['quick_pack'] = quickPack;
      _isGenerating = false;
      _processingProgress = 1.0;
    });
  }

  // ─── UI ────────────────────────────────────────────────────────────

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
          _buildToneRow(),
          const SizedBox(height: AppSpacing.md),
          _buildActionsGrid(),
          if (_isGenerating) ...[
            const SizedBox(height: AppSpacing.md),
            _buildLoading(),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildError(),
          ],
          if (_expandedAction != null && _results[_expandedAction] != null) ...[
            const SizedBox(height: AppSpacing.md),
            _buildExpandedResults(_expandedAction!),
          ],
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
                'Three options per tool — pick the one in your voice.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToneRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            'BRAND VOICE',
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
        ),
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _tones.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (id, label, icon) = _tones[i];
              final selected = _selectedTone == id;
              return GestureDetector(
                onTap: () => setState(() => _selectedTone = id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 14,
                        color: selected ? Colors.white : AppColors.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
        childAspectRatio: 1.05,
      ),
      itemCount: _actions.length,
      itemBuilder: (context, index) {
        final action = _actions[index];
        final locked = action.id != 'quick_pack' && !_isPremium;
        final hasResult = _results.containsKey(action.id);
        final isExpanded = _expandedAction == action.id;

        return GestureDetector(
          onTap: () => locked ? _showPremiumDialog() : _handleAction(action.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: locked ? AppColors.surfaceAlt : AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: isExpanded
                    ? AppColors.primary
                    : (locked
                        ? AppColors.border
                        : action.color.withValues(alpha: 0.2)),
                width: isExpanded ? 1.6 : 1,
              ),
              boxShadow: locked ? null : AppShadows.soft,
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: locked
                            ? AppColors.border
                            : action.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        locked ? Icons.lock_rounded : action.icon,
                        color: locked ? AppColors.textMuted : action.color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      action.label,
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: locked
                            ? AppColors.textMuted
                            : AppColors.textPrimary,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                if (hasResult)
                  Positioned(
                    top: 2,
                    right: 2,
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedResults(String actionId) {
    final variants = _results[actionId];
    if (variants == null || variants.isEmpty) return const SizedBox.shrink();

    final action = _actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => _actions.first,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(action.icon, size: 16, color: action.color),
              const SizedBox(width: 8),
              Text(
                '${action.label} — ${variants.length} options',
                style: AppTypography.titleMedium,
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _expandedAction = null),
                child: const Text('Hide', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...variants.asMap().entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _VariantCard(
                index: entry.key + 1,
                text: entry.value,
                color: action.color,
                onRemix: () => _handleAction(actionId),
              ),
            );
          }),
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
                  _processingMessage.isEmpty
                      ? 'AI is working...'
                      : _processingMessage,
                  style: AppTypography.bodyMedium,
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
    final isUpgrade = _error!.toLowerCase().contains('upgrade') ||
        _error!.toLowerCase().contains('pro');
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isUpgrade
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isUpgrade
              ? AppColors.primary.withValues(alpha: 0.25)
              : AppColors.error.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isUpgrade
                ? Icons.workspace_premium_rounded
                : Icons.error_outline_rounded,
            color: isUpgrade ? AppColors.primary : AppColors.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: TextStyle(
                color: isUpgrade ? AppColors.primary : AppColors.error,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('Dismiss', style: TextStyle(fontSize: 11)),
          ),
        ],
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
                'Get captions, hashtags, subtitles, translation, summaries, '
                'scripts and tweet threads — three options each, all tone-aware.',
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
}

// ─── Supporting widgets/models ─────────────────────────────────────────────

class _ActionItem {
  final String id;
  final IconData icon;
  final String label;
  final Color color;
  const _ActionItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _VariantCard extends StatelessWidget {
  final int index;
  final String text;
  final Color color;
  final VoidCallback onRemix;

  const _VariantCard({
    required this.index,
    required this.text,
    required this.color,
    required this.onRemix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Option $index',
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Copied'),
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
                tooltip: 'Copy',
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onRemix,
                icon: const Icon(Icons.refresh_rounded,
                    size: 16, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Regenerate',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            text,
            style: AppTypography.bodyMedium.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
