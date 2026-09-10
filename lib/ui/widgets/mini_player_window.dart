// // ui/widgets/mini_player_window.dart
// import 'package:flutter/material.dart';
// import 'ad_container.dart';

// class MiniPlayerWindow extends StatefulWidget {
//   const MiniPlayerWindow({Key? key}) : super(key: key);

//   @override
//   _MiniPlayerWindowState createState() => _MiniPlayerWindowState();
// }

// class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
//   double _progress = 0.0;
//   bool _isComplete = false;

//   @override
//   void initState() {
//     super.initState();
//     _simulateDownload();
//   }

//   Future<void> _simulateDownload() async {
//     // This simulates a download progress
//     for (int i = 0; i <= 100; i += 10) {
//       await Future.delayed(const Duration(milliseconds: 300));
//       if (mounted) {
//         setState(() {
//           _progress = i / 100;
//         });
//       }
//     }

//     if (mounted) {
//       setState(() {
//         _isComplete = true;
//       });
//     }

//     // Auto close after 3 seconds
//     await Future.delayed(const Duration(seconds: 3));
//     if (mounted) {
//       Navigator.of(context).pop();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Dialog(
//       child: Container(
//         width: 300,
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Row(
//               children: [
//                 const CircleAvatar(
//                   radius: 24,
//                   backgroundColor: Colors.blue,
//                   child: Icon(Icons.download, color: Colors.white),
//                 ),
//                 const SizedBox(width: 16),
//                 Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         _isComplete ? 'Download Complete' : 'Downloading...',
//                         style: const TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 16,
//                         ),
//                       ),
//                       const SizedBox(height: 4),
//                       const Text('video.mp4'),
//                     ],
//                   ),
//                 ),
//                 IconButton(
//                   icon: const Icon(Icons.close),
//                   onPressed: () {
//                     Navigator.of(context).pop();
//                   },
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),

//             // Progress bar
//             if (!_isComplete) LinearProgressIndicator(value: _progress),

//             const SizedBox(height: 16),

//             // Ad container
//             const AdContainer(height: 60),

//             const SizedBox(height: 16),

//             // Buttons
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 if (_isComplete)
//                   ElevatedButton.icon(
//                     icon: const Icon(Icons.play_arrow),
//                     label: const Text('Play'),
//                     onPressed: () {
//                       // Play the downloaded video
//                       Navigator.of(context).pop();
//                     },
//                   )
//                 else
//                   ElevatedButton.icon(
//                     icon: const Icon(Icons.cancel),
//                     label: const Text('Cancel'),
//                     onPressed: () {
//                       // Cancel download
//                       Navigator.of(context).pop();
//                     },
//                   ),
//                 ElevatedButton.icon(
//                   icon: const Icon(Icons.folder),
//                   label: const Text('Downloads'),
//                   onPressed: () {
//                     // Navigate to downloads screen
//                     Navigator.of(context).pop();
//                   },
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// // ui/widgets/mini_player_window.dart
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:video_player/video_player.dart';

// class MiniPlayerWindow extends StatefulWidget {
//   final String videoPath;
//   final VoidCallback onClose;

//   const MiniPlayerWindow({
//     Key? key,
//     required this.videoPath,
//     required this.onClose,
//   }) : super(key: key);

//   @override
//   _MiniPlayerWindowState createState() => _MiniPlayerWindowState();
// }

// class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
//   late VideoPlayerController _controller;
//   bool _isInitialized = false;
//   bool _isPlaying = false;

//   @override
//   void initState() {
//     super.initState();
//     _initializeVideoPlayer();
//   }

//   void _initializeVideoPlayer() {
//     _controller = VideoPlayerController.file(File(widget.videoPath))
//       ..initialize().then((_) {
//         setState(() {
//           _isInitialized = true;
//           // Start playing once initialized
//           _controller.play();
//           _isPlaying = true;
//         });
//       }).catchError((error) {
//         print('Error initializing video player: $error');
//       });

//     _controller.addListener(() {
//       if (_controller.value.position >= _controller.value.duration) {
//         setState(() {
//           _isPlaying = false;
//         });
//       }
//     });
//   }

