// ui/screens/home_screen.dart
// COMPLETE - Home Screen with Saved Edits

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/download_item.dart';
import '../../providers/download_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/cobalt_api_service.dart';
import '../themes/app_theme.dart';
import 'ai_content_coach.dart';
import 'browser_download_screen.dart';
import 'cloud_vault_screen.dart';
import 'creator_library_screen.dart';
import 'premium_screen.dart';
import 'private_vault_screen.dart';
import 'quick_editor_picker_screen.dart';
import 'repurpose_studio_screen.dart';
import 'saved_edits_screen.dart';
import 'smart_translator_screen.dart';
import 'whatsapp_status_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _ink = Color(0xFF101326);
  static const _muted = Color(0xFF73798F);
  static const _violet = Color(0xFF7357FF);
  static const _cyan = Color(0xFFDCD4FF);
  static const _lime = Color(0xFFE8E2FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _canvas = Color(0xFFF4F5FA);
  static const _nativeChannel =
      MethodChannel('com.yourapp.allsocialdownloader/native');

  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocus = FocusNode();
  bool _isProcessing = false;
  double _progress = 0.0;
  String _status = 'Ready when you are';
  String? _clipboardUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readClipboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<PremiumProvider>(context, listen: false)
            .refreshCreditBalance();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _readClipboard();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  Future<void> _readClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim() ?? '';
      if (!mounted || text.isEmpty || !CobaltApiService.isSupportedUrl(text)) {
        return;
      }
      setState(() => _clipboardUrl = text);
      _urlController.text = text;
    } catch (_) {}
  }

  Future<void> _download() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _message('Paste a link to download content.', error: true);
      return;
    }
    if (!CobaltApiService.isSupportedUrl(url)) {
      _message(
        'That link is not supported yet. Try TikTok, Instagram, Facebook, Twitter/X, Vimeo, or Reddit.',
        error: true,
      );
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.canDownload) {
      _showUpgradeSheet(premium);
      return;
    }

    _urlFocus.unfocus();
    setState(() {
      _isProcessing = true;
      _progress = 0;
      _status = 'Preparing your download...';
      _clipboardUrl = null;
    });

    final platform = CobaltApiService.detectPlatform(url);
    if (platform == 'facebook' ||
        platform == 'instagram' ||
        platform == 'linkedin') {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _status = 'Opening the secure downloader...';
        });
      }
      _open(BrowserDownloadScreen(url: url));
      return;
    }

    try {
      final downloads = Provider.of<DownloadProvider>(context, listen: false);
      await downloads.downloadFromUrl(
        url,
        preferHD: premium.isPremium,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value.clamp(0.0, 1.0).toDouble());
        },
        onStatus: (value) {
          if (!mounted) return;
          setState(() => _status = value);
        },
        onRecordDownload: premium.recordDownload,
      );

      if (!mounted) return;
      final item =
          downloads.downloads.isNotEmpty ? downloads.downloads.last : null;
      if (item?.status == DownloadStatus.completed) {
        setState(() {
          _progress = 1;
          _status = 'Downloaded into your library';
        });
        await Provider.of<MediaProvider>(context, listen: false)
            .refreshAllMedia();
        _message('Download completed and added to your library.');
        _urlController.clear();
      } else {
        final error = item?.errorMessage ?? '';
        if (error.contains('USE_BROWSER') || error.isEmpty) {
          _open(BrowserDownloadScreen(url: url));
        } else {
          _message(error, error: true);
        }
      }
    } catch (e) {
      if (mounted) _message('Capture failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _shareCurrentLink() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      _message('Paste a link first, then tap Share.', error: true);
      return;
    }
    try {
      await _nativeChannel.invokeMethod<void>('shareText', <String, dynamic>{
        'text': text,
        'title': 'Share with MediaNest',
      });
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      _message('Link copied. You can share it from your phone.');
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  void _openEditor() {
    _open(const QuickEditorPickerScreen());
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFB83A59) : _ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _showUpgradeSheet(PremiumProvider premium) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, color: _violet, size: 32),
              const SizedBox(height: 12),
              const Text(
                'Your daily capture limit is complete',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${premium.downloadsToday} of ${PremiumProvider.kFreeDailyLimit} free captures used today. Go unlimited with Pro.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _open(const PremiumScreen());
                  },
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Explore Pro'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _violet,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildCaptureDeck(),
                  const SizedBox(height: 18),
                  if (_isProcessing) ...[
                    _buildProgressCard(),
                    const SizedBox(height: 18),
                  ],
                  _buildSignalRow(),
                  const SizedBox(height: 24),
                  _buildSectionHeading(
                    'Your creator cockpit',
                    'Turn saved media into momentum',
                  ),
                  const SizedBox(height: 12),
                  _buildCommandGrid(),
                  const SizedBox(height: 24),
                  _buildWhatsAppCapture(),
                  const SizedBox(height: 24),
                  _buildActivitySection(),
                  const SizedBox(height: 24),
                  _buildCloudPulse(),
                  const SizedBox(height: 24),
                  _buildPlatformRail(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── BUILD HEADER WITH LOGO ───────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_violet, Color(0xFFAB65FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _violet.withValues(alpha: 0.24),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/branding/MediaNest_logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Image.asset(
                    'assets/icon/logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.cloud_rounded,
                        color: Colors.white,
                        size: 30,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MediaNest',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                Text(
                  'Creator command center',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Consumer<PremiumProvider>(
            builder: (_, premium, __) => GestureDetector(
              onTap: () => _open(const PremiumScreen()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                decoration: BoxDecoration(
                  color: premium.isPremium ? const Color(0xFFE8E2FF) : _ink,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      premium.isPremium
                          ? Icons.workspace_premium_rounded
                          : Icons.bolt_rounded,
                      size: 15,
                      color: premium.isPremium ? _violet : _lime,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      premium.isPremium ? 'PRO' : 'UPGRADE',
                      style: TextStyle(
                        color: premium.isPremium ? _violet : Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureDeck() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _violet.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _violet.withValues(alpha: 0.10),
            blurRadius: 24,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: _violet.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Text(
                  'CAPTURE MODE',
                  style: TextStyle(
                    color: _violet,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(Icons.wifi_tethering_rounded,
                  color: _violet, size: 18),
              const SizedBox(width: 5),
              const Text(
                'Ready',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Bring the internet\ninto your library.',
            style: TextStyle(
              color: _ink,
              fontSize: 28,
              height: 1.05,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.1,
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Download once. Organize it. Repurpose it everywhere.',
            style: TextStyle(color: _muted, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: _canvas,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _violet.withValues(alpha: 0.16)),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Icon(Icons.link_rounded, color: _violet, size: 19),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocus,
                    style: const TextStyle(color: _ink, fontSize: 13),
                    cursorColor: _violet,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Paste a link or share a post…',
                      hintStyle: TextStyle(color: _muted, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _download(),
                  ),
                ),
                if (_urlController.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _urlController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close_rounded,
                        color: _muted, size: 18),
                  ),
              ],
            ),
          ),
          if (_clipboardUrl != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _download,
              child: Row(
                children: [
                  const Icon(Icons.content_paste_rounded,
                      color: _violet, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Clipboard link detected · tap to capture',
                      style: TextStyle(
                          color: _violet.withValues(alpha: 0.9), fontSize: 11),
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded,
                      color: _violet, size: 15),
                ],
              ),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isProcessing ? null : _download,
                  icon: Icon(
                    _isProcessing
                        ? Icons.hourglass_top_rounded
                        : Icons.download_rounded,
                    size: 18,
                  ),
                  label:
                      Text(_isProcessing ? 'Downloading…' : 'Download content'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _violet,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _violet.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: _shareCurrentLink,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _violet.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _violet.withValues(alpha: 0.18)),
                  ),
                  child:
                      const Icon(Icons.share_rounded, color: _violet, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final value = _progress.clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _violet.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _violet.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.downloading_rounded,
                    color: _violet, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                    color: _violet, fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: value == 0 ? null : value,
              minHeight: 7,
              backgroundColor: const Color(0xFFE9EAF1),
              valueColor: const AlwaysStoppedAnimation<Color>(_violet),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'The file will appear in your library when it is ready.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalRow() {
    return Consumer3<DownloadProvider, PremiumProvider, MediaProvider>(
      builder: (_, downloads, premium, media, __) {
        final captured = downloads.downloads
            .where((item) => item.status == DownloadStatus.completed)
            .length;

        // Same logic as the translator screen's badge — premium shows real
        // USD-budget credits, free shows the monthly free-translation
        // allowance, since those are different things under the hood.
        final String creditsValue;
        if (premium.isPremium) {
          final credits = premium.remainingCredits;
          creditsValue = credits == null ? '…' : '$credits';
        } else {
          final remaining = premium.freeTranslationsRemaining;
          creditsValue = remaining == null ? '…' : '$remaining';
        }

        return Row(
          children: [
            Expanded(
                child: _signal(
                    '$captured', 'Captured', Icons.south_rounded, _violet)),
            const SizedBox(width: 9),
            Expanded(
                child: _signal('${media.allMedia.length}', 'In library',
                    Icons.grid_view_rounded, _cyan)),
            const SizedBox(width: 9),
            Expanded(
              child: _signal(
                premium.isPremium ? 'Pro' : '${premium.remainingDownloads}',
                premium.isPremium ? 'Plan' : 'Free left',
                Icons.bolt_rounded,
                _lime,
                dark: true,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: _signal(
                creditsValue,
                premium.isPremium ? 'AI credits' : 'Free AI left',
                Icons.auto_awesome_rounded,
                _violet,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _signal(String value, String label, IconData icon, Color color,
      {bool dark = false}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 13, 10, 12),
      decoration: BoxDecoration(
        color: dark ? _ink : _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: dark ? _ink : const Color(0xFFE8E9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: dark ? color : color, size: 17),
          const SizedBox(height: 9),
          Text(value,
              style: TextStyle(
                  color: dark ? Colors.white : _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  color: dark ? Colors.white60 : _muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(String title, String subtitle) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3)),
              const SizedBox(height: 3),
              Text(subtitle,
                  style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
        const Icon(Icons.more_horiz_rounded, color: _muted),
      ],
    );
  }

  Widget _buildCommandGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: _commandTile(
                    'Repurpose',
                    'Captions, tags & ideas',
                    Icons.auto_awesome_rounded,
                    _violet,
                    () => _open(const RepurposeStudioScreen()))),
            const SizedBox(width: 12),
            Expanded(
                child: _commandTile(
                    'Library',
                    'Search every asset',
                    Icons.dashboard_customize_rounded,
                    _cyan,
                    () => _open(const CreatorLibraryScreen()))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _commandTile(
                    'Translate',
                    'Speech, subtitles & tone',
                    Icons.translate_rounded,
                    const Color(0xFF9B7BFF),
                    () => _open(const SmartTranslatorScreen()))),
            const SizedBox(width: 12),
            Expanded(
                child: _commandTile(
                    'Quick Edit',
                    'Edit downloaded or device videos',
                    Icons.tune_rounded,
                    const Color(0xFF8E75E8),
                    _openEditor)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _commandTile(
                    'Private Vault',
                    'Protect what matters',
                    Icons.shield_rounded,
                    const Color(0xFF6B4CC4),
                    () => _open(const PrivateVaultScreen()))),
            const SizedBox(width: 12),
            Expanded(
                child: _commandTile(
                    'Creator Coach',
                    'Goals, streaks & strategy',
                    Icons.track_changes_rounded,
                    const Color(0xFFB39AFF),
                    () => _open(const AIContentCoach()))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _commandTile(
                    'Saved Edits',
                    'View your edited videos',
                    Icons.edit_rounded,
                    const Color(0xFF22C55E),
                    () => _open(const SavedEditsScreen()))),
            const SizedBox(width: 12),
            Expanded(
                child: _commandTile(
                    'Cloud Vault',
                    'Sync & backup',
                    Icons.cloud_rounded,
                    const Color(0xFF3B82F6),
                    () => _open(const CloudVaultScreen()))),
          ],
        ),
      ],
    );
  }

  Widget _commandTile(String title, String subtitle, IconData icon, Color color,
      VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w800, fontSize: 13)),
            const SizedBox(height: 4),
            Text(subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: _muted, fontSize: 10, height: 1.25)),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Open',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Icon(Icons.arrow_outward_rounded, color: color, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppCapture() {
    return InkWell(
      onTap: () => _open(const WhatsAppStatusScreen()),
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_violet, Color(0xFF4B2EA8)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_rounded,
                  color: Colors.white, size: 23),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status radar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text('Catch WhatsApp moments before they disappear.',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection() {
    return Consumer<DownloadProvider>(
      builder: (_, provider, __) {
        final items = provider.downloads.reversed.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeading(
                'Live workspace', 'Your latest captures and background jobs'),
            const SizedBox(height: 12),
            if (items.isEmpty)
              _emptyActivity()
            else
              Container(
                decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE7E8F0))),
                child: Column(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _activityItem(items[i]),
                    if (i != items.length - 1)
                      const Divider(height: 1, indent: 60, endIndent: 16)
                  ]
                ]),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyActivity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7E8F0))),
      child: const Row(
        children: [
          Icon(Icons.inbox_rounded, color: _violet, size: 24),
          SizedBox(width: 12),
          Expanded(
              child: Text(
                  'Your workspace is ready. Capture a link and your activity will appear here.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.35))),
        ],
      ),
    );
  }

  Widget _activityItem(DownloadItem item) {
    final active = item.status == DownloadStatus.downloading;
    final failed = item.status == DownloadStatus.failed;
    final color = failed
        ? const Color(0xFFB83A59)
        : active
            ? _violet
            : _cyan;
    final label = active
        ? 'Working'
        : failed
            ? 'Needs attention'
            : 'Captured';
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(
                  active
                      ? Icons.downloading_rounded
                      : failed
                          ? Icons.error_outline_rounded
                          : Icons.check_rounded,
                  color: color,
                  size: 19)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.fileName.isEmpty ? 'Untitled capture' : item.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    '$label · ${item.sourceApp.isEmpty ? 'web source' : item.sourceApp}',
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (active)
            SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                    value: item.progress > 0 ? item.progress : null,
                    strokeWidth: 3,
                    color: _violet,
                    backgroundColor: const Color(0xFFE9EAF1)))
          else
            const Icon(Icons.chevron_right_rounded, color: _muted),
        ],
      ),
    );
  }

  Widget _buildCloudPulse() {
    return InkWell(
      onTap: () => _open(const CloudVaultScreen()),
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
            color: const Color(0xFFECE9FF),
            borderRadius: BorderRadius.circular(22)),
        child: Row(
          children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: _violet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.cloud_done_rounded,
                    color: _violet, size: 22)),
            const SizedBox(width: 12),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Cloud Vault',
                      style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 14)),
                  SizedBox(height: 4),
                  Text('Back up your creative memory and keep it in sync.',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ])),
            const Icon(Icons.arrow_forward_rounded, color: _violet, size: 19),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformRail() {
    const platforms = [
      ('TikTok', Icons.music_note_rounded),
      ('Instagram', Icons.camera_alt_rounded),
      ('Facebook', Icons.facebook),
      ('Twitter/X', Icons.alternate_email_rounded),
      ('Vimeo', Icons.play_circle_fill_rounded),
      ('+ 15 more', Icons.add_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeading(
            'Capture from everywhere', 'One library for every source'),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: platforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final item = platforms[index];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE7E8F0))),
                child: Row(children: [
                  Icon(item.$2, size: 16, color: _violet),
                  const SizedBox(width: 7),
                  Text(item.$1,
                      style: const TextStyle(
                          color: _ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700))
                ]),
              );
            },
          ),
        ),
      ],
    );
  }
}
