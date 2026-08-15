import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../models/audit_entry.dart';
import '../../models/scan_result.dart';
import '../../services/audit_service.dart';

/// Shows the full audit trail for a scan result.
///
/// Displays a timeline of every change: who, when, what changed.
/// Answers "parent disputes a grade" by showing complete history.
///
/// Accessed from the result card in ReviewScreen via "View History" button.
class AuditTrailSheet extends StatelessWidget {
  final ScanResult result;
  final void Function(AuditEntry entry)? onRevert;

  const AuditTrailSheet({super.key, required this.result, this.onRevert});

  /// Show the audit trail as a modal bottom sheet.
  static Future<void> show(
    BuildContext context,
    ScanResult result, {
    void Function(AuditEntry entry)? onRevert,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AuditTrailSheet(result: result, onRevert: onRevert));
  }

  @override
  Widget build(BuildContext context) {
    final trail = AuditService().getTrail(result.id);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: AppTheme.primaryGreen),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Grade History',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold)),
                        Text(
                          result.studentName,
                          style: const TextStyle(
                            color: AppTheme.lightText,
                            fontSize: 14)),
                      ])),
                  // Current grade badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${result.grade} (${result.percentage.toStringAsFixed(1)}%)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGreen))),
                ])),
            const Divider(height: 1),
            // Timeline
            Expanded(
              child: trail.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'No changes recorded',
                            style: TextStyle(color: AppTheme.lightText)),
                          const Text(
                            'Grade is as originally entered',
                            style: TextStyle(
                              color: AppTheme.lightText,
                              fontSize: 12)),
                        ]))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      itemCount: trail.length,
                      itemBuilder: (context, index) {
                        return _TimelineEntry(
                          entry: trail[index],
                          isFirst: index == 0,
                          isLast: index == trail.length - 1,
                          onRevert: index < trail.length - 1
                              ? onRevert
                              : null, // Can't revert the latest entry
                        );
                      })),
          ]);
      });
  }
}

/// Single entry in the audit timeline.
class _TimelineEntry extends StatelessWidget {
  final AuditEntry entry;
  final bool isFirst;
  final bool isLast;
  final void Function(AuditEntry entry)? onRevert;

  const _TimelineEntry({
    required this.entry,
    required this.isFirst,
    required this.isLast,
    this.onRevert,
  });

  /// Whether this entry can be reverted (has previousValues to restore).
  bool get _canRevert =>
      onRevert != null &&
      entry.previousValues.isNotEmpty &&
      entry.action != 'created';

  IconData _actionIcon(String action) {
    switch (action) {
      case 'created':
        return Icons.add_circle;
      case 'score_override':
        return Icons.edit;
      case 'grade_change':
        return Icons.swap_horiz;
      case 'reassigned':
        return Icons.person;
      case 'comment_added':
        return Icons.comment;
      default:
        return Icons.circle;
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'created':
        return AppTheme.primaryGreen;
      case 'score_override':
      case 'grade_change':
        return AppTheme.warning;
      case 'reassigned':
        return AppTheme.info;
      case 'comment_added':
        return Colors.grey;
      default:
        return AppTheme.lightText;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}${"m ago"}';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}${"h ago"}';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}${"d ago"}';
    }
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _actionColor(entry.action);
    final description = entry.description;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline column
          SizedBox(
            width: 40,
            child: Column(
              children: [
                if (!isFirst)
                  Container(width: 2, height: 12, color: Colors.grey.shade300),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2)),
                  child: Icon(_actionIcon(entry.action), size: 16, color: color)),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: Colors.grey.shade300)),
              ])),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  Text(
                    description,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14)),
                  const SizedBox(height: 6),
                  // Who and when
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 14, color: AppTheme.lightText),
                      const SizedBox(width: 4),
                      Text(
                        entry.teacherName.isNotEmpty
                            ? entry.teacherName
                            : ('Unknown'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.lightText)),
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time, size: 14, color: AppTheme.lightText),
                      const SizedBox(width: 4),
                      Text(
                        _formatTimestamp(entry.timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.lightText)),
                    ]),
                  // Score change details (for overrides)
                  if (entry.action == 'score_override' ||
                      entry.action == 'grade_change') ...[
                    const SizedBox(height: 8),
                    _ScoreChangeDetail(entry: entry),
                  ],
                  // Reason
                  if (entry.reason != null && entry.reason!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, size: 14, color: AppTheme.info),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${"Reason: "}${entry.reason}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.info,
                              fontStyle: FontStyle.italic))),
                      ]),
                  ],
                  // Revert button
                  if (_canRevert) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => onRevert!(entry),
                        icon: const Icon(Icons.undo, size: 16),
                        label: const Text(
                          'Revert to this',
                          style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.warning,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap))),
                  ],
                ]))),
        ]));
  }
}

/// Shows old → new score comparison for override entries.
class _ScoreChangeDetail extends StatelessWidget {
  final AuditEntry entry;

  const _ScoreChangeDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final old = entry.previousValues;
    final newV = entry.newValues;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withOpacity(0.2))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Old value
          Column(
            children: [
              const Text(
                'Before',
                style: TextStyle(fontSize: 10, color: AppTheme.lightText)),
              Text(
                '${old['grade'] ?? ''} (${(old['percentage'] as num?)?.toStringAsFixed(1) ?? (old['totalScore']?.toString() ?? '')}%)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.error,
                  decoration: TextDecoration.lineThrough)),
            ]),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.arrow_forward, size: 16, color: AppTheme.warning)),
          // New value
          Column(
            children: [
              const Text(
                'After',
                style: TextStyle(fontSize: 10, color: AppTheme.lightText)),
              Text(
                '${newV['grade'] ?? ''} (${(newV['percentage'] as num?)?.toStringAsFixed(1) ?? (newV['totalScore']?.toString() ?? '')}%)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryGreen)),
            ]),
        ]));
  }
}
