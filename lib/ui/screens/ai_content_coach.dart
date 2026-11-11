// ui/screens/ai_content_coach.dart
// COMPLETE - AI Content Coach (Beta)
// Features: Content Analysis, Strategy Suggestions, Daily Challenges, Progress Tracking
//
// REWIRED: daily challenges, streak and points now all come from the real
// server endpoints in functions/index.js (/getDailyChallenge,
// /completeDailyChallenge, /getCoachProfile, /saveCoachProfile). The old
// version of this screen shipped a hardcoded pool of five challenges and
// a SharedPreferences counter that never agreed with what the server
// actually recorded. That disconnect is gone — this screen is a thin
// client over the server-side system that was already built and running
// idle.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';
import '../../providers/premium_provider.dart';
import '../themes/app_theme.dart';
import 'premium_screen.dart';

// ─── Coach Models ──────────────────────────────────────────────────────────

enum CoachGoal {
  growFollowers('Grow Followers', Icons.people_rounded),
  increaseEngagement('Increase Engagement', Icons.favorite_rounded),
  createContent('Create Better Content', Icons.create_rounded),
  buildBrand('Build Personal Brand', Icons.branding_watermark_rounded),
  monetize('Monetize Content', Icons.monetization_on_rounded),
  learnEditing('Learn Editing', Icons.cut_rounded),
  saveContent('Save & Organize', Icons.folder_rounded),
  growBusiness('Grow Business', Icons.business_center_rounded);

  final String label;
  final IconData icon;
  const CoachGoal(this.label, this.icon);
}

enum CoachNiche {
  tech('Tech', Icons.computer_rounded),
  fashion('Fashion', Icons.checkroom_rounded),
  fitness('Fitness', Icons.fitness_center_rounded),
  food('Food & Cooking', Icons.restaurant_rounded),
  travel('Travel', Icons.flight_takeoff_rounded),
  music('Music', Icons.music_note_rounded),
  gaming('Gaming', Icons.sports_esports_rounded),
  beauty('Beauty', Icons.spa_rounded),
  education('Education', Icons.menu_book_rounded),
  business('Business', Icons.business_center_rounded),
  photography('Photography', Icons.photo_camera_rounded),
  health('Health & Wellness', Icons.health_and_safety_rounded),
  comedy('Comedy', Icons.emoji_emotions_rounded),
  motivation('Motivation', Icons.auto_awesome_rounded),
  sports('Sports', Icons.sports_soccer_rounded),
  realEstate('Real Estate', Icons.home_rounded),
  finance('Finance', Icons.attach_money_rounded),
  parenting('Parenting', Icons.family_restroom_rounded),
  diy('DIY & Crafts', Icons.handyman_rounded),
  art('Art & Design', Icons.palette_rounded);

  final String label;
  final IconData icon;
  const CoachNiche(this.label, this.icon);
}

class CoachChallenge {
  final String id;
  final String title;
  final String description;
  final String category;
  final int difficulty; // 1-5
  final int estimatedMinutes;
  final List<String> steps;
  final String? tip;
  final bool isCompleted;
  // Points the server awards for this challenge.
  final int points;

  const CoachChallenge({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.estimatedMinutes,
    required this.steps,
    this.tip,
    this.isCompleted = false,
    this.points = 10,
  });

