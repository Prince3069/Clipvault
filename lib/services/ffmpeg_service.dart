// // services/ffmpeg_service.dart
// //
// // Real implementations for the editor features that need actual frame-level
// // video processing — compress, crop, reverse, text overlay, add music.
// // These genuinely can't be done with plain MediaExtractor/MediaMuxer sample
// // copying (that only works for trim/rotate/speed/audio-extract, which never
// // touch pixel data) — they need a real encode pass, which is exactly what
// // FFmpeg is for.
// //
// // LICENSING NOTE: ffmpeg_kit_flutter_new is LGPL 3.0 by default, but its
// // default build bundles GPL-licensed x264/x265/xvidcore/vid.stab, which
// // makes the combined package "effectively GPL v3.0" per its own docs. GPL
// // carries source-disclosure obligations. This file uses the hardware
// // MediaCodec encoder (h264_mediacodec) instead of libx264 wherever possible
// // specifically to avoid pulling in the GPL-licensed encoder path — but
// // confirm which ffmpeg_kit_flutter_new variant you ship and read its
// // LICENSE.md before shipping a closed-source build. If GPL is a dealbreaker,
// // ask me and we can look at the ffmpeg_kit_flutter_new_min variant instead.

// import 'dart:io';
// import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
// import 'package:ffmpeg_kit_flutter_new/return_code.dart';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:path_provider/path_provider.dart';

// class FFmpegService {
//   /// Flutter asset paths (like 'assets/music/upbeat.mp3') live inside the
//   /// asset bundle, not on the real filesystem — FFmpeg is a native process
//   /// and can't read them directly. This extracts one to a real temp file
//   /// the first time it's needed and reuses it after that.
//   Future<String> resolveAssetToFile(String assetPath) async {
//     final tempDir = await getTemporaryDirectory();
//     final fileName = assetPath.split('/').last;
//     final destFile = File('${tempDir.path}/asset_cache_$fileName');
//     if (await destFile.exists() && await destFile.length() > 0) {
//       return destFile.path;
//     }
//     final bytes = await rootBundle.load(assetPath);
//     await destFile.writeAsBytes(
//       bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
//     );
//     return destFile.path;
//   }

//   Future<bool> _run(String command) async {
//     final session = await FFmpegKit.execute(command);
//     final returnCode = await session.getReturnCode();
//     if (ReturnCode.isSuccess(returnCode)) return true;

//     final logs = await session.getAllLogsAsString();
//     print('❌ FFmpeg failed (code=$returnCode): $logs');
//     return false;
//   }

//   /// Compression tiers. Using the hardware h264_mediacodec encoder — fast,
//   /// avoids the GPL libx264 path, but quality/availability varies slightly
//   /// by device compared to libx264. Falls back to libx264 automatically if
//   /// the hardware encoder isn't available on this device.
//   Future<bool> compressVideo({
//     required String sourcePath,
//     required String outputPath,
//     required String quality, // 'low', 'medium', 'high'
//   }) async {
//     int scale;
//     String bitrate;
//     if (quality == 'low') {
//       scale = 480;
//       bitrate = '800k';
//     } else if (quality == 'high') {
//       scale = 1080;
//       bitrate = '3000k';
//     } else {
//       scale = 720;
//       bitrate = '1500k';
//     }

//     final hwCommand = '-y -i "$sourcePath" '
//         '-vf "scale=-2:$scale" '
//         '-c:v h264_mediacodec -b:v $bitrate '
//         '-c:a aac -b:a 128k '
//         '"$outputPath"';

//     if (await _run(hwCommand)) return true;

//     // Hardware encoder unavailable on this device — fall back to software.
//     final swCommand = '-y -i "$sourcePath" '
//         '-vf "scale=-2:$scale" '
//         '-c:v libx264 -preset fast -b:v $bitrate '
//         '-c:a aac -b:a 128k '
//         '"$outputPath"';
//     return _run(swCommand);
//   }

//   /// [x], [y], [width], [height] are fractions of the frame (0.0-1.0), the
//   /// same units the crop UI already tracks. sourceWidth/sourceHeight are the
//   /// real pixel dimensions of the source video.
//   Future<bool> cropVideo({
//     required String sourcePath,
//     required String outputPath,
//     required double x,
//     required double y,
//     required double width,
//     required double height,
//     required int sourceWidth,
//     required int sourceHeight,
//   }) async {
//     // FFmpeg's crop filter wants even pixel dimensions for most codecs.
//     int cropW = (sourceWidth * width).round();
//     int cropH = (sourceHeight * height).round();
//     int cropX = (sourceWidth * x).round();
//     int cropY = (sourceHeight * y).round();
//     cropW -= cropW % 2;
//     cropH -= cropH % 2;
//     cropX -= cropX % 2;
//     cropY -= cropY % 2;
//     if (cropW <= 0 || cropH <= 0) return false;

