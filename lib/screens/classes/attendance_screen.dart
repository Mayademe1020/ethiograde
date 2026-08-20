import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/attendance_record.dart';
import '../../models/class_info.dart';
import '../../models/student.dart';
import '../../services/attendance_provider.dart';
import '../../services/student_provider.dart';
import '../../widgets/ui_components.dart';

/// Daily attendance for a single class.
///
/// Pick a date, mark each student Present / Absent / Late / Excused, then
/// save. A history of past records is shown below and can be re-opened.
class AttendanceScreen extends StatefulWidget {
  final ClassInfo classInfo;

  const AttendanceScreen({super.key, required this.classInfo});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late DateTime _selectedDate;
  final Map<String, String> _statuses = {};
  AttendanceRecord? _existing;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadForDate();
  }

  void _loadForDate() {
    final prov = context.read<AttendanceProvider>();
    final rec = prov.recordForDate(widget.classInfo.id, _selectedDate);
    _existing = rec;
    _statuses.clear();
    if (rec != null) {
      for (final e in rec.entries) {
        _statuses[e.studentId] = e.status;
      }
    }
  }

  List<Student> _students(BuildContext context) {
    final all = context.watch<StudentProvider>().students;
    return all
        .where((s) => s.classIds.contains(widget.classInfo.id))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  int _count(String status, List<Student> students) =>
      students.where((s) => (_statuses[s.id] ?? AttendanceStatus.present) == status).length;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _loadForDate();
      });
    }
  }

  Future<void> _save() async {
    final students = _students(context);
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add students to this class first')),
      );
      return;
    }
    final entries = students
        .map(
          (s) => AttendanceEntry(
            studentId: s.id,
            status: _statuses[s.id] ?? AttendanceStatus.present,
          ),
        )
        .toList();
    final record = AttendanceRecord(
      id: _existing?.id ?? '',
      classId: widget.classInfo.id,
      date: _selectedDate,
      entries: entries,
      updatedAt: DateTime.now(),
    );
    final result = await context.read<AttendanceProvider>().saveRecord(record);
    if (!mounted) return;
    if (result.success) {
      setState(() => _existing = result.data);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Could not save attendance'),
          backgroundColor: context.primaryRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final students = _students(context);
    final prov = context.watch<AttendanceProvider>();
    final history = prov.historyForClass(widget.classInfo.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => _showHistory(context, history),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Date selector + summary
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: context.primaryGreen.withValues(alpha: 0.05),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() {
                          _selectedDate = _selectedDate
                              .subtract(const Duration(days: 1));
                          _loadForDate();
                        }),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _pickDate,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _formatDate(_selectedDate),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.calendar_today, size: 16),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() {
                          _selectedDate =
                              _selectedDate.add(const Duration(days: 1));
                          _loadForDate();
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (students.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _SummaryChip(
                          label: 'Present',
                          count: _count(AttendanceStatus.present, students),
                          color: Colors.green,
                        ),
                        _SummaryChip(
                          label: 'Absent',
                          count: _count(AttendanceStatus.absent, students),
                          color: context.primaryRed,
                        ),
                        _SummaryChip(
                          label: 'Late',
                          count: _count(AttendanceStatus.late, students),
                          color: Colors.orange,
                        ),
                        _SummaryChip(
                          label: 'Excused',
                          count: _count(AttendanceStatus.excused, students),
                          color: Colors.blue,
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Student list
            Expanded(
              child: students.isEmpty
                  ? AppEmptyState(
                      icon: Icons.people_outline,
                      title: 'No students yet',
                      message:
                          'Add students to ${widget.classInfo.displayName} to take attendance.',
                      buttonLabel: 'Add Students',
                      onPressed: () => Navigator.pushNamed(
                        context,
                        AppRoutes.addStudent,
                        arguments: widget.classInfo.id,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final s = students[index];
                        final status =
                            _statuses[s.id] ?? AttendanceStatus.present;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor:
                                context.primaryGreen.withValues(alpha: 0.1),
                            child: Text(
                              s.fullName[0].toUpperCase(),
                              style: TextStyle(
                                color: context.primaryGreen,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(s.fullName),
                          subtitle: Text(
                            s.studentId.isNotEmpty
                                ? 'ID: ${s.studentId}'
                                : '',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.lightText,
                            ),
                          ),
                          trailing: _StatusSelector(
                            value: status,
                            onChanged: (v) =>
                                setState(() => _statuses[s.id] = v),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: students.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _save,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
    );
  }

  void _showHistory(
    BuildContext context,
    List<AttendanceRecord> history,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Attendance History',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No past records'),
              )
            else
              Expanded(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final rec = history[i];
                    final present = rec.entries
                        .where((e) => e.status == AttendanceStatus.present)
                        .length;
                    return ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(_formatDate(rec.date)),
                      subtitle: Text('$present present / ${rec.entries.length}'),
                      trailing: rec.date.year == _selectedDate.year &&
                              rec.date.month == _selectedDate.month &&
                              rec.date.day == _selectedDate.day
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.pop(c);
                        setState(() {
                          _selectedDate = rec.date;
                          _loadForDate();
                        });
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StatusSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusSelector({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: AttendanceStatus.present,
          icon: Icon(Icons.check, size: 18),
        ),
        ButtonSegment(
          value: AttendanceStatus.absent,
          icon: Icon(Icons.close, size: 18),
        ),
        ButtonSegment(
          value: AttendanceStatus.late,
          icon: Icon(Icons.schedule, size: 18),
        ),
        ButtonSegment(
          value: AttendanceStatus.excused,
          icon: Icon(Icons.block, size: 18),
        ),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (set) => onChanged(set.first),
      style: SegmentedButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
