import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/media_file.dart';
import '../../providers/media_provider.dart';
import '../themes/app_theme.dart';
import 'quick_clip_editor.dart';
import 'quick_photo_editor.dart';

/// A calm, gallery-first entry point for editing.
///
/// The user sees recent ClipVaults media first and only opens Android's picker
/// after explicitly choosing Photos or Videos. The picker is never opened as a
/// folder tree by default.
class QuickEditorPickerScreen extends StatefulWidget {
  const QuickEditorPickerScreen({Key? key}) : super(key: key);

  @override
  State<QuickEditorPickerScreen> createState() => _QuickEditorPickerScreenState();
}

class _QuickEditorPickerScreenState extends State<QuickEditorPickerScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _picking = false;

  Future<void> _pickPhoto() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery);
      if (file != null && mounted) _openPhoto(file.path, file.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _pickVideo() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery);
      if (file != null && mounted) _openVideo(file.path, file.name);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _openMedia(MediaFile item) {
    if (item.isVideo) {
      _openVideo(item.path, item.fileName);
    } else {
      _openPhoto(item.path, item.fileName);
    }
  }

  void _openVideo(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuickClipEditor(videoPath: path, videoTitle: title),
    ));
  }

  void _openPhoto(String path, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuickPhotoEditor(imagePath: path, imageTitle: title),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = Provider.of<MediaProvider>(context);
    final recent = [...media.allMedia]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Quick Editor'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => Provider.of<MediaProvider>(context, listen: false)
            .refreshAllMedia(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            _buildHero(),
            const SizedBox(height: 18),
            _buildAddMediaCard(),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent media',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (recent.isNotEmpty)
                  Text(
                    '${recent.length} saved',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (recent.isEmpty)
              _buildEmptyState()
            else
              _buildRecentGrid(recent.take(24).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.heroGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
          SizedBox(height: 12),
          Text(
            'Choose something to create with',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your latest ClipVaults downloads appear here first. Add a photo or video from your phone whenever you need it.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMediaCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Add media',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking ? null : _pickPhoto,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Photos'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking ? null : _pickVideo,
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Videos'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Opens your phone’s recent gallery. Downloads are included by Android Gallery when available.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentGrid(List<MediaFile> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: .82,
      ),
      itemBuilder: (_, index) => _recentTile(items[index]),
    );
  }

  Widget _recentTile(MediaFile item) {
    return InkWell(
      onTap: () => _openMedia(item),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: item.thumbnailPath != null &&
                        File(item.thumbnailPath!).existsSync()
                    ? Image.file(File(item.thumbnailPath!), fit: BoxFit.cover)
                    : Container(
                        color: AppColors.primary.withValues(alpha: .08),
                        child: Icon(
                          item.isVideo
                              ? Icons.play_circle_outline_rounded
                              : Icons.image_outlined,
                          color: AppColors.primary,
                          size: 30,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              item.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
            Text(
              item.isVideo ? 'Video' : 'Photo',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.collections_outlined,
              color: AppColors.primary, size: 38),
          SizedBox(height: 12),
          Text(
            'Your recent downloads will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Tap Add media to choose from your phone instead.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }
}
