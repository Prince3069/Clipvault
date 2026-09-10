// ui/widgets/download_progress_indicator.dart
// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../models/download_item.dart';

class DownloadProgressIndicator extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onCancel;

  const DownloadProgressIndicator({
    Key? key,
    required this.item,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onCancel,
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: item.progress,
            backgroundColor: Colors.grey[300],
          ),
          const SizedBox(height: 8),
          Text(
            '${(item.progress * 100).toInt()}%',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
