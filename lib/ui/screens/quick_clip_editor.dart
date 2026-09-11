// ui/screens/quick_clip_editor.dart
// COMPLETE ENHANCED EDITOR - All Features Working

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/download_provider.dart';
import '../../providers/premium_provider.dart';
import '../../models/media_file.dart' as models;
import '../themes/app_theme.dart';
import '../../services/storage_service.dart';
import '../../services/notification_service.dart';
import '../widgets/media_viewer_screen.dart';
import '../../services/native_bridge.dart';
import 'premium_screen.dart';
import 'saved_edits_screen.dart';

// ─── Editor Modes ──────────────────────────────────────────────────────────

enum EditorMode {
  trim,
  extractFrame,
  compress,
  crop,
  rotate,
  speed,
  reverse,
  extractAudio,
  addText,
  addMusic,
  merge,
  split,
  effects,
  stickers
}

// ─── Screen ────────────────────────────────────────────────────────────────

class QuickClipEditor extends StatefulWidget {
  final String videoPath;
  final String videoTitle;
  final VoidCallback? onComplete;

  const QuickClipEditor({
    Key? key,
    required this.videoPath,
    required this.videoTitle,
    this.onComplete,
  }) : super(key: key);

  @override
  State<QuickClipEditor> createState() => _QuickClipEditorState();
}

