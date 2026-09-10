import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/media_file.dart';
import '../../providers/media_provider.dart';
import '../../services/native_bridge.dart';
import '../themes/app_theme.dart';
import '../widgets/premium/repurpose_studio.dart';

/// Media-backed entry point for Repurpose Studio.
///
/// A user selects a downloaded or device-storage video first. The actual
/// actions are rendered by RepurposeStudio, which separates local Quick Packs
/// from provider-backed AI actions.
class RepurposeStudioScreen extends StatefulWidget {
  const RepurposeStudioScreen({Key? key}) : super(key: key);

  @override
  State<RepurposeStudioScreen> createState() => _RepurposeStudioScreenState();
}

class _RepurposeStudioScreenState extends State<RepurposeStudioScreen> {
  MediaFile? _selected;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<MediaProvider>(context, listen: false).refreshAllMedia();
      }
    });
  }

  Future<void> _pickFromDevice() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final path = await NativeBridge.pickVideoFile();
      if (path != null && path.isNotEmpty && mounted) {
        setState(() => _selected = MediaFile.fromPath(path));
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = Provider.of<MediaProvider>(context);
    final videos = media.allMedia.where((item) => item.isVideo).toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Repurpose Studio'),
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _selected == null
          ? _buildPicker(videos)
          : _buildStudio(_selected!),
    );
  }

  Widget _buildPicker(List<MediaFile> videos) {
    return RefreshIndicator(
      onRefresh: () => Provider.of<MediaProvider>(context, listen: false)
          .refreshAllMedia(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Container(
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
                  'Turn one video into a content pack',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Choose a saved download or a video from your phone. Local Quick Packs are free; AI actions use your AI allowance.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _isPicking ? null : _pickFromDevice,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(_isPicking ? 'Opening picker…' : 'Choose from phone storage'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withValues(alpha: .35)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            videos.isEmpty ? 'No downloaded videos yet' : 'Recent videos',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (videos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Text(
                'Download a video or choose one from Downloads to start repurposing it.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.45),
              ),
            )
          else
            ...videos.take(20).map(_videoTile),
        ],
      ),
    );
  }

  Widget _videoTile(MediaFile item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        onTap: () => setState(() => _selected = item),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.video_file_rounded, color: AppColors.primary),
        ),
        title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(item.sourceApp.isEmpty ? 'ClipVaults video' : item.sourceApp),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  Widget _buildStudio(MediaFile item) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _selected = null),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Choose another video'),
          style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const SizedBox(height: 4),
        Text(
          item.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        RepurposeStudio(
          videoId: item.id,
          videoTitle: item.fileName,
          videoPath: item.path,
          platform: item.sourceApp,
        ),
      ],
    );
  }
}
