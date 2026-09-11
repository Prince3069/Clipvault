// ui/screens/settings_screen.dart
// REBRANDED: MediaNest
// ADDED: Auto-sync to Cloud Vault toggle
// ignore_for_file: use_build_context_synchronously

import 'package:all_social_downloader/ui/screens/cloud_vault_screen.dart';
import 'package:all_social_downloader/ui/screens/premium_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/permission_service.dart';
import '../themes/app_theme.dart';
import 'privacy_policy_screen.dart';
import 'terms_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final PermissionService _ps = PermissionService();
  PermissionState? _perm;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final s = await _ps.getPermissionState();
    if (mounted) {
      setState(() {
        _perm = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverAppBar(
              floating: true,
              backgroundColor: AppColors.bg,
              elevation: 0,
              title: Text('Settings',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
              centerTitle: false,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Consumer<SettingsProvider>(
                  builder: (_, settings, __) => Column(
                    children: [
                      const SizedBox(height: 4),
                      _buildAppCard(),
                      const SizedBox(height: 28),
                      _permissionsSection(),
                      const SizedBox(height: 24),
                      _downloadSection(settings),
                      const SizedBox(height: 24),
                      _cloudSection(settings),
                      const SizedBox(height: 24),
                      _aboutSection(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── App identity card ───────────────────────────────────────────────────

  Widget _buildAppCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3D36AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(15),
          ),
          child:
              const Icon(Icons.download_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MediaNest',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3)),
            const SizedBox(height: 3),
            Text('Free · No Ads · All Platforms',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: const Text('v1.0.0',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  // ─── Permissions section ─────────────────────────────────────────────────

  Widget _permissionsSection() {
    final s = _perm;
    return _section(
      'PERMISSIONS',
      Icons.security_rounded,
      AppColors.primary,
      _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)),
              ),
            )
          : Column(children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  'MediaNest uses Android MediaStore for its own downloads and asks for a folder grant only inside WhatsApp Status. No broad storage, overlay, or accessibility permission is required for the core app.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5),
                ),
              ),
              _div(),
              _permRow(
                title: 'Notifications',
                icon: Icons.notifications_outlined,
                color: AppColors.secondary,
                granted: s?.notifications ?? false,
                sub: 'Optional download-completion alerts',
                onGrant: () async {
                  await _ps.requestNotificationPermission();
                  _refresh();
                },
              ),
              _div(),
              _tile(
                icon: Icons.refresh_rounded,
                color: AppColors.textMuted,
                title: 'Refresh Status',
                onTap: _refresh,
              ),
            ]),
    );
  }

  // ─── Downloads section ───────────────────────────────────────────────────

  Widget _downloadSection(SettingsProvider settings) {
    return _section(
      'DOWNLOADS',
      Icons.download_rounded,
      AppColors.secondary,
      Column(children: [
        _switchRow(
          icon: Icons.notifications_active_outlined,
          color: AppColors.secondary,
          title: 'Download Notifications',
          sub: 'Notify when a download completes',
          value: settings.showNotifications,
          onChanged: settings.setShowNotifications,
        ),
        _div(),
        _switchRow(
          icon: Icons.content_paste_rounded,
          color: AppColors.primary,
          title: 'Auto-detect Links',
          sub: 'Detect video URLs from clipboard',
          value: settings.autoDetectLinks,
          onChanged: settings.setAutoDetectLinks,
        ),
        _div(),
        _switchRow(
          icon: Icons.window_rounded,
          color: AppColors.warning,
          title: 'Floating Button',
          sub: 'Show download button in other apps',
          value: settings.showFloatingButton,
          onChanged: settings.setShowFloatingButton,
        ),
        _div(),
        _tile(
          icon: Icons.folder_open_rounded,
          color: AppColors.primary,
          title: 'Download Location',
          sub: settings.downloadPath,
        ),
      ]),
    );
  }

  // ─── Cloud section (NEW) ──────────────────────────────────────────────────

  Widget _cloudSection(SettingsProvider settings) {
    return Consumer<PremiumProvider>(
      builder: (_, premium, __) {
        final bool isPremium = premium.isPremium;

        return _section(
          'CLOUD VAULT',
          Icons.cloud_rounded,
          isPremium ? AppColors.secondary : AppColors.textMuted,
          Column(children: [
            _switchRow(
              icon: Icons.cloud_sync_rounded,
              color: isPremium ? AppColors.secondary : AppColors.textMuted,
              title: 'Auto-sync to Cloud',
              sub: isPremium
                  ? 'Automatically upload downloaded files to cloud'
                  : 'Upgrade to Pro to enable auto-sync',
              value: settings.autoSyncToCloud,
              onChanged: isPremium
                  ? settings.setAutoSyncToCloud
                  : (_) {
                      _showPremiumRequiredDialog();
                    },
            ),
            _div(),
            _tile(
              icon: Icons.cloud_upload_rounded,
              color: isPremium ? AppColors.secondary : AppColors.textMuted,
              title: 'Cloud Vault Pro',
              sub: isPremium ? '0.0 GB / 3.0 GB used' : '3GB synced storage · Pro',
              onTap: isPremium
                  ? () {
                      // Navigate to Cloud Vault
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CloudVaultScreen(),
                        ),
                      );
                    }
                  : null,
            ),
            if (!isPremium) ...[
              _div(),
              _tile(
                icon: Icons.workspace_premium_rounded,
                color: AppColors.primary,
                title: 'Upgrade to Pro',
                sub: 'Get 3GB cloud storage + unlimited downloads',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }

  void _showPremiumRequiredDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Premium Feature',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Cloud Vault is a premium feature with 3GB of secure cloud storage.\n'
          'Upgrade to Pro to enable auto-sync and access your files from anywhere.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PremiumScreen()),
              );
            },
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }

  // ─── About section ───────────────────────────────────────────────────────

  Widget _aboutSection() {
    return _section(
      'ABOUT',
      Icons.info_outline_rounded,
      AppColors.textMuted,
      Column(children: [
        _tile(
          icon: Icons.privacy_tip_outlined,
          color: AppColors.primary,
          title: 'Privacy Policy',
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
        ),
        _div(),
        _tile(
          icon: Icons.gavel_rounded,
          color: AppColors.secondary,
          title: 'Terms of Service',
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const TermsScreen())),
        ),
        _div(),
        _tile(
          icon: Icons.verified_rounded,
          color: AppColors.success,
          title: 'App Version',
          sub: 'v1.0.0  ·  Free  ·  No Ads',
        ),
        _div(),
        _tile(
          icon: Icons.star_rounded,
          color: const Color(0xFFFFB300),
          title: 'Rate MediaNest',
          sub: 'Help others find us on Play Store',
          onTap: () {},
        ),
      ]),
    );
  }

  // ─── Reusable widgets ────────────────────────────────────────────────────

  Widget _section(String title, IconData icon, Color color, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Row(children: [
            // Colored left accent bar
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _div() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: AppColors.border,
      );

  Widget _permRow({
    required String title,
    required IconData icon,
    required Color color,
    required bool granted,
    required String sub,
    bool required = false,
    VoidCallback? onGrant,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color:
                  (granted ? AppColors.success : color).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(granted ? Icons.check_circle_outline : icon,
              color: granted ? AppColors.success : color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            if (required) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('Required',
                    style: TextStyle(
                        color: AppColors.error,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ]),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ])),
        if (!granted && onGrant != null)
          TextButton(
            onPressed: onGrant,
            style: TextButton.styleFrom(
                foregroundColor: color,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: const Text('Grant',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          )
        else if (granted)
          const Icon(Icons.check_rounded, color: AppColors.success, size: 18),
      ]),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required bool value,
    required void Function(bool) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          Text(sub,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ])),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withValues(alpha: 0.25),
          inactiveThumbColor: AppColors.textMuted,
          inactiveTrackColor: AppColors.border,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ]),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? sub,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                if (sub != null)
                  Text(sub,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
              ])),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 18),
        ]),
      ),
    );
  }
}
