// ui/widgets/force_refresh_button.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/media_provider.dart';

class ForceRefreshButton extends StatefulWidget {
  final String text;
  final IconData icon;

  const ForceRefreshButton({
    Key? key,
    this.text = 'Scan Now',
    this.icon = Icons.search,
  }) : super(key: key);

  @override
  State<ForceRefreshButton> createState() => _ForceRefreshButtonState();
}

class _ForceRefreshButtonState extends State<ForceRefreshButton>
    with SingleTickerProviderStateMixin {
  bool _isScanning = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.linear,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _performForceRefresh() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
    });

    _animationController.repeat();

    try {
      final mediaProvider = Provider.of<MediaProvider>(context, listen: false);

      // Show scanning dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('Scanning for real media files...'),
                const SizedBox(height: 8),
                Text(
                  'This may take a few seconds',
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

      // Force refresh with real file access
      await mediaProvider.refreshAllMedia();

      // Close scanning dialog
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show results
      final totalFiles = mediaProvider.allMedia.length;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    totalFiles > 0
                        ? 'Found $totalFiles real media files!'
                        : 'No media files found. Try viewing some content in social apps first.',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: totalFiles > 0 ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: totalFiles == 0
                ? SnackBarAction(
                    label: 'Help',
                    textColor: Colors.white,
                    onPressed: () => _showHelpDialog(),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      // Close scanning dialog if open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning files: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _animationController.stop();
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Why No Files Found?'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To find real media files, try this:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 12),
              Text('📱 WhatsApp:'),
              Text('• Open WhatsApp'),
              Text('• View some status updates'),
              Text('• Come back and scan again'),
              SizedBox(height: 8),
              Text('📸 Instagram:'),
              Text('• Open Instagram'),
              Text('• Watch some stories or reels'),
              Text('• Come back and scan again'),
              SizedBox(height: 8),
              Text('🎵 TikTok:'),
              Text('• Open TikTok'),
              Text('• Watch some videos'),
              Text('• Come back and scan again'),
              SizedBox(height: 12),
              Text(
                'Note: Social media apps only cache content temporarily while you view it.',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: _isScanning ? null : _performForceRefresh,
        icon: AnimatedBuilder(
          animation: _rotationAnimation,
          builder: (context, child) {
            return Transform.rotate(
              angle: _rotationAnimation.value * 2.0 * 3.14159,
              child: Icon(
                _isScanning ? Icons.refresh : widget.icon,
                size: 20,
              ),
            );
          },
        ),
        label: Text(
          _isScanning ? 'Scanning...' : widget.text,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isScanning ? Colors.grey : Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: _isScanning ? 2 : 4,
        ),
      ),
    );
  }
}
