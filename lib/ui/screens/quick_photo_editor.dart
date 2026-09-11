import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../services/storage_service.dart';
import '../themes/app_theme.dart';

/// Rotates and re-encodes an image file. Runs via compute() in its own
/// isolate — decoding/encoding a full-resolution photo on the UI thread
/// would freeze the app for a moment on anything but a tiny image.
/// Top-level (not a method) because compute() requires that.
Future<bool> _rotateAndSaveImage(_RotateJob job) async {
  try {
    final bytes = await File(job.sourcePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return false;

    final rotated = img.copyRotate(decoded, angle: job.degrees);

    final ext = job.destPath.split('.').last.toLowerCase();
    final encoded = ext == 'png'
        ? img.encodePng(rotated)
        : img.encodeJpg(rotated, quality: 92);

    await File(job.destPath).writeAsBytes(encoded);
    return true;
  } catch (_) {
    return false;
  }
}

class _RotateJob {
  final String sourcePath;
  final String destPath;
  final int degrees;
  const _RotateJob(this.sourcePath, this.destPath, this.degrees);
}

/// Lightweight, reliable photo destination for the shared media picker.
/// Video-only operations remain in QuickClipEditor.
class QuickPhotoEditor extends StatefulWidget {
  final String imagePath;
  final String imageTitle;

  const QuickPhotoEditor({
    Key? key,
    required this.imagePath,
    required this.imageTitle,
  }) : super(key: key);

  @override
  State<QuickPhotoEditor> createState() => _QuickPhotoEditorState();
}

class _QuickPhotoEditorState extends State<QuickPhotoEditor> {
  final StorageService _storage = StorageService();
  bool _saving = false;
  double _rotation = 0;

  Future<void> _saveCopy() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final source = File(widget.imagePath);
      if (!await source.exists())
        throw 'The selected photo is no longer available.';
      final folder = await _storage.getPlatformDownloadPath('Edits');
      final safeName =
          widget.imageTitle.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final path =
          '$folder/edit_${DateTime.now().millisecondsSinceEpoch}_$safeName';

      var rotationApplied = true;
      if (_rotation == 0) {
        // Nothing to bake in — a plain byte copy is correct and fast.
        await source.copy(path);
      } else {
        final ok = await compute(
          _rotateAndSaveImage,
          _RotateJob(source.path, path, _rotation.round()),
        );
        if (!ok) {
          // Decoding/encoding failed (corrupt file, unsupported format,
          // etc.) — save the unrotated original rather than fail outright,
          // but say plainly that the rotation didn't make it in.
          rotationApplied = false;
          await source.copy(path);
        }
      }

      await _storage.scanMediaFile(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          rotationApplied
              ? 'Photo saved to your Edits folder.'
              : 'Saved, but the rotation could not be applied — original orientation was kept.',
        ),
        backgroundColor:
            rotationApplied ? AppColors.success : AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not save photo: $e'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(widget.imagePath);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Quick Photo'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Rotate',
            onPressed: () => setState(() => _rotation = (_rotation + 90) % 360),
            icon: const Icon(Icons.rotate_right_rounded),
          ),
          IconButton(
            tooltip: 'Save copy',
            onPressed: _saving ? null : _saveCopy,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Center(
        child: file.existsSync()
            ? RotatedBox(
                quarterTurns: (_rotation ~/ 90).toInt(),
                child: InteractiveViewer(
                  minScale: .5,
                  maxScale: 4,
                  child: Image.file(file, fit: BoxFit.contain),
                ),
              )
            : const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This photo is no longer available on the device.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveCopy,
            icon: const Icon(Icons.save_alt_rounded),
            label: Text(_saving ? 'Saving…' : 'Save edited copy'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}
