// ui/screens/cloud_vault_screen.dart
// Complete Cloud Vault UI with Tabs (Images/Videos), Upload, Download, Delete
// Premium only - with subscription check
// ignore_for_file: use_build_context_synchronously, avoid_print, no_leading_underscores_for_library_prefixes, unused_local_variable

import 'dart:io';
// import 'package:all_social_downloader/services/cloud_vault_service.dart'
//     as cloud_vault_service;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart' as _image_picker;
import '../../providers/cloud_vault_provider.dart';
import '../../providers/premium_provider.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';
import '../../models/media_file.dart';
import '../screens/premium_screen.dart';

typedef ImageSource = _image_picker.ImageSource;
typedef ImagePicker = _image_picker.ImagePicker;
typedef XFile = _image_picker.XFile;

class CloudVaultScreen extends StatefulWidget {
  const CloudVaultScreen({Key? key}) : super(key: key);

  @override
  State<CloudVaultScreen> createState() => _CloudVaultScreenState();
}

class _CloudVaultScreenState extends State<CloudVaultScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Provider.of<CloudVaultProvider>(context, listen: false).loadFiles();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CloudVaultProvider, PremiumProvider>(
      builder: (_, cloudProvider, premium, __) {
        // Check if user is premium
        if (!premium.isPremium) {
          return _buildPremiumWall();
        }

        // Check grace period
        return FutureBuilder<bool>(
          future: cloudProvider.checkGracePeriod(),
          builder: (context, snapshot) {
            final inGrace = snapshot.data ?? false;
            if (inGrace) {
              return _buildGracePeriodBanner(cloudProvider);
            }
            return _buildVaultContent(cloudProvider);
          },
        );
      },
    );
  }

  Widget _buildPremiumWall() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Cloud Vault Pro'),
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.cloud_off_rounded,
                  color: AppColors.primary,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Cloud Vault Pro',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Backup your files to the cloud with 3GB storage.\nCloud Vault Pro keeps your library synced and available anywhere.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                ),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Upgrade to Pro'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGracePeriodBanner(CloudVaultProvider provider) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Cloud Vault Pro'),
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: AppColors.warning,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '⚠️ Subscription Expired',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your subscription has expired. You have 24 hours to renew\n'
                'before your cloud files are permanently deleted.\n\n'
                'Renew now to keep your files safe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PremiumScreen()),
                ),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Renew Subscription'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // User can still access files during grace period
                  Navigator.pop(context);
                },
                child: const Text('View Files (Read Only)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultContent(CloudVaultProvider provider) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Cloud Vault Pro'),
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          tabs: const [
            Tab(icon: Icon(Icons.image_rounded), text: 'Images'),
            Tab(icon: Icon(Icons.videocam_rounded), text: 'Videos'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Quota bar
          _buildQuotaBar(provider),

          // Status messages
          if (provider.isUploading || provider.isDownloading)
            _buildProgressBanner(provider),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(provider.imageFiles, provider, isVideo: false),
                _buildGrid(provider.videoFiles, provider, isVideo: true),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadDialog(provider),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white),
        label: const Text(
          'Upload',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildQuotaBar(CloudVaultProvider provider) {
    final usedGB = provider.usedBytes / (1024 * 1024 * 1024);
    final quotaGB = provider.quotaBytes / (1024 * 1024 * 1024);
    final fraction = provider.usageFraction;

    Color barColor;
    if (fraction < 0.7) {
      barColor = AppColors.success;
    } else if (fraction < 0.9) {
      barColor = AppColors.warning;
    } else {
      barColor = AppColors.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Storage Usage',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                '${usedGB.toStringAsFixed(2)} GB / ${quotaGB.toStringAsFixed(2)} GB',
                style: TextStyle(
                  color: fraction > 0.8
                      ? AppColors.error
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              backgroundColor: AppColors.border,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${provider.files.length} files in cloud',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBanner(CloudVaultProvider provider) {
    final isUpload = provider.isUploading;
    final progress =
        isUpload ? provider.uploadProgress : provider.downloadProgress;
    final message = provider.statusMessage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        border: Border(
            bottom:
                BorderSide(color: AppColors.primary.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
              value: progress > 0 ? progress : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${(progress * 100).toInt()}%',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<CloudFile> files, CloudVaultProvider provider,
      {required bool isVideo}) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (files.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVideo ? Icons.videocam_off_rounded : Icons.image_outlined,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              isVideo ? 'No videos in cloud' : 'No images in cloud',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the + button to upload files',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.85,
      ),
      itemCount: files.length,
      itemBuilder: (_, i) => _buildGridItem(files[i], provider, isVideo),
    );
  }

  Widget _buildGridItem(
      CloudFile file, CloudVaultProvider provider, bool isVideo) {
    return GestureDetector(
      onTap: () => _openFile(file),
      onLongPress: () => _showItemOptions(file, provider),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail
            _buildThumbnail(file, isVideo),

            // Gradient overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // File info
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
                      size: 14,
                    ),
                  Expanded(
                    child: Text(
                      file.fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Source badge
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  file.source,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            // 3-dot menu
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () => _showItemOptions(file, provider),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(CloudFile file, bool isVideo) {
    return CachedNetworkImage(
      imageUrl: file.thumbnailUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: AppColors.cardAlt,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam_rounded : Icons.image_outlined,
            color: AppColors.textMuted,
            size: 28,
          ),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: AppColors.cardAlt,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
            color: AppColors.textMuted,
            size: 28,
          ),
        ),
      ),
    );
  }

  void _openFile(CloudFile file) async {
    // For now, open in a simple viewer
    // We need to download first or stream directly
    // Let's stream directly from Firebase Storage

    final mediaFile = MediaFile(
      id: file.id,
      path: file.storagePath,
      fileName: file.fileName,
      fileSize: file.fileSize,
      isVideo: file.isVideo,
      sourceApp: 'cloud',
      createdAt: file.uploadDate,
      viewedAt: DateTime.now(),
      isDownloaded: false,
      // We'll need to handle streaming for cloud files
    );

    // Show loading indicator while getting URL
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    try {
      // Get download URL for streaming
      final provider = Provider.of<CloudVaultProvider>(context, listen: false);
      final result = await provider.downloadFile(file);

      Navigator.pop(context); // Close loading dialog

      if (result != null) {
        // Now open the media viewer with the downloaded file
        final downloadedFile = MediaFile(
          id: file.id,
          path: result,
          fileName: file.fileName,
          fileSize: file.fileSize,
          isVideo: file.isVideo,
          sourceApp: 'cloud',
          createdAt: file.uploadDate,
          viewedAt: DateTime.now(),
          isDownloaded: true,
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MediaViewerScreen(
              mediaFiles: [downloadedFile],
              initialIndex: 0,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load file')),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _showItemOptions(CloudFile file, CloudVaultProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                file.fileName,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 20),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.download_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
              ),
              title: const Text(
                'Download to Device',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(file, provider);
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
                'Delete from Cloud',
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(file, provider);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(
      CloudFile file, CloudVaultProvider provider) async {
    final result = await provider.downloadFile(file);
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ File downloaded to device'),
          backgroundColor: AppColors.success,
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Download failed'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _confirmDelete(CloudFile file, CloudVaultProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete from Cloud?'),
        content: Text(
          'Delete "${file.fileName}" from cloud storage?\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await provider.deleteFile(file);
              if (result && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🗑️ File deleted from cloud'),
                    backgroundColor: AppColors.success,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showUploadDialog(CloudVaultProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Upload to Cloud Vault',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary),
              title: const Text(
                'Choose an image from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(provider, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_rounded,
                  color: AppColors.primary),
              title: const Text(
                'Choose a video from Gallery',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickVideoAndUpload(provider, ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded,
                  color: AppColors.primary),
              title: const Text(
                'Take a photo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAndUpload(provider, ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.videocam_rounded, color: AppColors.primary),
              title: const Text(
                'Record a video',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickVideoAndUpload(provider, ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndUpload(
      CloudVaultProvider provider, ImageSource source) async {
    try {
      // Use pickImage (supports camera/gallery) since pickMedia doesn't
      // define a 'source' named parameter in some image_picker versions.
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (picked == null) return;

      final file = File(picked.path);
      final fileName = picked.name;

      // Determine if video
      final isVideo = picked.mimeType?.startsWith('video') ?? false;

      final success = await provider.uploadFile(
        localPath: file.path,
        fileName: fileName,
        source: 'manual',
        mimeType: picked.mimeType,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Uploaded to cloud successfully!'),
            backgroundColor: AppColors.success,
          ),
        );
        provider.refreshQuota();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('❌ Upload failed: ${provider.error ?? "Unknown error"}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      print('Pick error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickVideoAndUpload(
      CloudVaultProvider provider, ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 10),
      );
      if (picked == null) return;

      final success = await provider.uploadFile(
        localPath: picked.path,
        fileName: picked.name,
        source: 'manual',
        mimeType: picked.mimeType ?? 'video/mp4',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? '✅ Video uploaded to Cloud Vault Pro'
              : '❌ Video upload failed: ${provider.error ?? "Unknown error"}'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) await provider.refreshQuota();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Video upload error: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ─── CachedNetworkImage placeholder ──────────────────────────────────────────
// For simplicity, we'll use a simple Image.network with error handling
// In production, use cached_network_image package

class CachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;

  const CachedNetworkImage({
    Key? key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : super(key: key);

  @override
  State<CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<CachedNetworkImage> {
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    try {
      await NetworkImage(widget.imageUrl).resolve(const ImageConfiguration());
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.placeholder?.call(context, widget.imageUrl) ??
          Container(color: AppColors.cardAlt);
    }

    if (_error) {
      return widget.errorWidget?.call(context, widget.imageUrl, null) ??
          Container(
            color: AppColors.cardAlt,
            child: const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: AppColors.textMuted, size: 28),
            ),
          );
    }

    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      errorBuilder: (_, __, ___) =>
          widget.errorWidget?.call(context, widget.imageUrl, null) ??
          Container(
            color: AppColors.cardAlt,
            child: const Center(
              child: Icon(Icons.broken_image_rounded,
                  color: AppColors.textMuted, size: 28),
            ),
          ),
    );
  }
}
