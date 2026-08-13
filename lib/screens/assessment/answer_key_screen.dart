import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/responsive.dart';
import '../../models/assessment.dart';
import '../../models/scan_result.dart';
import '../../services/assessment_provider.dart';
import '../../services/hybrid_grading_service.dart';
import '../../services/answer_key_recalculation_service.dart';
import '../../services/answer_key_fingerprint_service.dart';
import 'answer_key_photo_scan.dart';
import 'answer_key_section_setup.dart';
import '../../widgets/assessment/section_header.dart';

enum _KeyChangeAction { recalculateNow, saveAndRecalculateLater, cancel }

class AnswerKeyRouteArgs {
  final Assessment assessment;
  final bool returnToReview;
  final bool returnToConfirmation;

  const AnswerKeyRouteArgs({
    required this.assessment,
    this.returnToReview = false,
    this.returnToConfirmation = false,
  });
}

class AnswerKeyScreen extends StatefulWidget {
  const AnswerKeyScreen({super.key});

  @override
  State<AnswerKeyScreen> createState() => _AnswerKeyScreenState();
}

class _AnswerKeyScreenState extends State<AnswerKeyScreen> {
  Assessment? _assessment;
  String? _preEditFingerprint;
  Map<int, String> _originalAnswers = {};
  int _typeFilter = -1;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _rowKeys = {};

  // Auto-advance state
  int _activeQuestionIndex = 0;
  bool _autoAdvanceEnabled = true;

  // Auto-save state
  bool _isLocked = false;
  DateTime? _lastSavedAt;
  bool _showRecoveryBanner = false;
  int _recoveredCount = 0;

  // Flags and filtering
  final Set<int> _flaggedQuestions = {};
  int _filterMode = 0; // 0=All, 1=Flagged, 2=Empty

