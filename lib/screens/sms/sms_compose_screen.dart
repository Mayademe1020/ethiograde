import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/sms_service.dart';
import '../../services/student_provider.dart';

class SmsComposeScreen extends StatefulWidget {
  final List<Map<String, String>>? initialMessages;
  final String? assessmentName;

  const SmsComposeScreen({
    super.key,
    this.initialMessages,
    this.assessmentName,
  });

  @override
  State<SmsComposeScreen> createState() => _SmsComposeScreenState();
}

class _SmsComposeScreenState extends State<SmsComposeScreen> {
  final _smsService = SmsService();
  SmsTemplate _selectedTemplate = DefaultTemplates.resultNotification;
  bool _useAmharic = false;
  bool _isSending = false;
  List<SmsResult>? _results;
  List<Map<String, String>> _pendingMessages = [];
  bool _messagesPrepared = false;
  bool _prepareFailed = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialMessages != null && widget.initialMessages!.isNotEmpty) {
      _pendingMessages = widget.initialMessages!;
      _messagesPrepared = true;
    } else {
      _prepareMessages();
    }
  }

  final _schoolNameController = TextEditingController(text: 'My School');

  @override
  void dispose() {
    _schoolNameController.dispose();
    super.dispose();
  }

  Future<void> _prepareMessages() async {
    final students = context.read<StudentProvider>().students;
    final assessments = context.read<AssessmentProvider>().assessments;

    if (assessments.isEmpty || students.isEmpty) {
      setState(() => _messagesPrepared = true);
      return;
    }

    try {
      final latestAssessment = assessments.first;
      final results = await HybridGradingService().loadScanResults(
        latestAssessment.id,
        throwOnError: true,
      );

      final messages = <Map<String, String>>[];

      for (final student in students) {
        if (student.parentPhone == null || student.parentPhone!.isEmpty) {
          continue;
        }

        final studentResults = results.where((r) => r.studentId == student.id);
        if (studentResults.isEmpty) continue;

        final best = studentResults.reduce(
          (a, b) => a.percentage > b.percentage ? a : b,
        );

        final message = _selectedTemplate.render(
          studentName: student.fullName,
          subject: latestAssessment.subject,
          percentage: best.percentage,
          schoolName: _schoolNameController.text,
          amharic: _useAmharic,
        );

        messages.add({
          'phone': student.parentPhone!,
          'message': message,
          'student': student.fullName,
        });
      }

      setState(() {
        _pendingMessages = messages;
        _messagesPrepared = true;
        _prepareFailed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _messagesPrepared = true;
          _prepareFailed = true;
        });
      }
    }
  }

  Future<void> _sendAll() async {
    if (_pendingMessages.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Send'),
        content: Text('Send ${_pendingMessages.length} SMS message(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSending = true;
      _results = null;
    });

    final results = await _smsService.sendBulk(messages: _pendingMessages);

    setState(() {
      _isSending = false;
      _results = results;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Parent SMS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextField(
              controller: _schoolNameController,
              decoration: const InputDecoration(
                labelText: 'School Name',
                hintText: 'Your school name',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Template', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            RadioGroup<String>(
              groupValue: _selectedTemplate.name,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedTemplate = DefaultTemplates.all.firstWhere(
                    (t) => t.name == v,
                  );
                  _results = null;
                });
              },
              child: Column(
                children: [
                  ...DefaultTemplates.all.map((t) {
                    final selected = t.name == _selectedTemplate.name;
                    return Card(
                      color: selected
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : null,
                      child: RadioListTile<String>(
                        title: Text(t.name),
                        subtitle: Text(
                          _useAmharic ? t.amharicTemplate : t.englishTemplate,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: t.name,
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text('Language', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                const Text('English'),
                Switch(
                  value: _useAmharic,
                  onChanged: (v) => setState(() {
                    _useAmharic = v;
                    _results = null;
                  }),
                ),
                const Text('Amharic'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (!_messagesPrepared)
              const Center(child: CircularProgressIndicator())
            else if (_prepareFailed)
              Card(
                color: AppTheme.error.withValues(alpha: 0.06),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.error),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text(
                          'Couldn\'t load grading results. Check your data and try again.',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _messagesPrepared = false;
                            _prepareFailed = false;
                          });
                          _prepareMessages();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recipients (${_pendingMessages.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_pendingMessages.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(AppSpacing.md),
                        child: Text(
                          'No students with parent phone numbers found.',
                        ),
                      ),
                    )
                  else
                    ..._pendingMessages
                        .take(5)
                        .map(
                          (m) => Card(
                            margin: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: ListTile(
                              dense: true,
                              title: Text(m['student'] ?? ''),
                              subtitle: Text(m['message'] ?? ''),
                              trailing: Text(
                                m['phone'] ?? '',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                  if (_pendingMessages.length > 5)
                    Text(
                      '... and ${_pendingMessages.length - 5} more',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            if (_results != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Results',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Sent: ${_results!.where((r) => r.success).length}',
                        style: const TextStyle(color: AppTheme.success),
                      ),
                      Text(
                        'Failed: ${_results!.where((r) => !r.success).length}',
                        style: const TextStyle(color: AppTheme.error),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _pendingMessages.isEmpty || _isSending
                    ? null
                    : _sendAll,
                icon: _isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _isSending
                      ? 'Sending...'
                      : 'Send ${_pendingMessages.length} Messages',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