//   @override
//   void dispose() {
//     _controller.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 250,
//       decoration: BoxDecoration(
//         color: Colors.black,
//         borderRadius: BorderRadius.circular(12),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: 0.3),
//             spreadRadius: 1,
//             blurRadius: 10,
//           ),
//         ],
//       ),
//       child: Column(
//         children: [
//           // Player header
//           _buildHeader(),

//           // Video content
//           Expanded(
//             child: _isInitialized
//                 ? AspectRatio(
//                     aspectRatio: _controller.value.aspectRatio,
//                     child: VideoPlayer(_controller),
//                   )
//                 : const Center(
//                     child: CircularProgressIndicator(),
//                   ),
//           ),

//           // Player controls
//           _buildControls(),
//         ],
//       ),
//     );
//   }

//   Widget _buildHeader() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black.withValues(alpha: 0.8),
//         borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: [
//           const Text(
//             'Now Playing',
//             style: TextStyle(
//               color: Colors.white,
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//           IconButton(
//             icon: const Icon(Icons.close, color: Colors.white),
//             padding: EdgeInsets.zero,
//             constraints: const BoxConstraints(),
//             onPressed: widget.onClose,
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildControls() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//       decoration: BoxDecoration(
//         color: Colors.black.withValues(alpha: 0.8),
//         borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
//       ),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//         children: [
//           IconButton(
//             icon: Icon(
//               _isPlaying ? Icons.pause : Icons.play_arrow,
//               color: Colors.white,
//             ),
//             onPressed: () {
//               setState(() {
//                 if (_isPlaying) {
//                   _controller.pause();
//                 } else {
//                   _controller.play();
//                 }
//                 _isPlaying = !_isPlaying;
//               });
//             },
//           ),
//           Expanded(
//             child: _isInitialized
//                 ? VideoProgressIndicator(
//                     _controller,
//                     allowScrubbing: true,
//                     colors: const VideoProgressColors(
//                       playedColor: Colors.blue,
//                       bufferedColor: Colors.grey,
//                       backgroundColor: Colors.white24,
//                     ),
//                   )
//                 : Container(),
//           ),
//           Text(
//             _isInitialized
//                 ? _formatDuration(_controller.value.position)
//                 : '0:00',
//             style: const TextStyle(color: Colors.white),
//           ),
//         ],
//       ),
//     );
//   }

//   String _formatDuration(Duration duration) {
//     String twoDigits(int n) => n.toString().padLeft(2, '0');
//     final minutes = twoDigits(duration.inMinutes.remainder(60));
//     final seconds = twoDigits(duration.inSeconds.remainder(60));
//     return '$minutes:$seconds';
//   }
// }

// ignore_for_file: library_private_types_in_public_api, avoid_print

// ui/widgets/mini_player_window.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MiniPlayerWindow extends StatefulWidget {
  final String videoPath;
  final VoidCallback onClose;

  const MiniPlayerWindow({
    Key? key,
    required this.videoPath,
    required this.onClose,
  }) : super(key: key);

  @override
  _MiniPlayerWindowState createState() => _MiniPlayerWindowState();
}

class _MiniPlayerWindowState extends State<MiniPlayerWindow> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  void _initializeVideoPlayer() {
    _controller = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          // Start playing once initialized
          _controller.play();
          _isPlaying = true;
        });
      }).catchError((error) {
        print('Error initializing video player: $error');
      });

    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withAlpha(77), // Using withAlpha instead of withOpacity
              spreadRadius: 1,
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          children: [
            // Player header
            _buildHeader(),

            // Video content
            Expanded(
              child: _isInitialized
                  ? AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    )
                  : const Center(
                      child: CircularProgressIndicator(),
                    ),
            ),

            // Player controls
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black
            .withAlpha(204), // Using withAlpha instead of withOpacity
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Now Playing',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black
            .withAlpha(204), // Using withAlpha instead of withOpacity
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: () {
              setState(() {
                if (_isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                _isPlaying = !_isPlaying;
              });
            },
          ),
          Expanded(
            child: _isInitialized
                ? VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Colors.blue,
                      bufferedColor: Colors.grey,
                      backgroundColor: Colors.white24,
                    ),
                  )
                : Container(),
          ),
          Text(
            _isInitialized
                ? _formatDuration(_controller.value.position)
                : '0:00',
            style: const TextStyle(color: Colors.white),
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
