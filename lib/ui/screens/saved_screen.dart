// ui/screens/saved_screen.dart
// ADDED: Cloud Vault button + Auto-sync toggle in header
// ignore_for_file: use_build_context_synchronously, unused_element_parameter

import 'dart:io';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/download_item.dart';
import '../../models/media_file.dart';
import '../../providers/download_provider.dart';
import '../../providers/media_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/premium_provider.dart';
import '../../services/vault_service.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';
import 'cloud_vault_screen.dart' hide XFile;
import 'premium_screen.dart';

// ─── Folder model ─────────────────────────────────────────────────────────────

class _SavedFolder {
  final String name;
  final String platform;
  final IconData icon;
  final Color color;
  int count;
  int bytes;
  String? thumbPath;
  bool thumbIsVideo;

  _SavedFolder({
    required this.name,
    required this.platform,
    required this.icon,
    required this.color,
    this.count = 0,
    this.bytes = 0,
    this.thumbPath,
    this.thumbIsVideo = false,
  });
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class SavedScreen extends StatefulWidget {
  const SavedScreen({Key? key}) : super(key: key);

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final VaultService _vault = VaultService();
  String? _openFolder;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  final List<_SavedFolder> _folders = [
    _SavedFolder(
        name: 'TikTok',
        platform: 'tiktok',
        icon: Icons.music_note_rounded,
        color: AppColors.tiktok),
    _SavedFolder(
        name: 'Instagram',
        platform: 'instagram',
        icon: Icons.camera_alt_rounded,
        color: AppColors.instagram),
    _SavedFolder(
        name: 'Vimeo',
        platform: 'vimeo',
        icon: Icons.play_circle_rounded,
        color: AppColors.secondary),
    _SavedFolder(
        name: 'Facebook',
        platform: 'facebook',
        icon: Icons.facebook,
        color: AppColors.facebook),
    _SavedFolder(
        name: 'Twitter',
        platform: 'twitter',
        icon: Icons.alternate_email,
        color: AppColors.twitter),
    _SavedFolder(
        name: 'WhatsApp',
        platform: 'whatsapp',
        icon: Icons.chat_bubble_rounded,
        color: AppColors.whatsapp),
    _SavedFolder(
        name: 'Others',
        platform: 'unknown',
        icon: Icons.folder_rounded,
        color: AppColors.primary),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MediaProvider>(context, listen: false).refreshAllMedia();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _computeFolderStats(List<MediaFile> allMedia, List<DownloadItem> allDl) {
    for (final f in _folders) {
      f.count = 0;
      f.bytes = 0;
      f.thumbPath = null;
      f.thumbIsVideo = false;
    }

    final thumbDates = <String, DateTime>{};

    for (final item in allDl) {
      final f = _folderFor(item.sourceApp);
      if (item.status == DownloadStatus.completed &&
          item.localPath.isNotEmpty) {
        f.count++;
        try {
          f.bytes += File(item.localPath).lengthSync();
        } catch (_) {}
        final existing = thumbDates[f.platform];
        if (existing == null || item.dateAdded.isAfter(existing)) {
          thumbDates[f.platform] = item.dateAdded;
          f.thumbPath = item.localPath;
          final ext = item.fileName.toLowerCase();
          f.thumbIsVideo = ext.endsWith('.mp4') ||
              ext.endsWith('.webm') ||
              ext.endsWith('.mov') ||
              ext.endsWith('.mkv');
        }
      }
    }

    for (final item in allMedia) {
      final f = _folderFor(item.sourceApp);
      if (item.isDownloaded) {
        f.count++;
        f.bytes += item.fileSize;
        final existing = thumbDates[f.platform];
        if (existing == null || item.createdAt.isAfter(existing)) {
          thumbDates[f.platform] = item.createdAt;
          f.thumbPath = item.path;
          f.thumbIsVideo = item.isVideo;
        }
      }
    }
  }

  /// Resolve display names and provider-specific labels to one folder key.
  String _canonicalPlatform(String value) {
    final normalized = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normalized.contains('whatsapp')) return 'whatsapp';
    if (normalized.contains('instagram')) return 'instagram';
    if (normalized.contains('tiktok') || normalized.contains('musically')) return 'tiktok';
    if (normalized.contains('facebook')) return 'facebook';
    if (normalized.contains('twitter') || normalized == 'x') return 'twitter';
    if (normalized.contains('vimeo')) return 'vimeo';
    return 'unknown';
  }

  _SavedFolder _folderFor(String platform) {
    final key = _canonicalPlatform(platform);
    return _folders.firstWhere(
      (f) => f.platform == key,
      orElse: () => _folders.last,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Consumer2<DownloadProvider, MediaProvider>(
          builder: (_, dlProvider, mediaProvider, __) {
            _computeFolderStats(mediaProvider.allMedia, dlProvider.downloads);

            if (_openFolder != null) {
              return _buildFolderContent(
                  dlProvider, mediaProvider, _openFolder!);
            }
            return _buildFolderGrid(dlProvider, mediaProvider);
          },
        ),
      ),
    );
  }

