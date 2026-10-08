import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../services/hive_box_mixin.dart';
import '../../widgets/ui_components.dart';

/// Record of an SMS send attempt.
class SmsLogEntry {
  final String id;
  final String studentName;
  final String phoneNumber;
  final String message;
  final String templateName;
  final bool success;
  final String? errorMessage;
  final DateTime sentAt;

  const SmsLogEntry({
    required this.id,
    required this.studentName,
    required this.phoneNumber,
    required this.message,
    required this.templateName,
    required this.success,
    this.errorMessage,
    required this.sentAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'studentName': studentName,
    'phoneNumber': phoneNumber,
    'message': message,
    'templateName': templateName,
    'success': success,
    'errorMessage': errorMessage,
    'sentAt': sentAt.toIso8601String(),
  };

  factory SmsLogEntry.fromMap(Map<String, dynamic> map) => SmsLogEntry(
    id: map['id'] ?? '',
    studentName: map['studentName'] ?? '',
    phoneNumber: map['phoneNumber'] ?? '',
    message: map['message'] ?? '',
    templateName: map['templateName'] ?? '',
    success: map['success'] ?? false,
    errorMessage: map['errorMessage'],
    sentAt: DateTime.tryParse(map['sentAt'] ?? '') ?? DateTime.now(),
  );
}

/// Screen showing history of SMS messages sent to parents.
class SmsHistoryScreen extends StatefulWidget {
  const SmsHistoryScreen({super.key});

  @override
  State<SmsHistoryScreen> createState() => _SmsHistoryScreenState();
}

class _SmsHistoryScreenState extends State<SmsHistoryScreen> with HiveBoxMixin {
  static const String _boxName = 'sms_history';
  List<SmsLogEntry> _logs = [];
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    try {
      final box = await openBox(_boxName);
      final logs = <SmsLogEntry>[];

      for (final key in box.keys) {
        final data = await box.get(key);
        if (data != null) {
          logs.add(SmsLogEntry.fromMap(Map<String, dynamic>.from(data as Map)));
        }
      }

      logs.sort((a, b) => b.sentAt.compareTo(a.sentAt));

      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
          _loadFailed = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text('Delete all SMS history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: context.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final box = await openBox(_boxName);
      await box.clear();
      setState(() => _logs = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS History'),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearHistory,
              tooltip: 'Clear History',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadFailed
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: context.error,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Couldn\'t load SMS history',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Your SMS history couldn\'t be read from storage.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.lightText,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _loadFailed = false;
                          });
                          _loadLogs();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _logs.isEmpty
                  ? _buildEmptyState()
                  : _buildLogList(),
    );
  }

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.sms_outlined,
      title: 'No SMS history',
      message: 'SMS messages sent to parents will appear here',
    );
  }

  Widget _buildLogList() {
    final sentCount = _logs.where((l) => l.success).length;
    final failedCount = _logs.where((l) => !l.success).length;

    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          color: context.primaryGreen.withValues(alpha: 0.05),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStat('Total', _logs.length.toString(), context.primaryGreen),
              _buildStat('Sent', sentCount.toString(), AppTheme.success),
              _buildStat('Failed', failedCount.toString(), context.error),
            ],
          ),
        ),
        // Log list
        Expanded(
          child: ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final log = _logs[index];
              return _buildLogTile(log);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: context.lightText,
          ),
        ),
      ],
    );
  }

  Widget _buildLogTile(SmsLogEntry log) {
    final timeStr = _formatTime(log.sentAt);

    return ListTile(
      leading: Icon(
        log.success ? Icons.check_circle : Icons.error,
        color: log.success ? AppTheme.success : context.error,
      ),
      title: Text(log.studentName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            log.phoneNumber,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            log.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.lightText,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            log.templateName,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.lightText,
              fontSize: 10,
            ),
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${dt.day}/${dt.month}/${dt.year}';
  }
}