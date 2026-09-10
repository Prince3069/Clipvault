// ui/screens/saved_edits_screen.dart
// COMPLETE - View All Saved Edits

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../../models/media_file.dart';
import '../../services/storage_service.dart';
import '../themes/app_theme.dart';
import '../widgets/media_viewer_screen.dart';

class SavedEditsScreen extends StatefulWidget {
  const SavedEditsScreen({Key? key}) : super(key: key);

  @override
  State<SavedEditsScreen> createState() => _SavedEditsScreenState();
}

class _SavedEditsScreenState extends State<SavedEditsScreen> {
  final StorageService _storage = StorageService();
  List<Map<String, dynamic>> _edits = [];
  bool _isLoading = true;
  bool _selectionMode = false;
  final Set<int> _selectedIndices = {};

  @override
  void initState() {
    super.initState();
    _loadEdits();
  }

  Future<void> _loadEdits() async {
    setState(() => _isLoading = true);
    _edits = await _storage.getSavedEdits();
    setState(() => _isLoading = false);
  }

  String _getEditIcon(String editType) {
    switch (editType) {
      case 'trim':
        return '✂️';
      case 'frame':
        return '🖼️';
      case 'compress':
        return '📦';
      case 'crop':
        return '📐';
      case 'rotate':
        return '🔄';
      case 'speed':
        return '⏱️';
      case 'reverse':
        return '🔁';
      case 'extract_audio':
        return '🎵';
      case 'add_text':
        return '📝';
      case 'add_music':
        return '🎶';
      case 'effect':
        return '🎨';
      case 'sticker':
        return '🎯';
      default:
        return '📄';
    }
  }

  String _getEditLabel(String editType) {
    switch (editType) {
      case 'trim':
        return 'Trimmed';
      case 'frame':
        return 'Frame';
      case 'compress':
        return 'Compressed';
      case 'crop':
        return 'Cropped';
      case 'rotate':
        return 'Rotated';
      case 'speed':
        return 'Speed Change';
      case 'reverse':
        return 'Reversed';
      case 'extract_audio':
        return 'Audio Extract';
      case 'add_text':
        return 'Text Overlay';
      case 'add_music':
        return 'Music Added';
      case 'effect':
        return 'Effect';
      case 'sticker':
        return 'Stickers';
      default:
        return 'Edited';
    }
  }

  Color _getEditColor(String editType) {
    switch (editType) {
      case 'trim':
        return const Color(0xFF6C63FF);
      case 'frame':
        return const Color(0xFF00C2FF);
      case 'compress':
        return const Color(0xFF22C55E);
      case 'crop':
        return const Color(0xFF3B82F6);
      case 'rotate':
        return const Color(0xFF8B5CF6);
      case 'speed':
        return const Color(0xFFF59E0B);
      case 'reverse':
        return const Color(0xFFEF4444);
      case 'extract_audio':
        return const Color(0xFFEC4899);
      case 'add_text':
        return const Color(0xFF06B6D4);
      case 'add_music':
        return const Color(0xFF10B981);
      case 'effect':
        return const Color(0xFF8B5CF6);
      case 'sticker':
        return const Color(0xFFF472B6);
      default:
        return AppColors.primary;
    }
  }

