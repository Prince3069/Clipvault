// ui/widgets/media_viewer_screen.dart — Complete rewrite with premium player UI
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../models/media_file.dart';
import '../themes/app_theme.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MediaFile> mediaFiles;
  final int initialIndex;

  const MediaViewerScreen({
    Key? key,
    required this.mediaFiles,
    required this.initialIndex,
  }) : super(key: key);

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showUI = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
    if (_showUI) _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showUI = false);
    });
  }

  MediaFile get _current => widget.mediaFiles[_currentIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleUI,
        child: Stack(children: [
          // Main content — page swipe between files
          PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaFiles.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (_, i) => _buildPage(widget.mediaFiles[i]),
          ),

          // Top bar — back + title + share
          AnimatedSlide(
            offset: _showUI ? Offset.zero : const Offset(0, -1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded,
                            color: Colors.white, size: 20),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          _current.fileName.length > 30
                              ? '${_current.fileName.substring(0, 28)}...'
                              : _current.fileName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.mediaFiles.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.mediaFiles.length}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.share_rounded,
                            color: Colors.white, size: 22),
                        onPressed: () =>
                            Share.shareXFiles([XFile(_current.path)]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildPage(MediaFile file) {
    if (!File(file.path).existsSync()) {
      return _errorWidget('File not found.\nIt may have been deleted.');
    }
    try {
      final size = File(file.path).lengthSync();
      if (size < 512) {
        return _errorWidget('File appears corrupt.\nPlease download again.');
      }
    } catch (_) {}

    if (file.isVideo) {
      return _VideoPlayer(
        filePath: file.path,
        onTap: _toggleUI,
        showControls: _showUI,
        onControlsActivity: _startHideTimer,
      );
    }

    return GestureDetector(
      onTap: _toggleUI,
      child: InteractiveViewer(
        child: Center(
          child: Image.file(
            File(file.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _errorWidget('Cannot load image.'),
          ),
        ),
      ),
    );
  }

  Widget _errorWidget(String msg) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.broken_image_outlined,
            size: 72, color: Colors.white30),
        const SizedBox(height: 20),
        Text(msg,
            style: const TextStyle(
                color: Colors.white54, fontSize: 14, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white38),
          label: const Text('Go back', style: TextStyle(color: Colors.white38)),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// VIDEO PLAYER — Full featured with time display, seek, loop, speed
// ═══════════════════════════════════════════════════════════════════════════════

class _VideoPlayer extends StatefulWidget {
  final String filePath;
  final VoidCallback? onTap;
  final bool showControls;
  final VoidCallback? onControlsActivity;

  const _VideoPlayer({
    required this.filePath,
    this.onTap,
    required this.showControls,
    this.onControlsActivity,
  });

  @override
  State<_VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<_VideoPlayer>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _hasError = false;
  String _errorMsg = '';
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  bool _isSeeking = false;
  late AnimationController _playPulse;

  @override
  void initState() {
    super.initState();
    _playPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _initVideo();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _playPulse.dispose();
    super.dispose();
  }

  Future<void> _initVideo() async {
    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        setState(() {
          _hasError = true;
          _errorMsg = 'File not found';
        });
        return;
      }
      final size = await file.length();
      if (size < 1024) {
        setState(() {
          _hasError = true;
          _errorMsg = 'File is corrupt (${size}B)';
        });
        return;
      }

      _ctrl = VideoPlayerController.file(file);
      _ctrl!.addListener(() {
        if (mounted) setState(() {});
      });
      await _ctrl!.initialize().timeout(const Duration(seconds: 20));
      await _ctrl!.play();
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      print('Video init: $e');
      if (mounted)
        setState(() {
          _hasError = true;
          _errorMsg = 'Cannot play this video.\nFormat may not be supported.';
        });
    }
  }

  void _togglePlay() {
    if (_ctrl == null || !_initialized) return;
    if (_ctrl!.value.isPlaying) {
      _ctrl!.pause();
    } else {
      _ctrl!.play();
    }
    _playPulse.forward(from: 0);
    widget.onControlsActivity?.call();
  }

  void _toggleLoop() {
    setState(() => _isLooping = !_isLooping);
    _ctrl?.setLooping(_isLooping);
    widget.onControlsActivity?.call();
  }

  void _setSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _ctrl?.setPlaybackSpeed(speed);
    widget.onControlsActivity?.call();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.videocam_off_rounded,
              size: 72, color: Colors.white30),
          const SizedBox(height: 20),
          Text(_errorMsg,
              style: const TextStyle(
                  color: Colors.white54, fontSize: 14, height: 1.5),
              textAlign: TextAlign.center),
        ]),
      );
    }

    if (!_initialized) {
      return const Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2.5)),
          SizedBox(height: 16),
          Text('Loading...',
              style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ));
    }

    final ctrl = _ctrl!;
    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final isPlaying = ctrl.value.isPlaying;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Stack(fit: StackFit.expand, children: [
      // ── Video ─────────────────────────────────────────────────────────────
      GestureDetector(
        onTap: () {
          _togglePlay();
          widget.onTap?.call();
        },
        child: Center(
          child: AspectRatio(
            aspectRatio:
                ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : 16 / 9,
            child: VideoPlayer(ctrl),
          ),
        ),
      ),

      // ── Centre play/pause pulse ───────────────────────────────────────────
      if (!isPlaying || widget.showControls)
        GestureDetector(
          onTap: () {
            _togglePlay();
            widget.onTap?.call();
          },
          child: Center(
            child: AnimatedScale(
              scale: isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 46),
              ),
            ),
          ),
        ),

      // ── Bottom controls ───────────────────────────────────────────────────
      AnimatedSlide(
        offset: widget.showControls ? Offset.zero : const Offset(0, 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: widget.showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.black.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
              padding: EdgeInsets.fromLTRB(
                  16, 24, 16, MediaQuery.of(context).padding.bottom + 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ── Seek bar ────────────────────────────────────────────────
                Row(children: [
                  Text(_fmt(position),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 7),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 14),
                          trackHeight: 3.5,
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white24,
                        ),
                        child: Slider(
                          value: _isSeeking ? null ?? progress : progress,
                          onChangeStart: (_) {
                            setState(() => _isSeeking = true);
                            _ctrl?.pause();
                          },
                          onChanged: (v) {
                            setState(() {});
                            final newPos = Duration(
                                milliseconds:
                                    (v * duration.inMilliseconds).toInt());
                            _ctrl?.seekTo(newPos);
                            widget.onControlsActivity?.call();
                          },
                          onChangeEnd: (v) {
                            setState(() => _isSeeking = false);
                            _ctrl?.play();
                          },
                        ),
                      ),
                    ),
                  ),
                  Text(_fmt(duration),
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11)),
                ]),

                const SizedBox(height: 8),

                // ── Action row ──────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Loop toggle
                    _ControlBtn(
                      icon: _isLooping
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      color: _isLooping ? AppColors.primary : Colors.white54,
                      onTap: _toggleLoop,
                      label: 'Loop',
                    ),

                    // Rewind 10s
                    _ControlBtn(
                      icon: Icons.replay_10_rounded,
                      onTap: () {
                        final newPos = position - const Duration(seconds: 10);
                        _ctrl?.seekTo(
                            newPos < Duration.zero ? Duration.zero : newPos);
                        widget.onControlsActivity?.call();
                      },
                    ),

                    // Play/pause (large)
                    GestureDetector(
                      onTap: _togglePlay,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),

                    // Forward 10s
                    _ControlBtn(
                      icon: Icons.forward_10_rounded,
                      onTap: () {
                        final newPos = position + const Duration(seconds: 10);
                        _ctrl?.seekTo(newPos > duration ? duration : newPos);
                        widget.onControlsActivity?.call();
                      },
                    ),

                    // Speed
                    _SpeedButton(
                      speed: _playbackSpeed,
                      onSpeed: _setSpeed,
                    ),
                  ],
                ),
              ]),
            ),
          ),
        ),
      ),

      // ── Buffering indicator ───────────────────────────────────────────────
      if (_initialized && ctrl.value.isBuffering && !ctrl.value.isPlaying)
        const Center(
            child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                    color: Colors.white54, strokeWidth: 2))),
    ]);
  }
}

// ── Small reusable control button ─────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? label;

  const _ControlBtn({
    required this.icon,
    required this.onTap,
    this.color = Colors.white,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        if (label != null) ...[
          const SizedBox(height: 4),
          Text(label!,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w500)),
        ],
      ]),
    );
  }
}

// ── Playback speed button ─────────────────────────────────────────────────────

class _SpeedButton extends StatelessWidget {
  final double speed;
  final void Function(double) onSpeed;

  const _SpeedButton({required this.speed, required this.onSpeed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
        final idx = speeds.indexOf(speed);
        final next = speeds[(idx + 1) % speeds.length];
        onSpeed(next);
      },
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: speed != 1.0
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              speed == 1.0
                  ? '1×'
                  : speed == 1.25
                      ? '1.25×'
                      : speed == 1.5
                          ? '1.5×'
                          : speed == 2.0
                              ? '2×'
                              : speed == 0.75
                                  ? '0.75×'
                                  : '0.5×',
              style: TextStyle(
                color: speed != 1.0 ? AppColors.primary : Colors.white,
                fontSize: speed >= 1.25 ? 9 : 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Speed',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 9,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
