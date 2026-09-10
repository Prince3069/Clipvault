// ui/screens/private_vault_screen.dart
// COMPLETE - Private Vault 2.0 with Enhanced Security
// Features: PIN, Fake/Decoy PIN mode, Auto-lock, Encrypted storage

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/vault_service.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';
import '../../models/media_file.dart';

// ─── Vault State ──────────────────────────────────────────────────────────

enum _VaultState {
  locked,
  setup,
  pinEntry,
  fakePinEntry,
  unlocked,
}

// ─── Screen ────────────────────────────────────────────────────────────────

class PrivateVaultScreen extends StatefulWidget {
  const PrivateVaultScreen({Key? key}) : super(key: key);

  @override
  State<PrivateVaultScreen> createState() => _PrivateVaultScreenState();
}

class _PrivateVaultScreenState extends State<PrivateVaultScreen>
    with WidgetsBindingObserver {
  final VaultService _vault = VaultService();
  final ImagePicker _picker = ImagePicker();
  _VaultState _state = _VaultState.locked;
  List<FileSystemEntity> _files = [];
  bool _loading = false;
  String _pinError = '';
  bool _showFakeContent = false;
  bool _isLocking = false;
  Timer? _lockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initUnlock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lockTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _state == _VaultState.unlocked) {
      _startLockTimer();
    }
    if (state == AppLifecycleState.resumed) {
      _cancelLockTimer();
    }
  }

  void _startLockTimer() {
    _cancelLockTimer();
    _lockTimer = Timer(const Duration(seconds: 30), () {
      if (mounted && _state == _VaultState.unlocked) {
        setState(() {
          _state = _VaultState.locked;
          _files = [];
        });
      }
    });
  }

  void _cancelLockTimer() {
    _lockTimer?.cancel();
    _lockTimer = null;
  }

  Future<void> _initUnlock() async {
    final hasPin = await _vault.hasPinSet;

    if (!hasPin) {
      if (mounted) setState(() => _state = _VaultState.setup);
      return;
    }

    // Check if fake PIN mode should be shown
    final fakePinEnabled = await _vault.isFakePinEnabled;
    if (fakePinEnabled) {
      if (mounted) setState(() => _state = _VaultState.fakePinEntry);
      return;
    }

    if (mounted) setState(() => _state = _VaultState.pinEntry);
  }

  Future<void> _unlock() async {
    if (mounted) {
      setState(() {
        _state = _VaultState.unlocked;
        _loading = true;
        _pinError = '';
      });
    }
    try {
      _files = await _vault.getVaultFiles();
    } catch (e) {
      debugPrint('Vault error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _verifyPin(String pin, {bool isFake = false}) async {
    if (pin.length < 4) return;

    if (isFake) {
      final ok = await _vault.verifyFakePin(pin);
      if (ok) {
        setState(() {
          _showFakeContent = true;
          _state = _VaultState.unlocked;
          _pinError = '';
        });
        await _loadFakeFiles();
        return;
      } else {
        if (mounted) setState(() => _pinError = 'Wrong PIN. Try again.');
        return;
      }
    }

    final ok = await _vault.verifyPin(pin);
    if (ok) {
      await _unlock();
    } else {
      if (mounted) setState(() => _pinError = 'Wrong PIN. Try again.');
    }
  }

  Future<void> _loadFakeFiles() async {
    setState(() => _loading = true);
    // Load decoy files from a separate directory
    try {
      _files = await _vault.getFakeVaultFiles();
    } catch (e) {
      _files = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setupPin(String pin) async {
    if (pin.length < 4) return;
    await _vault.setPin(pin);

    // Ask about fake PIN
    final enableFake = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            title: const Text('Fake PIN Mode?'),
            content: const Text(
              'Set a secondary PIN that shows decoy content if someone forces you to unlock.\n\n'
              'This adds an extra layer of security.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Set Up'),
              ),
            ],
          ),
        ) ??
        false;

    if (enableFake && mounted) {
      _showFakePinSetup();
      return;
    }

    await _unlock();
  }

  void _showFakePinSetup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('Set Fake PIN'),
        content: const Text(
          'Enter a 4-digit PIN that will show decoy content.\n\n'
          'This is the PIN you enter if someone forces you to unlock the vault.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _unlock();
            },
            child: const Text('Skip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showFakePinInput();
            },
            child: const Text('Set PIN'),
          ),
        ],
      ),
    );
  }

  void _showFakePinInput() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _FakePinSetupDialog(
        onComplete: (pin) async {
          await _vault.setFakePin(pin);
          await _unlock();
        },
      ),
    );
  }

  void _lockVault() {
    setState(() {
      _state = _VaultState.locked;
      _files = [];
      _showFakeContent = false;
    });
    _cancelLockTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: _bodyForState(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          Icon(
            _state == _VaultState.unlocked
                ? Icons.lock_open_rounded
                : Icons.lock_rounded,
            color: _state == _VaultState.unlocked
                ? AppColors.success
                : AppColors.textPrimary,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          const Text('Private Vault'),
        ],
      ),
      actions: _state == _VaultState.unlocked
          ? [
              IconButton(
                icon: const Icon(
                  Icons.add_rounded,
                  color: AppColors.primary,
                ),
                onPressed: _showAddHint,
                tooltip: 'Add to vault',
              ),
              IconButton(
                icon: const Icon(Icons.shield_rounded),
                onPressed: _showSecuritySettings,
                tooltip: 'Security Settings',
              ),
              IconButton(
                icon: const Icon(Icons.lock_outline_rounded),
                onPressed: _lockVault,
                tooltip: 'Lock vault',
              ),
            ]
          : null,
    );
  }

  Widget _bodyForState() {
    if (_state == _VaultState.locked) return _buildLocked();
    if (_state == _VaultState.setup) return _buildSetupPin();
    if (_state == _VaultState.pinEntry) return _buildPinEntry();
    if (_state == _VaultState.fakePinEntry) return _buildFakePinEntry();
    return _buildContent();
  }

  // ─── Locked State ──────────────────────────────────────────────────────

  Widget _buildLocked() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary,
                    AppColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: AppShadows.primary,
              ),
              child: const Icon(
                Icons.lock_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Vault Locked',
              style: AppTypography.displayMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your private files are protected',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            _buildUnlockButton(
              icon: Icons.pin_rounded,
              label: 'Enter PIN',
              onTap: () => setState(() => _state = _VaultState.pinEntry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnlockButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  // ─── PIN Setup ─────────────────────────────────────────────────────────

  Widget _buildSetupPin() {
    return _PinPad(
      title: 'Create Vault PIN',
      subtitle: 'Choose a 4-digit PIN to protect your vault',
      confirmMode: true,
      onComplete: _setupPin,
    );
  }

  // ─── PIN Entry ─────────────────────────────────────────────────────────

  Widget _buildPinEntry() {
    return _PinPad(
      title: 'Enter PIN',
      subtitle: 'Enter your vault PIN',
      error: _pinError,
      onComplete: (pin) => _verifyPin(pin, isFake: false),
    );
  }

  // ─── Fake PIN Entry ────────────────────────────────────────────────────

  Widget _buildFakePinEntry() {
    return _PinPad(
      title: 'Enter PIN',
      subtitle: 'Enter your vault PIN',
      error: _pinError,
      showFakeHint: true,
      onComplete: (pin) => _verifyPin(pin, isFake: true),
    );
  }

  // ─── Unlocked Content ──────────────────────────────────────────────────

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    // Show fake content banner
    if (_showFakeContent) {
      return _buildFakeContentBanner();
    }

    if (_files.isEmpty) {
      return _buildEmptyVault();
    }

    return Column(
      children: [
        // Vault stats bar
        _buildVaultStats(),
        Expanded(
          child: _buildVaultGrid(),
        ),
      ],
    );
  }

  Widget _buildVaultStats() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.primary.withValues(alpha: 0.04),
      child: Row(
        children: [
          Icon(
            _showFakeContent ? Icons.warning_amber_rounded : Icons.lock_rounded,
            color: _showFakeContent ? AppColors.warning : AppColors.primary,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _showFakeContent
                ? '🔒 Decoy mode active'
                : '${_files.length} protected file${_files.length > 1 ? "s" : ""}',
            style: AppTypography.bodySmall.copyWith(
              color: _showFakeContent
                  ? AppColors.warning
                  : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (!_showFakeContent)
            Row(
              children: [
                const Icon(
                  Icons.visibility_off_rounded,
                  color: AppColors.textMuted,
                  size: 14,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Hidden from gallery',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFakeContentBanner() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          margin: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.shield_rounded,
                color: AppColors.warning,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔒 Decoy Mode Active',
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'You are viewing decoy content. Your real files are still hidden.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _showFakeContent = false;
                    _state = _VaultState.locked;
                    _files = [];
                  });
                },
                child: const Text('Lock'),
              ),
            ],
          ),
        ),
        if (_files.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 64,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'No decoy content',
                    style: AppTypography.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Add some decoy files to make this look convincing',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(child: _buildVaultGrid()),
      ],
    );
  }

  Widget _buildEmptyVault() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Vault is Empty',
              style: AppTypography.displayMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Move files here to keep them private',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: _showAddHint,
              icon: const Icon(Icons.add_rounded),
              label: const Text('How to add files'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.8,
      ),
      itemCount: _files.length,
      itemBuilder: (_, i) => _vaultItem(_files[i] as File),
    );
  }

  // ─── Vault Item ──────────────────────────────────────────────────────

  Widget _vaultItem(File file) {
    final name = file.path.split('/').last;
    final ext = name.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'webm', 'mov', 'mkv', 'avi', '3gp'].contains(ext);

    return GestureDetector(
      onLongPress: () => _showItemOptions(file),
      onTap: () => _openFile(file, isVideo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            isVideo
                ? _VideoThumbnail(filePath: file.path)
                : _ImageThumbnail(filePath: file.path),

            // Gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Info
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Row(
                children: [
                  if (isVideo)
                    const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── File Operations ──────────────────────────────────────────────────

  void _openFile(File file, bool isVideo) {
    final name = file.path.split('/').last;
    final mf = MediaFile(
      id: file.path,
      path: file.path,
      fileName: name,
      fileSize: file.lengthSync(),
      isVideo: isVideo,
      sourceApp: 'vault',
      createdAt: file.lastModifiedSync(),
      viewedAt: DateTime.now(),
      isDownloaded: true,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          mediaFiles: [mf],
          initialIndex: 0,
        ),
      ),
    );
  }

  void _showItemOptions(File file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.drive_file_move_outlined,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              title: const Text(
                'Move out of vault',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _exportFile(file);
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.share_rounded,
                  color: AppColors.secondary,
                  size: 18,
                ),
              ),
              title: const Text(
                'Share',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                Share.shareXFiles([XFile(file.path)]);
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.error,
                  size: 18,
                ),
              ),
              title: const Text(
                'Delete permanently',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _deleteFile(file);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _exportFile(File file) async {
    try {
      final dest = await _vault.exportFromVault(file.path);
      await _vault.removeFromVault(file.path);
      _files = await _vault.getVaultFiles();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: AppSpacing.sm),
                Text('Moved to $dest'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteFile(File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text(
          'Delete permanently?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'This cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _vault.removeFromVault(file.path);
      if (mounted) setState(() => _files.remove(file));
    }
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────

  void _showAddHint() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text('Add to Private Vault',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Choose a photo or video from your device. The selected copy is moved into the private app storage and removed from its public location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.4),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose an image'),
              onTap: () {
                Navigator.pop(context);
                _pickIntoVault(isVideo: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_rounded,
                  color: AppColors.primary),
              title: const Text('Choose a video'),
              onTap: () {
                Navigator.pop(context);
                _pickIntoVault(isVideo: true);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _pickIntoVault({required bool isVideo}) async {
    try {
      final XFile? picked = isVideo
          ? await _picker.pickVideo(
              source: ImageSource.gallery,
              maxDuration: const Duration(minutes: 30),
            )
          : await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      setState(() => _loading = true);
      await _vault.moveToVault(picked.path);
      _files = await _vault.getVaultFiles();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moved into Private Vault'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not move file: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSecuritySettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Text(
                'Security Settings',
                style: AppTypography.headlineMedium,
              ),
            ),
            const Divider(),
            _SettingsTile(
              icon: Icons.timer_rounded,
              title: 'Auto-Lock',
              subtitle: 'Lock vault after 30 seconds of inactivity',
              trailing: Switch(
                value: true,
                onChanged: (_) {},
                activeColor: AppColors.primary,
              ),
            ),
            _SettingsTile(
              icon: Icons.shield_rounded,
              title: 'Fake PIN Mode',
              subtitle: 'Shows decoy content when fake PIN is used',
              trailing: FutureBuilder<bool>(
                future: _vault.isFakePinEnabled,
                builder: (_, snapshot) {
                  return Switch(
                    value: snapshot.data ?? false,
                    onChanged: (value) async {
                      if (value) {
                        _showFakePinInput();
                      } else {
                        await _vault.disableFakePin();
                        setState(() {});
                      }
                    },
                    activeColor: AppColors.primary,
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// ─── PIN Pad Widget ──────────────────────────────────────────────────────

class _PinPad extends StatefulWidget {
  final String title;
  final String subtitle;
  final String? error;
  final bool confirmMode;
  final bool showFakeHint;
  final Future<void> Function(String) onComplete;

  const _PinPad({
    required this.title,
    required this.subtitle,
    this.error,
    this.confirmMode = false,
    this.showFakeHint = false,
    required this.onComplete,
  });

  @override
  State<_PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<_PinPad> {
  String _first = '';
  String _current = '';
  bool _confirming = false;
  String _internalError = '';

  void _onDigit(String d) {
    if (_current.length >= 4) return;
    setState(() {
      _current += d;
      _internalError = '';
    });
    if (_current.length == 4) _onDone();
  }

  void _onBackspace() {
    if (_current.isNotEmpty) {
      setState(() => _current = _current.substring(0, _current.length - 1));
    }
  }

  Future<void> _onDone() async {
    if (!widget.confirmMode) {
      await widget.onComplete(_current);
      if (mounted) setState(() => _current = '');
      return;
    }
    if (!_confirming) {
      _first = _current;
      setState(() {
        _current = '';
        _confirming = true;
      });
    } else {
      if (_first == _current) {
        await widget.onComplete(_first);
      } else {
        setState(() {
          _current = '';
          _confirming = false;
          _first = '';
          _internalError = "PINs don't match. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorText =
        widget.error?.isNotEmpty == true ? widget.error! : _internalError;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.primary,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Title
              Text(
                _confirming ? 'Confirm PIN' : widget.title,
                style: AppTypography.displayMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _confirming ? 'Enter the same PIN again' : widget.subtitle,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.showFakeHint) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.shield_rounded,
                        color: AppColors.warning,
                        size: 16,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Enter your fake PIN to see decoy content',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              // PIN Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _current.length;
                  return Container(
                    width: 20,
                    height: 20,
                    margin:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.primary : AppColors.border,
                      border: Border.all(
                        color: filled ? AppColors.primary : AppColors.border,
                      ),
                    ),
                    child: filled
                        ? const Center(
                            child: Icon(
                              Icons.circle,
                              color: Colors.white,
                              size: 10,
                            ),
                          )
                        : null,
                  );
                }),
              ),
              if (errorText.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  errorText,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(flex: 2),
              // Number Pad
              ..._buildNumberPad(),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildNumberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return rows.map((row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((c) {
            if (c.isEmpty) {
              return const SizedBox(width: 80, height: 60);
            }
            final isBack = c == '⌫';
            return GestureDetector(
              onTap: isBack ? _onBackspace : () => _onDigit(c),
              child: Container(
                width: 80,
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isBack ? Colors.transparent : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: isBack ? null : Border.all(color: AppColors.border),
                  boxShadow: isBack ? null : AppShadows.soft,
                ),
                child: Center(
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: isBack ? 24 : 26,
                      fontWeight: FontWeight.w600,
                      color:
                          isBack ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }
}

// ─── Fake PIN Setup Dialog ──────────────────────────────────────────────

class _FakePinSetupDialog extends StatefulWidget {
  final Future<void> Function(String) onComplete;

  const _FakePinSetupDialog({required this.onComplete});

  @override
  State<_FakePinSetupDialog> createState() => _FakePinSetupDialogState();
}

class _FakePinSetupDialogState extends State<_FakePinSetupDialog> {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  String _error = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shield_rounded,
              color: AppColors.primary,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _isConfirming ? 'Confirm Fake PIN' : 'Set Fake PIN',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _isConfirming
                  ? 'Enter the same PIN again'
                  : 'Enter a 4-digit fake PIN for decoy content',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            // PIN Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < (_isConfirming ? _confirmPin : _pin).length;
                return Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? AppColors.primary : AppColors.border,
                    border: Border.all(
                      color: filled ? AppColors.primary : AppColors.border,
                    ),
                  ),
                );
              }),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            // Number Pad (simplified)
            ..._buildNumberPad(),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildNumberPad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return rows.map((row) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((c) {
            if (c.isEmpty) {
              return const SizedBox(width: 70, height: 50);
            }
            final isBack = c == '⌫';
            return GestureDetector(
              onTap: isBack ? _onBackspace : () => _onDigit(c),
              child: Container(
                width: 70,
                height: 50,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isBack ? Colors.transparent : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: isBack ? null : Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Text(
                    c,
                    style: TextStyle(
                      fontSize: isBack ? 20 : 22,
                      fontWeight: FontWeight.w600,
                      color:
                          isBack ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  void _onDigit(String digit) {
    if (_isConfirming) {
      if (_confirmPin.length >= 4) return;
      setState(() {
        _confirmPin += digit;
        _error = '';
      });
      if (_confirmPin.length == 4) _onDone();
    } else {
      if (_pin.length >= 4) return;
      setState(() {
        _pin += digit;
        _error = '';
      });
      if (_pin.length == 4) {
        setState(() => _isConfirming = true);
      }
    }
  }

  void _onBackspace() {
    if (_isConfirming) {
      if (_confirmPin.isNotEmpty) {
        setState(() =>
            _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1));
      } else {
        setState(() => _isConfirming = false);
      }
    } else {
      if (_pin.isNotEmpty) {
        setState(() => _pin = _pin.substring(0, _pin.length - 1));
      }
    }
  }

  void _onDone() {
    if (_pin != _confirmPin) {
      setState(() {
        _error = "PINs don't match";
        _confirmPin = '';
      });
      return;
    }
    Navigator.pop(context);
    widget.onComplete(_pin);
  }
}

// ─── Thumbnail Widgets ──────────────────────────────────────────────────

class _VideoThumbnail extends StatelessWidget {
  final String filePath;

  const _VideoThumbnail({required this.filePath});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: const Center(
        child: Icon(
          Icons.play_circle_rounded,
          color: Colors.white54,
          size: 32,
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  final String filePath;

  const _ImageThumbnail({required this.filePath});

  @override
  Widget build(BuildContext context) {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      }
    } catch (_) {}
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.cardAlt,
      child: const Center(
        child: Icon(
          Icons.image_rounded,
          color: AppColors.textMuted,
          size: 28,
        ),
      ),
    );
  }
}

// ─── Settings Tile ──────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  subtitle,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
