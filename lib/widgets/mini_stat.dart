import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// Compact stat display (value + label) with colored background.
class MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const MiniStat({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.lightText),
          ),
        ],
      ),
    );
  }
}
