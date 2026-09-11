// ui/screens/onboarding_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/permission_service.dart';
import '../themes/app_theme.dart';
import 'main_navigation_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PermissionService _ps = PermissionService();
  PermissionState? _permState;
  bool _isLoading = false;
  bool _showAccessibilityGuide = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final state = await _ps.getPermissionState();
    if (mounted) setState(() { _permState = state; _isLoading = false; });
  }

  Future<void> _grantCore() async {
    setState(() => _isLoading = true);
    await _ps.requestCorePermissions();
    await _refresh();
  }

  Future<void> _grantOverlay() async {
    setState(() => _isLoading = true);
    await _ps.requestOverlayPermission();
    await _refresh();
  }

  Future<void> _openAccessibility() async {
    // On Android 12+, show the restricted settings guide first
    final sdk = await _ps.getSdkVersion();
    if (sdk >= 31 && !(_permState?.accessibility ?? false)) {
      setState(() => _showAccessibilityGuide = true);
      return;
    }
    await _ps.openAccessibilitySettings();
    await Future.delayed(const Duration(seconds: 3));
    await _refresh();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showAccessibilityGuide) {
      return _buildAccessibilityGuide();
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 16),
              _buildLogo(),
              const SizedBox(height: 24),
              _buildTitle(),
              const SizedBox(height: 28),
              Expanded(child: _buildPermissions()),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.45),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(Icons.download_rounded, color: Colors.white, size: 38),
    );
  }

  Widget _buildTitle() {
    return Column(
      children: [
        const Text('Setup MediaNest',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5)),
        const SizedBox(height: 8),
        Text(
          'A private, focused workspace for your media',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPermissions() {
    return ListView(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_rounded,
                  color: AppColors.primary, size: 34),
              SizedBox(height: 14),
              Text('Ready when you are',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 8),
              Text(
                'MediaNest does not ask for broad storage, overlay, or accessibility access during setup. Downloads are saved through Android MediaStore. WhatsApp Status asks for one folder grant only when you open Status Saver.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.55),
              ),
              SizedBox(height: 14),
              Text('You stay in control of every permission.',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _permTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool granted,
    bool required = false,
    bool showInfoBadge = false,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: granted
              ? AppColors.success.withValues(alpha: 0.5)
              : AppColors.border,
          width: granted ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (granted ? AppColors.success : color)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              granted ? Icons.check_circle_outline : icon,
              color: granted ? AppColors.success : color,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if (required) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Required',
                            style: TextStyle(
                                color: AppColors.error,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (showInfoBadge && !granted) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Extra steps',
                            style: TextStyle(
                                color: AppColors.info,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (!granted)
            GestureDetector(
              onTap: _isLoading ? null : onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Text('Allow',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            )
          else
            const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 24),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _finish,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Get Started →',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Permissions appear only when the selected feature needs them.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }

  // ─── Accessibility Guide (Android 12+ "Allow restricted settings") ─────────

  Widget _buildAccessibilityGuide() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button
              GestureDetector(
                onTap: () => setState(() => _showAccessibilityGuide = false),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Icon(Icons.arrow_back_ios_rounded,
                      color: AppColors.textSecondary, size: 18),
                ),
              ),
              const SizedBox(height: 24),

              // Header
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.info_outline_rounded,
                    color: AppColors.info, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Enable Accessibility\nService',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.2),
              ),
              const SizedBox(height: 10),
              const Text(
                'Android 12+ requires extra steps for sideloaded apps to use accessibility services.',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 28),

              // Steps
              const Text('Follow these steps:',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _guideStep('1', 'Tap "Open App Info" below',
                  Icons.info_outline_rounded, AppColors.primary),
              const SizedBox(height: 12),
              _guideStep(
                  '2',
                  'Tap the ⋮ three-dot menu (top right corner)',
                  Icons.more_vert_rounded,
                  AppColors.secondary),
              const SizedBox(height: 12),
              _guideStep(
                  '3',
                  'Select "Allow restricted settings" and enable it',
                  Icons.toggle_on_rounded,
                  AppColors.warning),
              const SizedBox(height: 12),
              _guideStep(
                  '4',
                  'Come back here and tap "Open Accessibility Settings"',
                  Icons.accessibility_new_rounded,
                  AppColors.accent),
              const SizedBox(height: 12),
              _guideStep(
                  '5',
                  'Find "MediaNest" in the list and enable it',
                  Icons.check_circle_outline,
                  AppColors.success),

              const Spacer(),

              // Buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await _ps.openAppInfoSettings();
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open App Info'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _ps.openAccessibilitySettings();
                    setState(() => _showAccessibilityGuide = false);
                    await Future.delayed(const Duration(seconds: 3));
                    await _refresh();
                  },
                  icon: const Icon(Icons.accessibility_new_rounded, size: 18),
                  label: const Text('Open Accessibility Settings'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: const BorderSide(color: AppColors.accent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    setState(() => _showAccessibilityGuide = false);
                  },
                  child: const Text(
                    'Skip — I\'ll do this later',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _guideStep(
      String number, String text, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: Text(number,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(text,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5)),
          ),
        ),
      ],
    );
  }
}
