// ui/widgets/video_thumbnail_widget.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class VideoThumbnailWidget extends StatefulWidget {
  final String videoPath;
  final double width;
  final double height;

  const VideoThumbnailWidget({
    Key? key,
    required this.videoPath,
    required this.width,
    required this.height,
  }) : super(key: key);

  @override
  State<VideoThumbnailWidget> createState() => _VideoThumbnailWidgetState();
}

class _VideoThumbnailWidgetState extends State<VideoThumbnailWidget> {
  String? _thumbnailPath;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _generateThumbnail();
  }

  Future<void> _generateThumbnail() async {
    try {
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoPath,
        imageFormat: ImageFormat.JPEG,
        maxHeight: 200,
        quality: 75,
      );

      if (mounted) {
        setState(() {
          _thumbnailPath = thumbnailPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black87,
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );
    }

    if (_thumbnailPath != null && File(_thumbnailPath!).existsSync()) {
      return Image.file(
        File(_thumbnailPath!),
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      color: Colors.black87,
      child: const Center(
        child: Icon(
          Icons.movie,
          size: 40,
          color: Colors.white70,
        ),
      ),
    );
  }
}
