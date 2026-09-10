// ui/widgets/whatsapp_media_viewer.dart - Direct playable viewer
// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/media_file.dart';

class WhatsAppMediaViewer extends StatefulWidget {
  final MediaFile mediaFile;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;

  const WhatsAppMediaViewer({
    Key? key,
    required this.mediaFile,
    this.onDownload,
    this.onShare,
  }) : super(key: key);

  @override
  State<WhatsAppMediaViewer> createState() => _WhatsAppMediaViewerState();
}

class _WhatsAppMediaViewerState extends State<WhatsAppMediaViewer> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    if (widget.mediaFile.isVideo && widget.mediaFile.exists) {
      _initializeVideoPlayer();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideoPlayer() async {
    try {
      _videoController =
          VideoPlayerController.file(File(widget.mediaFile.path));
      await _videoController!.initialize();

      setState(() {
        _isVideoInitialized = true;
      });

      // Listen to video state changes
      _videoController!.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _videoController!.value.isPlaying;
          });
        }
      });
    } catch (e) {
      print('Error initializing video player: $e');
    }
  }

  void _togglePlayPause() {
    if (_videoController != null && _isVideoInitialized) {
      setState(() {
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _showControls
          ? AppBar(
              backgroundColor: Colors.black.withValues(alpha: 0.7),
              foregroundColor: Colors.white,
              title: Text(
                widget.mediaFile.fileName,
                style: const TextStyle(fontSize: 16),
              ),
              actions: [
                if (widget.onShare != null)
                  IconButton(
                    icon: const Icon(Icons.share),
                    onPressed: widget.onShare,
                  ),
                if (widget.onDownload != null)
                  IconButton(
                    icon: Icon(
                      widget.mediaFile.isDownloaded
                          ? Icons.download_done
                          : Icons.download,
                    ),
                    onPressed: widget.onDownload,
                  ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: widget.mediaFile.isVideo ? _toggleControls : null,
        child: Center(
          child: _buildMediaContent(),
        ),
      ),
      bottomSheet:
          _showControls && widget.mediaFile.isVideo && _isVideoInitialized
              ? _buildVideoControls()
              : null,
    );
  }

  Widget _buildMediaContent() {
    if (!widget.mediaFile.exists) {
      return _buildErrorView('File not found');
    }

    if (widget.mediaFile.isVideo) {
      return _buildVideoPlayer();
    } else {
      return _buildImageViewer();
    }
  }

  Widget _buildVideoPlayer() {
    if (!_isVideoInitialized) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 16),
          Text(
            'Loading video...',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),

        // Play/Pause overlay
        if (_showControls && !_isPlaying)
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              iconSize: 64,
              icon: const Icon(
                Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _togglePlayPause,
            ),
          ),
      ],
    );
  }

  Widget _buildImageViewer() {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Image.file(
        File(widget.mediaFile.path),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorView('Could not load image');
        },
      ),
    );
  }

  Widget _buildErrorView(String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          widget.mediaFile.isVideo
              ? Icons.broken_image
              : Icons.image_not_supported,
          size: 80,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.mediaFile.fileName,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildVideoControls() {
    if (_videoController == null || !_isVideoInitialized) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          VideoProgressIndicator(
            _videoController!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Colors.white,
              bufferedColor: Colors.grey,
              backgroundColor: Colors.black54,
            ),
          ),

          const SizedBox(height: 16),

          // Control buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Seek backward
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () {
                  final currentPosition = _videoController!.value.position;
                  final newPosition =
                      currentPosition - const Duration(seconds: 10);
                  _videoController!.seekTo(
                    newPosition < Duration.zero ? Duration.zero : newPosition,
                  );
                },
              ),

              // Play/Pause
              IconButton(
                iconSize: 48,
                icon: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: _togglePlayPause,
              ),

              // Seek forward
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () {
                  final currentPosition = _videoController!.value.position;
                  final duration = _videoController!.value.duration;
                  final newPosition =
                      currentPosition + const Duration(seconds: 10);
                  _videoController!.seekTo(
                    newPosition > duration ? duration : newPosition,
                  );
                },
              ),
            ],
          ),

          // Time display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_videoController!.value.position),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              Text(
                _formatDuration(_videoController!.value.duration),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
}

// Updated WhatsApp Status Screen to use direct viewer
class WhatsAppStatusItem extends StatelessWidget {
  final MediaFile mediaFile;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onMoreOptions;

  const WhatsAppStatusItem({
    Key? key,
    required this.mediaFile,
    this.onDownload,
    this.onShare,
    this.onMoreOptions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openDirectViewer(context),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Media preview
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    _buildMediaPreview(),

                    // Play icon for videos
                    if (mediaFile.isVideo)
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 32,
                            color: Colors.white,
                          ),
                        ),
                      ),

                    // Duration badge for videos
                    if (mediaFile.isVideo && mediaFile.duration != null)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            mediaFile.formattedDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                    // Download status
                    if (mediaFile.isDownloaded)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.download_done,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // File info and actions
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mediaFile.fileName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        mediaFile.isVideo ? Icons.videocam : Icons.image,
                        size: 12,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        mediaFile.formattedSize,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _getTimeAgo(mediaFile.createdAt),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onDownload,
                          icon: Icon(
                            mediaFile.isDownloaded
                                ? Icons.download_done
                                : Icons.download,
                            size: 14,
                          ),
                          label: Text(
                            mediaFile.isDownloaded ? 'Saved' : 'Save',
                            style: const TextStyle(fontSize: 11),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            backgroundColor: mediaFile.isDownloaded
                                ? Colors.green
                                : Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onMoreOptions,
                        icon: const Icon(Icons.more_vert, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (!mediaFile.exists) {
      return _buildPlaceholder();
    }

    if (mediaFile.isVideo) {
      // For videos, show thumbnail or first frame
      return FutureBuilder<Widget>(
        future: _getVideoThumbnail(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return snapshot.data!;
          }
          return _buildPlaceholder();
        },
      );
    } else {
      // For images, show directly
      return Image.file(
        File(mediaFile.path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
  }

  Future<Widget> _getVideoThumbnail() async {
    try {
      // Try to get video thumbnail
      final controller = VideoPlayerController.file(File(mediaFile.path));
      await controller.initialize();

      // Create a widget that shows the first frame
      final thumbnail = AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );

      controller.dispose();
      return thumbnail;
    } catch (e) {
      return _buildPlaceholder();
    }
  }

  Widget _buildPlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.grey[300],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              mediaFile.isVideo ? Icons.movie_outlined : Icons.image_outlined,
              size: 40,
              color: Colors.grey[600],
            ),
            const SizedBox(height: 8),
            Text(
              mediaFile.exists ? 'Loading...' : 'File not found',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDirectViewer(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WhatsAppMediaViewer(
          mediaFile: mediaFile,
          onDownload: onDownload,
          onShare: onShare,
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.day}/${dateTime.month}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}