  // Sections
  List<ExamSection> _sections = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_assessment != null) return;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is AnswerKeyRouteArgs) {
      _assessment = args.assessment;
    } else if (args is Assessment) {
      _assessment = args;
    } else {
      _assessment = context.read<AssessmentProvider>().currentAssessment;
    }

    if (_assessment != null) {
      _preEditFingerprint = _assessment!.answerKeyFingerprint.isNotEmpty
          ? _assessment!.answerKeyFingerprint
          : const AnswerKeyFingerprintService().compute(_assessment!);
      _originalAnswers = {
        for (final q in _assessment!.questions)
          q.number: q.correctAnswer?.toString() ?? '',
      };
      for (final q in _assessment!.questions) {
        _rowKeys[q.number] = GlobalKey();
      }

      // Load lock state from settings
      _isLocked = _assessment!.settings['answerKeyLocked'] == true;

      // Load sections
      _loadSections();

      // Check for recovery draft
      _checkForRecoveryDraft();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Question> get _filteredQuestions {
    if (_assessment == null) return [];
    var questions = _assessment!.questions;

    // Filter by type
    if (_typeFilter >= 0) {
      const types = QuestionType.values;
      if (_typeFilter < types.length) {
        final type = types[_typeFilter];
        questions = questions.where((q) => q.type == type).toList();
      }
    }

    // Filter by flag/empty mode
    if (_filterMode == 1) {
      // Flagged only
      questions = questions
          .where((q) => _flaggedQuestions.contains(q.number))
          .toList();
    } else if (_filterMode == 2) {
      // Empty only
      questions = questions.where((q) {
        final answer = q.correctAnswer?.toString() ?? '';
        return answer.isEmpty;
      }).toList();
    }

    return questions;
  }

  Map<String, int> get _typeCounts {
    if (_assessment == null) return {};
    final counts = <String, int>{};
    counts['ALL'] = _assessment!.questions.length;
    for (final q in _assessment!.questions) {
      final label = _typeLabel(q.type);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _answerDistribution {
    if (_assessment == null) return {};
    final dist = <String, int>{};
    for (final q in _assessment!.questions) {
      final ans = q.correctAnswer?.toString().trim() ?? '';
      if (ans.isEmpty) continue;
      if (q.type == QuestionType.mcq || q.type == QuestionType.multiAnswer) {
        final letters = ans
            .split(RegExp(r'[,+]+'))
            .map((s) => s.trim().toUpperCase());
        for (final l in letters) {
          if (l.isNotEmpty) dist[l] = (dist[l] ?? 0) + 1;
        }
      } else if (q.type == QuestionType.trueFalse) {
        dist['T/F'] = (dist['T/F'] ?? 0) + 1;
      } else {
        dist['Text'] = (dist['Text'] ?? 0) + 1;
      }
    }
    return dist;
  }

  String _typeLabel(QuestionType type) {
    return switch (type) {
      QuestionType.mcq => 'MCQ',
      QuestionType.trueFalse => 'T/F',
      QuestionType.shortAnswer => 'SHORT',
      QuestionType.essay => 'ESSAY',
      QuestionType.matching => 'MATCH',
      QuestionType.multiAnswer => 'MULTI',
    };
  }

  @override
  Widget build(BuildContext context) {
    final assessment = _assessment;
    final args = ModalRoute.of(context)?.settings.arguments;
    final returnToReview = args is AnswerKeyRouteArgs && args.returnToReview;

    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('No assessment selected')),
      );
    }

    final answered = assessment.answeredQuestionCount;
    final total = assessment.questionCount;
    final completeness = assessment.answerKeyCompleteness;
    final dist = _answerDistribution;
    final typeCounts = _typeCounts;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Answer Key'),
            if (_lastSavedAt != null) ...[
              const SizedBox(width: 8),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF18A558),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            onPressed: _toggleLock,
            icon: Icon(_isLocked ? Icons.lock : Icons.lock_open),
            tooltip: _isLocked ? 'Unlock answer key' : 'Lock answer key',
            color: _isLocked ? const Color(0xFFF4A623) : Colors.white54,
          ),
          IconButton(
            onPressed: () => _openPhotoScan(context, assessment),
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Scan answer key from photo',
            color: const Color(0xFFF4A623),
          ),
          TextButton.icon(
            onPressed: () => _handleDone(context, assessment, returnToReview),
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Recovery banner
          if (_showRecoveryBanner)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveLayout.horizontalPadding(context),
                vertical: 10,
              ),
              color: const Color(0xFF1A6FD4).withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.restore, color: Color(0xFF1A6FD4), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recovered: $_recoveredCount answers restored from draft',
                      style: const TextStyle(
                        color: Color(0xFF1A6FD4),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _showRecoveryBanner = false),
                    child: const Icon(
                      Icons.close,
                      color: Color(0xFF1A6FD4),
                      size: 16,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveLayout.horizontalPadding(context),
                      12,
                      ResponsiveLayout.horizontalPadding(context),
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildExamInfo(assessment),
                        const SizedBox(height: 12),
                        _buildProgressSection(answered, total, completeness),
                        if (dist.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildDistributionBar(dist),
                        ],
                        const SizedBox(height: 10),
                        _buildTypeFilterTabs(typeCounts),
                        const SizedBox(height: 8),
                        _buildToolbar(assessment),
                        const SizedBox(height: 8),
                        _buildFlagFilterBar(),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: _sections.isNotEmpty
                      ? _buildSectionedList()
                      : _buildPlainList(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildAutoAdvanceBar(),
    );
  }

  Widget _buildAutoAdvanceBar() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveLayout.horizontalPadding(context),
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        border: Border(top: BorderSide(color: Colors.grey.shade800)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Icon(
              _autoAdvanceEnabled ? Icons.skip_next : Icons.touch_app,
              color: _autoAdvanceEnabled
                  ? const Color(0xFF7EB8DA)
                  : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _autoAdvanceEnabled ? 'Auto-advance' : 'Manual',
                style: TextStyle(
                  color: _autoAdvanceEnabled
                      ? const Color(0xFF7EB8DA)
                      : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Switch(
              value: _autoAdvanceEnabled,
              onChanged: (v) => setState(() => _autoAdvanceEnabled = v),
              activeThumbColor: const Color(0xFF7EB8DA),
              inactiveTrackColor: Colors.grey.shade700,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamInfo(Assessment assessment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            '${assessment.subject} • ${assessment.questionCount} questions • ${assessment.maxScore.toInt()} pts',
            style: const TextStyle(color: AppTheme.lightText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(int answered, int total, double completeness) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1929).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$answered / $total answers set',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (answered < total)
                TextButton.icon(
                  onPressed: _scrollToNextEmpty,
                  icon: const Icon(Icons.keyboard_arrow_down, size: 16),
                  label: const Text(
                    'Next empty',
                    style: TextStyle(fontSize: 11),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 6,
            child: LinearProgressIndicator(
              value: completeness,
              color: AppTheme.primaryGreen,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall completeness',
                style: TextStyle(fontSize: 11, color: AppTheme.lightText),
              ),
              Text(
                '${(completeness * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.primaryGreen,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(Map<String, int> dist) {
    if (dist.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: dist.entries.map((e) {
          return Text(
            '${e.key}:${e.value}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFFF0ECE4),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTypeFilterTabs(Map<String, int> typeCounts) {
    final tabs = <Widget>[];
    final entries = typeCounts.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isActive =
          (i == 0 && _typeFilter < 0) || (i > 0 && _typeFilter == i - 1);
      tabs.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _typeFilter = i == 0 ? -1 : i - 1;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${e.key} (${e.value})',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: isActive ? Colors.white : AppTheme.lightText,
              ),
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: tabs),
    );
  }

  Widget _buildToolbar(Assessment assessment) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolbarButton(
              'Paste All',
              Icons.content_paste,
              isPrimary: true,
              onTap: () => _showBulkPasteDialog(assessment),
            ),
            const SizedBox(width: 5),
            Container(width: 1, height: 12, color: Colors.grey.shade300),
            const SizedBox(width: 5),
            _toolbarButton(
              'Sections',
              Icons.view_agenda_outlined,
              onTap: _openSectionSetup,
            ),
            const SizedBox(width: 5),
            Container(width: 1, height: 12, color: Colors.grey.shade300),
            const SizedBox(width: 5),
            const Text(
              'All:',
              style: TextStyle(fontSize: 10, color: AppTheme.lightText),
            ),
            const SizedBox(width: 4),
            _toolbarDropdown<QuestionType>(
              hint: 'Type',
              items: QuestionType.values,
              labelBuilder: _typeLabel,
              onChanged: (type) => _setAllType(assessment, type),
            ),
            const SizedBox(width: 4),
            _toolbarDropdown<double>(
              hint: 'Pts',
              items: const [1.0, 2.0, 5.0, 10.0],
              labelBuilder: (p) => '${p.toInt()}pt',
              onChanged: (pts) => _setAllPoints(assessment, pts),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagFilterBar() {
    if (_assessment == null) return const SizedBox.shrink();
    final total = _assessment!.questionCount;
    final flagged = _flaggedQuestions.length;
    final empty = _assessment!.questions.where((q) {
      final answer = q.correctAnswer?.toString() ?? '';
      return answer.isEmpty;
    }).length;

    return Row(
      children: [
        _filterChip('All ($total)', 0),
        const SizedBox(width: 6),
        _filterChip('Flagged ($flagged) ★', 1),
        const SizedBox(width: 6),
        _filterChip('Empty ($empty)', 2),
      ],
    );
  }

  Widget _filterChip(String label, int mode) {
    final isActive = _filterMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _filterMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF0B6E4F) : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isActive ? Colors.white : AppTheme.lightText,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionedList() {
    final questions = _filteredQuestions;
    final items = <_ListItem>[];

    for (final section in _sections) {
      final sectionQuestions = questions
          .where((q) => q.number >= section.startQ && q.number <= section.endQ)
          .toList();
      if (sectionQuestions.isEmpty) continue;

      final answeredCount = sectionQuestions.where((q) {
        final answer = q.correctAnswer?.toString() ?? '';
        return answer.isNotEmpty;
      }).length;

      items.add(_ListItem.section(section, answeredCount));
      for (final q in sectionQuestions) {
        items.add(_ListItem.question(q));
      }
    }

    // Questions not in any section
    for (final q in questions) {
      final inSection = _sections.any(
        (s) => q.number >= s.startQ && q.number <= s.endQ,
      );
      if (!inSection) {
        items.add(_ListItem.question(q));
      }
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildListItem(items[index], index),
        childCount: items.length,
      ),
    );
  }

  Widget _buildPlainList() {
    final questions = _filteredQuestions;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) =>
            _buildListItem(_ListItem.question(questions[index]), index),
        childCount: questions.length,
      ),
    );
  }

  Widget _buildListItem(_ListItem item, int flatIndex) {
    if (item.isSection) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: SectionHeader(
          section: item.section!,
          answeredCount: item.answeredCount,
          onTap: () => _editSection(item.section!),
        ),
      );
    }

    final q = item.question!;
    final isAnswered = q.correctAnswer?.toString().isNotEmpty ?? false;
    // Find the question's index in _filteredQuestions for active highlighting
    final filteredIndex = _filteredQuestions.indexWhere(
      (fq) => fq.number == q.number,
    );

    return Dismissible(
      key: ValueKey('q_${q.number}'),
      direction: isAnswered && !_isLocked
          ? DismissDirection.startToEnd
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFDA2A2A).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.clear, color: Color(0xFFDA2A2A), size: 18),
            SizedBox(width: 6),
            Text(
              'Clear',
              style: TextStyle(color: Color(0xFFDA2A2A), fontSize: 12),
            ),
          ],
        ),
      ),
      onDismissed: (_) {
        _updateAnswer(q, '');
        _flaggedQuestions.remove(q.number);
      },
      child: _QuestionRow(
        key: _rowKeys[q.number],
        question: q,
        assessment: _assessment!,
        isActive: filteredIndex == _activeQuestionIndex,
        isFlagged: _flaggedQuestions.contains(q.number),
        onFlagToggled: () => _toggleFlag(q.number),
        onAnswerChanged: (answer) => _updateAnswer(q, answer),
        onTypeChanged: (type) => _updateType(q, type),
        onPointsChanged: (pts) => _updatePoints(q, pts),
      ),
    );
  }

  void _editSection(ExamSection section) {
    final assessment = _assessment!;
    final updated = assessment.questions.map((q) {
      if (q.number >= section.startQ && q.number <= section.endQ) {
        final sectionType = _parseQuestionType(section.type);
        if (q.type != sectionType || q.points != section.points) {
          return q.copyWith(
            type: sectionType,
            points: section.points,
            options: sectionType == QuestionType.trueFalse
                ? ['True', 'False']
                : (sectionType == QuestionType.multiAnswer
                      ? const ['A', 'B', 'C', 'D', 'E']
                      : q.options),
          );
        }
      }
      return q;
    }).toList();

    setState(() => _assessment = assessment.copyWith(questions: updated));
    _autoSave();
  }

  Widget _toolbarButton(
    String label,
    IconData icon, {
    bool isPrimary = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF3D6B4F) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isPrimary ? const Color(0xFF3D6B4F) : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isPrimary ? const Color(0xFFA8D5BA) : AppTheme.lightText,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: isPrimary ? const Color(0xFFA8D5BA) : AppTheme.lightText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarDropdown<T>({
    required String hint,
    required List<T> items,
    required String Function(T) labelBuilder,
    required void Function(T) onChanged,
  }) {
    return DropdownButton<T>(
      value: null,
      hint: Text(
        hint,
        style: const TextStyle(fontSize: 10, color: AppTheme.lightText),
      ),
      isDense: true,
      underline: const SizedBox(),
      items: items
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(
                labelBuilder(item),
                style: const TextStyle(fontSize: 10),
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  void _scrollToNextEmpty() {
    if (_assessment == null) return;
    for (final q in _assessment!.questions) {
      if (q.correctAnswer == null || q.correctAnswer.toString().isEmpty) {
        final key = _rowKeys[q.number];
        if (key?.currentContext != null) {
          Scrollable.ensureVisible(
            key!.currentContext!,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
        return;
      }
    }
  }

  void _updateAnswer(Question q, dynamic answer) {
    if (_isLocked) return;
    final assessment = _assessment!;
    final updated = assessment.questions.map((question) {
      if (question.number == q.number) {
        return question.copyWith(correctAnswer: answer);
      }
      return question;
    }).toList();
    setState(() => _assessment = assessment.copyWith(questions: updated));
    _autoSave();

    // Auto-advance: scroll to next unanswered question after a short delay
    if (_autoAdvanceEnabled && answer.toString().isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _scrollToNextUnanswered();
      });
    }
  }

  void _scrollToNextUnanswered() {
    final questions = _filteredQuestions;
    if (questions.isEmpty) return;

    // Find next unanswered question starting from current position
    int nextIndex = -1;
    for (int i = _activeQuestionIndex + 1; i < questions.length; i++) {
      final q = questions[i];
      final answer = q.correctAnswer?.toString() ?? '';
      if (answer.isEmpty) {
        nextIndex = i;
        break;
      }
    }

    // If no unanswered below, wrap around from the top
    if (nextIndex == -1) {
      for (int i = 0; i < questions.length; i++) {
        final q = questions[i];
        final answer = q.correctAnswer?.toString() ?? '';
        if (answer.isEmpty) {
          nextIndex = i;
          break;
        }
      }
    }

    // If all answered, stay where we are
    if (nextIndex == -1) return;

    setState(() => _activeQuestionIndex = nextIndex);

    // Smooth scroll to the next question
    final key = _rowKeys[questions[nextIndex].number];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.1,
      );
    }
  }

  // ── Auto-Save ────────────────────────────────────────────────────────

  Future<void> _autoSave() async {
    if (_assessment == null) return;
    try {
      // Update draft timestamp in settings
      final settings = Map<String, dynamic>.from(_assessment!.settings);
      settings['lastDraftTimestamp'] = DateTime.now().toIso8601String();
      _assessment = _assessment!.copyWith(settings: settings);

      final provider = context.read<AssessmentProvider>();
      await provider.updateAssessment(_assessment!);
      if (mounted) {
        setState(() => _lastSavedAt = DateTime.now());
      }
    } catch (e) {
      debugPrint('[AnswerKey] auto-save failed: $e');
    }
  }

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      // Persist lock state in assessment settings
      final settings = Map<String, dynamic>.from(_assessment!.settings);
      settings['answerKeyLocked'] = _isLocked;
      _assessment = _assessment!.copyWith(settings: settings);
    });
    _autoSave();
  }

  void _toggleFlag(int questionNumber) {
    setState(() {
      if (_flaggedQuestions.contains(questionNumber)) {
        _flaggedQuestions.remove(questionNumber);
      } else {
        _flaggedQuestions.add(questionNumber);
      }
    });
  }

  void _checkForRecoveryDraft() {
    if (_assessment == null) return;
    final lastDraftTimestamp = _assessment!.settings['lastDraftTimestamp'];
    if (lastDraftTimestamp == null) return;

    try {
      final timestamp = DateTime.parse(lastDraftTimestamp.toString());
      final age = DateTime.now().difference(timestamp);
      if (age.inMinutes > 5) {
        // Count answered questions as a rough recovery indicator
        final answered = _assessment!.answeredQuestionCount;
        if (answered > 0) {
          setState(() {
            _showRecoveryBanner = true;
            _recoveredCount = answered;
          });
        }
      }
    } catch (_) {
      // Ignore parse errors
    }
  }

  void _loadSections() {
    if (_assessment == null) return;
    final stored = _assessment!.settings['sections'];
    if (stored is List && stored.isNotEmpty) {
      _sections = stored
          .map((s) => ExamSection.fromMap(s as Map<String, dynamic>))
          .toList();
    } else {
      _sections = [];
    }
  }

  Future<void> _openSectionSetup() async {
    if (_assessment == null) return;
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.answerKeySectionSetup,
      arguments: _assessment,
    );

    if (result is SectionSetupResult && mounted) {
      _applySections(result.sections);
    }
  }

  void _applySections(List<ExamSection> sections) {
    // Apply section type and points to questions in each section
    final assessment = _assessment!;
    final updated = assessment.questions.map((q) {
      for (final section in sections) {
        if (q.number >= section.startQ && q.number <= section.endQ) {
          final sectionType = _parseQuestionType(section.type);
          if (q.type != sectionType || q.points != section.points) {
            return q.copyWith(
              type: sectionType,
              points: section.points,
              options: sectionType == QuestionType.trueFalse
                  ? ['True', 'False']
                  : (sectionType == QuestionType.multiAnswer
                        ? const ['A', 'B', 'C', 'D', 'E']
                        : q.options),
            );
          }
        }
      }
      return q;
    }).toList();

    setState(() {
      _assessment = assessment.copyWith(questions: updated);
      _sections = sections;
    });

    // Persist sections to settings
    final settings = Map<String, dynamic>.from(_assessment!.settings);
    settings['sections'] = sections.map((s) => s.toMap()).toList();
    _assessment = _assessment!.copyWith(settings: settings);
    _autoSave();
  }

  QuestionType _parseQuestionType(String type) {
    return switch (type) {
      'mcq' => QuestionType.mcq,
      'trueFalse' => QuestionType.trueFalse,
      'shortAnswer' => QuestionType.shortAnswer,
      'essay' => QuestionType.essay,
      'matching' => QuestionType.matching,
      'multiAnswer' => QuestionType.multiAnswer,
      _ => QuestionType.mcq,
    };
  }

  void _updateType(Question q, QuestionType type) {
    if (_isLocked) return;
    final assessment = _assessment!;
    final updated = assessment.questions.map((question) {
      if (question.number == q.number) {
        return question.copyWith(
          type: type,
          correctAnswer: '',
          options:
              type == QuestionType.trueFalse || type == QuestionType.multiAnswer
              ? (type == QuestionType.trueFalse
                    ? ['True', 'False']
                    : const ['A', 'B', 'C', 'D', 'E'])
              : question.options,
        );
      }
      return question;
    }).toList();
    setState(() => _assessment = assessment.copyWith(questions: updated));
    _autoSave();
  }

  void _updatePoints(Question q, double points) {
    if (_isLocked) return;
    final assessment = _assessment!;
    final updated = assessment.questions.map((question) {
      if (question.number == q.number) {
        return question.copyWith(points: points);
      }
      return question;
    }).toList();
    setState(() => _assessment = assessment.copyWith(questions: updated));
    _autoSave();
  }

  // ── Photo Scan ───────────────────────────────────────────────────────

  Future<void> _openPhotoScan(
    BuildContext context,
    Assessment assessment,
  ) async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.answerKeyPhotoScan,
      arguments: assessment.questionCount,
    );

    if (result is PhotoScanResult && mounted) {
      _applyPhotoScanAnswers(assessment, result);
    }
  }

  void _applyPhotoScanAnswers(
    Assessment assessment,
    PhotoScanResult scanResult,
  ) {
    final updated = assessment.questions.map((question) {
      // Find matching OCR answer by question number
      final ocrAnswer = scanResult.answers
          .where((a) => a.questionNumber == question.number)
          .toList();
      if (ocrAnswer.isEmpty) return question;

      final answer = ocrAnswer.first.answer;
      // Only apply to unanswered questions (don't overwrite existing answers)
      final currentAnswer = question.correctAnswer?.toString() ?? '';
      if (currentAnswer.isNotEmpty) return question;

      // Auto-detect type from answer format
      var type = question.type;
      if (type == QuestionType.mcq) {
        if (answer == 'True' || answer == 'False') {
          type = QuestionType.trueFalse;
        } else if (answer.contains(',')) {
          type = QuestionType.multiAnswer;
        }
      }

      return question.copyWith(correctAnswer: answer, type: type);
    }).toList();

    setState(() => _assessment = assessment.copyWith(questions: updated));

    // Show feedback
    final applied = scanResult.answers.length;
    final total = assessment.questionCount;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied $applied answers from photo scan ($total questions total)',
          ),
          backgroundColor: const Color(0xFF18A558),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _setAllType(Assessment assessment, QuestionType type) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Change all to ${_typeLabel(type)}?'),
        content: Text(
          'This will change all ${assessment.questionCount} questions to ${_typeLabel(type)}. Existing answers will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final updated = assessment.questions
                  .map(
                    (q) => Question(
                      id: q.id,
                      number: q.number,
                      type: type,
                      text: q.text,
                      points: q.points,
                      options: type == QuestionType.trueFalse
                          ? ['True', 'False']
                          : (type == QuestionType.multiAnswer
                                ? const ['A', 'B', 'C', 'D', 'E']
                                : q.options),
                      correctAnswer: '',
                      essayRubric: q.essayRubric,
                    ),
                  )
                  .toList();
              setState(
                () => _assessment = assessment.copyWith(questions: updated),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _setAllPoints(Assessment assessment, double pts) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set all to ${pts.toInt()} pts?'),
        content: Text(
          'This will set all ${assessment.questionCount} questions to ${pts.toInt()} points.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final updated = assessment.questions
                  .map(
                    (q) => Question(
                      id: q.id,
                      number: q.number,
                      type: q.type,
                      text: q.text,
                      points: pts,
                      options: q.options,
                      correctAnswer: q.correctAnswer,
                      essayRubric: q.essayRubric,
                    ),
                  )
                  .toList();
              setState(
                () => _assessment = assessment.copyWith(questions: updated),
              );
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _showBulkPasteDialog(Assessment assessment) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final parsed = _parseBulkPaste(
            controller.text,
            assessment.questionCount,
          );
          return AlertDialog(
            title: const Text('Paste Answer Key'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'A, B, C, D, A+C, "mitochondria", T, F...',
                      helperText:
                          'MCQ=A-E, Multi=A+C, T/F=T or F, Short="text"',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  if (parsed != null && parsed.isNotEmpty) ...[
                    Text(
                      'Preview (${parsed.length} answers):',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: parsed
                              .map(
                                (p) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryGreen.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Q${p['num']}: ${p['answer']} (${p['type']})',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.darkText,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ] else if (controller.text.isNotEmpty) ...[
                    const Text(
                      'Could not parse. Format: A, B+C, "text", T',
                      style: TextStyle(
                        color: AppTheme.primaryRed,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: (parsed != null && parsed.isNotEmpty)
                    ? () {
                        Navigator.pop(ctx);
                        _applyBulkPaste(assessment, parsed);
                      }
                    : null,
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>>? _parseBulkPaste(String raw, int expectedCount) {
    if (raw.trim().isEmpty) return null;
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final qNum = i + 1;

      if (part == '—' || part == '-' || part.isEmpty) {
        continue;
      }

      // Quoted text → short answer
      if (part.startsWith('"') && part.endsWith('"')) {
        results.add({
          'num': qNum,
          'answer': part.substring(1, part.length - 1),
          'type': 'SHORT',
        });
        continue;
      }
      if (part.startsWith('"')) {
        results.add({
          'num': qNum,
          'answer': part.replaceAll('"', ''),
          'type': 'SHORT',
        });
        continue;
      }

      // Number+letter pairs → matching (e.g., "1C,2A,3D")
      if (RegExp(r'^\d+[A-E]').hasMatch(part)) {
        results.add({'num': qNum, 'answer': part, 'type': 'MATCH'});
        continue;
      }

      // Letters with + → multi-answer (e.g., "A+C")
      if (part.contains('+') &&
          RegExp(r'^[A-Ea-e]+(\+[A-Ea-e]+)+$').hasMatch(part)) {
        results.add({
          'num': qNum,
          'answer': part.toUpperCase(),
          'type': 'MULTI',
        });
        continue;
      }

      // T or F → true/false
      final upper = part.toUpperCase();
      if (upper == 'T' || upper == 'TRUE' || upper == 'F' || upper == 'FALSE') {
        final tfVal = upper.startsWith('T') ? 'True' : 'False';
        results.add({'num': qNum, 'answer': tfVal, 'type': 'T/F'});
        continue;
      }

      // Single letter A-E → MCQ
      if (RegExp(r'^[A-Ea-e]$').hasMatch(part)) {
        results.add({'num': qNum, 'answer': upper, 'type': 'MCQ'});
        continue;
      }

      // Anything else → short answer
      results.add({'num': qNum, 'answer': part, 'type': 'SHORT'});
    }

    return results.isEmpty ? null : results;
  }

  void _applyBulkPaste(
    Assessment assessment,
    List<Map<String, dynamic>> parsed,
  ) {
    final updated = assessment.questions.map((q) {
      final match = parsed.where((p) => p['num'] == q.number);
      if (match.isEmpty) return q;
      final p = match.first;
      final typeStr = p['type'] as String;
      final answer = p['answer'] as String;

      QuestionType newType;
      switch (typeStr) {
        case 'MCQ':
          newType = QuestionType.mcq;
          break;
        case 'T/F':
          newType = QuestionType.trueFalse;
          break;
        case 'MULTI':
          newType = QuestionType.multiAnswer;
          break;
        case 'SHORT':
          newType = QuestionType.shortAnswer;
          break;
        case 'MATCH':
          newType = QuestionType.matching;
          break;
        default:
          newType = q.type;
      }

      return q.copyWith(
        type: newType,
        correctAnswer: answer,
        options: newType == QuestionType.trueFalse
            ? ['True', 'False']
            : (newType == QuestionType.multiAnswer
                  ? const ['A', 'B', 'C', 'D', 'E']
                  : q.options),
      );
    }).toList();
    setState(() => _assessment = assessment.copyWith(questions: updated));
  }

  Future<void> _handleDone(
    BuildContext context,
    Assessment assessment,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();
    final currentFingerprint = const AnswerKeyFingerprintService().compute(
      assessment,
    );
    final keyChanged =
        _preEditFingerprint != null &&
        _preEditFingerprint!.isNotEmpty &&
        currentFingerprint != _preEditFingerprint;

    if (!keyChanged) {
      await provider.saveAssessment(assessment);
      if (!context.mounted) return;
      _navigateAfterSave(context, assessment, returnToReview);
      return;
    }

    final List<ScanResult> results = await HybridGradingService()
        .loadScanResults(assessment.id);
    if (!context.mounted) return;

    if (results.isEmpty) {
      final updated = await provider.saveAnswerKeyChange(assessment);
      if (!context.mounted) return;
      _navigateAfterSave(context, updated, returnToReview);
      return;
    }

    await _showRecalculationDialog(
      context,
      assessment,
      results,
      returnToReview,
    );
  }

  void _navigateAfterSave(
    BuildContext context,
    Assessment assessment,
    bool returnToReview,
  ) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final returnToConfirmation =
        args is AnswerKeyRouteArgs && args.returnToConfirmation;

    if (returnToConfirmation) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.camera,
        arguments: {'assessment': assessment, 'scanMode': 'batch'},
      );
      return;
    }
    if (returnToReview) {
      Navigator.pop(context, assessment);
      return;
    }
    Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
  }

  Future<void> _showRecalculationDialog(
    BuildContext context,
    Assessment assessment,
    List<ScanResult> results,
    bool returnToReview,
  ) async {
    final diff = _computeDiff(assessment);

    final action = await showDialog<_KeyChangeAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Answer key changed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${results.length} paper${results.length == 1 ? ' was' : 's were'} graded '
              'using the previous answer key. Their scores must be recalculated.',
            ),
            if (diff.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Changes:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 4),
              ...diff
                  .take(5)
                  .map(
                    (d) => Text(
                      '  $d',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.lightText,
                      ),
                    ),
                  ),
              if (diff.length > 5)
                Text(
                  '  and ${diff.length - 5} more...',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.lightText,
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _KeyChangeAction.cancel),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              context,
              _KeyChangeAction.saveAndRecalculateLater,
            ),
            child: const Text('Save & recalculate later'),
          ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.pop(context, _KeyChangeAction.recalculateNow),
            icon: const Icon(Icons.refresh),
            label: const Text('Recalculate now'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;

    switch (action) {
      case _KeyChangeAction.recalculateNow:
        await _recalculateNow(context, assessment, results, returnToReview);
        break;
      case _KeyChangeAction.saveAndRecalculateLater:
        await _saveAndRecalculateLater(context, assessment, returnToReview);
        break;
      case _KeyChangeAction.cancel:
      case null:
        break;
    }
  }

  List<String> _computeDiff(Assessment assessment) {
    final changes = <String>[];
    for (final q in assessment.questions) {
      final oldAnswer = _originalAnswers[q.number] ?? '';
      final newAnswer = q.correctAnswer?.toString() ?? '';
      if (oldAnswer != newAnswer &&
          (oldAnswer.isNotEmpty || newAnswer.isNotEmpty)) {
        final oldDisplay = oldAnswer.isEmpty ? '(empty)' : oldAnswer;
        final newDisplay = newAnswer.isEmpty ? '(empty)' : newAnswer;
        changes.add('Q${q.number}: $oldDisplay → $newDisplay');
      }
    }
    return changes;
  }

  Future<void> _recalculateNow(
    BuildContext context,
    Assessment assessment,
    List<ScanResult> results,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();
    final updatedAssessment = await provider.saveAnswerKeyChange(assessment);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Recalculating ${results.length} results...'),
        duration: const Duration(seconds: 2),
      ),
    );

    final result = await AnswerKeyRecalculationService().recalculateAll(
      assessment: updatedAssessment,
      results: results,
    );

    if (!context.mounted) return;

    final summary = StringBuffer();
    summary.write('${result.recalculated} recalculated');
    if (result.scoresChanged > 0)
      summary.write(', ${result.scoresChanged} scores changed');
    if (result.scoresUnchanged > 0)
      summary.write(', ${result.scoresUnchanged} unchanged');
    if (result.preserved > 0)
      summary.write(', ${result.preserved} preserved (manual)');
    if (result.failed > 0) summary.write(', ${result.failed} failed');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary.toString()),
        backgroundColor: result.allSucceeded
            ? AppTheme.primaryGreen
            : Colors.orange,
      ),
    );

    if (returnToReview) {
      Navigator.pop(context, updatedAssessment);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }

  Future<void> _saveAndRecalculateLater(
    BuildContext context,
    Assessment assessment,
    bool returnToReview,
  ) async {
    final provider = context.read<AssessmentProvider>();
    final updatedAssessment = await provider.saveAnswerKeyChange(assessment);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Key saved. Recalculate results when ready.'),
      ),
    );

    if (returnToReview) {
      Navigator.pop(context, updatedAssessment);
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
    }
  }
}

