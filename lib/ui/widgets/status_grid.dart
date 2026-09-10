import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/status_item.dart';

class StatusGrid extends StatelessWidget {
  final List<StatusItem> statuses;
  final Function(StatusItem) onTap;

  const StatusGrid({super.key, required this.statuses, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: statuses.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final item = statuses[index];
        return GestureDetector(
          onTap: () => onTap(item),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Image.file(File(item.path), fit: BoxFit.cover),
              if (item.isVideo)
                const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.videocam, color: Colors.white),
                ),
            ],
          ),
        );
      },
    );
  }
}
