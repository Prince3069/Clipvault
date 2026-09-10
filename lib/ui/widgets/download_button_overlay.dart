// // ui/widgets/download_button_overlay.dart
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../../providers/download_provider.dart';
// import 'mini_player_window.dart';
// 
// class DownloadButtonOverlay extends StatefulWidget {
//   const DownloadButtonOverlay({Key? key}) : super(key: key);

//   @override
//   _DownloadButtonOverlayState createState() => _DownloadButtonOverlayState();
// }

// class _DownloadButtonOverlayState extends State<DownloadButtonOverlay> {
//   bool _isExpanded = false;
//   Offset _position = const Offset(20, 100);

//   @override
//   Widget build(BuildContext context) {
//     // This would be an overlay shown over other apps
//     return Stack(
//       children: [
//         // Draggable button
//         Positioned(
//           left: _position.dx,
//           top: _position.dy,
//           child: Draggable(
//             feedback: _buildButton(),
//             childWhenDragging: Container(),
//             onDragEnd: (details) {
//               setState(() {
//                 _position = details.offset;
//               });
//             },
//             child: _buildButton(),
//           ),
//         ),

//         // Expanded panel when button is tapped
//         if (_isExpanded)
//           Positioned(
//             left: 20,
//             bottom: 100,
//             right: 20,
//             child: Material(
//               elevation: 8,
//               borderRadius: BorderRadius.circular(12),
//               child: Container(
//                 padding: const EdgeInsets.all(16),
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     const Text(
//                       'Download Detected Media',
//                       style: TextStyle(fontWeight: FontWeight.bold),
//                     ),
//                     const SizedBox(height: 16),
//                     // Ad container
// //                     const SizedBox(height: 16),
//                     Row(
//                       mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//                       children: [
//                         ElevatedButton.icon(
//                           icon: const Icon(Icons.download),
//                           label: const Text('Download'),
//                           onPressed: () {
//                             // Start download
//                             _handleDownload();
//                             setState(() {
//                               _isExpanded = false;
//                             });
//                           },
//                         ),
//                         TextButton.icon(
//                           icon: const Icon(Icons.close),
//                           label: const Text('Cancel'),
//                           onPressed: () {
//                             setState(() {
//                               _isExpanded = false;
//                             });
//                           },
//                         ),
//                       ],
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//       ],
//     );
//   }

//   Widget _buildButton() {
//     return GestureDetector(
//       onTap: () {
//         setState(() {
//           _isExpanded = !_isExpanded;
//         });
//       },
//       child: Container(
//         width: 50,
//         height: 50,
//         decoration: BoxDecoration(
//           color: Theme.of(context).primaryColor,
//           shape: BoxShape.circle,
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withValues(alpha: 0.3),
//               blurRadius: 8,
//               offset: const Offset(0, 3),
//             ),
//           ],
//         ),
//         child: const Icon(
//           Icons.download,
//           color: Colors.white,
//           size: 24,
//         ),
//       ),
//     );
//   }

//   void _handleDownload() {
//     // This would be triggered when the user taps the download button
//     // In a real app, this would extract the URL from the current app/context
//     const url = 'https://example.com/sample_video.mp4';
//     Provider.of<DownloadProvider>(context, listen: false).downloadFromUrl(url);

//     // Show mini player window
//     showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => const MiniPlayerWindow(),
//     );
//   }
// }

// ignore_for_file: library_private_types_in_public_api

// ui/widgets/download_button_overlay.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/download_provider.dart';
import 'mini_player_window.dart';

class DownloadButtonOverlay extends StatefulWidget {
  const DownloadButtonOverlay({Key? key}) : super(key: key);

  @override
  _DownloadButtonOverlayState createState() => _DownloadButtonOverlayState();
}

class _DownloadButtonOverlayState extends State<DownloadButtonOverlay> {
  bool _isExpanded = false;
  Offset _position = const Offset(20, 100);

  @override
  Widget build(BuildContext context) {
    // This would be an overlay shown over other apps
    return Stack(
      children: [
        // Draggable button
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: Draggable(
            feedback: _buildButton(),
            childWhenDragging: Container(),
            onDragEnd: (details) {
              setState(() {
                _position = details.offset;
              });
            },
            child: _buildButton(),
          ),
        ),

        // Expanded panel when button is tapped
        if (_isExpanded)
          Positioned(
            left: 20,
            bottom: 100,
            right: 20,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Download Detected Media',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    // Ad container
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('Download'),
                          onPressed: () {
                            // Start download
                            _handleDownload();
                            setState(() {
                              _isExpanded = false;
                            });
                          },
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                          onPressed: () {
                            setState(() {
                              _isExpanded = false;
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isExpanded = !_isExpanded;
        });
      },
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withAlpha(77), // Using withAlpha instead of withOpacity
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(
          Icons.download,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  void _handleDownload() {
    // This would be triggered when the user taps the download button
    // In a real app, this would extract the URL from the current app/context
    const url = 'https://example.com/sample_video.mp4';
    final downloadProvider =
        Provider.of<DownloadProvider>(context, listen: false);
    downloadProvider.downloadFromUrl(url);

    // Simulate a path where the video would be downloaded
    const String videoPath = '/storage/emulated/0/Download/sample_video.mp4';

    // Show mini player window with the required videoPath parameter
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MiniPlayerWindow(
        videoPath: videoPath,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}