  // ─── Folder grid (main screen) ────────────────────────────────────────────

  Widget _buildFolderGrid(DownloadProvider dlProvider, MediaProvider media) {
    final totalFiles = _folders.fold<int>(0, (s, f) => s + f.count);
    final totalBytes = _folders.fold<int>(0, (s, f) => s + f.bytes);

    return Column(children: [
      _buildHeader(totalFiles, totalBytes),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            padding: const EdgeInsets.only(top: 16, bottom: 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.88,
            ),
            itemCount: _folders.length,
            itemBuilder: (_, i) => _buildFolderCard(_folders[i]),
          ),
        ),
      ),
    ]);
  }

  Widget _buildHeader(int totalFiles, int totalBytes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(children: [
        Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Saved',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5)),
              Text(
                '$totalFiles files · ${_formatBytes(totalBytes)}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ]),
          ),
          // ── Cloud Vault Button (NEW) ──────────────────────────────────
          Consumer<PremiumProvider>(
            builder: (_, premium, __) {
              return GestureDetector(
                onTap: () {
                  if (!premium.isPremium) {
                    _showPremiumRequiredDialog();
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CloudVaultScreen(),
                    ),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: premium.isPremium
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.border,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: premium.isPremium
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        premium.isPremium
                            ? Icons.cloud_rounded
                            : Icons.cloud_off_rounded,
                        color: premium.isPremium
                            ? AppColors.primary
                            : AppColors.textMuted,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        premium.isPremium ? 'Cloud Vault Pro' : 'Cloud Pro',
                        style: TextStyle(
                          color: premium.isPremium
                              ? AppColors.primary
                              : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          // ── Auto-sync Toggle (NEW) ──────────────────────────────────────
          Consumer<SettingsProvider>(
            builder: (_, settings, __) {
              return Consumer<PremiumProvider>(
                builder: (__, premium, ___) {
                  final bool enabled =
                      settings.autoSyncToCloud && premium.isPremium;
                  return GestureDetector(
                    onTap: () {
                      if (!premium.isPremium) {
                        _showPremiumRequiredDialog();
                        return;
                      }
                      settings.setAutoSyncToCloud(!settings.autoSyncToCloud);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: enabled
                              ? AppColors.success.withValues(alpha: 0.3)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            enabled
                                ? Icons.cloud_sync_rounded
                                : Icons.cloud_sync_rounded,
                            color: enabled
                                ? AppColors.success
                                : AppColors.textMuted,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            enabled ? 'Auto-sync ON' : 'Auto-sync OFF',
                            style: TextStyle(
                              color: enabled
                                  ? AppColors.success
                                  : AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ]),
        const SizedBox(height: 12),
        Consumer<DownloadProvider>(builder: (_, p, __) {
          final active = p.activeDownloads.length;
          if (active == 0) return const SizedBox.shrink();
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Text(
                '$active download${active > 1 ? "s" : ""} in progress...',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ]),
          );
        }),
      ]),
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
          'Upgrade to Pro to access your files from anywhere.',
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

  // ─── Folder card with thumbnail preview ──────────────────────────────────

  Widget _buildFolderCard(_SavedFolder folder) {
    final active = folder.count > 0;
    return GestureDetector(
      onTap:
          active ? () => setState(() => _openFolder = folder.platform) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active
                  ? folder.color.withValues(alpha: 0.4)
                  : const Color(0xFFEEEEF5),
              width: active ? 1.5 : 1.0,
            ),
            boxShadow: [
              if (active)
                BoxShadow(
                    color: folder.color.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Thumbnail area ──
              Expanded(
                flex: 62,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (active && folder.thumbPath != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14)),
                        child: folder.thumbIsVideo
                            ? _VideoThumb(
                                filePath: folder.thumbPath!, fit: BoxFit.cover)
                            : Image.file(
                                File(folder.thumbPath!),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _folderPlaceholder(folder),
                              ),
                      )
                    else
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(14),
                            topRight: Radius.circular(14)),
                        child: _folderPlaceholder(folder),
                      ),
                    if (active && folder.thumbPath != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.55),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    // Cloud upload icon (top-right)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.cloud_upload_outlined,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Info strip ──
              Expanded(
                flex: 38,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: active
                              ? folder.color.withValues(alpha: 0.15)
                              : const Color(0xFFF5F5FA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(folder.icon,
                            color: active ? folder.color : AppColors.textMuted,
                            size: 15),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(folder.name,
                                style: TextStyle(
                                    color: active
                                        ? AppColors.textPrimary
                                        : AppColors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(
                              active
                                  ? '${folder.count} file${folder.count > 1 ? "s" : ""} · ${_formatBytes(folder.bytes)}'
                                  : 'Empty',
                              style: TextStyle(
                                  color: active
                                      ? AppColors.textSecondary
                                      : AppColors.textMuted,
                                  fontSize: 10,
                                  fontWeight: active
                                      ? FontWeight.w500
                                      : FontWeight.w400),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _folderPlaceholder(_SavedFolder folder) {
    return Container(
      color: folder.color.withValues(alpha: 0.06),
      child: Center(
        child: Icon(folder.icon,
            color: folder.color.withValues(alpha: 0.4), size: 38),
      ),
    );
  }

  // ─── Folder content: 2-column grid ────────────────────────────────────────

  Widget _buildFolderContent(
      DownloadProvider dlProvider, MediaProvider media, String platform) {
    final folder = _folderFor(platform);
    final items = _getItemsForPlatform(dlProvider, media, platform);

    final filtered = _search.isEmpty
        ? items
        : items
            .where(
                (i) => i.filename.toLowerCase().contains(_search.toLowerCase()))
            .toList();

    return Column(children: [
      // ── Folder header ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Row(children: [
          GestureDetector(
            onTap: () => setState(() {
              _openFolder = null;
              _search = '';
              _searchCtrl.clear();
            }),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border)),
              child: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textSecondary, size: 16),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: folder.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9)),
            child: Icon(folder.icon, color: folder.color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(folder.name,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              Text('${folder.count} files · ${_formatBytes(folder.bytes)}',
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11)),
            ]),
          ),
          // Cloud backup button - now navigates to Cloud Vault
          Consumer<PremiumProvider>(
            builder: (_, premium, __) {
              return GestureDetector(
                onTap: () {
                  if (!premium.isPremium) {
                    _showPremiumRequiredDialog();
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CloudVaultScreen(),
                    ),
                  );
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: premium.isPremium
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: premium.isPremium
                          ? AppColors.primary.withValues(alpha: 0.3)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      premium.isPremium
                          ? Icons.cloud_upload_outlined
                          : Icons.cloud_off_outlined,
                      color: premium.isPremium
                          ? AppColors.primary
                          : AppColors.textMuted,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      premium.isPremium ? 'Cloud Vault Pro' : 'Cloud Pro',
                      style: TextStyle(
                        color: premium.isPremium
                            ? AppColors.primary
                            : AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ),
              );
            },
          ),
        ]),
      ),

      // ── Search bar ──
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.search_rounded,
                  color: AppColors.textMuted, size: 17),
            ),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style:
                    const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Search files...',
                  hintStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (_search.isNotEmpty)
              IconButton(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textMuted, size: 15),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
          ]),
        ),
      ),

      const SizedBox(height: 8),

      // ── 2-column grid ──
      Expanded(
        child: filtered.isEmpty
            ? _buildEmptyFolder(folder)
            : GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.68,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) =>
                    _buildGridCard(filtered[i], folder, dlProvider, media),
              ),
      ),
    ]);
  }

  // ─── Grid item card ───────────────────────────────────────────────────────

  Widget _buildGridCard(_FolderItem item, _SavedFolder folder,
      DownloadProvider dlProvider, MediaProvider media) {
    return GestureDetector(
      onTap: () => _showGridItemMenu(item, dlProvider, media),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Thumbnail ──
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.isVideo)
                      _VideoThumb(filePath: item.path, fit: BoxFit.cover)
                    else if (item.path.isNotEmpty &&
                        File(item.path).existsSync())
                      Image.file(
                        File(item.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _mediaThumbnailPlaceholder(folder),
                      )
                    else
                      _mediaThumbnailPlaceholder(folder),
                    if (item.isVideo)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: _DurationBadge(filePath: item.path),
                      ),
                    if (!item.isVideo)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.image_rounded,
                              color: Colors.white, size: 11),
                        ),
                      ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showGridItemMenu(item, dlProvider, media),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.more_vert_rounded,
                              color: Colors.white, size: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.filename,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(
                      item.isVideo
                          ? Icons.videocam_outlined
                          : Icons.image_outlined,
                      color: AppColors.textMuted,
                      size: 11,
                    ),
                    const SizedBox(width: 3),
                    Text(item.sizeLabel,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 6),
                    Text(item.timeAgo,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaThumbnailPlaceholder(_SavedFolder folder) {
    return Container(
      color: folder.color.withValues(alpha: 0.07),
      child: Center(
        child: Icon(folder.icon,
            color: folder.color.withValues(alpha: 0.35), size: 30),
      ),
    );
  }

  void _showGridItemMenu(
      _FolderItem item, DownloadProvider dlProvider, MediaProvider media) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(item.filename,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const Divider(height: 20),
          ListTile(
            leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                    item.isVideo
                        ? Icons.play_arrow_rounded
                        : Icons.open_in_new_rounded,
                    color: AppColors.primary,
                    size: 18)),
            title: Text(item.isVideo ? 'Play' : 'View',
                style: const TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _open(item, media);
            },
          ),
          ListTile(
            leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.share_rounded,
                    color: AppColors.secondary, size: 18)),
            title: const Text('Share',
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              Share.shareXFiles([XFile(item.path)]);
            },
          ),
          ListTile(
            leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.primary, size: 18)),
            title: const Text('Move to Private Vault',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _moveToPrivateVault(item, dlProvider, media);
            },
          ),
          ListTile(
            leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 18)),
            title: const Text('Delete',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(item, dlProvider, media);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─── Actions ──────────────────────────────────────────────────────────────


  Future<void> _moveToPrivateVault(
      _FolderItem item, DownloadProvider dlProvider, MediaProvider media) async {
    try {
      if (!await File(item.path).exists()) throw 'File not found';
      await _vault.moveToVault(item.path);
      dlProvider.removeDownload(item.id);
      await media.refreshAllMedia();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Moved to Private Vault'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not move file: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _open(_FolderItem item, MediaProvider media) {
    if (!File(item.path).existsSync()) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('File not found')));
      return;
    }
    final mf = MediaFile(
      id: item.id,
      path: item.path,
      fileName: item.filename,
      fileSize: item.bytes,
      isVideo: item.isVideo,
      sourceApp: item.platform,
      createdAt: item.date,
      viewedAt: item.date,
      isDownloaded: true,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MediaViewerScreen(mediaFiles: [mf], initialIndex: 0)),
    );
  }

  void _confirmDelete(
      _FolderItem item, DownloadProvider dlProvider, MediaProvider media) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete File',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text('Delete "${item.filename}"?',
            style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              try {
                File(item.path).deleteSync();
              } catch (_) {}
              dlProvider.removeDownload(item.id);
              media.refreshAllMedia();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Data helpers ─────────────────────────────────────────────────────────

  List<_FolderItem> _getItemsForPlatform(
      DownloadProvider dlProvider, MediaProvider media, String platform) {
    final items = <_FolderItem>[];
    final seenPaths = <String>{};

    for (final d in dlProvider.downloads) {
      if (d.status == DownloadStatus.completed &&
          d.localPath.isNotEmpty &&
          _canonicalPlatform(d.sourceApp) == platform.toLowerCase()) {
        final item = _FolderItem.fromDownload(d);
        if (seenPaths.add(item.path)) items.add(item);
      }
    }

    for (final m in media.allMedia) {
      if (m.isDownloaded &&
          _canonicalPlatform(m.sourceApp) == platform.toLowerCase()) {
        final item = _FolderItem.fromMedia(m);
        if (seenPaths.add(item.path)) items.add(item);
      }
    }

    items.sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  // ─── Empty states ─────────────────────────────────────────────────────────

  Widget _buildEmptyFolder(_SavedFolder folder) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: folder.color.withValues(alpha: 0.1),
              shape: BoxShape.circle),
          child: Icon(folder.icon,
              size: 40, color: folder.color.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 20),
        Text('No ${folder.name} files yet',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Download from the Download tab\nto fill this folder',
            style: TextStyle(
                color: AppColors.textMuted, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ─── Utils ────────────────────────────────────────────────────────────────

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)}MB';
    return '${(bytes / 1073741824).toStringAsFixed(2)}GB';
  }
}