// ─────────────────────────────────────────────
//  Question Row Widget
// ─────────────────────────────────────────────

class _QuestionRow extends StatelessWidget {
  final Question question;
  final Assessment assessment;
  final Function(dynamic) onAnswerChanged;
  final Function(QuestionType) onTypeChanged;
  final Function(double) onPointsChanged;
  final bool isActive;
  final bool isFlagged;
  final VoidCallback onFlagToggled;

  const _QuestionRow({
    super.key,
    required this.question,
    required this.assessment,
    required this.onAnswerChanged,
    required this.onTypeChanged,
    required this.onPointsChanged,
    this.isActive = false,
    this.isFlagged = false,
    required this.onFlagToggled,
  });

  bool get _isAnswered =>
      question.correctAnswer != null &&
      question.correctAnswer.toString().isNotEmpty;

  Color get _rowBg => _isAnswered
      ? const Color(0xFFA8D5BA).withValues(alpha: 0.06)
      : const Color(0xFFF0C674).withValues(alpha: 0.04);

  Color get _dotColor => _isAnswered
      ? const Color(0xFFA8D5BA)
      : const Color(0xFFF0C674).withValues(alpha: 0.6);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isFlagged
              ? const Color(0xFFF0C674)
              : isActive
              ? const Color(0xFF7EB8DA)
              : Colors.grey.shade200.withValues(alpha: 0.5),
          width: (isFlagged || isActive) ? 3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopRow(context),
          const SizedBox(height: 6),
          _buildAnswerArea(context),
        ],
      ),
    );
  }

  Widget _buildTopRow(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 22,
          child: Text(
            '${question.number}'.padLeft(2, '0'),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppTheme.lightText,
            ),
          ),
        ),
        const SizedBox(width: 6),
        _buildTypeBadge(),
        const Spacer(),
        GestureDetector(
          onTap: onFlagToggled,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              isFlagged ? Icons.star : Icons.star_border,
              size: 16,
              color: isFlagged ? const Color(0xFFF0C674) : Colors.grey.shade400,
            ),
          ),
        ),
        _buildPointsChip(context),
      ],
    );
  }

  Widget _buildTypeBadge() {
    final label = _typeLabel(question.type);
    final bgColor = _typeBgColor(question.type);
    final textColor = _typeTextColor(question.type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 8,
          color: textColor,
          letterSpacing: 0.04,
        ),
      ),
    );
  }

  Widget _buildPointsChip(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPointsDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          '${question.points.toInt()}pt',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 9,
            color: AppTheme.lightText,
          ),
        ),
      ),
    );
  }

  Widget _buildAnswerArea(BuildContext context) {
    return switch (question.type) {
      QuestionType.mcq => _buildMcqChips(),
      QuestionType.trueFalse => _buildTfChips(),
      QuestionType.multiAnswer => _buildMultiChip(context),
      QuestionType.shortAnswer ||
      QuestionType.essay => _buildShortAnswerInline(context),
      QuestionType.matching => _buildMatchingInline(context),
    };
  }

  Widget _buildMcqChips() {
    return Row(
      children: question.options.take(5).map((opt) {
        final isSelected =
            question.correctAnswer?.toString().toUpperCase() ==
            opt.toUpperCase();
        return GestureDetector(
          onTap: () => onAnswerChanged(opt),
          child: Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF3D6B4F)
                  : const Color(0xFF242424),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFA8D5BA)
                    : Colors.grey.shade300,
                width: isSelected ? 2 : 1.5,
              ),
            ),
            child: Text(
              opt,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isSelected
                    ? const Color(0xFFA8D5BA)
                    : const Color(0xFF555555),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTfChips() {
    return Row(
      children: ['True', 'False'].map((opt) {
        final isSelected = question.correctAnswer?.toString() == opt;
        final isTrue = opt == 'True';
        final selectedColor = isTrue
            ? AppTheme.primaryGreen
            : AppTheme.primaryRed;
        return GestureDetector(
          onTap: () => onAnswerChanged(opt),
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? selectedColor : const Color(0xFF242424),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected ? selectedColor : Colors.grey.shade300,
                width: isSelected ? 2 : 1.5,
              ),
            ),
            child: Text(
              opt,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isSelected ? Colors.white : const Color(0xFF555555),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMultiChip(BuildContext context) {
    final answer = question.correctAnswer?.toString() ?? '';
    final display = answer.isEmpty ? '+' : answer.replaceAll(',', '+');
    final isSet = answer.isNotEmpty;

    return GestureDetector(
      onTap: () => _showMultiSelector(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSet ? const Color(0xFF3A2650) : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSet ? const Color(0xFFC5A3E8) : Colors.grey.shade300,
            width: isSet ? 2 : 1.5,
          ),
        ),
        child: Text(
          display,
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: isSet ? const Color(0xFFC5A3E8) : const Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  Widget _buildShortAnswerInline(BuildContext context) {
    final answer = question.correctAnswer?.toString() ?? '';
    final alts = answer.contains('|')
        ? answer.split('|').skip(1).toList()
        : <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _showTextAnswerDialog(context),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: answer.isNotEmpty
                  ? const Color(0xFF5C3A1A).withValues(alpha: 0.3)
                  : const Color(0xFF242424),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: answer.isNotEmpty
                    ? const Color(0xFFE8B07A)
                    : Colors.grey.shade300,
                width: answer.isNotEmpty ? 2 : 1.5,
                style: answer.isNotEmpty ? BorderStyle.solid : BorderStyle.none,
              ),
            ),
            child: Text(
              answer.isEmpty ? 'Tap to set answer' : answer.split('|').first,
              style: TextStyle(
                fontSize: 12,
                color: answer.isNotEmpty
                    ? const Color(0xFFE8B07A)
                    : const Color(0xFF555555),
              ),
            ),
          ),
        ),
        if (alts.isNotEmpty || answer.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ...alts.map(
                (alt) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF5C3A1A).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFE8B07A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    alt,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFE8B07A),
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showAddAltDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: const Color(0xFFE8B07A).withValues(alpha: 0.3),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Text(
                    '+ Add alt',
                    style: TextStyle(
                      fontSize: 9,
                      color: const Color(0xFFE8B07A).withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
              if (answer.isNotEmpty)
                Text(
                  '${1 + alts.length} accepted',
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppTheme.lightText,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildMatchingInline(BuildContext context) {
    final answer = question.correctAnswer?.toString() ?? '';
    final pairs = answer.isNotEmpty
        ? answer
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList()
        : <String>[];

    return GestureDetector(
      onTap: () => _showMatchingDialog(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: pairs.isNotEmpty
              ? const Color(0xFF5C2040).withValues(alpha: 0.2)
              : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: pairs.isNotEmpty
                ? const Color(0xFFE8A0B8)
                : Colors.grey.shade300,
            width: pairs.isNotEmpty ? 2 : 1.5,
            style: pairs.isNotEmpty ? BorderStyle.solid : BorderStyle.none,
          ),
        ),
        child: pairs.isEmpty
            ? const Text(
                'Tap to set matching pairs...',
                style: TextStyle(fontSize: 11, color: AppTheme.lightText),
              )
            : Wrap(
                spacing: 6,
                runSpacing: 4,
                children: pairs.map((pair) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5C2040).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pair,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: Color(0xFFE8A0B8),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  void _showMultiSelector(BuildContext context) {
    final current =
        question.correctAnswer
            ?.toString()
            .split(',')
            .map((s) => s.trim().toUpperCase())
            .toSet() ??
        {};
    final selected = Set<String>.from(current);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Q${question.number} — Select all correct'),
            content: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['A', 'B', 'C', 'D', 'E'].map((letter) {
                final isSelected = selected.contains(letter);
                return GestureDetector(
                  onTap: () {
                    setDialogState(() {
                      if (isSelected) {
                        selected.remove(letter);
                      } else {
                        selected.add(letter);
                      }
                    });
                  },
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF3A2650)
                          : const Color(0xFF242424),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFC5A3E8)
                            : Colors.grey.shade300,
                        width: isSelected ? 2.5 : 1.5,
                      ),
                    ),
                    child: Text(
                      letter,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isSelected
                            ? const Color(0xFFC5A3E8)
                            : const Color(0xFF555555),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  final answer = selected.toList()..sort();
                  onAnswerChanged(answer.join(','));
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTextAnswerDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: question.correctAnswer?.toString().split('|').first ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Q${question.number} Answer'),
        content: TextField(
          controller: ctrl,
          maxLines: question.type == QuestionType.essay ? 4 : 1,
          decoration: const InputDecoration(labelText: 'Correct answer'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newAnswer = ctrl.text.trim();
              final existing = question.correctAnswer?.toString() ?? '';
              final alts = existing.contains('|')
                  ? existing.split('|').skip(1).join('|')
                  : '';
              final full = alts.isNotEmpty ? '$newAnswer|$alts' : newAnswer;
              onAnswerChanged(full);
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showAddAltDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Q${question.number} — Add alternative'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Alternative answer',
            hintText: 'e.g. another valid spelling',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final alt = ctrl.text.trim();
              if (alt.isEmpty) {
                ctrl.dispose();
                Navigator.pop(ctx);
                return;
              }
              final existing = question.correctAnswer?.toString() ?? '';
              final full = '$existing|$alt';
              onAnswerChanged(full);
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showMatchingDialog(BuildContext context) {
    final answer = question.correctAnswer?.toString() ?? '';
    final pairs = answer.isNotEmpty
        ? answer
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .toList()
        : <String>[];
    final usedRight = pairs
        .map((p) => p.length > 1 ? p.substring(1).toUpperCase() : '')
        .toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Q${question.number} — Matching pairs'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final pairStr = i < pairs.length ? pairs[i] : '';
                  final left = '${i + 1}';
                  final right = pairStr.length > 1
                      ? pairStr.substring(1).toUpperCase()
                      : '';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          alignment: Alignment.center,
                          child: Text(
                            left,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: AppTheme.lightText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '→',
                          style: TextStyle(color: AppTheme.lightText),
                        ),
                        const SizedBox(width: 4),
                        if (right.isEmpty)
                          DropdownButton<String>(
                            value: null,
                            hint: const Text(
                              'select',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.lightText,
                              ),
                            ),
                            isDense: true,
                            items: ['A', 'B', 'C', 'D', 'E']
                                .where(
                                  (l) => !usedRight.contains(l) || l == right,
                                )
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val == null) return;
                              setDialogState(() {
                                if (i < pairs.length) {
                                  pairs[i] = '$left$val';
                                } else {
                                  while (pairs.length <= i) {
                                    pairs.add('');
                                  }
                                  pairs[i] = '$left$val';
                                }
                                usedRight.add(val);
                              });
                            },
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF5C2040,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              right,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Color(0xFFE8A0B8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  final validPairs = pairs.where((p) => p.length > 1).toList();
                  onAnswerChanged(validPairs.join(','));
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showPointsDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: question.points.toInt().toString(),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Q${question.number} — Points'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Points'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final pts = double.tryParse(ctrl.text);
              if (pts != null && pts > 0 && pts <= 100) {
                onPointsChanged(pts);
              }
              ctrl.dispose();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _typeLabel(QuestionType type) {
    return switch (type) {
      QuestionType.mcq => 'MCQ',
      QuestionType.trueFalse => 'T/F',
      QuestionType.shortAnswer => 'SHORT',
      QuestionType.essay => 'ESSAY',
      QuestionType.matching => 'MATCH',
      QuestionType.multiAnswer => 'MULTI',
    };
  }

  Color _typeBgColor(QuestionType type) {
    return switch (type) {
      QuestionType.mcq => const Color(0xFF1E3A4F),
      QuestionType.trueFalse => const Color(0xFF5C4A1A),
      QuestionType.shortAnswer => const Color(0xFF5C3A1A),
      QuestionType.essay => const Color(0xFF3A2650),
      QuestionType.matching => const Color(0xFF5C2040),
      QuestionType.multiAnswer => const Color(0xFF3A2650),
    };
  }

  Color _typeTextColor(QuestionType type) {
    return switch (type) {
      QuestionType.mcq => const Color(0xFF7EB8DA),
      QuestionType.trueFalse => const Color(0xFFF0C674),
      QuestionType.shortAnswer => const Color(0xFFE8B07A),
      QuestionType.essay => const Color(0xFFC5A3E8),
      QuestionType.matching => const Color(0xFFE8A0B8),
      QuestionType.multiAnswer => const Color(0xFFC5A3E8),
    };
  }
}

class _ListItem {
  final ExamSection? section;
  final Question? question;
  final int answeredCount;

  const _ListItem.section(this.section, this.answeredCount) : question = null;
  const _ListItem.question(this.question) : section = null, answeredCount = 0;

  bool get isSection => section != null;
}
