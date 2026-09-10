// ui/screens/ai_content_coach.dart
// COMPLETE - AI Content Coach (Beta)
// Features: Content Analysis, Strategy Suggestions, Daily Challenges, Progress Tracking

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/ai_service.dart';
import '../../providers/premium_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/media_provider.dart';
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
  Map<String, dynamic> _analysis = {};
  List<Map<String, dynamic>> _contentIdeas = [];
  List<Map<String, dynamic>> _learningPath = [];
  int _streak = 0;
  int _points = 0;

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
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      _userName = prefs.getString('coach_user_name') ?? 'Creator';

      // Load preferences
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

      // Check if onboarding is complete
      _isOnboarding = !(prefs.getBool('coach_onboarding_complete') ?? false);

      // Load challenges
      await _loadChallenges();

      // Load analysis
      await _analyzeContent();

      // Generate content ideas
      await _generateContentIdeas();

      // Load streak
      _streak = prefs.getInt('coach_streak') ?? 0;
      _points = prefs.getInt('coach_points') ?? 0;

      // Update daily streak
      final lastActive = prefs.getString('coach_last_active');
      final today = DateTime.now().toIso8601String().split('T')[0];
      if (lastActive != today) {
        final yesterday = DateTime.now()
            .subtract(const Duration(days: 1))
            .toIso8601String()
            .split('T')[0];
        if (lastActive == yesterday) {
          _streak++;
        } else {
          _streak = 1;
        }
        await prefs.setString('coach_last_active', today);
        await prefs.setInt('coach_streak', _streak);
      }
    } catch (e) {
      setState(() => _error = 'Failed to load coach data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChallenges() async {
    final prefs = await SharedPreferences.getInstance();
    final challengesJson = prefs.getString('coach_challenges');
    final completedJson = prefs.getString('coach_completed_challenges');

    if (challengesJson != null) {
      final List<dynamic> data = jsonDecode(challengesJson);
      _dailyChallenges = data.map((e) => CoachChallenge.fromJson(e)).toList();
    } else {
      // Generate default challenges
      _dailyChallenges = _generateDefaultChallenges();
      await _saveChallenges();
    }

    if (completedJson != null) {
      final List<dynamic> data = jsonDecode(completedJson);
      _completedChallenges =
          data.map((e) => CoachChallenge.fromJson(e)).toList();
    }
  }

  Future<void> _saveChallenges() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_dailyChallenges.map((c) => c.toJson()).toList());
    await prefs.setString('coach_challenges', json);
    final completedJson =
        jsonEncode(_completedChallenges.map((c) => c.toJson()).toList());
    await prefs.setString('coach_completed_challenges', completedJson);
  }

  List<CoachChallenge> _generateDefaultChallenges() {
    return [
      const CoachChallenge(
        id: 'challenge_1',
        title: 'Create a 15-Second Hook',
        description: 'Capture attention in the first 3 seconds',
        category: 'Content Creation',
        difficulty: 2,
        estimatedMinutes: 10,
        steps: [
          'Open your camera app',
          'Record a 15-second video with a strong opening',
          'Watch it back and critique the hook',
          'Record 2 more versions with different approaches',
          'Pick the best one',
        ],
        tip: 'The first 3 seconds determine if someone watches the rest.',
      ),
      const CoachChallenge(
        id: 'challenge_2',
        title: 'Analyze a Top Creator',
        description: 'Study what makes their content work',
        category: 'Strategy',
        difficulty: 1,
        estimatedMinutes: 15,
        steps: [
          'Find a creator in your niche with 100K+ followers',
          'Watch 5 of their most popular videos',
          'Note: Hook, Visuals, Audio, Call-to-Action',
          'Write down 3 things you can learn from them',
        ],
        tip: 'Don\'t copy - learn what works and make it your own.',
      ),
      const CoachChallenge(
        id: 'challenge_3',
        title: 'Write 10 Caption Ideas',
        description: 'Generate a week\'s worth of captions',
        category: 'Copywriting',
        difficulty: 2,
        estimatedMinutes: 20,
        steps: [
          'Brainstorm 3 topics from your niche',
          'Write 3-4 captions per topic',
          'Include different tones: Educational, Funny, Inspirational',
          'Add 3 relevant hashtags to each',
          'Save the best 5 for future use',
        ],
        tip: 'Captions that ask questions get more comments.',
      ),
      const CoachChallenge(
        id: 'challenge_4',
        title: 'Create a Content Pillar',
        description: 'Define your content pillars',
        category: 'Strategy',
        difficulty: 3,
        estimatedMinutes: 25,
        steps: [
          'Identify 3-5 topics you can consistently create content about',
          'For each pillar, list 5 sub-topics',
          'Create a content calendar for the next 7 days',
          'Ensure each post fits into one of your pillars',
        ],
        tip: 'Content pillars help you stay focused and build authority.',
      ),
      const CoachChallenge(
        id: 'challenge_5',
        title: 'Repurpose Your Best Content',
        description: 'Extend the life of your content',
        category: 'Growth',
        difficulty: 2,
        estimatedMinutes: 15,
        steps: [
          'Find your best-performing video',
          'Extract key moments as individual clips',
          'Create a carousel post from screenshots',
          'Write a thread on X/Twitter with key insights',
        ],
        tip: 'One piece of content can become 5+ posts.',
      ),
    ];
  }

  // ─── AI Analysis ─────────────────────────────────────────────────────

  Future<void> _analyzeContent() async {
    try {
      // Get user's media library
      final mediaProvider = Provider.of<MediaProvider>(context, listen: false);
      final allMedia = mediaProvider.allMedia;

      if (allMedia.isEmpty) {
        _analysis = {
          'status': 'empty',
          'message': 'Download some content to get personalized analysis',
        };
        return;
      }

      // Analyze library stats
      final stats = await _ai.getLibraryStats();

      // Generate insights based on stats
      final categories = stats['categories'] as Map<String, dynamic>? ?? {};
      final topCategory = categories.entries.isNotEmpty
          ? categories.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : 'Unknown';

      final platforms = stats['platforms'] as Map<String, dynamic>? ?? {};
      final topPlatform = platforms.entries.isNotEmpty
          ? platforms.entries.reduce((a, b) => a.value > b.value ? a : b).key
          : 'Unknown';

      _analysis = {
        'status': 'ready',
        'totalItems': allMedia.length,
        'topCategory': topCategory,
        'topPlatform': topPlatform,
        'categories': categories,
        'platforms': platforms,
        'contentMix': {
          'videos': allMedia.where((m) => m.isVideo).length,
          'images': allMedia.where((m) => !m.isVideo).length,
        },
        'recommendations': _generateRecommendations(topCategory, topPlatform),
        'createdAt': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('Analysis error: $e');
      _analysis = {
        'status': 'error',
        'message': 'Could not analyze content: $e',
      };
    }
  }

  List<String> _generateRecommendations(
      String topCategory, String topPlatform) {
    final recommendations = <String>[];

    // Based on category
    switch (topCategory) {
      case 'Comedy':
        recommendations.add(
            '🎭 Try different humor styles: observational, situational, parody');
        recommendations.add('📊 Track which jokes get the best response');
        break;
      case 'Tutorial':
        recommendations.add('📚 Create a series of related tutorials');
        recommendations.add('🎯 Make sure each tutorial has a clear takeaway');
        break;
      case 'Music':
        recommendations.add('🎵 Experiment with different genres and formats');
        recommendations.add('🎤 Use captions to make lyrics accessible');
        break;
      case 'Fitness':
        recommendations.add('💪 Show progress and transformations');
        recommendations
            .add('🏋️ Create beginner-friendly versions of exercises');
        break;
      default:
        recommendations.add('📈 Analyze which of your posts perform best');
        recommendations.add('🎯 Double down on what\'s working');
    }

    // Based on platform
    if (topPlatform == 'tiktok') {
      recommendations.add('🎵 Use trending sounds to increase discoverability');
      recommendations
          .add('⏱️ Keep videos between 15-30 seconds for best retention');
    } else if (topPlatform == 'instagram') {
      recommendations
          .add('📸 Use high-quality visuals and consistent aesthetics');
      recommendations.add('📝 Write captions that encourage comments');
    }

    recommendations.add('📊 Post consistently to build momentum');

    return recommendations;
  }

  // ─── Content Ideas ──────────────────────────────────────────────────

  Future<void> _generateContentIdeas() async {
    setState(() => _isProcessing = true);

    try {
      // Provide an offline starter set while the dedicated Repurpose Studio
      // handles provider-backed AI actions with explicit allowance tracking.
      _contentIdeas = [
        {
          'title': 'Behind the Scenes',
          'description': 'Show your creative process and workspace',
          'format': 'video',
          'difficulty': 2,
          'estimatedTime': 15,
          'hook': 'Ever wondered how this is made? 🤔',
        },
        {
          'title': 'Top 5 Tips',
          'description': 'Share your expertise in a quick list',
          'format': 'video',
          'difficulty': 1,
          'estimatedTime': 10,
          'hook': 'Here are 5 things I wish I knew earlier 📝',
        },
        {
          'title': 'Common Mistakes',
          'description': 'Help others avoid your early mistakes',
          'format': 'video',
          'difficulty': 2,
          'estimatedTime': 20,
          'hook': 'Don\'t make this mistake like I did 🚫',
        },
        {
          'title': 'Day in the Life',
          'description': 'Document a full day as a creator',
          'format': 'video',
          'difficulty': 3,
          'estimatedTime': 30,
          'hook': 'This is what a real day looks like 👀',
        },
        {
          'title': 'Tool Review',
          'description': 'Share your favorite tools or apps',
          'format': 'video',
          'difficulty': 1,
          'estimatedTime': 10,
          'hook': 'This tool changed everything for me 🛠️',
        },
        {
          'title': 'Q&A Session',
          'description': 'Answer your audience\'s burning questions',
          'format': 'video',
          'difficulty': 2,
          'estimatedTime': 20,
          'hook': 'You asked, I answered 📢',
        },
        {
          'title': 'Trend Take',
          'description': 'Put your unique spin on a current trend',
          'format': 'video',
          'difficulty': 2,
          'estimatedTime': 15,
          'hook': 'My take on this trend 💭',
        },
        {
          'title': 'Motivation Moment',
          'description': 'Inspire others with your story',
          'format': 'text',
          'difficulty': 1,
          'estimatedTime': 10,
          'hook': 'If I can do it, so can you ✨',
        },
      ];
    } catch (e) {
      debugPrint('Content ideas error: $e');
      _contentIdeas = [];
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ─── User Actions ────────────────────────────────────────────────────

  Future<void> _completeChallenge(CoachChallenge challenge) async {
    setState(() {
      _completedChallenges.add(challenge);
      _points += challenge.difficulty * 10;
      _dailyChallenges.removeWhere((c) => c.id == challenge.id);
    });

    await _saveChallenges();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('coach_points', _points);

    // Show celebration
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '🎉 Challenge complete! +${challenge.difficulty * 10} points',
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

    // Track completion
    await _ai.trackEvent('coach_challenge_completed', properties: {
      'challenge_id': challenge.id,
      'points_earned': challenge.difficulty * 10,
    });
  }

  Future<void> _saveOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('coach_user_name', _userName);
    await prefs.setString('coach_goal', _selectedGoal.toString());
    await prefs.setString('coach_niche', _selectedNiche.toString());
    await prefs.setString('coach_experience', _experienceLevel);
    await prefs.setStringList('coach_interests', _interests);
    await prefs.setBool('coach_onboarding_complete', true);

    setState(() => _isOnboarding = false);
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
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ─── Tabs ──────────────────────────────────────────────────────────
          _buildTabs(),

          // ─── Content ──────────────────────────────────────────────────────
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
          Text('AI Coach'),
        ],
      ),
      actions: [
        // Streak
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
        // Points
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
                    Text(
                      tab['label'] as String,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textMuted,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
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
    final analysis = _analysis;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          // ─── Welcome ──────────────────────────────────────────────────────
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
                  child: Text(
                    _userName[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good ${_getTimeOfDay()}, $_userName!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Keep creating and growing 🚀',
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
                    '${_selectedNiche.label}',
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

          // ─── Quick Stats ─────────────────────────────────────────────────
          Row(
            children: [
              _StatCard(
                label: 'Streak',
                value: '$_streak days',
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
                label: 'Challenges',
                value: '${_completedChallenges.length}',
                icon: Icons.task_alt_rounded,
                color: AppColors.success,
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ─── Analysis ────────────────────────────────────────────────────
          if (analysis.isNotEmpty && analysis['status'] == 'ready') ...[
            Container(
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
                      const Icon(
                        Icons.analytics_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text(
                        'Content Analysis',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '${analysis['totalItems']} items',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      _AnalysisItem(
                        label: 'Top Category',
                        value: analysis['topCategory'] ?? 'N/A',
                      ),
                      _AnalysisItem(
                        label: 'Top Platform',
                        value: analysis['topPlatform'] ?? 'N/A',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Recommendations',
                    style: AppTypography.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ...(analysis['recommendations'] as List<String>? ?? []).map(
                    (rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              rec,
                              style: AppTypography.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // ─── Daily Challenge Card ──────────────────────────────────────
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
                      const Text(
                        'Daily Challenge',
                        style: AppTypography.titleMedium,
                      ),
                      const Spacer(),
                      Text(
                        '${_dailyChallenges.length} left',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_dailyChallenges.isNotEmpty) ...[
                    _ChallengeCard(
                      challenge: _dailyChallenges.first,
                      onComplete: _completeChallenge,
                    ),
                  ],
                ],
              ),
            ),
          ],
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
        title: 'All Challenges Complete! 🎉',
        description: 'Check back tomorrow for new challenges.',
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
          onComplete: isCompleted ? null : _completeChallenge,
        );
      },
    );
  }

  // ─── Ideas Tab ──────────────────────────────────────────────────────

  Widget _buildIdeas() {
    if (_contentIdeas.isEmpty) {
      return _buildEmptyState(
        icon: Icons.lightbulb_rounded,
        title: 'No Ideas Yet',
        description: 'Generate ideas based on your niche and goals.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: _contentIdeas.length,
      itemBuilder: (context, index) {
        final idea = _contentIdeas[index];
        return _IdeaCard(idea: idea);
      },
    );
  }

  // ─── Learning Path Tab ─────────────────────────────────────────────

  Widget _buildLearningPath() {
    final learningPath = [
      {
        'title': 'Getting Started with Content Creation',
        'description': 'Learn the fundamentals of creating engaging content',
        'lessonCount': 5,
        'icon': Icons.start_rounded,
      },
      {
        'title': 'Growth Hacking for Creators',
        'description': 'Proven strategies to grow your audience',
        'lessonCount': 7,
        'icon': Icons.trending_up_rounded,
      },
      {
        'title': 'Advanced Editing Techniques',
        'description': 'Take your editing skills to the next level',
        'lessonCount': 6,
        'icon': Icons.cut_rounded,
      },
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: learningPath.length,
      itemBuilder: (context, index) {
        final lesson = learningPath[index];
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  lesson['icon'] as IconData,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lesson['title'] as String,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      lesson['description'] as String,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${lesson['lessonCount'] as int} lessons',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Onboarding ────────────────────────────────────────────────────

  Widget _buildOnboarding() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(flex: 1),

              // Header
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.primary,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                'Welcome to AI Coach',
                style: AppTypography.displayMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Get personalized coaching and content ideas',
                style: AppTypography.bodyMedium,
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.xl),

              // Goal Selection
              const Text(
                'What do you want to achieve?',
                style: AppTypography.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: CoachGoal.values.map((goal) {
                  final isSelected = _selectedGoal == goal;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedGoal = goal),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(goal.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              size: 16),
                          const SizedBox(width: 4),
                          Text(
                            goal.label,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Niche Selection
              const Text(
                'What\'s your niche?',
                style: AppTypography.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                height: 150,
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: CoachNiche.values.map((niche) {
                      final isSelected = _selectedNiche == niche;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedNiche = niche),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.12)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.borderLight,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(niche.icon,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  size: 16),
                              const SizedBox(width: 4),
                              Text(
                                niche.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.md),

              // Name
              TextField(
                decoration: const InputDecoration(
                  hintText: 'What should we call you?',
                  prefixIcon: Icon(Icons.person_rounded),
                ),
                onChanged: (value) => setState(
                    () => _userName = value.isNotEmpty ? value : 'Creator'),
              ),

              const Spacer(flex: 1),

              // Start button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveOnboarding,
                  child: const Text('Start Your Journey 🚀'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helper Widgets ──────────────────────────────────────────────────

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String description,
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
          const SizedBox(height: AppSpacing.sm),
          if (challenge.steps.isNotEmpty) ...[
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
    final difficultyStars =
        List.generate(5, (i) => i < (idea['difficulty'] as int? ?? 1));

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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  idea['format'] as String? ?? 'video',
                  style: const TextStyle(
                    color: AppColors.primary,
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
                '${idea['estimatedTime'] as int? ?? 10} min',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            idea['title'] as String? ?? 'Content Idea',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            idea['description'] as String? ?? '',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (idea['hook'] != null) ...[
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
                    Icons.link_rounded,
                    color: AppColors.warning,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      idea['hook'] as String,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
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
