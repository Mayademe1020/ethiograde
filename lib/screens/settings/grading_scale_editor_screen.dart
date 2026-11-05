import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../models/grading_scale.dart';
import '../../services/audit_service.dart';
import '../../services/settings_provider.dart';
import '../../services/teacher_provider.dart';

/// Screen for creating and editing custom grading scales.
///
/// Teachers define their own grade bands (e.g. 97-100 = A+, 93-96 = A).
/// Scales are stored locally via SettingsProvider.
class GradingScaleEditorScreen extends StatefulWidget {
  /// If non-null, we're editing an existing scale.
  final GradingScale? existingScale;

  const GradingScaleEditorScreen({super.key, this.existingScale});

  @override
  State<GradingScaleEditorScreen> createState() =>
      _GradingScaleEditorScreenState();
}

class _GradingScaleEditorScreenState extends State<GradingScaleEditorScreen> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late List<_RangeEntry> _ranges;

  @override
  void initState() {
    super.initState();
    if (widget.existingScale != null) {
      final s = widget.existingScale!;
      _nameController.text = s.name;
      _ranges = s.ranges
          .map(
            (r) => _RangeEntry(
              grade: r.grade,
              min: r.minScore.toString(),
              max: r.maxScore.toString(),
            ),
          )
          .toList();
    } else {
      // Start with a sensible default template
      _ranges = [
        _RangeEntry(grade: 'A+', min: '95', max: '100'),
        _RangeEntry(grade: 'A', min: '90', max: '94'),
        _RangeEntry(grade: 'B', min: '75', max: '89'),
        _RangeEntry(grade: 'C', min: '60', max: '74'),
        _RangeEntry(grade: 'D', min: '50', max: '59'),
        _RangeEntry(grade: 'F', min: '0', max: '49'),
      ];
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingScale != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? ('Edit Grading Scale') : ('New Grading Scale')),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Scale Name',
                  hintText: 'e.g. My School Scale',
                  prefixIcon: Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? ('Name is required') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(
                  hintText: 'Optional',
                  prefixIcon: Icon(Icons.translate),
                ),
              ),
              const SizedBox(height: 24),

              // Header
              Row(
                children: [
                  Icon(Icons.grading, color: context.primaryGreen, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Grade Bands',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addRange,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Grade range entries
              ..._ranges.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                return _buildRangeCard(r, i);
              }),

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: Text(isEditing ? ('Update Scale') : ('Create Scale')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRangeCard(_RangeEntry r, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Grade label
            SizedBox(
              width: 56,
              child: TextFormField(
                initialValue: r.grade,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                decoration: const InputDecoration(
                  labelText: 'Grade',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                ),
                onChanged: (v) => r.grade = v.trim(),
              ),
            ),
            const SizedBox(width: 12),

            // Min score
            Expanded(
              child: TextFormField(
                initialValue: r.min,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'From %',
                  isDense: true,
                  suffixText: '%',
                ),
                onChanged: (v) => r.min = v,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('–'),
            ),

            // Max score
            Expanded(
              child: TextFormField(
                initialValue: r.max,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'To %',
                  isDense: true,
                  suffixText: '%',
                ),
                onChanged: (v) => r.max = v,
              ),
            ),
            const SizedBox(width: 4),

            // Delete button
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: context.error,
              onPressed: () => setState(() => _ranges.removeAt(index)),
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }

  void _addRange() {
    setState(() {
      _ranges.add(_RangeEntry(grade: '', min: '0', max: '0'));
    });
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    // Validate ranges
    final ranges = <GradeRange>[];
    for (final r in _ranges) {
      if (r.grade.isEmpty) continue;
      final min = int.tryParse(r.min);
      final max = int.tryParse(r.max);
      if (min == null || max == null || min < 0 || max > 100 || min > max) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid score range for ${r.grade}')),
        );
        return;
      }
      ranges.add(GradeRange(grade: r.grade, minScore: min, maxScore: max));
    }

    if (ranges.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('At least one grade band is required')),
      );
      return;
    }

    final isEditing = widget.existingScale != null;

    final scale = GradingScale(
      id: widget.existingScale?.id,
      name: _nameController.text.trim(),
      ranges: ranges,
    );

    // Show confirmation before saving
    _confirmAndSave(scale, isEditing);
  }

  /// Show confirmation dialog explaining impact, then save + audit.
  Future<void> _confirmAndSave(GradingScale scale, bool isEditing) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isEditing ? 'Update Grading Scale?' : 'Create Grading Scale?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing
                  ? 'Changes to "${scale.name}" will affect all future grading sessions using this scale.'
                  : 'The scale "${scale.name}" will be available for grading sessions.',
            ),
            const SizedBox(height: 12),
            Text(
              'Existing saved records keep their current grades unless you explicitly regrade them.',
              style: TextStyle(color: context.lightText, fontSize: 13),
            ),
            if (isEditing) ...[
              const SizedBox(height: 12),
              const Text(
                'New grade bands:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              ...scale.ranges.map(
                (r) => Text(
                  '  ${r.grade}: ${r.minScore}–${r.maxScore}%',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEditing ? 'Update' : 'Create'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final settingsProvider = context.read<SettingsProvider>();
    final teacherProvider = context.read<TeacherProvider>();

    // Save the scale
    await settingsProvider.saveCustomScale(scale);

    // Audit: record the scale change
    try {
      final teacher = teacherProvider.activeTeacher;
      await AuditService().recordScaleChange(
        scaleId: scale.id,
        scaleName: scale.name,
        teacherId: teacher?.id ?? 'unknown',
        teacherName: teacher?.name ?? 'Unknown',
        previousRanges: isEditing
            ? widget.existingScale!.ranges.map((r) => r.toMap()).toList()
            : [],
        newRanges: scale.ranges.map((r) => r.toMap()).toList(),
        reason: isEditing ? 'Scale updated' : 'Scale created',
      );
    } catch (_) {
      // Never crash on audit failure
    }

    if (mounted) Navigator.pop(context, scale);
  }
}

/// Mutable entry for the range editor UI.
class _RangeEntry {
  String grade;
  String min;
  String max;
  _RangeEntry({required this.grade, required this.min, required this.max});
}