// ─── Data model ───────────────────────────────────────────────────────────────

class _FolderItem {
  final String id;
  final String path;
  final String filename;
  final String platform;
  final bool isVideo;
  final int bytes;
  final DateTime date;

  _FolderItem({
    required this.id,
    required this.path,
    required this.filename,
    required this.platform,
    required this.isVideo,
    required this.bytes,
    required this.date,
  });

  factory _FolderItem.fromDownload(DownloadItem d) {
    int size = 0;
    try {
      size = File(d.localPath).lengthSync();
    } catch (_) {}
    final ext = d.fileName.toLowerCase();
    return _FolderItem(
      id: d.id,
      path: d.localPath,
      filename: d.fileName,
      platform: d.sourceApp.isEmpty ? 'unknown' : d.sourceApp,
      isVideo: ext.endsWith('.mp4') ||
          ext.endsWith('.webm') ||
          ext.endsWith('.mov') ||
          ext.endsWith('.mkv'),
      bytes: size,
      date: d.dateAdded,
    );
  }

  factory _FolderItem.fromMedia(MediaFile m) => _FolderItem(
        id: m.id,
        path: m.path,
        filename: m.fileName,
        platform: m.sourceApp.isEmpty ? 'unknown' : m.sourceApp,
        isVideo: m.isVideo,
        bytes: m.fileSize,
        date: m.createdAt,
      );

