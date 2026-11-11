// ui/widgets/premium/repurpose_studio.dart
// Repurpose Studio — multi-variant + tone-aware.
//
// Each AI tool returns THREE options written from what is actually said
// in the video (the video is transcribed once, on the first AI action).
// When the video can't be read, the person is told why and that the
// results are based on the title only — nothing fails silently.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:medianest/ui/screens/buy_credits_screen.dart';
import 'package:medianest/ui/screens/premium_screen.dart';
import 'package:medianest/ui/themes/app_theme.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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
  bool _errorIsBudget = false;
  String _processingMessage = '';
  double _processingProgress = 0.0;

  // Result storage: actionId → list of variant strings.
  final Map<String, List<String>> _results = {};

  // Currently selected tone for the NEXT action. Defaults to 'default'.
  String _selectedTone = 'default';

  // Which action's result is expanded for viewing right now.
  String? _expandedAction;

  // ─── Video analysis (transcription) state ───────────────────────────
  // Runs once per video; every AI action afterwards reuses the key.
  String? _analysisKey;
  bool _analysisTried = false;
  bool _hasSpeech = false;
  // Shown under the tools when the video's speech could not be used.
  String? _analysisNote;

  // Language the Translate tool writes in.
  String _translateLanguage = 'Spanish';

  static const List<String> _languages = [
    'English',
    'Spanish',
    'French',
    'Portuguese',
    'German',
    'Italian',
    'Arabic',
    'Hindi',
    'Chinese (Simplified)',
    'Japanese',
    'Korean',
    'Russian',
    'Turkish',
    'Indonesian',
    'Swahili',
    'Yoruba',
    'Igbo',
    'Hausa',
    'Nigerian Pidgin',
  ];

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

  String get _prefsKey => 'repurpose_results_${widget.videoPath.hashCode}';

  @override
  void initState() {
    super.initState();
    _restoreResults();
  }

  /// Results are kept per video so leaving the screen (or picking another
  /// video and coming back) doesn't throw away paid-for output.
  Future<void> _restoreResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final restored = <String, List<String>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          final list = value.map((e) => e.toString()).toList();
          if (list.isNotEmpty) restored[key.toString()] = list;
        }
      });
      if (!mounted || restored.isEmpty) return;
      setState(() {
        _results.addAll(restored);
      });
    } catch (e) {
      debugPrint('Could not restore repurpose results: $e');
    }
  }

  Future<void> _persistResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(_results));
    } catch (e) {
      debugPrint('Could not save repurpose results: $e');
    }
  }

  /// Transcribes the video once. Later actions on the same video reuse
  /// the key, so the analysis cost is paid exactly once.
  Future<String?> _ensureAnalysisKey() async {
    if (_analysisTried) return _analysisKey;
    final result = await _ai.analyzeVideoFileFull(widget.videoPath);
    _analysisTried = true;
    if (result == null) {
      _analysisKey = null;
      _hasSpeech = false;
      final reason = _ai.lastAnalysisError ?? 'The video could not be read.';
      _analysisNote = '$reason Results are based on the title only.';
      return null;
    }
    _analysisKey = result['analysisKey'] as String?;
    final transcript = (result['transcript'] as String?)?.trim() ?? '';
    _hasSpeech = result['hasSpeech'] == true || transcript.length >= 10;
    _analysisNote = _hasSpeech
        ? null
        : 'No speech was found in this video, so results are based on the '
            'title only.';
    return _analysisKey;
  }

  // ─── Actions ───────────────────────────────────────────────────────

  bool get _isPremium =>
      Provider.of<PremiumProvider>(context, listen: false).isPremium;

  Future<void> _onActionTap(String actionId) async {
    if (_isGenerating) return;
    if (actionId == 'quick_pack') {
      _handleQuickPack();
      return;
    }
    if (!_isPremium) {
      _showPremiumDialog();
      return;
    }
    // Already generated → just show it. Regenerating is an explicit tap
    // on the refresh buttons, so nobody spends credits by accident.
    if (_results[actionId] != null && _results[actionId]!.isNotEmpty) {
      setState(() {
        _expandedAction = actionId;
        _error = null;
      });
      return;
    }
    if (actionId == 'translate') {
      final picked = await _pickLanguage();
      if (picked == null) return;
      _translateLanguage = picked;
    }
    await _handleAction(actionId);
  }

  /// Runs an AI action. When [replaceIndex] is given, only that one
  /// option is swapped for a fresh one; the other options stay.
  Future<void> _handleAction(String actionId, {int? replaceIndex}) async {
    if (_isGenerating) return;
    if (!_isPremium) {
      _showPremiumDialog();
      return;
    }

    setState(() {
      _isGenerating = true;
      _processingMessage = _analysisTried
          ? 'Writing three versions...'
          : 'Reading what is said in the video...';
      _processingProgress = _analysisTried ? 0.5 : 0.15;
      _error = null;
      _errorIsBudget = false;
      _expandedAction = actionId;
    });

    try {
      final analysisKey = await _ensureAnalysisKey();
      if (!mounted) return;

      if (actionId == 'subtitle' && !_hasSpeech) {
        setState(() {
          _isGenerating = false;
          _processingProgress = 0;
          _error = _analysisKey == null
              ? 'Subtitles need the video\'s speech. '
                  '${_ai.lastAnalysisError ?? 'The video could not be read.'}'
              : 'No speech was found in this video, so there is nothing to '
                  'turn into subtitles.';
        });
        return;
      }

      setState(() {
        _processingMessage = actionId == 'subtitle'
            ? 'Building subtitles...'
            : 'Writing three versions...';
        _processingProgress = 0.6;
      });

      final result = await _repurpose.processActionVariants(
        actionId: actionId,
        videoTitle: widget.videoTitle,
        videoPath: widget.videoPath,
        platform: widget.platform,
        analysisKey: analysisKey,
        tone: _selectedTone,
        targetLanguage: actionId == 'translate' ? _translateLanguage : null,
      );

      if (!mounted) return;

      if (result.success && result.variants.isNotEmpty) {
        setState(() {
          final existing = _results[actionId];
          if (replaceIndex != null &&
              existing != null &&
              replaceIndex < existing.length) {
            final fresh = replaceIndex < result.variants.length
                ? result.variants[replaceIndex]
                : result.variants.first;
            final updated = List<String>.from(existing);
            updated[replaceIndex] = fresh;
            _results[actionId] = updated;
          } else {
            _results[actionId] = result.variants;
          }
          _isGenerating = false;
          _processingProgress = 1.0;
          _expandedAction = actionId;
        });
        _persistResults();
        if (result.remainingCredits != null) {
          Provider.of<PremiumProvider>(context, listen: false)
              .updateCreditsFromResponse(result.remainingCredits);
        }
        widget.onComplete?.call();
      } else {
        setState(() {
          _isGenerating = false;
          _processingProgress = 0;
          _errorIsBudget = result.outOfBudget;
          _error = result.error ??
              (result.success
                  ? 'The AI returned nothing — please try again.'
                  : 'Something went wrong.');
        });
        if (result.needsUpgrade) _showPremiumDialog();
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

  // ─── Quick Pack (free, on-device, no AI) ────────────────────────────

  /// The video's title if it means something, or null when it is just an
  /// auto-generated filename like "facebook_1794295844920.mp4".
  String? _meaningfulTitle() {
    var t = widget.videoTitle.trim();
    t = t.replaceFirst(RegExp(r'\.[A-Za-z0-9]{2,5}$'), '');
    if (t.isEmpty) return null;
    final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
    final digits = RegExp(r'\d').allMatches(t).length;
    if (digits >= 6 && digits >= letters) return null;
    if (RegExp(r'^[A-Za-z]+[\s_-]*\d{6,}$').hasMatch(t)) return null;
    t = t.replaceAll(RegExp(r'[_-]+'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    return t.trim().isEmpty ? null : t.trim();
  }

  String _platformKey() {
    final p = '${widget.platform} ${widget.videoTitle}'.toLowerCase();
    if (p.contains('tiktok')) return 'tiktok';
    if (p.contains('instagram') || p.contains('insta')) return 'instagram';
    if (p.contains('facebook') || p.contains('fb_')) return 'facebook';
    if (p.contains('twitter') || p.contains('x.com')) return 'twitter';
    if (p.contains('whatsapp')) return 'whatsapp';
    if (p.contains('youtube')) return 'youtube';
    return 'general';
  }

  void _handleQuickPack() {
    final title = _meaningfulTitle();
    final platform = _platformKey();
    final random = Random();

    const platformTags = {
      'tiktok': '#fyp #foryou #foryoupage #tiktok #viral',
      'instagram': '#reels #reelsinstagram #explore #instagood #viral',
      'facebook': '#facebookreels #fbreels #viralvideo #trending',
      'twitter': '#trending #video #viral',
      'whatsapp': '#whatsappstatus #status #statusvideo',
      'youtube': '#shorts #youtubeshorts #viral #trending',
      'general': '#viral #trending #explore #video',
    };
    const platformTips = {
      'tiktok':
          'TikTok checklist\n• Hook in the first 2 seconds\n• Keep it 15–35 seconds\n• Add on-screen text for silent viewers\n• Use 3–5 hashtags, not 20\n• Reply to early comments in the first hour',
      'instagram':
          'Instagram Reels checklist\n• Strong cover frame with readable text\n• Keep it under 30 seconds\n• First line of the caption is the hook\n• 5–8 focused hashtags\n• Share it to your Story after posting',
      'facebook':
          'Facebook Reels checklist\n• Caption that asks a question\n• Subtitles on — most people watch muted\n• Keep it 20–45 seconds\n• Post when your followers are online (evenings work well)\n• Share into one relevant group',
      'twitter':
          'X / Twitter checklist\n• One clear sentence above the video\n• Keep the clip under 45 seconds\n• 1–2 hashtags at most\n• Reply to your own post with context\n• Pin it if it performs',
      'whatsapp':
          'WhatsApp Status checklist\n• Split into clips of 30 seconds or less\n• Add a short text caption on the first clip\n• Post when your contacts are active (morning / evening)\n• End with what you want people to do: "Reply to order"',
      'youtube':
          'YouTube Shorts checklist\n• Vertical, under 60 seconds\n• Title with the main keyword first\n• Hook in the first 2 seconds\n• Pin a comment that asks a question\n• Add #shorts in the title or description',
      'general':
          'Posting checklist\n• Hook in the first 2 seconds\n• Keep it short — under 45 seconds\n• Subtitles on for silent viewers\n• One clear call to action at the end\n• 3–6 focused hashtags',
    };
    const hookPool = [
      'Nobody talks about this, but…',
      'Watch till the end — the last part matters.',
      'I didn\'t expect this to work.',
      'Stop scrolling if this is you.',
      'Here\'s what changed everything for me.',
      'You\'re probably doing this wrong.',
      'This took me way too long to learn.',
      'Save this before you forget.',
      'The part nobody shows you.',
      'If you only watch one video today, make it this one.',
    ];

    final titleTags = title == null
        ? ''
        : title
            .toLowerCase()
            .split(RegExp(r'[^a-z0-9]+'))
            .where((w) => w.length >= 4 && !RegExp(r'^\d+$').hasMatch(w))
            .take(4)
            .map((w) => '#$w')
            .join(' ');
    final tags = [titleTags, platformTags[platform]!]
        .where((t) => t.isNotEmpty)
        .join(' ');

    final hooks = List<String>.from(hookPool)..shuffle(random);
    final captionStarter = title != null
        ? '$title 👀\n\n[Add one line: why should someone watch this?]\n\n$tags'
        : '[Say what happens in this clip in one line] 👀\n\n'
            '[Add one line: why should someone watch this?]\n\n$tags';

    setState(() {
      _error = null;
      _expandedAction = 'quick_pack';
      _results['quick_pack'] = [
        captionStarter,
        'Hook starters — pick one and finish the sentence\n'
            '• ${hooks[0]}\n• ${hooks[1]}\n• ${hooks[2]}',
        platformTips[platform]!,
      ];
    });
    _persistResults();
  }

  Future<String?> _pickLanguage() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text('Translate into',
                    style: AppTypography.titleMedium),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _languages.length,
                  itemBuilder: (_, i) {
                    final lang = _languages[i];
                    final selected = lang == _translateLanguage;
                    return ListTile(
                      dense: true,
                      title: Text(lang),
                      trailing: selected
                          ? const Icon(Icons.check_rounded,
                              color: AppColors.primary, size: 18)
                          : null,
                      onTap: () => Navigator.pop(sheetContext, lang),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Listening here (not a one-off read in initState) means the tools
    // unlock the moment Pro status arrives, instead of staying locked
    // until the screen is reopened.
    final isPremium = context.watch<PremiumProvider>().isPremium;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
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
          _buildActionsGrid(isPremium),
          if (_analysisNote != null && !_isGenerating) ...[
            const SizedBox(height: AppSpacing.md),
            _buildAnalysisNote(),
          ],
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
                'Three options per tool, written from what is said in '
                'your video.',
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

  Widget _buildActionsGrid(bool isPremium) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tiles need ~84px to show their label without cutting it off:
        // 4 per row on normal phones, 3 on narrow ones, more on tablets.
        final width = constraints.maxWidth;
        final columns = (width / 84).floor().clamp(2, 8);
        const spacing = AppSpacing.sm;
        final tileWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: _actions.map((action) {
            final locked = action.id != 'quick_pack' && !isPremium;
            final hasResult = _results.containsKey(action.id);
            final isExpanded = _expandedAction == action.id;

            return SizedBox(
              width: tileWidth,
              height: 78,
              child: GestureDetector(
                onTap: () =>
                    locked ? _showPremiumDialog() : _onActionTap(action.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: locked
                                    ? AppColors.border
                                    : action.color.withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(
                                locked ? Icons.lock_rounded : action.icon,
                                color:
                                    locked ? AppColors.textMuted : action.color,
                                size: 20,
                              ),
                            ),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                action.label,
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: locked
                                      ? AppColors.textMuted
                                      : AppColors.textPrimary,
                                  fontSize: 11,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasResult)
                        Positioned(
                          top: 0,
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
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAnalysisNote() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.warning, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _analysisNote!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          GestureDetector(
            onTap: _isGenerating
                ? null
                : () => setState(() {
                      // Lets the next AI action try reading the video again.
                      _analysisTried = false;
                      _analysisNote = null;
                    }),
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedResults(String actionId) {
    final variants = _results[actionId];
    if (variants == null || variants.isEmpty) return const SizedBox.shrink();

    final action = _actions.firstWhere(
      (a) => a.id == actionId,
      orElse: () => _actions.first,
    );
    final isQuickPack = actionId == 'quick_pack';
    final isSubtitle = actionId == 'subtitle';
    const subtitleLabels = ['SRT file text', 'Timed lines', 'Plain text'];
    const quickPackLabels = ['Caption starter', 'Hooks', 'Checklist'];

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
              Expanded(
                child: Text(
                  actionId == 'translate'
                      ? '${action.label} — $_translateLanguage'
                      : '${action.label} — ${variants.length} options',
                  style: AppTypography.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isQuickPack && !isSubtitle)
                IconButton(
                  onPressed: _isGenerating
                      ? null
                      : () async {
                          if (actionId == 'translate') {
                            final picked = await _pickLanguage();
                            if (picked == null) return;
                            _translateLanguage = picked;
                          }
                          _handleAction(actionId);
                        },
                  icon: Icon(
                    actionId == 'translate'
                        ? Icons.language_rounded
                        : Icons.refresh_rounded,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: actionId == 'translate'
                      ? 'Change language'
                      : 'Regenerate all three',
                ),
              if (isQuickPack)
                IconButton(
                  onPressed: _handleQuickPack,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 18, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: 'Shuffle',
                ),
              TextButton(
                onPressed: () => setState(() => _expandedAction = null),
                child: const Text('Hide', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (isQuickPack)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Free fill-in templates made on your phone. The AI tools '
                'write finished text from what is actually said in the video.',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textMuted, height: 1.4),
              ),
            ),
          const SizedBox(height: AppSpacing.xs),
          ...variants.asMap().entries.map((entry) {
            String? label;
            if (isSubtitle && entry.key < subtitleLabels.length) {
              label = subtitleLabels[entry.key];
            } else if (isQuickPack && entry.key < quickPackLabels.length) {
              label = quickPackLabels[entry.key];
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _VariantCard(
                index: entry.key + 1,
                label: label,
                text: entry.value,
                color: action.color,
                // Long outputs (a full SRT) scroll inside the card.
                maxHeight: isSubtitle ? 220 : null,
                onRemix: (isQuickPack || isSubtitle || _isGenerating)
                    ? null
                    : () => _handleAction(actionId, replaceIndex: entry.key),
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
    final lower = _error!.toLowerCase();
    final isUpgrade = !_errorIsBudget && lower.contains('upgrade');
    final accent = isUpgrade ? AppColors.primary : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isUpgrade
                    ? Icons.workspace_premium_rounded
                    : Icons.error_outline_rounded,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: accent, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (_errorIsBudget)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const BuyCreditsScreen(),
                    ));
                  },
                  child:
                      const Text('Buy credits', style: TextStyle(fontSize: 12)),
                ),
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
              ),
            ],
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
      builder: (sheetContext) => SafeArea(
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
                    Navigator.pop(sheetContext);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PremiumScreen(),
                    ));
                  },
                  child: const Text('Upgrade to Pro'),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
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
  final String? label;
  final String text;
  final Color color;
  final double? maxHeight;
  // Null hides the regenerate button (free templates, real subtitles).
  final VoidCallback? onRemix;

  const _VariantCard({
    required this.index,
    required this.text,
    required this.color,
    this.label,
    this.maxHeight,
    this.onRemix,
  });

  @override
  Widget build(BuildContext context) {
    final textWidget = SelectableText(
      text,
      style: AppTypography.bodyMedium.copyWith(height: 1.5),
    );

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
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    label ?? 'Option $index',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
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
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Copy',
              ),
              IconButton(
                onPressed: () => Share.share(text),
                icon: const Icon(Icons.share_rounded,
                    size: 16, color: AppColors.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Share',
              ),
              if (onRemix != null)
                IconButton(
                  onPressed: onRemix,
                  icon: const Icon(Icons.refresh_rounded,
                      size: 16, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Regenerate this option',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (maxHeight != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight!),
              child: SingleChildScrollView(child: textWidget),
            )
          else
            textWidget,
        ],
      ),
    );
  }
}
