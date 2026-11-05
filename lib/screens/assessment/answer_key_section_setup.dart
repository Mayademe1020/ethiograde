import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/assessment.dart';
import '../../widgets/assessment/section_header.dart';

class SectionSetupResult {
  final List<ExamSection> sections;
  const SectionSetupResult(this.sections);
}

class AnswerKeySectionSetup extends StatefulWidget {
  final Assessment assessment;
  const AnswerKeySectionSetup({super.key, required this.assessment});

  @override
  State<AnswerKeySectionSetup> createState() => _AnswerKeySectionSetupState();
}

class _AnswerKeySectionSetupState extends State<AnswerKeySectionSetup> {
  late List<ExamSection> _sections;
  final _letterLabels = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  @override
  void initState() {
    super.initState();
    _sections = _buildDefaultSections();
  }

  List<ExamSection> _buildDefaultSections() {
    final total = widget.assessment.questionCount;
    // Prefer the canonical persisted structure (single source of truth).
    final canonical = widget.assessment.sections;
    if (canonical != null && canonical.isNotEmpty) {
      return [
        for (var i = 0; i < canonical.length; i++)
          ExamSection(
            name: _letterLabels[i],
            startQ: canonical[i].start,
            endQ: canonical[i].end,
            type: canonical[i].type.name,
          ),
      ];
    }
    // Legacy fallback (older assessments that still store sections here).
    final existing = widget.assessment.settings['sections'];
    if (existing is List && existing.isNotEmpty) {
      return existing
          .map((s) => ExamSection.fromMap(s as Map<String, dynamic>))
          .toList();
    }
    return [
      ExamSection(name: 'A', startQ: 1, endQ: total, type: 'mcq'),
    ];
  }

  void _addSection() {
    if (_sections.length >= 26) return;
    final last = _sections.last;
    final nextStart = last.endQ + 1;
    final total = widget.assessment.questionCount;
    if (nextStart > total) return;

    setState(() {
      _sections.add(
        ExamSection(
          name: _letterLabels[_sections.length],
          startQ: nextStart,
          endQ: total,
          type: 'mcq',
        ),
      );
    });
  }

  void _removeSection(int index) {
    if (_sections.length <= 1) return;
    setState(() {
      final removed = _sections.removeAt(index);
      // Redistribute questions: expand previous section to cover removed range
      if (index > 0) {
        final prev = _sections[index - 1];
        _sections[index - 1] = ExamSection(
          name: prev.name,
          startQ: prev.startQ,
          endQ: removed.endQ,
          type: prev.type,
        );
      } else if (_sections.isNotEmpty) {
        final next = _sections[0];
        _sections[0] = ExamSection(
          name: next.name,
          startQ: removed.startQ,
          endQ: next.endQ,
          type: next.type,
        );
      }
      // Re-letter sections
      for (var i = 0; i < _sections.length; i++) {
        _sections[i] = ExamSection(
          name: _letterLabels[i],
          startQ: _sections[i].startQ,
          endQ: _sections[i].endQ,
          type: _sections[i].type,
        );
      }
    });
  }

  void _updateSection(
    int index, {
    int? startQ,
    int? endQ,
    String? type,
  }) {
    setState(() {
      final old = _sections[index];
      _sections[index] = ExamSection(
        name: old.name,
        startQ: startQ ?? old.startQ,
        endQ: endQ ?? old.endQ,
        type: type ?? old.type,
      );
    });
  }

  bool _isValid() {
    if (_sections.isEmpty) return false;
    final total = widget.assessment.questionCount;
    // Check coverage
    final sorted = List<ExamSection>.from(_sections)
      ..sort((a, b) => a.startQ.compareTo(b.startQ));
    if (sorted.first.startQ != 1) return false;
    if (sorted.last.endQ != total) return false;
    // Check no overlaps
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i].startQ <= sorted[i - 1].endQ) return false;
    }
    return true;
  }

  void _apply() {
    if (!_isValid()) return;
    Navigator.pop(context, SectionSetupResult(_sections));
  }

  void _skip() {
    final total = widget.assessment.questionCount;
    Navigator.pop(
      context,
      SectionSetupResult([
        ExamSection(
          name: 'A',
          startQ: 1,
          endQ: total,
          type: 'mcq',
          
        ),
      ]),
    );
  }

  void _requestAutoFix() {
    final total = widget.assessment.questionCount;
    final fixed = autoFixSections(_sections, total);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fix sections automatically?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Your sections overlap or leave gaps. We'll adjust them into "
                'a clean split that keeps each section’s type:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                describeSections(fixed),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
              setState(() => _sections = fixed);
            },
            child: const Text('Fix & apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.assessment.questionCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Up Sections'),
        actions: [TextButton(onPressed: _skip, child: const Text('Skip'))],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              decoration: BoxDecoration(
                color: context.primaryGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Organize $total questions into sections. Each section can have a different question type.',
                style: TextStyle(fontSize: 12, color: context.lightText),
              ),
            ),
            if (!_isValid())
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDA2A2A).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFDA2A2A).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sections must cover 1 to N with no gaps or overlaps.',
                      style: TextStyle(
                        color: Color(0xFFDA2A2A),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _requestAutoFix,
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Fix automatically'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.primaryGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sections.length,
                itemBuilder: (context, index) => _buildSectionCard(index, total),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_sections.length < 26)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _addSection,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Section'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isValid() ? _apply : null,
                      child: const Text('Start Answering'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(int index, int total) {
    final section = _sections[index];
    final canRemove = _sections.length > 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SectionHeader.typeColor(section.type),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Section ${section.name}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: SectionHeader.typeColor(section.type),
                  ),
                ),
                const Spacer(),
                if (canRemove)
                  IconButton(
                    onPressed: () => _removeSection(index),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: context.primaryRed,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildRangeField(
                    label: 'Start Q',
                    value: section.startQ,
                    min: index == 0 ? 1 : _sections[index - 1].endQ + 1,
                    max: total,
                    onChanged: (v) => _updateSection(index, startQ: v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildRangeField(
                    label: 'End Q',
                    value: section.endQ,
                    min: section.startQ,
                    max: total,
                    onChanged: (v) => _updateSection(index, endQ: v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTypeDropdown(
                    value: section.type,
                    onChanged: (v) => _updateSection(index, type: v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRangeField({
    required String label,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: context.lightText)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: () {
              // Always include the current value, even if an overlap/gap left it
              // outside the [min, max] clamp (otherwise the dropdown crashes and
              // the teacher can't reach the auto-fix).
              final lo = value < min ? value : min;
              final hi = value > max ? value : max;
              final count = hi - lo + 1;
              if (count <= 0) {
                return [
                  DropdownMenuItem(
                    value: value,
                    child: Text('$value', style: const TextStyle(fontSize: 13)),
                  ),
                ];
              }
              return List.generate(
                count,
                (i) => DropdownMenuItem(
                  value: lo + i,
                  child: Text('${lo + i}', style: const TextStyle(fontSize: 13)),
                ),
              );
            }(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTypeDropdown({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type', style: TextStyle(fontSize: 10, color: context.lightText)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: 'mcq',
                child: Text('MCQ', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'trueFalse',
                child: Text('True/False', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'multiAnswer',
                child: Text('Multi-Answer', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'shortAnswer',
                child: Text('Short Answer', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'essay',
                child: Text('Essay', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'matching',
                child: Text('Matching', style: TextStyle(fontSize: 12)),
              ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

}
