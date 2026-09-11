// ui/screens/whatsapp_status_screen.dart
// UPDATED: Removed android_intent_plus, uses url_launcher instead
// ignore_for_file: use_build_context_synchronously, avoid_print, unused_import

import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/media_file.dart';
import '../../providers/media_provider.dart';
import '../../services/platform_services/whatsapp_service.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';

class WhatsAppStatusScreen extends StatefulWidget {
  const WhatsAppStatusScreen({Key? key}) : super(key: key);
  @override
  State<WhatsAppStatusScreen> createState() => _WhatsAppStatusScreenState();
}

class _WhatsAppStatusScreenState extends State<WhatsAppStatusScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  bool _isLoading = false;
  bool _showBusiness = false;
  final Set<String> _selectedIds = {};
  bool _selectionMode = false;

  bool _hasStatusFolderAccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    _checkAndLoad();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndLoad();
    }
  }

  Future<void> _checkAndLoad() async {
    final folderAccess = await WhatsAppService().hasStatusFolderAccess(
      isBusinessWhatsApp: _showBusiness,
    );
    if (!mounted) return;
    setState(() => _hasStatusFolderAccess = folderAccess);
    if (folderAccess) await _loadStatuses();
  }

  Future<void> _requestStatusFolderAccess() async {
    if (_isLoading) return;
    final proceed = await _showManualInstructions();
    if (proceed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      final requested = await WhatsAppService().requestStatusFolderAccess(
        isBusinessWhatsApp: _showBusiness,
      );
      if (requested) {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) setState(() => _isLoading = false);
        if (mounted) await _checkAndLoad();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool?> _showManualInstructions() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Find WhatsApp\'s status folder'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'A folder picker will open next. If it doesn\'t already land '
                'you inside the right folder, tap through this exact path:',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              _step('1', 'Android'),
              _step('2', 'media'),
              _step('3', _showBusiness ? 'com.whatsapp.w4b' : 'com.whatsapp'),
              _step('4', 'WhatsApp'),
              _step('5', 'Media  ← select this one, the folder itself'),
              const SizedBox(height: 8),
              const Text(
                'Then tap "Use this folder" or "Select" at the bottom of the '
                'picker. Don\'t create a new folder — pick the existing '
                '"Media" folder shown above.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.whatsapp.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.whatsapp.withValues(alpha: 0.4),
                ),
              ),
              child: Center(
                child: Text(
                  n,
                  style: const TextStyle(
                    color: AppColors.whatsapp,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Future<void> _loadStatuses() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final provider = Provider.of<MediaProvider>(context, listen: false);
      await provider.refreshWhatsAppStatuses(isBusiness: _showBusiness);
    } catch (e) {
      print('Error loading statuses: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(
              child: Consumer<MediaProvider>(
                builder: (_, provider, __) {
                  if (!_hasStatusFolderAccess) {
                    return _buildPermissionScreen();
                  }
                  if (provider.whatsappError != null) {
                    return _buildError(provider.whatsappError!);
                  }
                  if (_isLoading) return _buildLoading();
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGrid(provider.whatsappImages),
                      _buildGrid(provider.whatsappVideos),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectionMode ? _buildSelectionFab() : null,
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.whatsapp,
                      AppColors.whatsapp.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.whatsapp.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WhatsApp Status',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Consumer<MediaProvider>(
                      builder: (_, p, __) => Text(
                        '${p.whatsappImages.length + p.whatsappVideos.length} statuses available',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _showBusiness = !_showBusiness);
                  _loadStatuses();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _showBusiness
                        ? AppColors.whatsapp.withValues(alpha: 0.15)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _showBusiness
                          ? AppColors.whatsapp.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _showBusiness ? 'Business' : 'Personal',
                    style: TextStyle(
                      color: _showBusiness
                          ? AppColors.whatsapp
                          : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _checkAndLoad,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.whatsapp,
                AppColors.whatsapp.withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }

  // ─── Tab bar ─────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.whatsapp,
              AppColors.whatsapp.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: AppColors.whatsapp.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.all(4),
        tabs: [
          Consumer<MediaProvider>(
            builder: (_, p, __) => Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Images (${p.whatsappImages.length})'),
                ],
              ),
            ),
          ),
          Consumer<MediaProvider>(
            builder: (_, p, __) => Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Videos (${p.whatsappVideos.length})'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Grid ─────────────────────────────────────────────────────────────────

  Widget _buildGrid(List<MediaFile> items) {
    if (items.isEmpty) return _buildEmpty();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 6,
          mainAxisSpacing: 6,
          childAspectRatio: 0.85,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _gridItem(items, i),
      ),
    );
  }

  Widget _gridItem(List<MediaFile> items, int index) {
    final item = items[index];
    final isSelected = _selectedIds.contains(item.id);

    return GestureDetector(
      onTap: () {
        if (_selectionMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(item.id);
              if (_selectedIds.isEmpty) _selectionMode = false;
            } else {
              _selectedIds.add(item.id);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MediaViewerScreen(
                mediaFiles: items,
                initialIndex: index,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        setState(() {
          _selectionMode = true;
          _selectedIds.add(item.id);
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail
              item.isVideo
                  ? _VideoThumb(filePath: item.path)
                  : Image.file(
                      File(item.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.card,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),

              // Video badge
              if (item.isVideo)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                        SizedBox(width: 2),
                        Text(
                          'Video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Selection overlay
              if (_selectionMode)
                Positioned.fill(
                  child: Container(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : Colors.transparent,
                    child: isSelected
                        ? const Center(
                            child: Icon(
                              Icons.check_circle_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          )
                        : null,
                  ),
                ),

              // Download button
              if (!_selectionMode)
                Positioned(
                  bottom: 5,
                  right: 5,
                  child: GestureDetector(
                    onTap: item.isDownloaded ? null : () => _saveItem(item),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: item.isDownloaded
                            ? LinearGradient(
                                colors: [
                                  Colors.green.shade600,
                                  Colors.green.shade400,
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : LinearGradient(
                                colors: [
                                  AppColors.whatsapp,
                                  AppColors.whatsapp.withValues(alpha: 0.8),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (item.isDownloaded
                                    ? Colors.green
                                    : AppColors.whatsapp)
                                .withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        item.isDownloaded
                            ? Icons.check_rounded
                            : Icons.download_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty state ──────────────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.whatsapp.withValues(alpha: 0.15),
                    AppColors.whatsapp.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.whatsapp.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Icon(
                Icons.chat_bubble_rounded,
                color: AppColors.whatsapp.withValues(alpha: 0.6),
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No statuses found',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Open WhatsApp and view some statuses first,\nthen come back here and tap Refresh.',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            if (!_hasStatusFolderAccess) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WhatsApp folder access needed',
                            style: TextStyle(
                              color: AppColors.warning,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Choose the WhatsApp Media folder once so MediaNest can read hidden statuses safely.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _requestStatusFolderAccess,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Choose folder',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _checkAndLoad,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.whatsapp,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Permission screen ────────────────────────────────────────────────────

  Widget _buildPermissionScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.whatsapp.withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.whatsapp.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AppColors.whatsapp,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'See your viewed statuses here',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'View a WhatsApp status first, then return to MediaNest.\nGrant access once and this screen will refresh automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _requestStatusFolderAccess,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Grant one-time access'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.whatsapp,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isLoading ? null : _checkAndLoad,
                child: const Text('I already granted access · Refresh'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.refresh_rounded,
                  color: AppColors.error, size: 30),
            ),
            const SizedBox(height: 18),
            const Text(
              'Status scan stopped',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadStatuses,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry scan'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Loading ──────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.whatsapp.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: AppColors.whatsapp,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Loading statuses...',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ─── FAB ─────────────────────────────────────────────────────────────────

  Widget _buildSelectionFab() {
    return FloatingActionButton.extended(
      onPressed: _saveSelected,
      backgroundColor: AppColors.whatsapp,
      elevation: 4,
      icon: const Icon(Icons.download_rounded, color: Colors.white),
      label: Text(
        'Save ${_selectedIds.length} item${_selectedIds.length == 1 ? "" : "s"}',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────────

  Future<void> _saveItem(MediaFile item) async {
    if (item.isDownloaded) return;

    try {
      final provider = Provider.of<MediaProvider>(context, listen: false);
      final success = await provider.downloadMedia(item);
      if (mounted) {
        final failReason = provider.lastDownloadError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle_outline : Icons.error_outline,
                  color: success ? Colors.green.shade300 : Colors.red.shade300,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    success
                        ? '✅ Saved to gallery!'
                        : failReason != null
                            ? '❌ Save failed: $failReason'
                            : '❌ Save failed',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.textPrimary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      print('Save error: $e');
    }
  }

  Future<void> _saveSelected() async {
    final provider = Provider.of<MediaProvider>(context, listen: false);
    int saved = 0;
    for (final id in _selectedIds) {
      try {
        final item = provider.allMedia.firstWhere(
          (m) => m.id == id,
          orElse: () => provider.whatsappImages
              .followedBy(provider.whatsappVideos)
              .firstWhere((m) => m.id == id),
        );
        if (await provider.downloadMedia(item)) saved++;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _selectedIds.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Saved $saved items to gallery'),
          backgroundColor: AppColors.textPrimary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }
}

// ─── Video thumbnail widget ──────────────────────────────────────────────────

class _VideoThumb extends StatefulWidget {
  final String filePath;
  const _VideoThumb({required this.filePath});
  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  dynamic _thumbData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists() || await file.length() < 1024) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final videoPath = widget.filePath.startsWith('file://')
          ? widget.filePath
          : 'file://${widget.filePath}';
      final data = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400,
        quality: 75,
        timeMs: 500,
      );
      if (mounted) {
        setState(() {
          _thumbData = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white38,
            ),
          ),
        ),
      );
    }
    if (_thumbData == null) {
      return Container(
        color: Colors.black54,
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white38,
            size: 28,
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _thumbData,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: Colors.black54,
            child: const Icon(
              Icons.videocam_rounded,
              color: Colors.white38,
              size: 28,
            ),
          ),
        ),
        Center(
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }
}