  String get sizeLabel {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / 1048576).toStringAsFixed(1)}MB';
  }

  String get timeAgo {
    final diff = DateTime.now().difference(date);
    if (diff.inDays > 30) return '${date.day}/${date.month}/${date.year}';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

// ─── Video thumbnail widget ───────────────────────────────────────────────────

class _VideoThumb extends StatefulWidget {
  final String filePath;
  final BoxFit fit;
  const _VideoThumb({required this.filePath, this.fit = BoxFit.cover});

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  bool _loading = true;
  dynamic _thumbData;

  static final _cache = <String, dynamic>{};

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.filePath];
    if (cached != null) {
      _thumbData = cached;
      _loading = false;
    } else {
      _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (await file.length() < 1024) {
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
        quality: 80,
        timeMs: 500,
      );

      if (data != null) _cache[widget.filePath] = data;
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
        color: AppColors.cardAlt,
        child: const Center(
          child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary)),
        ),
      );
    }
    if (_thumbData == null) {
      return Container(
        color: AppColors.cardAlt,
        child: const Center(
          child:
              Icon(Icons.videocam_rounded, color: AppColors.primary, size: 28),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(_thumbData,
            fit: widget.fit,
            errorBuilder: (_, __, ___) => Container(
                color: AppColors.cardAlt,
                child: const Icon(Icons.videocam_rounded,
                    color: AppColors.primary, size: 28))),
        Positioned(
          bottom: 5,
          right: 5,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 12),
          ),
        ),
      ],
    );
  }
}

// ─── Duration badge widget ────────────────────────────────────────────────────

class _DurationBadge extends StatefulWidget {
  final String filePath;
  const _DurationBadge({required this.filePath});

  @override
  State<_DurationBadge> createState() => _DurationBadgeState();
}

class _DurationBadgeState extends State<_DurationBadge> {
  String? _label;
  static final _cache = <String, String>{};

  @override
  void initState() {
    super.initState();
    final cached = _cache[widget.filePath];
    if (cached != null) {
      _label = cached;
    } else {
      _loadDuration();
    }
  }

  Future<void> _loadDuration() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) return;

      final controller = VideoPlayerController.file(file);
      await controller.initialize().timeout(const Duration(seconds: 8));
      final dur = controller.value.duration;
      await controller.dispose();

      if (!mounted) return;
      final label = _fmtDur(dur);
      if (label.isNotEmpty) {
        _cache[widget.filePath] = label;
        setState(() => _label = label);
      }
    } catch (_) {}
  }

  String _fmtDur(Duration d) {
    if (d.inSeconds <= 0) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_label == null || _label!.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _label!,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