  Future<void> _deleteEdit(Map<String, dynamic> edit) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('Delete Edit?'),
        content: Text('Delete "${edit['originalName']}" permanently?'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final deleted = await _storage.deleteSavedEdit(edit['path']);
      if (deleted) {
        setState(() => _edits.remove(edit));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🗑️ Edit deleted'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelected() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: Text('Delete ${_selectedIndices.length} items?'),
        content: const Text('This cannot be undone.'),
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final toDelete = _selectedIndices.map((i) => _edits[i]).toList();
      for (final edit in toDelete) {
        await _storage.deleteSavedEdit(edit['path']);
      }
      setState(() {
        _edits.removeWhere((e) => toDelete.contains(e));
        _selectedIndices.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🗑️ Deleted ${toDelete.length} items'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
      if (_selectedIndices.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _shareEdit(Map<String, dynamic> edit) {
    final file = File(edit['path']);
    if (file.existsSync()) {
      Share.shareXFiles([XFile(edit['path'])]);
    }
  }

  void _openEdit(Map<String, dynamic> edit) {
    final isVideo = edit['path'].toString().endsWith('.mp4') ||
        edit['path'].toString().endsWith('.mov') ||
        edit['path'].toString().endsWith('.3gp') ||
        edit['path'].toString().endsWith('.mkv');

    final mediaFile = MediaFile(
      id: edit['path'],
      path: edit['path'],
      fileName: edit['originalName'] ?? 'Edited Video',
      fileSize: edit['size'] ?? 0,
      isVideo: isVideo,
      sourceApp: 'Editor',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        edit['timestamp'] ?? 0,
      ),
      viewedAt: DateTime.now(),
      isDownloaded: true,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          mediaFiles: [mediaFile],
          initialIndex: 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            )
          : _edits.isEmpty
              ? _buildEmptyState()
              : _buildEditList(),
      floatingActionButton: _selectionMode
          ? FloatingActionButton.extended(
              onPressed: _deleteSelected,
              backgroundColor: AppColors.error,
              icon: const Icon(Icons.delete_rounded, color: Colors.white),
              label: Text(
                'Delete ${_selectedIndices.length}',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      title: Row(
        children: [
          const Icon(Icons.edit_rounded, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            _selectionMode
                ? '${_selectedIndices.length} selected'
                : 'Saved Edits',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
      actions: [
        if (!_selectionMode) ...[
          IconButton(
            onPressed: _loadEdits,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectionMode = true;
              });
            },
            icon: const Icon(Icons.select_all_rounded),
            tooltip: 'Select',
          ),
        ],
        if (_selectionMode) ...[
          IconButton(
            onPressed: () {
              setState(() {
                _selectionMode = false;
                _selectedIndices.clear();
              });
            },
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Cancel',
          ),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.edit_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Saved Edits',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Edit a video and it will appear here',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Go Edit a Video'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(Map<String, dynamic> edit, Color color) {
    final path = edit['path']?.toString() ?? '';
    final editType = edit['editType'] ?? '';
    final isVideo = path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.3gp') ||
        path.endsWith('.mkv');

    final fallback = Container(
      color: color.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          _getEditIcon(editType),
          style: const TextStyle(fontSize: 22),
        ),
      ),
    );

    Widget content;
    if (path.isEmpty || !File(path).existsSync()) {
      content = fallback;
    } else if (isVideo) {
      content = _SavedEditVideoThumb(filePath: path, fallback: fallback);
    } else {
      content = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 48, height: 48, child: content),
        ),
        Positioned(
          bottom: -4,
          right: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              _getEditIcon(editType),
              style: const TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _edits.length,
      itemBuilder: (context, index) {
        final edit = _edits[index];
        final isSelected = _selectedIndices.contains(index);
        final editType = edit['editType'] ?? '';
        final color = _getEditColor(editType);

        return GestureDetector(
          onTap: () {
            if (_selectionMode) {
              _toggleSelection(index);
              return;
            }
            _openEdit(edit);
          },
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
                _selectedIndices.add(index);
              });
            }
          },
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
            elevation: isSelected ? 4 : 1,
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  if (_selectionMode)
                    Container(
                      margin: const EdgeInsets.only(right: 12),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMuted,
                        size: 24,
                      ),
                    ),
                  _buildThumbnail(edit, color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          edit['originalName'] ?? 'Edited Video',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getEditLabel(editType),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: color,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatFileSize(edit['size'] ?? 0),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(edit['timestamp'] ?? 0),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (!_selectionMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _shareEdit(edit),
                          icon: const Icon(
                            Icons.share_rounded,
                            color: AppColors.textMuted,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _deleteEdit(edit),
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: AppColors.error,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textMuted,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        if (diff.inMinutes == 0) return 'Just now';
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ─── Video thumbnail widget ──────────────────────────────────────────────────
// Generates a real preview frame for saved video edits instead of showing
// only the edit-type emoji, matching the pattern used in saved_screen.dart
// and creator_library_screen.dart.

class _SavedEditVideoThumb extends StatefulWidget {
  final String filePath;
  final Widget fallback;

  const _SavedEditVideoThumb({
    required this.filePath,
    required this.fallback,
  });

  @override
  State<_SavedEditVideoThumb> createState() => _SavedEditVideoThumbState();
}

class _SavedEditVideoThumbState extends State<_SavedEditVideoThumb> {
  dynamic _thumbData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void didUpdateWidget(_SavedEditVideoThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath) {
      _thumbData = null;
      _loading = true;
      _generate();
    }
  }

  Future<void> _generate() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists() || await file.length() < 1024) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final data = await VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 65,
      );
      if (mounted) {
        setState(() {
          _thumbData = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: Colors.black12,
        child: const Center(
          child: SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_thumbData == null) {
      return widget.fallback;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(_thumbData, fit: BoxFit.cover),
        const Center(
          child: Icon(
            Icons.play_circle_rounded,
            color: Colors.white70,
            size: 18,
          ),
        ),
      ],
    );
  }
}
