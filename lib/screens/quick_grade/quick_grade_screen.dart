import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/routes.dart';
import '../../models/assessment.dart';
import '../../services/assessment_provider.dart';
import '../../services/settings_provider.dart';

/// Quick Grade — one-tap scanning path.
///
/// Saves last answer key as template. Next time, one tap to scan.
/// First time: enter answer key. After that: just tap "Use Last".
class QuickGradeScreen extends StatefulWidget {
  const QuickGradeScreen({super.key});

  @override
  State<QuickGradeScreen> createState() => _QuickGradeScreenState();
}

class _QuickGradeScreenState extends State<QuickGradeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _questionCountController = TextEditingController();
  final _answerKeyController = TextEditingController();
  bool _isProcessing = false;
  _SavedTemplate? _lastTemplate;

  @override
  void initState() {
    super.initState();
    _loadLastTemplate();
  }

  @override
  void dispose() {
    _questionCountController.dispose();
    _answerKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadLastTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('quickgrade_last_template');
    if (json != null) {
      try {
        final map = jsonDecode(json) as Map<String, dynamic>;
        setState(() {
          _lastTemplate = _SavedTemplate(
            questionCount: map['count'] ?? 20,
            answerKey: map['answers'] ?? '',
            label: map['label'] ?? '',
            savedAt: map['savedAt'] ?? '',
          );
        });
      } catch (_) {}
    }
  }

  Future<void> _saveTemplate(int count, String answers) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final label = 'Quick Grade — ${now.day}/${now.month}/${now.year}';
    final map = {
      'count': count,
      'answers': answers,
      'label': label,
      'savedAt': now.toString().substring(0, 16),
    };
    await prefs.setString('quickgrade_last_template', jsonEncode(map));
    setState(() {
      _lastTemplate = _SavedTemplate(
        questionCount: count,
        answerKey: answers,
        label: label,
        savedAt: now.toString().substring(0, 16),
      );
    });
  }

  List<String>? _parseAnswerKey(String raw, int expectedCount) {
    final parts = raw
        .split(RegExp(r'[,;\s]+'))
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.length != expectedCount) return null;

    const validAnswers = {'A', 'B', 'C', 'D', 'E', 'T', 'F'};
    for (final ans in parts) {
      if (!validAnswers.contains(ans)) return null;
    }

    return parts;
  }

  Future<void> _startScanning(int count, String answerKey) async {
    setState(() => _isProcessing = true);

    final answers = _parseAnswerKey(answerKey, count)!;

    final questions = List.generate(count, (i) {
      final ans = answers[i];
      final isTF = ans == 'T' || ans == 'F';
      return Question(
        id: 'qg_q${i + 1}',
        number: i + 1,
        type: isTF ? QuestionType.trueFalse : QuestionType.mcq,
        points: 1,
        correctAnswer: isTF ? (ans == 'T' ? 'True' : 'False') : ans,
        options: isTF ? ['True', 'False'] : ['A', 'B', 'C', 'D']);
    });

    final now = DateTime.now();
    final dateStr = now.toString().substring(0, 10);
    final rubric = context.read<SettingsProvider>().defaultRubric;

    final assessment = Assessment(
      id: 'quickgrade_${now.millisecondsSinceEpoch}',
      title: 'Quick Grade — $dateStr',
      subject: '',
      rubricType: rubric,
      questions: questions,
      status: AssessmentStatus.active,
      isQuickGrade: true);

    await context.read<AssessmentProvider>().addAssessment(assessment);
    await _saveTemplate(count, answerKey);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.camera,
      arguments: {'assessment': assessment, 'isQuickGrade': true});
  }

  void _useLastTemplate() {
    if (_lastTemplate == null) return;
    _startScanning(_lastTemplate!.questionCount, _lastTemplate!.answerKey);
  }

  void _enterNewKey() {
    if (_lastTemplate != null) {
      _questionCountController.text = '${_lastTemplate!.questionCount}';
      _answerKeyController.text = _lastTemplate!.answerKey;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text('Enter Answer Key',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _questionCountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Number of questions',
                    hintText: 'e.g. 20',
                    prefixIcon: Icon(Icons.format_list_numbered)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1 || n > 100) return '1-100';
                    return null;
                  }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _answerKeyController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Answer key',
                    hintText: 'A,B,C,D,A,B,C,D...',
                    prefixIcon: Icon(Icons.check_circle_outline),
                    helperText: 'A-E for MCQ, T/F for True/False'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final count = int.tryParse(_questionCountController.text.trim());
                    if (count == null) return null;
                    if (_parseAnswerKey(v.trim(), count) == null) {
                      return 'Must match question count (A-E, T/F)';
                    }
                    return null;
                  }),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (!_formKey.currentState!.validate()) return;
                      final count = int.parse(_questionCountController.text.trim());
                      final answers = _answerKeyController.text.trim();
                      Navigator.pop(ctx);
                      _startScanning(count, answers);
                    },
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Start Scanning', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTemplate = _lastTemplate != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Quick Grade')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.teal.shade700, Colors.teal.shade500]),
                borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const Icon(Icons.flash_on, color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  const Text('Scan Papers in One Tap',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    hasTemplate
                        ? 'Use your last answer key or enter a new one'
                        : 'Enter your answer key once, then scan papers instantly',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
                ])),
            const SizedBox(height: 24),

            // Last used template card
            if (hasTemplate) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.teal.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2))]),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, color: Colors.teal.shade600, size: 20),
                        const SizedBox(width: 8),
                        Text('Last Used',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
                        const Spacer(),
                        Text(_lastTemplate!.savedAt,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                    const SizedBox(height: 8),
                    Text('${_lastTemplate!.questionCount} questions',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      _lastTemplate!.answerKey.length > 40
                          ? '${_lastTemplate!.answerKey.substring(0, 40)}...'
                          : _lastTemplate!.answerKey,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontFamily: 'monospace')),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing ? null : _useLastTemplate,
                        icon: _isProcessing
                            ? const SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.flash_on),
                        label: Text(_isProcessing ? 'Starting...' : 'Use Last & Scan',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
                    ),
                  ])),
              const SizedBox(height: 16),
              // Divider with "or"
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or', style: TextStyle(color: Colors.grey.shade500))),
                  const Expanded(child: Divider()),
                ]),
              const SizedBox(height: 16),
            ],

            // Enter new key button
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _enterNewKey,
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  hasTemplate ? 'Enter New Answer Key' : 'Enter Answer Key',
                  style: const TextStyle(fontSize: 15)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
            ),
          ])),
    );
  }
}

class _SavedTemplate {
  final int questionCount;
  final String answerKey;
  final String label;
  final String savedAt;
  const _SavedTemplate({
    required this.questionCount,
    required this.answerKey,
    required this.label,
    required this.savedAt,
  });
}