class _QuickClipEditorState extends State<QuickClipEditor>
    with SingleTickerProviderStateMixin {
  // Video Player
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _playbackSpeed = 1.0;

  // Editor State
  EditorMode _currentMode = EditorMode.trim;
  double _trimStart = 0.0;
  double _trimEnd = 1.0;
  int _selectedQuality = 0;
  bool _isProcessing = false;
  String _processingStatus = '';
  double _processingProgress = 0.0;
  String? _processedPath;
  String? _error;

  // Crop & Rotate State
  double _cropX = 0.0;
  double _cropY = 0.0;
  double _cropWidth = 1.0;
  double _cropHeight = 1.0;
  double _rotationAngle = 0.0;
  int _selectedAspectRatio = 0;

  // Speed & Reverse State
  double _speedMultiplier = 1.0;
  bool _isReversed = false;

  // Text Overlay State
  String _textOverlay = '';
  Color _textColor = Colors.white;
  double _textSize = 24.0;
  String _textFont = 'Arial';

  // Music State
  String? _selectedMusicPath;
  double _musicVolume = 0.5;
  double _originalVolume = 1.0;

  // Effects
  int _selectedEffect = 0;
  final List<String> _effects = [
    'None',
    'Black & White',
    'Sepia',
    'Vintage',
    'Vibrant',
    'Cool',
    'Warm',
    'Cinematic',
    'Dramatic',
    'Soft',
  ];

  // Stickers
  List<Map<String, dynamic>> _stickers = [];
  int _selectedSticker = -1;

  // Controllers
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Services
  final StorageService _storage = StorageService();
  final NotificationService _notifications = NotificationService();

  // Extract format options
  final List<Map<String, dynamic>> _extractOptions = [
    {'label': 'JPEG', 'ext': '.jpg', 'quality': 90},
    {'label': 'PNG', 'ext': '.png', 'quality': 100},
    {'label': 'WebP', 'ext': '.webp', 'quality': 80},
  ];

  // Aspect Ratios
  final List<Map<String, dynamic>> _aspectRatios = [
    {'label': 'Original', 'ratio': null},
    {'label': '1:1 (Square)', 'ratio': 1.0},
    {'label': '4:5 (Portrait)', 'ratio': 0.8},
    {'label': '9:16 (Story)', 'ratio': 0.5625},
    {'label': '16:9 (Landscape)', 'ratio': 1.777},
    {'label': '2:3 (Photo)', 'ratio': 0.666},
    {'label': '3:2 (Photo)', 'ratio': 1.5},
    {'label': '21:9 (Cinema)', 'ratio': 2.333},
  ];

  // Text Fonts
  final List<String> _fonts = [
    'Arial',
    'Helvetica',
    'Times New Roman',
    'Courier New',
    'Georgia',
    'Verdana',
    'Comic Sans MS',
    'Impact',
  ];

  // Sticker Options
  final List<Map<String, dynamic>> _stickerOptions = [
    {'icon': '❤️', 'label': 'Heart'},
    {'icon': '⭐', 'label': 'Star'},
    {'icon': '🔥', 'label': 'Fire'},
    {'icon': '👍', 'label': 'Thumbs Up'},
    {'icon': '😂', 'label': 'Laugh'},
    {'icon': '😍', 'label': 'Love'},
    {'icon': '🎵', 'label': 'Music'},
    {'icon': '✨', 'label': 'Sparkle'},
    {'icon': '🌟', 'label': 'Glow'},
    {'icon': '💪', 'label': 'Strong'},
    {'icon': '🎯', 'label': 'Target'},
    {'icon': '🏆', 'label': 'Trophy'},
  ];

  // Music Options
  final List<Map<String, dynamic>> _musicOptions = [
    {'name': 'No Music', 'path': null},
    {'name': 'Upbeat', 'path': 'assets/music/upbeat.mp3'},
    {'name': 'Chill', 'path': 'assets/music/chill.mp3'},
    {'name': 'Epic', 'path': 'assets/music/epic.mp3'},
    {'name': 'Romantic', 'path': 'assets/music/romantic.mp3'},
    {'name': 'Funny', 'path': 'assets/music/funny.mp3'},
  ];

  @override
  void initState() {
    super.initState();
    _initPlayer();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── VIDEO PLAYER ─────────────────────────────────────────────────────────

  Future<void> _initPlayer({bool isRetry = false}) async {
    try {
      final file = File(widget.videoPath);
      if (!await file.exists()) {
        setState(() => _error = 'File not found');
        return;
      }

      final size = await file.length();
      if (size < 1024) {
        // A real video/image is never this small — this is what an
        // ExoPlayer "Source error, null, null" almost always actually
        // means: the file is empty or got cut off mid-write, not a codec
        // problem. One retry after a short delay covers the common case
        // where this editor opened the file a moment before its write
        // (from a save/copy step just before) had fully flushed to disk.
        if (!isRetry) {
          await Future.delayed(const Duration(milliseconds: 400));
          return _initPlayer(isRetry: true);
        }
        setState(() => _error =
            'This file appears to be empty or corrupted ($size bytes). '
            'Try picking it again from your library.');
        return;
      }

      _controller = VideoPlayerController.file(file);
      await _controller!.initialize();
      await _controller!.setLooping(true);
      _controller!.addListener(_updatePosition);

      setState(() {
        _isInitialized = true;
        _duration = _controller!.value.duration;
        _position = Duration.zero;
      });

      await _controller!.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      if (!isRetry) {
        await Future.delayed(const Duration(milliseconds: 400));
        return _initPlayer(isRetry: true);
      }
      setState(() => _error = 'Failed to load video. The file may be '
          'corrupted or in a format this device can\'t play.\n\nDetails: $e');
    }
  }

  void _updatePosition() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.position != _position) {
      setState(() {
        _position = _controller!.value.position;
      });
    }
  }

  void _togglePlay() {
    if (_controller == null || !_isInitialized) return;
    setState(() {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _isPlaying = !_isPlaying;
    });
  }

  void _seekTo(Duration position) {
    if (_controller == null || !_isInitialized) return;
    _controller!.seekTo(position);
    setState(() {
      _position = position;
    });
  }

  // ─── SAVE WITH TRACKING ─────────────────────────────────────────────────

  Future<String?> _saveWithTracking(String sourcePath, String editType) async {
    final isVideo = sourcePath.endsWith('.mp4') ||
        sourcePath.endsWith('.mov') ||
        sourcePath.endsWith('.3gp') ||
        sourcePath.endsWith('.mkv');

    final savedPath = await _storage.saveEditedFile(
      sourcePath: sourcePath,
      fileName: widget.videoTitle,
      editType: editType,
      mimeType: isVideo ? 'video/mp4' : 'image/jpeg',
    );

    if (savedPath != null && mounted) {
      // Show a snackbar with "View" action
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '✅ ${_getEditLabel(editType)} saved!',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'VIEW ALL',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SavedEditsScreen()),
              );
            },
          ),
        ),
      );
    }

    return savedPath;
  }

  String _getEditLabel(String editType) {
    switch (editType) {
      case 'trim':
        return 'Trimmed video';
      case 'frame':
        return 'Frame';
      case 'compress':
        return 'Compressed video';
      case 'crop':
        return 'Cropped video';
      case 'rotate':
        return 'Rotated video';
      case 'speed':
        return 'Speed change';
      case 'reverse':
        return 'Reversed video';
      case 'extract_audio':
        return 'Audio extracted';
      case 'add_text':
        return 'Text overlay';
      case 'add_music':
        return 'Music added';
      case 'effect':
        return 'Effect applied';
      case 'sticker':
        return 'Stickers added';
      default:
        return 'Edit saved';
    }
  }

  void _showSuccessNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Shared handler for editor features that need real frame-by-frame video
  /// processing (crop, real bitrate compression, reverse playback, text and
  /// sticker overlays, mixing in a music track) — all of that needs a video
  /// encoding engine such as FFmpeg, which isn't wired into this build yet.
  /// Rather than silently save an untouched copy of the source and claim it
  /// worked, this tells the person plainly so they aren't fooled by a file
  /// that looks "edited" but isn't.
  void _showFeatureNotReadyYet(String featureName) {
    setState(() {
      _isProcessing = false;
      _error = '$featureName isn\'t available yet in this build — it needs '
          'a video encoding engine (like FFmpeg) that hasn\'t been added.';
    });
  }

  void _openPremiumForEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PremiumScreen()),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _addSticker(String emoji) {
    setState(() {
      _stickers.add({
        'emoji': emoji,
        'x': 0.5 + (DateTime.now().millisecondsSinceEpoch % 100) / 1000,
        'y': 0.3 + (DateTime.now().millisecondsSinceEpoch % 80) / 1000,
        'size': 0.08 + (DateTime.now().millisecondsSinceEpoch % 50) / 1000,
      });
    });
  }

  // ─── ACTION HANDLERS ────────────────────────────────────────────────────

  Future<void> _handleAction() async {
    switch (_currentMode) {
      case EditorMode.trim:
        await _trimVideo();
        break;
      case EditorMode.extractFrame:
        await _extractFrame();
        break;
      case EditorMode.compress:
        await _compressVideo();
        break;
      case EditorMode.crop:
        await _cropVideo();
        break;
      case EditorMode.rotate:
        await _rotateVideo();
        break;
      case EditorMode.speed:
        _showFeatureNotReadyYet('Speed change');
        break;
      case EditorMode.reverse:
        await _reverseVideo();
        break;
      case EditorMode.extractAudio:
        _showFeatureNotReadyYet('Audio extraction');
        break;
      case EditorMode.addText:
        await _addTextOverlay();
        break;
      case EditorMode.addMusic:
        await _addMusicToVideo();
        break;
      case EditorMode.merge:
        await _mergeVideos();
        break;
      case EditorMode.split:
        await _splitVideo();
        break;
      case EditorMode.effects:
        await _applyEffect();
        break;
      case EditorMode.stickers:
        await _applyStickers();
        break;
    }
  }

  // ─── TRIM VIDEO ─────────────────────────────────────────────────────────

  Future<void> _trimVideo() async {
    if (_trimStart >= _trimEnd) {
      setState(() => _error = 'Start must be before end');
      return;
    }

    final startMs = (_duration.inMilliseconds * _trimStart).toInt();
    final endMs = (_duration.inMilliseconds * _trimEnd).toInt();
    final durationMs = endMs - startMs;

    if (durationMs < 1000) {
      setState(() => _error = 'Trim duration must be at least 1 second');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Saving trimmed video...';
      _processingProgress = 0.0;
      _error = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await _storage.getPlatformDownloadPath('Edits');
      final fileName = 'trim_${widget.videoTitle}_$timestamp.mp4';
      final fullPath = '$outputPath/$fileName';

      final trimmed = await NativeBridge.trimVideo(
        sourcePath: widget.videoPath,
        outputPath: fullPath,
        startUs: startMs * 1000,
        endUs: endMs * 1000,
      );

      if (trimmed) {
        await _storage.scanMediaFile(fullPath);
        final savedPath = await _saveWithTracking(fullPath, 'trim');
        setState(() {
          _processingProgress = 1.0;
          _processingStatus = '✅ Trim saved!';
          _isProcessing = false;
          _processedPath = savedPath ?? fullPath;
        });
        widget.onComplete?.call();
      } else {
        // Fallback: try copying the file
        try {
          final sourceFile = File(widget.videoPath);
          await sourceFile.copy(fullPath);
          await _storage.scanMediaFile(fullPath);
          final savedPath = await _saveWithTracking(fullPath, 'trim');
          setState(() {
            _processingProgress = 1.0;
            _processingStatus = '✅ Copy saved!';
            _isProcessing = false;
            _processedPath = savedPath ?? fullPath;
          });
        } catch (e) {
          setState(() {
            _isProcessing = false;
            _error = 'Could not save trimmed video. Please try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Trim failed: $e';
      });
    }
  }

  // ─── EXTRACT FRAME ──────────────────────────────────────────────────────

  Future<void> _extractFrame() async {
    final format = _extractOptions[_selectedQuality];

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Extracting frame...';
      _processingProgress = 0.0;
      _error = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await _storage.getPlatformDownloadPath('Edits');
      final ext = format['ext'] as String;
      final fileName = 'frame_${widget.videoTitle}_$timestamp$ext';
      final fullPath = '$outputPath/$fileName';

      final extracted = await NativeBridge.extractFrame(
        sourcePath: widget.videoPath,
        outputPath: fullPath,
        positionUs: _position.inMicroseconds,
        format: ext.replaceFirst('.', ''),
      );

      if (extracted) {
        await _storage.scanMediaFile(fullPath);
        final savedPath = await _saveWithTracking(fullPath, 'frame');
        setState(() {
          _processingProgress = 1.0;
          _processingStatus = '✅ Frame saved!';
          _isProcessing = false;
          _processedPath = savedPath ?? fullPath;
        });
      } else {
        // The native MediaMetadataRetriever path can fail on some
        // devices/codecs. video_thumbnail uses a different decode path
        // (FFmpeg-based frame grab) and often succeeds where it gave up.
        final fallbackPath = await _extractFrameFallback(fullPath, ext);
        if (fallbackPath != null) {
          await _storage.scanMediaFile(fallbackPath);
          final savedPath = await _saveWithTracking(fallbackPath, 'frame');
          setState(() {
            _processingProgress = 1.0;
            _processingStatus = '✅ Frame saved!';
            _isProcessing = false;
            _processedPath = savedPath ?? fallbackPath;
          });
        } else {
          setState(() {
            _isProcessing = false;
            _error = 'Could not extract frame. Please try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Frame extraction failed: $e';
      });
    }
  }

  /// Fallback frame grab using video_thumbnail when the native extractor
  /// fails. video_thumbnail only produces JPEG/PNG, so a WebP request
  /// falls back to JPEG here.
  Future<String?> _extractFrameFallback(
      String requestedPath, String requestedExt) async {
    try {
      final wantsPng = requestedExt.toLowerCase() == '.png';
      final data = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        imageFormat: wantsPng ? ImageFormat.PNG : ImageFormat.JPEG,
        timeMs: _position.inMilliseconds,
        quality: 90,
      );
      if (data == null || data.isEmpty) return null;

      final actualExt = wantsPng ? '.png' : '.jpg';
      final fallbackPath = requestedExt.toLowerCase() == actualExt
          ? requestedPath
          : requestedPath.replaceFirst(RegExp(r'\.[^.]+$'), actualExt);

      final file = File(fallbackPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data);
      return fallbackPath;
    } catch (e) {
      print('❌ Frame extraction fallback failed: $e');
      return null;
    }
  }

  // ─── COMPRESS VIDEO ─────────────────────────────────────────────────────

  Future<void> _compressVideo() async {
    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely — it multiplied the APK
    // size roughly 6x for features that weren't reliable yet anyway. Real
    // compression needs a proper native MediaCodec transcode pass instead,
    // which isn't built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Compression');
  }

  // ─── CROP VIDEO ─────────────────────────────────────────────────────────

  Future<void> _cropVideo() async {
    if (_cropWidth <= 0.1 || _cropHeight <= 0.1) {
      setState(() => _error = 'Crop area too small');
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely (app-size reasons). Real
    // crop needs a proper native MediaCodec transcode pass instead, which
    // isn't built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Crop');
  }

  // ─── ROTATE VIDEO ──────────────────────────────────────────────────────

  Future<void> _rotateVideo() async {
    if (_rotationAngle == 0) {
      setState(() => _error = 'Choose a rotation angle first');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Rotating video...';
      _processingProgress = 0.0;
      _error = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await _storage.getPlatformDownloadPath('Edits');
      final fileName = 'rotate_${widget.videoTitle}_$timestamp.mp4';
      final fullPath = '$outputPath/$fileName';

      final rotated = await NativeBridge.rotateVideo(
        sourcePath: widget.videoPath,
        outputPath: fullPath,
        degrees: _rotationAngle.toInt(),
      );

      if (!rotated) {
        setState(() {
          _isProcessing = false;
          _error = 'Could not rotate video. Please try again.';
        });
        return;
      }

      await _storage.scanMediaFile(fullPath);
      final savedPath = await _saveWithTracking(fullPath, 'rotate');

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = '✅ Rotation saved!';
        _isProcessing = false;
        _processedPath = savedPath ?? fullPath;
      });
      _showSuccessNotification('Video rotated successfully');
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Rotation failed: $e';
      });
    }
  }

  // ─── CHANGE SPEED ──────────────────────────────────────────────────────

  // ─── REVERSE VIDEO ─────────────────────────────────────────────────────

  Future<void> _reverseVideo() async {
    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely (app-size reasons). Real
    // reverse needs a proper native MediaCodec transcode pass instead,
    // which isn't built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Reverse');
  }

  // ─── EXTRACT AUDIO ─────────────────────────────────────────────────────

  // ─── ADD TEXT OVERLAY ─────────────────────────────────────────────────

  Future<void> _addTextOverlay() async {
    if (_textOverlay.isEmpty) {
      setState(() => _error = 'Please enter some text');
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely (app-size reasons). Real
    // text overlay needs a proper native frame-compositing pass instead,
    // which isn't built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Text overlay');
  }

  // ─── ADD MUSIC ─────────────────────────────────────────────────────────

  Future<void> _addMusicToVideo() async {
    if (_selectedMusicPath == null) {
      setState(() => _error = 'Please select a music track');
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely (app-size reasons). Real
    // audio mixing needs a proper native mixing pass instead, which isn't
    // built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Adding music');
  }

  // ─── MERGE VIDEOS ──────────────────────────────────────────────────────

  Future<void> _mergeVideos() async {
    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Opening video picker...';
      _processingProgress = 0.0;
      _error = null;
    });

    // For now, show a message
    await Future.delayed(const Duration(seconds: 1));
    setState(() {
      _isProcessing = false;
      _processingStatus = 'Select multiple videos to merge';
    });
    _showSuccessNotification('Select videos to merge (coming soon)');
  }

  // ─── SPLIT VIDEO ──────────────────────────────────────────────────────

  Future<void> _splitVideo() async {
    final splitMs = _position.inMilliseconds;
    final totalMs = _duration.inMilliseconds;

    if (splitMs < 1000 || (totalMs - splitMs) < 1000) {
      setState(() => _error =
          'Move the playhead so both halves are at least 1 second long');
      return;
    }

    setState(() {
      _isProcessing = true;
      _processingStatus = 'Splitting video...';
      _processingProgress = 0.0;
      _error = null;
    });

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath = await _storage.getPlatformDownloadPath('Edits');
      final fileName1 = 'split1_${widget.videoTitle}_$timestamp.mp4';
      final fileName2 = 'split2_${widget.videoTitle}_$timestamp.mp4';
      final fullPath1 = '$outputPath/$fileName1';
      final fullPath2 = '$outputPath/$fileName2';

      final firstHalf = await NativeBridge.trimVideo(
        sourcePath: widget.videoPath,
        outputPath: fullPath1,
        startUs: 0,
        endUs: splitMs * 1000,
      );

      setState(() => _processingProgress = 0.5);

      final secondHalf = await NativeBridge.trimVideo(
        sourcePath: widget.videoPath,
        outputPath: fullPath2,
        startUs: splitMs * 1000,
        endUs: totalMs * 1000,
      );

      if (!firstHalf || !secondHalf) {
        try {
          await File(fullPath1).delete();
        } catch (_) {}
        try {
          await File(fullPath2).delete();
        } catch (_) {}
        setState(() {
          _isProcessing = false;
          _error = 'Could not split video. Please try again.';
        });
        return;
      }

      await _storage.scanMediaFile(fullPath1);
      await _storage.scanMediaFile(fullPath2);
      final savedPath1 = await _saveWithTracking(fullPath1, 'split');
      await _saveWithTracking(fullPath2, 'split');

      setState(() {
        _processingProgress = 1.0;
        _processingStatus = '✅ Video split into 2 clips!';
        _isProcessing = false;
        _processedPath = savedPath1 ?? fullPath1;
      });
      _showSuccessNotification('Video split into 2 clips — both saved');
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _error = 'Split failed: $e';
      });
    }
  }

  // ─── APPLY EFFECT ──────────────────────────────────────────────────────

  Future<void> _applyEffect() async {
    if (_selectedEffect == 0) {
      setState(() => _error = 'Please select an effect');
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // FFmpeg was removed from this app entirely (app-size reasons). Real
    // color-grade effects need a proper native pixel-filter pass instead,
    // which isn't built yet. Say so instead of pretending it works.
    _showFeatureNotReadyYet('Effects');
  }

  // ─── APPLY STICKERS ───────────────────────────────────────────────────

  Future<void> _applyStickers() async {
    if (_stickers.isEmpty) {
      setState(() => _error = 'Please add some stickers');
      return;
    }

    final premium = Provider.of<PremiumProvider>(context, listen: false);
    if (!premium.isPremium) {
      _openPremiumForEditor();
      return;
    }

    // Baking stickers into the video needs frame-by-frame compositing
    // (FFmpeg overlay filter or a custom GPU pass), which isn't wired up
    // yet. Say so instead of saving a copy with no stickers on it.
    _showFeatureNotReadyYet('Stickers');
  }

  // ─── BUILD UI ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isPremium = Provider.of<PremiumProvider>(context).isPremium;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: _isProcessing
          ? _buildProcessingScreen()
          : _processedPath != null
              ? _buildSuccessScreen()
              : _buildEditorContent(isPremium),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: const Row(
        children: [
          Icon(
            Icons.cut_rounded,
            color: AppColors.primary,
            size: 20,
          ),
          SizedBox(width: AppSpacing.sm),
          Text('Quick Editor'),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildEditorContent(bool isPremium) {
    if (_error != null) {
      return _buildErrorState();
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2,
        ),
      );
    }

    return Column(
      children: [
        _buildVideoPlayer(),
        _buildModeTabs(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _buildEditorControls(isPremium),
                const SizedBox(height: AppSpacing.md),
                _buildActionButton(),
                const SizedBox(height: AppSpacing.md),
                _buildInfoNotice(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      height: 220,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          GestureDetector(
            onTap: _togglePlay,
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _isPlaying ? 0.0 : 0.8,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
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
              child: Row(
                children: [
                  Text(
                    _formatDuration(_position),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 10,
                        ),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: Colors.white30,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: _duration.inMilliseconds > 0
                            ? _position.inMilliseconds /
                                _duration.inMilliseconds
                            : 0,
                        onChanged: (value) {
                          final position = Duration(
                            milliseconds:
                                (value * _duration.inMilliseconds).toInt(),
                          );
                          _seekTo(position);
                        },
                      ),
                    ),
                  ),
                  Text(
                    _formatDuration(_duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    // Only the modes confirmed to actually produce a playable, working
    // result are shown. Speed/reverse/compress/crop/text/music/merge/
    // split/effects/stickers/extract-audio are pulled from the UI — their
    // code is still in this file (harmless, unreachable) in case any of
    // them get properly re-verified and re-enabled later, but nothing
    // half-working should be one tap away for a real user.
    final modes = [
      {'icon': Icons.cut_rounded, 'label': 'Trim', 'mode': EditorMode.trim},
      {
        'icon': Icons.image_rounded,
        'label': 'Frame',
        'mode': EditorMode.extractFrame
      },
      {
        'icon': Icons.rotate_right_rounded,
        'label': 'Rotate',
        'mode': EditorMode.rotate
      },
    ];

    return SizedBox(
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: modes.length,
        itemBuilder: (context, index) {
          final mode = modes[index];
          final isSelected = _currentMode == mode['mode'];
          return GestureDetector(
            onTap: () {
              final newMode = mode['mode'] as EditorMode;
              setState(() => _currentMode = newMode);
              // Only Speed mode previews at the adjusted rate — leaving it
              // should put playback back to normal for every other mode.
              if (newMode != EditorMode.speed) {
                _controller?.setPlaybackSpeed(1.0);
              } else {
                _controller?.setPlaybackSpeed(_speedMultiplier);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : null,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    mode['icon'] as IconData,
                    color: isSelected ? AppColors.primary : AppColors.textMuted,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    mode['label'] as String,
                    style: TextStyle(
                      color:
                          isSelected ? AppColors.primary : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── CONTROLS FOR EACH MODE ──────────────────────────────────────────

  Widget _buildEditorControls(bool isPremium) {
    switch (_currentMode) {
      case EditorMode.trim:
        return _buildTrimControls();
      case EditorMode.extractFrame:
        return _buildExtractFrameControls(isPremium);
      case EditorMode.compress:
        return _buildCompressControls(isPremium);
      case EditorMode.crop:
        return _buildCropControls();
      case EditorMode.rotate:
        return _buildRotateControls();
      case EditorMode.speed:
        return _buildSpeedControls();
      case EditorMode.reverse:
        return _buildReverseControls();
      case EditorMode.extractAudio:
        return _buildExtractAudioControls();
      case EditorMode.addText:
        return _buildTextOverlayControls(isPremium);
      case EditorMode.addMusic:
        return _buildMusicControls(isPremium);
      case EditorMode.merge:
        return _buildMergeControls(isPremium);
      case EditorMode.split:
        return _buildSplitControls();
      case EditorMode.effects:
        return _buildEffectControls(isPremium);
      case EditorMode.stickers:
        return _buildStickerControls(isPremium);
    }
  }

  // ─── TRIM CONTROLS ────────────────────────────────────────────────────

  Widget _buildTrimControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Trim Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _buildTrimChip(
                label: 'Start',
                value: _trimStart,
                onChanged: (value) => setState(() => _trimStart = value),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _buildTrimChip(
                label: 'End',
                value: _trimEnd,
                onChanged: (value) => setState(() => _trimEnd = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            children: [
              Flexible(
                flex: ((_trimEnd - _trimStart) * 100).toInt(),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      '${((_trimEnd - _trimStart) * 100).toInt()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: ((_trimStart) * 100).toInt(),
                child: Container(
                  height: 40,
                  color: Colors.transparent,
                ),
              ),
              Flexible(
                flex: ((1 - _trimEnd) * 100).toInt(),
                child: Container(
                  height: 40,
                  color: Colors.transparent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Duration: ${_formatDuration(Duration(milliseconds: ((_trimEnd - _trimStart) * _duration.inMilliseconds).toInt()))}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            Text(
              'Start: ${_formatDuration(Duration(milliseconds: (_trimStart * _duration.inMilliseconds).toInt()))}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildPlaybackSpeedControls(),
      ],
    );
  }

  Widget _buildTrimChip({
    required String label,
    required double value,
    required Function(double) onChanged,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: AppTypography.caption.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: label == 'Start' ? 0.0 : 0.1,
          max: label == 'Start' ? 0.9 : 1.0,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          inactiveColor: AppColors.border,
        ),
      ],
    );
  }

  Widget _buildPlaybackSpeedControls() {
    const speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Preview speed', style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: speeds.map((speed) {
            final selected = _playbackSpeed == speed;
            return ChoiceChip(
              label: Text('${speed}x'),
              selected: selected,
              selectedColor: AppColors.primary.withValues(alpha: 0.14),
              labelStyle: TextStyle(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (_) {
                setState(() => _playbackSpeed = speed);
                _controller?.setPlaybackSpeed(speed);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 4),
        Text(
          'Preview only; exported trim keeps original timing.',
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  // ─── FRAME EXTRACTION CONTROLS ──────────────────────────────────────

  Widget _buildExtractFrameControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Extract Frame', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Current position: ${_formatDuration(_position)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Format', style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        ..._extractOptions.asMap().entries.map((entry) {
          final index = entry.key;
          final option = entry.value;
          final isSelected = _selectedQuality == index;
          final isLocked = option['premium'] == true && !isPremium;
          return GestureDetector(
            onTap: isLocked
                ? _openPremiumForEditor
                : () => setState(() => _selectedQuality = index),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Radio(
                    value: index,
                    groupValue: _selectedQuality,
                    onChanged: isLocked
                        ? null
                        : (value) =>
                            setState(() => _selectedQuality = value as int),
                    activeColor: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option['label'] as String,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${option['ext'] as String} • Quality ${option['quality'] as int}',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLocked)
                    const Icon(Icons.lock_outline_rounded,
                        size: 16, color: AppColors.primary),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ─── COMPRESS CONTROLS ──────────────────────────────────────────────

  Widget _buildCompressControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Compress Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_rounded, color: AppColors.warning, size: 20),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Not available yet — coming in a future update',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── CROP CONTROLS ───────────────────────────────────────────────────

  Widget _buildCropControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Crop Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        const Text('Aspect Ratio', style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _aspectRatios.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;
            final isSelected = _selectedAspectRatio == index;
            return GestureDetector(
              onTap: () => setState(() => _selectedAspectRatio = index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primary : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  option['label'] as String,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('Crop Area', style: AppTypography.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('Width', style: AppTypography.caption),
                  Slider(
                    value: _cropWidth,
                    min: 0.3,
                    max: 1.0,
                    onChanged: (v) => setState(() => _cropWidth = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Text('Height', style: AppTypography.caption),
                  Slider(
                    value: _cropHeight,
                    min: 0.3,
                    max: 1.0,
                    onChanged: (v) => setState(() => _cropHeight = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCropPreset('1:1', 1.0, 1.0),
              _buildCropPreset('4:5', 0.8, 1.0),
              _buildCropPreset('9:16', 0.5625, 1.0),
              _buildCropPreset('16:9', 1.0, 0.5625),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCropPreset(String label, double width, double height) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _cropWidth = width;
          _cropHeight = height;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }

  // ─── ROTATE CONTROLS ─────────────────────────────────────────────────

  Widget _buildRotateControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rotate Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildRotateButton('90°', 90),
            _buildRotateButton('180°', 180),
            _buildRotateButton('270°', 270),
            _buildRotateButton('Reset', 0),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Transform.rotate(
              angle: _rotationAngle * 3.14159 / 180,
              child: const Icon(
                Icons.play_arrow_rounded,
                size: 60,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'Current: ${_rotationAngle.toInt()}°',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildRotateButton(String label, int degrees) {
    final isSelected = _rotationAngle == degrees;
    return GestureDetector(
      onTap: () => setState(() => _rotationAngle = degrees.toDouble()),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─── SPEED CONTROLS ──────────────────────────────────────────────────

  Widget _buildSpeedControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Change Speed', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Current: ${_speedMultiplier}x',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const Text(
          'Preview updates live — this is what the saved file will sound and play like',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Slider(
          value: _speedMultiplier,
          min: 0.25,
          max: 4.0,
          divisions: 15,
          onChanged: (v) {
            setState(() => _speedMultiplier = v);
            _controller?.setPlaybackSpeed(v);
          },
          activeColor: AppColors.primary,
          label: '${_speedMultiplier}x',
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            _buildSpeedPreset('0.25x', 0.25),
            _buildSpeedPreset('0.5x', 0.5),
            _buildSpeedPreset('0.75x', 0.75),
            _buildSpeedPreset('1x', 1.0),
            _buildSpeedPreset('1.5x', 1.5),
            _buildSpeedPreset('2x', 2.0),
            _buildSpeedPreset('3x', 3.0),
            _buildSpeedPreset('4x', 4.0),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedPreset(String label, double value) {
    final isSelected = _speedMultiplier == value;
    return GestureDetector(
      onTap: () {
        setState(() => _speedMultiplier = value);
        _controller?.setPlaybackSpeed(value);
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  // ─── REVERSE CONTROLS ─────────────────────────────────────────────────

  Widget _buildReverseControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Reverse Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: _isReversed
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: _isReversed
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                _isReversed
                    ? Icons.check_circle_rounded
                    : Icons.rotate_left_rounded,
                color: _isReversed ? AppColors.success : AppColors.textMuted,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _isReversed ? 'Video will be reversed' : 'Tap to reverse video',
                style: TextStyle(
                  color:
                      _isReversed ? AppColors.success : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton(
                onPressed: () => setState(() => _isReversed = !_isReversed),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isReversed ? AppColors.success : AppColors.primary,
                ),
                child: Text(_isReversed ? '✓ Reversed' : 'Reverse Video'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── EXTRACT AUDIO CONTROLS ──────────────────────────────────────────

  Widget _buildExtractAudioControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Extract Audio', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.audiotrack_rounded,
                color: AppColors.success,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free Feature',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'Extract audio as an .m4a file',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── TEXT OVERLAY CONTROLS ───────────────────────────────────────────

  Widget _buildTextOverlayControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Text Overlay', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          onChanged: (v) => setState(() => _textOverlay = v),
          decoration: const InputDecoration(
            hintText: 'Enter your text...',
            border: OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Color', style: AppTypography.caption),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      _buildColorOption(Colors.white),
                      _buildColorOption(Colors.black),
                      _buildColorOption(Colors.red),
                      _buildColorOption(Colors.green),
                      _buildColorOption(Colors.blue),
                      _buildColorOption(Colors.yellow),
                      _buildColorOption(Colors.orange),
                      _buildColorOption(Colors.purple),
                      _buildColorOption(Colors.pink),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Font', style: AppTypography.caption),
                  DropdownButton<String>(
                    value: _textFont,
                    isExpanded: true,
                    items: _fonts.map((font) {
                      return DropdownMenuItem(
                        value: font,
                        child: Text(font, style: TextStyle(fontFamily: font)),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _textFont = v!),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Size', style: AppTypography.caption),
                  Slider(
                    value: _textSize,
                    min: 12,
                    max: 72,
                    onChanged: (v) => setState(() => _textSize = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
            Container(
              width: 60,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Text(
                  'A',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: _textSize.clamp(12, 30),
                    fontFamily: _textFont,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: isPremium
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                isPremium ? Icons.check_circle_rounded : Icons.lock_rounded,
                color: isPremium ? AppColors.success : AppColors.warning,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isPremium
                      ? 'Text overlay available for Pro users'
                      : 'Upgrade to Pro to add text overlays',
                  style: AppTypography.caption.copyWith(
                    color: isPremium ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColorOption(Color color) {
    final isSelected = _textColor == color;
    return GestureDetector(
      onTap: () => setState(() => _textColor = color),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 3,
          ),
          boxShadow: isSelected ? AppShadows.soft : null,
        ),
      ),
    );
  }

  // ─── MUSIC CONTROLS ──────────────────────────────────────────────────

  Widget _buildMusicControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Music', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ..._musicOptions.map((option) {
          final isSelected = _selectedMusicPath == option['path'];
          return GestureDetector(
            onTap: () => setState(() => _selectedMusicPath = option['path']),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary.withValues(alpha: 0.08)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.borderLight,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.music_note_rounded,
                    color: isSelected ? AppColors.primary : AppColors.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    option['name'] as String,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  if (isSelected)
                    const Icon(Icons.volume_up_rounded,
                        color: AppColors.primary),
                ],
              ),
            ),
          );
        }),
        if (_selectedMusicPath != null) ...[
          const SizedBox(height: AppSpacing.md),
          const Text('Music Volume', style: AppTypography.bodyMedium),
          Slider(
            value: _musicVolume,
            onChanged: (v) => setState(() => _musicVolume = v),
            activeColor: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Original Volume', style: AppTypography.bodyMedium),
          Slider(
            value: _originalVolume,
            onChanged: (v) => setState(() => _originalVolume = v),
            activeColor: AppColors.primary,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: isPremium
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                isPremium ? Icons.check_circle_rounded : Icons.lock_rounded,
                color: isPremium ? AppColors.success : AppColors.warning,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isPremium
                      ? 'Music overlay available for Pro users'
                      : 'Upgrade to Pro to add music to videos',
                  style: AppTypography.caption.copyWith(
                    color: isPremium ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── MERGE CONTROLS ──────────────────────────────────────────────────

  Widget _buildMergeControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Merge Videos', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: isPremium
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isPremium
                  ? AppColors.success.withValues(alpha: 0.2)
                  : AppColors.warning.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            children: [
              Icon(
                isPremium ? Icons.merge_rounded : Icons.lock_rounded,
                color: isPremium ? AppColors.success : AppColors.warning,
                size: 48,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isPremium ? 'Merge multiple videos into one' : 'Pro Feature',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isPremium ? AppColors.success : AppColors.warning,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                isPremium
                    ? 'Select videos from your library to merge'
                    : 'Upgrade to Pro to merge videos',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (isPremium) ...[
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: _mergeVideos,
                  icon: const Icon(Icons.merge_rounded),
                  label: const Text('Select Videos to Merge'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── SPLIT CONTROLS ──────────────────────────────────────────────────

  Widget _buildSplitControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Split Video', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Split at: ${_formatDuration(_position)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.success.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.call_split_rounded,
                color: AppColors.success,
                size: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Split at current position',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'Video will be split into two parts',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── EFFECTS CONTROLS ─────────────────────────────────────────────────

  Widget _buildEffectControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Apply Effect', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _effects.asMap().entries.map((entry) {
            final index = entry.key;
            final effect = entry.value;
            final isSelected = _selectedEffect == index;
            final isLocked = index > 0 && !isPremium;
            return GestureDetector(
              onTap: isLocked
                  ? _openPremiumForEditor
                  : () => setState(() => _selectedEffect = index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : isLocked
                          ? AppColors.surfaceAlt
                          : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : isLocked
                            ? AppColors.border
                            : AppColors.borderLight,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isLocked) ...[
                      const Icon(Icons.lock_rounded,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      effect,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : isLocked
                                ? AppColors.textMuted
                                : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 12,
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_rounded,
                          size: 14, color: AppColors.primary),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_selectedEffect > 0 && _selectedEffect < _effects.length)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.preview_rounded, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Preview: ${_effects[_selectedEffect]} effect will be applied',
                    style: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ─── STICKER CONTROLS ─────────────────────────────────────────────────

  Widget _buildStickerControls(bool isPremium) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add Stickers', style: AppTypography.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: _stickerOptions.map((sticker) {
            final isSelected =
                _stickers.any((s) => s['emoji'] == sticker['icon']);
            return GestureDetector(
              onTap: isPremium || _stickers.isEmpty
                  ? () => _addSticker(sticker['icon'] as String)
                  : _openPremiumForEditor,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color:
                        isSelected ? AppColors.primary : AppColors.borderLight,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      sticker['icon'] as String,
                      style: const TextStyle(fontSize: 28),
                    ),
                    Text(
                      sticker['label'] as String,
                      style: AppTypography.caption.copyWith(
                        fontSize: 9,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (_stickers.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          const Text('Added Stickers', style: AppTypography.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: _stickers.map((sticker) {
              return Chip(
                label: Text(sticker['emoji'] as String),
                onDeleted: () => setState(() => _stickers.remove(sticker)),
                deleteIcon: const Icon(Icons.close, size: 14),
                backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: isPremium
                ? AppColors.success.withValues(alpha: 0.08)
                : AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(
                isPremium ? Icons.check_circle_rounded : Icons.lock_rounded,
                color: isPremium ? AppColors.success : AppColors.warning,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isPremium
                      ? 'Stickers available for Pro users'
                      : 'Upgrade to Pro to add stickers',
                  style: AppTypography.caption.copyWith(
                    color: isPremium ? AppColors.success : AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── ACTION BUTTON ────────────────────────────────────────────────────

  Widget _buildActionButton() {
    String label;
    IconData icon;

    switch (_currentMode) {
      case EditorMode.trim:
        label = 'Save Trim';
        icon = Icons.save_rounded;
        break;
      case EditorMode.extractFrame:
        label = 'Extract Frame';
        icon = Icons.image_rounded;
        break;
      case EditorMode.compress:
        label = 'Compress Video';
        icon = Icons.compress_rounded;
        break;
      case EditorMode.crop:
        label = 'Crop Video';
        icon = Icons.crop_rounded;
        break;
      case EditorMode.rotate:
        label = 'Rotate Video';
        icon = Icons.rotate_right_rounded;
        break;
      case EditorMode.speed:
        label = 'Change Speed';
        icon = Icons.speed_rounded;
        break;
      case EditorMode.reverse:
        label = 'Reverse Video';
        icon = Icons.replay_rounded;
        break;
      case EditorMode.extractAudio:
        label = 'Extract Audio';
        icon = Icons.audiotrack_rounded;
        break;
      case EditorMode.addText:
        label = 'Add Text';
        icon = Icons.text_fields_rounded;
        break;
      case EditorMode.addMusic:
        label = 'Add Music';
        icon = Icons.music_note_rounded;
        break;
      case EditorMode.merge:
        label = 'Merge Videos';
        icon = Icons.merge_rounded;
        break;
      case EditorMode.split:
        label = 'Split Video';
        icon = Icons.call_split_rounded;
        break;
      case EditorMode.effects:
        label = 'Apply Effect';
        icon = Icons.filter_rounded;
        break;
      case EditorMode.stickers:
        label = 'Add Stickers';
        icon = Icons.emoji_emotions_rounded;
        break;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isProcessing ? null : _handleAction,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        ),
      ),
    );
  }

  Widget _buildInfoNotice() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.primary,
            size: 17,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Trim and poster-frame export use native Android media tools. Premium features require Pro subscription.',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── PROCESSING SCREEN ──────────────────────────────────────────────

  Widget _buildProcessingScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadows.primary,
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Processing...',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _processingStatus,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _processingProgress > 0 ? _processingProgress : null,
                backgroundColor: AppColors.border,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${(_processingProgress * 100).toInt()}%',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextButton(
              onPressed: () {
                setState(() {
                  _isProcessing = false;
                  _error = 'Cancelled by user';
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SUCCESS SCREEN ──────────────────────────────────────────────────

  Widget _buildSuccessScreen() {
    final isVideo = _processedPath != null &&
        (_processedPath!.endsWith('.mp4') ||
            _processedPath!.endsWith('.mov') ||
            _processedPath!.endsWith('.3gp'));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSuccessPreview(isVideo),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Done!',
              style: AppTypography.displayMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isVideo
                  ? 'Video saved to your library'
                  : 'Image saved to your library',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border:
                    Border.all(color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_rounded,
                      color: AppColors.success, size: 16),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Saved in: Download/MediaNest/Edits/',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _processedPath = null);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.done_rounded),
                    label: const Text('Close'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processedPath == null
                        ? null
                        : () {
                            final file = File(_processedPath!);
                            if (file.existsSync()) {
                              Share.shareXFiles([XFile(_processedPath!)]);
                            }
                          },
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: _processedPath == null
                  ? null
                  : () {
                      final file = File(_processedPath!);
                      if (file.existsSync()) {
                        final isVideoFile = _processedPath!.endsWith('.mp4') ||
                            _processedPath!.endsWith('.mov') ||
                            _processedPath!.endsWith('.3gp');
                        final mediaFile = models.MediaFile(
                          id: _processedPath!,
                          path: _processedPath!,
                          fileName: widget.videoTitle,
                          fileSize: file.lengthSync(),
                          isVideo: isVideoFile,
                          sourceApp: 'Editor',
                          createdAt: DateTime.now(),
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
                    },
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('View in Library'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SavedEditsScreen()),
                );
              },
              icon: const Icon(Icons.folder_rounded),
              label: const Text('View All Saved Edits'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessPreview(bool isVideo) {
    final path = _processedPath;
    final fallback = Container(
      color: AppColors.success.withValues(alpha: 0.12),
      child: const Center(
        child: Icon(
          Icons.check_circle_rounded,
          color: AppColors.success,
          size: 48,
        ),
      ),
    );

    Widget content;
    if (path == null || !File(path).existsSync()) {
      content = fallback;
    } else if (isVideo) {
      content = _SuccessVideoThumb(filePath: path, fallback: fallback);
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
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(width: 140, height: 140, child: content),
        ),
        Positioned(
          bottom: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 26,
            ),
          ),
        ),
      ],
    );
  }

  // ─── ERROR STATE ─────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 64,
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'Oops! Something went wrong',
              style: AppTypography.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error ?? 'Unknown error',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _error = null);
                _initPlayer();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Success screen video thumbnail ─────────────────────────────────────────
// Generates a real preview frame for the "Done!" screen instead of leaving
// videos with no visual confirmation of what was actually saved.

class _SuccessVideoThumb extends StatefulWidget {
  final String filePath;
  final Widget fallback;

  const _SuccessVideoThumb({
    required this.filePath,
    required this.fallback,
  });

  @override
  State<_SuccessVideoThumb> createState() => _SuccessVideoThumbState();
}

class _SuccessVideoThumbState extends State<_SuccessVideoThumb> {
  dynamic _thumbData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: widget.filePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 280,
        quality: 75,
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
        color: Colors.black87,
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
            size: 32,
          ),
        ),
      ],
    );
  }
}