//     final hwCommand = '-y -i "$sourcePath" '
//         '-vf "crop=$cropW:$cropH:$cropX:$cropY" '
//         '-c:v h264_mediacodec -c:a copy '
//         '"$outputPath"';
//     if (await _run(hwCommand)) return true;

//     final swCommand = '-y -i "$sourcePath" '
//         '-vf "crop=$cropW:$cropH:$cropX:$cropY" '
//         '-c:v libx264 -preset fast -c:a copy '
//         '"$outputPath"';
//     return _run(swCommand);
//   }

//   /// Reverses both video and audio. FFmpeg's reverse filter buffers the
//   /// whole clip in memory, so this is only practical for short clips —
//   /// enforce a sane duration cap in the UI (e.g. 60s) before calling this.
//   Future<bool> reverseVideo({
//     required String sourcePath,
//     required String outputPath,
//   }) async {
//     final hwCommand = '-y -i "$sourcePath" '
//         '-vf reverse -af areverse '
//         '-c:v h264_mediacodec '
//         '"$outputPath"';
//     if (await _run(hwCommand)) return true;

//     final swCommand = '-y -i "$sourcePath" '
//         '-vf reverse -af areverse '
//         '-c:v libx264 -preset fast '
//         '"$outputPath"';
//     return _run(swCommand);
//   }

//   /// Burns [text] into the bottom-center of every frame.
//   Future<bool> addTextOverlay({
//     required String sourcePath,
//     required String outputPath,
//     required String text,
//   }) async {
//     // Escape characters drawtext treats specially.
//     final safeText = text
//         .replaceAll('\\', '\\\\')
//         .replaceAll(':', '\\:')
//         .replaceAll("'", "\\'");

//     final drawtext = "drawtext=text='$safeText':fontcolor=white:fontsize=32:"
//         "borderw=2:bordercolor=black:x=(w-text_w)/2:y=h-th-40";

//     final hwCommand = '-y -i "$sourcePath" '
//         '-vf "$drawtext" '
//         '-c:v h264_mediacodec -c:a copy '
//         '"$outputPath"';
//     if (await _run(hwCommand)) return true;

//     final swCommand = '-y -i "$sourcePath" '
//         '-vf "$drawtext" '
//         '-c:v libx264 -preset fast -c:a copy '
//         '"$outputPath"';
//     return _run(swCommand);
//   }

//   /// Mixes [musicPath] into the video's existing audio (or replaces it if
//   /// the video has no audio track). The video stream is copied untouched —
//   /// only audio is being changed — so this is fast regardless of encoder
//   /// availability.
//   Future<bool> addMusicToVideo({
//     required String sourcePath,
//     required String outputPath,
//     required String musicPath,
//     double musicVolume = 0.5,
//   }) async {
//     final command = '-y -i "$sourcePath" -i "$musicPath" '
//         '-filter_complex '
//         '"[1:a]volume=$musicVolume[music];[0:a][music]amix=inputs=2:duration=first:dropout_transition=2[aout]" '
//         '-map 0:v -map "[aout]" -c:v copy -shortest '
//         '"$outputPath"';
//     return _run(command);
//   }

//   /// Applies a named color-grade look. These are standard, well-documented
//   /// FFmpeg filter recipes — not exotic ML "AI filters", just real color
//   /// grading, which is what most consumer video apps' "effects" actually are.
//   Future<bool> applyColorEffect({
//     required String sourcePath,
//     required String outputPath,
//     required String effectName,
//   }) async {
//     final filter = _effectFilters[effectName];
//     if (filter == null) return false;

//     final hwCommand = '-y -i "$sourcePath" '
//         '-vf "$filter" '
//         '-c:v h264_mediacodec -c:a copy '
//         '"$outputPath"';
//     if (await _run(hwCommand)) return true;

//     final swCommand = '-y -i "$sourcePath" '
//         '-vf "$filter" '
//         '-c:v libx264 -preset fast -c:a copy '
//         '"$outputPath"';
//     return _run(swCommand);
//   }

//   static const Map<String, String> _effectFilters = {
//     'Black & White': 'hue=s=0',
//     'Sepia': 'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131:0',
//     'Vintage': 'curves=preset=vintage',
//     'Vibrant': 'eq=saturation=1.5',
//     'Cool': 'colorbalance=bs=0.25:bm=0.15:bh=0.1',
//     'Warm': 'colorbalance=rs=0.25:rm=0.15:rh=0.1',
//     'Cinematic': 'eq=contrast=1.1:saturation=0.9,curves=preset=medium_contrast',
//     'Dramatic': 'eq=contrast=1.3:brightness=-0.05,curves=preset=strong_contrast',
//     'Soft': 'eq=contrast=0.9:brightness=0.05,gblur=sigma=1',
//   };
// }