  factory CoachChallenge.fromJson(Map<String, dynamic> json) {
    return CoachChallenge(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? '',
      difficulty: json['difficulty'] ?? 1,
      estimatedMinutes: json['estimatedMinutes'] ?? 5,
      steps: List<String>.from(json['steps'] ?? []),
      tip: json['tip'],
      isCompleted: json['isCompleted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'category': category,
        'difficulty': difficulty,
        'estimatedMinutes': estimatedMinutes,
        'steps': steps,
        'tip': tip,
        'isCompleted': isCompleted,
      };
}

// ─── Screen ──────────────────────────────────────────────────────────────

class AIContentCoach extends StatefulWidget {
  const AIContentCoach({Key? key}) : super(key: key);

  @override
  State<AIContentCoach> createState() => _AIContentCoachState();
}

class _AIContentCoachState extends State<AIContentCoach>
    with SingleTickerProviderStateMixin {
  // ─── Services ──────────────────────────────────────────────────────────
  final AIService _ai = AIService();

  // ─── State ─────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _isOnboarding = false;
  bool _isProcessing = false;
  String _error = '';
  String _userName = 'Creator';

  // ─── User Preferences ────────────────────────────────────────────────
  CoachGoal _selectedGoal = CoachGoal.growFollowers;
  CoachNiche _selectedNiche = CoachNiche.tech;
  String _experienceLevel = 'beginner'; // beginner, intermediate, advanced
  List<String> _interests = [];

  // ─── Coach Data ──────────────────────────────────────────────────────
  List<CoachChallenge> _dailyChallenges = [];
  List<CoachChallenge> _completedChallenges = [];
  List<Map<String, dynamic>> _contentIdeas = [];
  int _streak = 0;
  int _points = 0;
  String? _challengeError;

  // Ideas + tips + 30-day activity (one server call).
  List<String> _coachTips = [];
  Map<String, dynamic> _activity = {};
  bool _ideasLoading = false;
  String? _ideasError;

  // Learning path.
  List<Map<String, dynamic>> _planSteps = [];
  Set<String> _planCompleted = {};
  bool _planLoading = false;
  String? _planError;

  // ─── Animation ──────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ─── Tabs ─────────────────────────────────────────────────────────────
  int _selectedTab = 0; // 0: Dashboard, 1: Challenges, 2: Ideas, 3: Learning

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadUserData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Data Loading ────────────────────────────────────────────────────

  Future<void> _loadUserData() async {
    if (mounted) setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString('coach_user_name') ?? 'Creator';

      // Load local preferences (offline fallback / first-paint display)
      final goalStr = prefs.getString('coach_goal');
      final nicheStr = prefs.getString('coach_niche');
      _experienceLevel = prefs.getString('coach_experience') ?? 'beginner';
      _interests = prefs.getStringList('coach_interests') ?? [];

      if (goalStr != null) {
        _selectedGoal = CoachGoal.values.firstWhere(
          (g) => g.toString() == goalStr,
          orElse: () => CoachGoal.growFollowers,
        );
      }
      if (nicheStr != null) {
        _selectedNiche = CoachNiche.values.firstWhere(
          (n) => n.toString() == nicheStr,
          orElse: () => CoachNiche.tech,
        );
      }

      _isOnboarding = !(prefs.getBool('coach_onboarding_complete') ?? false);
      if (_isOnboarding) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // ─── Authoritative streak + points + niche from the server ─────
      // The old client kept these in SharedPreferences, which never agreed
      // with Firestore's coachStreak/coachPoints that the real
      // /completeDailyChallenge writes. Reading the server's copy is the
      // single source of truth now.
      final profile = await _ai.getCoachProfile();
      _streak = (profile['streak'] as num?)?.toInt() ?? 0;
      _points = (profile['points'] as num?)?.toInt() ?? 0;

      // If the server has a niche that differs from local prefs (e.g. the
      // person edited it on another device), prefer the server's.
      final serverNiche = profile['niche'] as String?;
      if (serverNiche != null && serverNiche.isNotEmpty) {
        final match = CoachNiche.values.firstWhere(
          (n) => n.label.toLowerCase() == serverNiche.toLowerCase(),
          orElse: () => _selectedNiche,
        );
        _selectedNiche = match;
      }

      final serverName = profile['name'] as String?;
      if (serverName != null && serverName.isNotEmpty) {
        _userName = serverName;
      }
      final serverGoal = profile['goal'] as String?;
      if (serverGoal != null && serverGoal.isNotEmpty) {
        _selectedGoal = CoachGoal.values.firstWhere(
          (g) => g.label.toLowerCase() == serverGoal.toLowerCase(),
          orElse: () => _selectedGoal,
        );
      }
      final serverExperience = profile['experience'] as String?;
      if (serverExperience != null && serverExperience.isNotEmpty) {
        _experienceLevel = serverExperience;
      }

      // ─── Today's real challenge, generated server-side ─────────────
      final challengeData = await _ai.getDailyChallenge();
      if (challengeData != null) {
        final c = _challengeFromServer(challengeData);
        if (c.isCompleted) {
          _dailyChallenges = [];
          _completedChallenges = [c];
        } else {
          _dailyChallenges = [c];
          _completedChallenges = [];
        }
        _challengeError = null;
      } else {
        _dailyChallenges = [];
        _completedChallenges = [];
        _challengeError = 'Could not load today\'s challenge. Check your '
            'connection and tap refresh.';
      }

      // Ideas, tips and the learning path load in the background — the
      // dashboard and today's challenge show as soon as they are ready.
      _loadIdeas();
      _loadPlan();
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load coach data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Converts the raw server challenge JSON into a CoachChallenge the UI
  /// already knows how to render. Server sends difficulty as "easy" /
  /// "medium" / "hard" — mapped here to the 1-5 integer scale the card
  /// widget uses, and to a rough minutes estimate.
  CoachChallenge _challengeFromServer(Map<String, dynamic> data) {
    final difficulty = (data['difficulty'] as String? ?? 'easy').toLowerCase();
    final int diffInt =
        difficulty == 'hard' ? 5 : (difficulty == 'medium' ? 3 : 1);
    final int estMinutes =
        difficulty == 'hard' ? 30 : (difficulty == 'medium' ? 15 : 5);
    final verifyFeature = data['verifyFeature'] as String?;
    final completed = data['completed'] == true;
    final dateId = data['date'] as String? ??
        DateTime.now().toIso8601String().split('T')[0];
    final steps = (data['steps'] as List? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    final serverTip = (data['tip'] as String?)?.trim();
    final points = (data['points'] as num?)?.toInt() ??
        (difficulty == 'hard' ? 30 : (difficulty == 'medium' ? 20 : 10));

    const featureNames = {
      'repurpose': 'Repurpose Studio',
      'translate': 'Translator',
      'download': 'Downloader',
    };
    const featureHowTo = {
      'repurpose': 'Use Repurpose Studio at least once today, then tap '
          'Complete.',
      'translate': 'Translate something today, then tap Complete.',
      'download': 'Download a video or photo today, then tap Complete.',
    };

    String? tip;
    if (completed) {
      tip = 'Completed today — nice work!';
    } else if (verifyFeature != null && featureHowTo[verifyFeature] != null) {
      tip = serverTip != null && serverTip.isNotEmpty
          ? '$serverTip  ${featureHowTo[verifyFeature]}'
          : featureHowTo[verifyFeature];
    } else if (serverTip != null && serverTip.isNotEmpty) {
      tip = serverTip;
    }

    return CoachChallenge(
      id: dateId,
      title: data['title'] as String? ?? "Today's challenge",
      description: data['description'] as String? ?? '',
      category: featureNames[verifyFeature] ?? 'Creator task',
      difficulty: diffInt,
      estimatedMinutes: estMinutes,
      steps: steps,
      tip: tip,
      isCompleted: completed,
      points: points,
    );
  }

  // ─── Ideas, tips & activity (server-generated) ───────────────────────

  Future<void> _loadIdeas({bool refresh = false}) async {
    if (_ideasLoading) return;
    if (mounted) {
      setState(() {
        _ideasLoading = true;
        _ideasError = null;
      });
    }
    final data = await _ai.getCoachIdeas(refresh: refresh);
    if (!mounted) return;
    setState(() {
      _ideasLoading = false;
      if (data['error'] != null) {
        _ideasError = data['error'].toString();
        return;
      }
      _contentIdeas = (data['ideas'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _coachTips = (data['tips'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
      _activity = data['activity'] is Map
          ? Map<String, dynamic>.from(data['activity'] as Map)
          : <String, dynamic>{};
    });
    if (refresh) {
      Provider.of<PremiumProvider>(context, listen: false)
          .refreshCreditBalance();
    }
  }

  // ─── Learning path (server-generated, progress saved) ────────────────

  Future<void> _loadPlan() async {
    if (_planLoading) return;
    if (mounted) {
      setState(() {
        _planLoading = true;
        _planError = null;
      });
    }
    final data = await _ai.getCoachPlan();
    if (!mounted) return;
    setState(() {
      _planLoading = false;
      if (data['error'] != null) {
        _planError = data['error'].toString();
        return;
      }
      _planSteps = (data['steps'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _planCompleted = (data['completed'] as List? ?? const [])
          .map((e) => e.toString())
          .toSet();
    });
  }

  Future<void> _togglePlanStep(String stepId) async {
    final wasDone = _planCompleted.contains(stepId);
    // Update the tick immediately; undo it if the server can't save.
    setState(() {
      if (wasDone) {
        _planCompleted.remove(stepId);
      } else {
        _planCompleted.add(stepId);
      }
    });
    final saved = await _ai.setCoachStepDone(stepId, !wasDone);
    if (!mounted) return;
    if (saved == null) {
      setState(() {
        if (wasDone) {
          _planCompleted.add(stepId);
        } else {
          _planCompleted.remove(stepId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save your progress. Try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      setState(() => _planCompleted = saved.toSet());
    }
  }

  String _platformLabel(String raw) {
    if (raw.isEmpty || raw == 'unknown') return 'Other';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  // ─── User Actions ────────────────────────────────────────────────────

  Future<void> _completeChallenge(CoachChallenge challenge) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final result = await _ai.completeDailyChallenge();
      if (!mounted) return;

      if (result['success'] == true) {
        final pointsEarned =
            (result['pointsEarned'] as num?)?.toInt() ?? challenge.points;
        setState(() {
          _dailyChallenges.removeWhere((c) => c.id == challenge.id);
          if (!_completedChallenges.any((c) => c.id == challenge.id)) {
            _completedChallenges.add(challenge);
          }
          _streak = (result['newStreak'] as num?)?.toInt() ?? (_streak + 1);
          // The server's totals are the truth — never a local guess.
          _points = (result['points'] as num?)?.toInt() ??
              (_points + pointsEarned);
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.celebration_rounded, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '🎉 Challenge complete! +$pointsEarned points',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        _ai.trackEvent('coach_challenge_completed', properties: {
          'challenge_id': challenge.id,
          'points_earned': pointsEarned,
        });
      } else {
        setState(() => _isProcessing = false);
        final error =
            result['error'] as String? ?? 'Could not complete challenge';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not reach the server. Check your connection and try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _savingProfile = false;

  Future<void> _saveOnboarding() async {
    if (_savingProfile) return;
    setState(() => _savingProfile = true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('coach_user_name', _userName);
    await prefs.setString('coach_goal', _selectedGoal.toString());
    await prefs.setString('coach_niche', _selectedNiche.toString());
    await prefs.setString('coach_experience', _experienceLevel);
    await prefs.setStringList('coach_interests', _interests);
    await prefs.setBool('coach_onboarding_complete', true);

    // Sync to the server — this is what makes challenges, ideas and the
    // learning path get written for the person's real niche and goal.
    // Non-fatal: if it fails, the local prefs still work for display and
    // the next save retries.
    try {
      await _ai.saveCoachProfile(
        niche: _selectedNiche.label,
        goal: _selectedGoal.label,
        name: _userName,
        experience: _experienceLevel,
      );
    } catch (e) {
      debugPrint('Coach profile sync failed (non-fatal): $e');
    }

    if (!mounted) return;
    setState(() {
      _savingProfile = false;
      _isOnboarding = false;
      // The old ideas / path were written for the previous answers.
      _contentIdeas = [];
      _coachTips = [];
      _planSteps = [];
      _planCompleted = {};
    });
    await _loadUserData();
  }

  // ─── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPremium = Provider.of<PremiumProvider>(context).isPremium;

    if (!isPremium) {
      return _buildPremiumWall();
    }

    if (_isOnboarding) {
      return _buildOnboarding();
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('AI Coach'),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
              SizedBox(height: AppSpacing.md),
              Text(
                'Getting your coach ready...',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildTabs(),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildDashboard(),
                _buildChallenges(),
                _buildIdeas(),
                _buildLearningPath(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Premium Wall ──────────────────────────────────────────────────

  Widget _buildPremiumWall() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('AI Content Coach'),
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.accentGradient,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.primary,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'AI Content Coach',
                style: AppTypography.displayMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Get personalized coaching, daily challenges, and creator starter ideas',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text('Upgrade to Pro'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── App Bar ─────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Row(
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text('AI Coach', overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                color: AppColors.warning,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '$_streak',
                style: AppTypography.caption.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          margin: const EdgeInsets.only(right: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.star_rounded,
                color: AppColors.primary,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '$_points',
                style: AppTypography.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loadUserData,
          tooltip: 'Refresh',
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded),
          onPressed: () => setState(() => _isOnboarding = true),
          tooltip: 'Edit niche & goal',
        ),
      ],
    );
  }

  // ─── Tabs ─────────────────────────────────────────────────────────────

  Widget _buildTabs() {
    final tabs = [
      {'icon': Icons.dashboard_rounded, 'label': 'Dashboard'},
      {'icon': Icons.task_rounded, 'label': 'Challenges'},
      {'icon': Icons.lightbulb_rounded, 'label': 'Ideas'},
      {'icon': Icons.school_rounded, 'label': 'Learning'},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = _selectedTab == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedTab = index),
              child: Container(
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      color: isSelected ? Colors.white : AppColors.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          tab['label'] as String,
                          maxLines: 1,
                          style: TextStyle(
                            color:
                                isSelected ? Colors.white : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Dashboard ──────────────────────────────────────────────────────

  Widget _buildDashboard() {
    final totalDownloads = (_activity['totalDownloads'] as num?)?.toInt() ?? 0;
    final repurposeCount = (_activity['repurposeCount'] as num?)?.toInt() ?? 0;
    final translateCount = (_activity['translateCount'] as num?)?.toInt() ?? 0;
    final topPlatform = (_activity['topPlatform'] as String?) ?? '';
    final hasActivity = _activity.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.primary,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Center(
                    child: Text(
                      _userName.isNotEmpty ? _userName[0].toUpperCase() : 'C',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good ${_getTimeOfDay()}, $_userName!',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Goal: ${_selectedGoal.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    _selectedNiche.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _StatCard(
                label: 'Streak',
                value: _streak == 1 ? '1 day' : '$_streak days',
                icon: Icons.local_fire_department_rounded,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatCard(
                label: 'Points',
                value: '$_points',
                icon: Icons.star_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatCard(
                label: 'Today',
                value: _completedChallenges.isNotEmpty ? 'Done' : 'To do',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
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
                const Row(
                  children: [
                    Icon(
                      Icons.analytics_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Your last 30 days',
                        style: AppTypography.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_ideasLoading && !hasActivity)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text(
                          'Looking at your activity...',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else if (!hasActivity && _ideasError != null)
                  Text(
                    _ideasError!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textMuted),
                  )
                else ...[
                  Row(
                    children: [
                      _AnalysisItem(label: 'Downloads', value: '$totalDownloads'),
                      _AnalysisItem(
                        label: 'Top platform',
                        value: topPlatform.isEmpty
                            ? '—'
                            : _platformLabel(topPlatform),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      _AnalysisItem(label: 'Repurposed', value: '$repurposeCount'),
                      _AnalysisItem(label: 'Translations', value: '$translateCount'),
                    ],
                  ),
                  if (totalDownloads == 0 &&
                      repurposeCount == 0 &&
                      translateCount == 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Nothing yet — download or repurpose a video and your '
                      'coach will tailor its advice to what you do.',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ],
                if (_coachTips.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Coach tips for you',
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ..._coachTips.map(
                    (tip) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              tip,
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_dailyChallenges.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: const Icon(
                          Icons.task_rounded,
                          color: AppColors.warning,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text(
                          'Daily Challenge',
                          style: AppTypography.titleMedium,
                        ),
                      ),
                      Text(
                        '+${_dailyChallenges.first.points} pts',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _ChallengeCard(
                    challenge: _dailyChallenges.first,
                    onComplete: _isProcessing ? null : _completeChallenge,
                  ),
                ],
              ),
            ),
          ] else if (_completedChallenges.isNotEmpty) ...[
            _ChallengeCard(
              challenge: _completedChallenges.first,
              isCompleted: true,
            ),
          ] else if (_challengeError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Text(
                _challengeError!,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
          // Clears the phone's navigation bar on edge-to-edge devices.
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  // ─── Challenges Tab ─────────────────────────────────────────────────

  Widget _buildChallenges() {
    final allChallenges = [..._dailyChallenges, ..._completedChallenges];

    if (allChallenges.isEmpty) {
      return _buildEmptyState(
        icon: Icons.task_alt_rounded,
        title: 'No Challenge Today',
        description: _challengeError ??
            'Tap refresh at the top, or check back tomorrow for a new one.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: allChallenges.length,
      itemBuilder: (context, index) {
        final challenge = allChallenges[index];
        final isCompleted = _completedChallenges.contains(challenge);

        return _ChallengeCard(
          challenge: challenge,
          isCompleted: isCompleted,
          onComplete: isCompleted || _isProcessing ? null : _completeChallenge,
        );
      },
    );
  }

  // ─── Ideas Tab ──────────────────────────────────────────────────────

  Widget _buildIdeas() {
    if (_ideasLoading && _contentIdeas.isEmpty) {
      return _buildBusyState('Writing ideas for your niche...');
    }
    if (_contentIdeas.isEmpty) {
      return _buildEmptyState(
        icon: Icons.lightbulb_rounded,
        title: 'No Ideas Yet',
        description:
            _ideasError ?? 'Get ideas written for your niche and goal.',
        actionLabel: 'Get ideas',
        onAction: () => _loadIdeas(refresh: _ideasError == null),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.of(context).padding.bottom),
      itemCount: _contentIdeas.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'For ${_selectedNiche.label} · ${_selectedGoal.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textMuted),
                  ),
                ),
                TextButton.icon(
                  onPressed:
                      _ideasLoading ? null : () => _loadIdeas(refresh: true),
                  icon: _ideasLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('New ideas'),
                ),
              ],
            ),
          );
        }
        return _IdeaCard(idea: _contentIdeas[index - 1]);
      },
    );
  }

  // ─── Learning Path Tab ─────────────────────────────────────────────

  Widget _buildLearningPath() {
    if (_planLoading && _planSteps.isEmpty) {
      return _buildBusyState('Building your learning path...');
    }
    if (_planSteps.isEmpty) {
      return _buildEmptyState(
        icon: Icons.school_rounded,
        title: 'No Learning Path Yet',
        description: _planError ??
            'Get a step-by-step path built for your goal and level.',
        actionLabel: 'Build my path',
        onAction: _loadPlan,
      );
    }

    final doneCount =
        _planSteps.where((s) => _planCompleted.contains(s['id'])).length;
    final progress = _planSteps.isEmpty ? 0.0 : doneCount / _planSteps.length;

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md,
          AppSpacing.md + MediaQuery.of(context).padding.bottom),
      itemCount: _planSteps.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your path to: ${_selectedGoal.label}',
                  style: AppTypography.bodyMedium
                      .copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '$doneCount of ${_planSteps.length} steps done',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary),
                  ),
                ),
              ],
            ),
          );
        }

        final step = _planSteps[index - 1];
        final stepId = (step['id'] ?? 'step$index').toString();
        final done = _planCompleted.contains(stepId);
        final action = (step['action'] ?? '').toString();
        final minutes = (step['minutes'] as num?)?.toInt();

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: done
                ? AppColors.success.withValues(alpha: 0.04)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: done
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.borderLight,
            ),
            boxShadow: done ? null : AppShadows.soft,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (done ? AppColors.success : AppColors.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  '$index',
                  style: TextStyle(
                    color: done ? AppColors.success : AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (step['title'] ?? '').toString(),
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (step['description'] ?? '').toString(),
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (action.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Do this: $action',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (minutes != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'About $minutes min',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Checkbox(
                value: done,
                activeColor: AppColors.success,
                onChanged: (_) => _togglePlanStep(stepId),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBusyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ─── Onboarding ────────────────────────────────────────────────────

  Widget _selectChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.textMuted,
                size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _onboardingHeading(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: AppTypography.titleMedium),
      ),
    );
  }

  /// One scrollable page (so nothing overflows on small phones or when
  /// the keyboard is open) that collects everything the coach
  /// personalises on: goal, niche, experience and a name.
  Widget _buildOnboarding() {
    final alreadySetUp = _streak > 0 ||
        _points > 0 ||
        _dailyChallenges.isNotEmpty ||
        _completedChallenges.isNotEmpty ||
        _contentIdeas.isNotEmpty;
    const levels = [
      ('beginner', 'Beginner', Icons.eco_rounded),
      ('intermediate', 'Intermediate', Icons.trending_up_rounded),
      ('advanced', 'Advanced', Icons.rocket_launch_rounded),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Set up your coach'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your challenges, ideas and learning path are written '
                      'for the answers you give here.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    _onboardingHeading('What do you want to achieve?'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: CoachGoal.values
                            .map((goal) => _selectChip(
                                  label: goal.label,
                                  icon: goal.icon,
                                  selected: _selectedGoal == goal,
                                  onTap: () =>
                                      setState(() => _selectedGoal = goal),
                                ))
                            .toList(),
                      ),
                    ),
                    _onboardingHeading('What\'s your niche?'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: CoachNiche.values
                            .map((niche) => _selectChip(
                                  label: niche.label,
                                  icon: niche.icon,
                                  selected: _selectedNiche == niche,
                                  onTap: () =>
                                      setState(() => _selectedNiche = niche),
                                ))
                            .toList(),
                      ),
                    ),
                    _onboardingHeading('How experienced are you?'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: levels
                            .map((level) => _selectChip(
                                  label: level.$2,
                                  icon: level.$3,
                                  selected: _experienceLevel == level.$1,
                                  onTap: () => setState(
                                      () => _experienceLevel = level.$1),
                                ))
                            .toList(),
                      ),
                    ),
                    _onboardingHeading('What should we call you?'),
                    TextFormField(
                      initialValue: _userName == 'Creator' ? '' : _userName,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        hintText: 'Your name or brand',
                        prefixIcon: Icon(Icons.person_rounded),
                        counterText: '',
                      ),
                      onChanged: (value) => _userName =
                          value.trim().isNotEmpty ? value.trim() : 'Creator',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _savingProfile ? null : _saveOnboarding,
                      child: Text(_savingProfile
                          ? 'Saving...'
                          : (alreadySetUp
                              ? 'Save changes'
                              : 'Start Your Journey 🚀')),
                    ),
                  ),
                  if (alreadySetUp)
                    TextButton(
                      onPressed: _savingProfile
                          ? null
                          : () => setState(() => _isOnboarding = false),
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helper Widgets ──────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppColors.textMuted),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTypography.headlineMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              description,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getTimeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Morning';
    if (hour < 17) return 'Afternoon';
    return 'Evening';
  }
}

// ─── Stat Card ──────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
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
        ),
      ),
    );
  }
}

// ─── Analysis Item ──────────────────────────────────────────────────────

class _AnalysisItem extends StatelessWidget {
  final String label;
  final String value;

  const _AnalysisItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            style: AppTypography.caption.copyWith(
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Challenge Card ─────────────────────────────────────────────────────

class _ChallengeCard extends StatelessWidget {
  final CoachChallenge challenge;
  final bool isCompleted;
  final Function(CoachChallenge)? onComplete;

  const _ChallengeCard({
    required this.challenge,
    this.isCompleted = false,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final difficultyStars = List.generate(5, (i) => i < challenge.difficulty);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isCompleted
            ? AppColors.success.withValues(alpha: 0.04)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isCompleted
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: challenge.difficulty <= 2
                      ? AppColors.success.withValues(alpha: 0.12)
                      : challenge.difficulty <= 4
                          ? AppColors.warning.withValues(alpha: 0.12)
                          : AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  challenge.category,
                  style: TextStyle(
                    color: challenge.difficulty <= 2
                        ? AppColors.success
                        : challenge.difficulty <= 4
                            ? AppColors.warning
                            : AppColors.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Row(
                children: difficultyStars
                    .map((_) => const Icon(Icons.star_rounded,
                        color: AppColors.warning, size: 12))
                    .toList(),
              ),
              const Spacer(),
              Text(
                '${challenge.estimatedMinutes} min',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            challenge.title,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            challenge.description,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (challenge.steps.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Steps:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            ...challenge.steps.map((step) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.circle_rounded,
                        color: AppColors.textMuted,
                        size: 6,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (challenge.tip != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_rounded,
                    color: AppColors.info,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      '💡 ${challenge.tip}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          if (onComplete != null && !isCompleted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => onComplete!(challenge),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('Complete Challenge'),
              ),
            ),
          if (isCompleted)
            const Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 16,
                ),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'Completed! 🎉',
                  style: TextStyle(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ─── Idea Card ─────────────────────────────────────────────────────────

class _IdeaCard extends StatelessWidget {
  final Map<String, dynamic> idea;

  const _IdeaCard({required this.idea});

  @override
  Widget build(BuildContext context) {
    final rawDifficulty = (idea['difficulty'] ?? '').toString().toLowerCase();
    final difficulty = rawDifficulty.isEmpty ? 'easy' : rawDifficulty;
    final Color difficultyColor = difficulty == 'hard'
        ? AppColors.error
        : (difficulty == 'medium' ? AppColors.warning : AppColors.success);
    final hook = (idea['hook'] ?? '').toString().trim();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (idea['format'] ?? 'Post').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: difficultyColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  difficulty[0].toUpperCase() + difficulty.substring(1),
                  style: TextStyle(
                    color: difficultyColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            (idea['title'] ?? 'Content idea').toString(),
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            (idea['description'] ?? '').toString(),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (hook.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    color: AppColors.warning,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      hook,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: hook));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Hook copied'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.only(left: AppSpacing.sm),
                      child: Icon(Icons.copy_rounded,
                          size: 16, color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
