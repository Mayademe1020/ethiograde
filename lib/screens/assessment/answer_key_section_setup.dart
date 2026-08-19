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
    final existing = widget.assessment.settings['sections'];
    if (existing is List && existing.isNotEmpty) {
      return existing
          .map((s) => ExamSection.fromMap(s as Map<String, dynamic>))
          .toList();
    }
    return [
      ExamSection(name: 'A', startQ: 1, endQ: total, type: 'mcq', points: 1.0),
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
          points: 1.0,
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
          points: prev.points,
        );
      } else if (_sections.isNotEmpty) {
        final next = _sections[0];
        _sections[0] = ExamSection(
          name: next.name,
          startQ: removed.startQ,
          endQ: next.endQ,
          type: next.type,
          points: next.points,
        );
      }
      // Re-letter sections
      for (var i = 0; i < _sections.length; i++) {
        _sections[i] = ExamSection(
          name: _letterLabels[i],
          startQ: _sections[i].startQ,
          endQ: _sections[i].endQ,
          type: _sections[i].type,
          points: _sections[i].points,
        );
      }
    });
  }

  void _updateSection(
    int index, {
    int? startQ,
    int? endQ,
    String? type,
    double? points,
  }) {
    setState(() {
      final old = _sections[index];
      _sections[index] = ExamSection(
        name: old.name,
        startQ: startQ ?? old.startQ,
        endQ: endQ ?? old.endQ,
        type: type ?? old.type,
        points: points ?? old.points,
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
          points: 1.0,
        ),
      ]),
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
                'Organize $total questions into sections. Each section can have a different type and point value.',
                style: TextStyle(fontSize: 12, color: context.lightText),
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
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPointsField(
                    value: section.points,
                    onChanged: (v) => _updateSection(index, points: v),
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
            items: List.generate(
              max - min + 1,
              (i) => DropdownMenuItem(
                value: min + i,
                child: Text('${min + i}', style: const TextStyle(fontSize: 13)),
              ),
            ),
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

  Widget _buildPointsField({
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Points per Q',
          style: TextStyle(fontSize: 10, color: context.lightText),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButton<double>(
            value: value,
            isExpanded: true,
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(
                value: 0.5,
                child: Text('0.5', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 1.0,
                child: Text('1', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 2.0,
                child: Text('2', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 3.0,
                child: Text('3', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 5.0,
                child: Text('5', style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 10.0,
                child: Text('10', style: TextStyle(fontSize: 12)),
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
