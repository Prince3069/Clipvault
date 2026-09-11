// app.dart — Main App Widget with Splash Screen
// ignore_for_file: avoid_print

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/screens/main_navigation_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/splash_screen.dart';
import 'ui/themes/app_theme.dart';
import 'ui/widgets/share_target_listener.dart';

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediaNest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      home: kIsWeb
          ? const _StartupGate()
          : ShareTargetListener(child: const _StartupGate()),
    );
  }
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate>
    with SingleTickerProviderStateMixin {
  static const _purple = Color(0xFF7357FF);
  static const _deepPurple = Color(0xFF4B2EA8);
  static const _ink = Color(0xFF101326);

  late final AnimationController _animation;
  Timer? _taglineTimer;
  bool? _onboardingCompleted;
  int _taglineIndex = 0;

  static const _taglines = [
    'Capture. Organize. Create.',
    'Translate every idea.',
    'Turn inspiration into momentum.',
  ];

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..forward();
    _taglineTimer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted) return;
      setState(() => _taglineIndex = (_taglineIndex + 1) % _taglines.length);
    });
    _loadStartupState();
  }

  @override
  void dispose() {
    _taglineTimer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  Future<void> _loadStartupState() async {
    final started = DateTime.now();
    try {
      final prefsFuture = SharedPreferences.getInstance();
      final prefs = await prefsFuture;
      final elapsed = DateTime.now().difference(started);
      final remaining = const Duration(milliseconds: 850) - elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!mounted) return;
      setState(() {
        _onboardingCompleted = prefs.getBool('onboarding_done') ?? false;
      });
    } catch (_) {
      final elapsed = DateTime.now().difference(started);
      final remaining = const Duration(milliseconds: 850) - elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!mounted) return;
      setState(() => _onboardingCompleted = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final completed = _onboardingCompleted;
    if (completed != null) {
      return completed
          ? const MainNavigationScreen()
          : const OnboardingScreen();
    }

    // Show splash screen while loading
    return const SplashScreen();
  }
}
