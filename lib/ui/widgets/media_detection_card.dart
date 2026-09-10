// ui/widgets/media_detection_card.dart - FIXED VERSION
// ignore_for_file: deprecated_member_use, avoid_print

import 'package:flutter/material.dart';
import '../../services/native_bridge.dart';

class MediaDetectionCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool isActive;
  final IconData icon;
  final VoidCallback? onTap;

  const MediaDetectionCard({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.isActive,
    required this.icon,
    this.onTap,
  }) : super(key: key);

  @override
  State<MediaDetectionCard> createState() => _MediaDetectionCardState();
}

class _MediaDetectionCardState extends State<MediaDetectionCard> {
  bool _isCheckingStatus = false;

  @override
  void initState() {
    super.initState();
    _checkAccessibilityStatus();
  }

  Future<void> _checkAccessibilityStatus() async {
    setState(() {
      _isCheckingStatus = true;
    });

    try {
      // Add delay to ensure proper checking
      await Future.delayed(const Duration(milliseconds: 500));

      // Force refresh the accessibility status
      await NativeBridge.isAccessibilityServiceEnabled();

      // Trigger rebuild after status check
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
    } catch (e) {
      print('Error checking accessibility status: $e');
      if (mounted) {
        setState(() {
          _isCheckingStatus = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isActive
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.3),
              width: 2,
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: widget.isActive
                  ? [
                      Colors.green.withValues(alpha: 0.1),
                      Colors.green.withValues(alpha: 0.05)
                    ]
                  : [
                      Colors.orange.withValues(alpha: 0.1),
                      Colors.orange.withValues(alpha: 0.05)
                    ],
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.isActive ? Colors.green : Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  widget.icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (_isCheckingStatus)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  widget.isActive ? Icons.check_circle : Icons.error_outline,
                  color: widget.isActive ? Colors.green : Colors.orange,
                  size: 28,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
