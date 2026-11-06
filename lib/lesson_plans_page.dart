import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'class_report_page.dart';
import 'class_timer_page.dart';
import 'lesson_plan.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// How a finished class went, as a coloured badge: on time, over, or early.
Pill finishPill(BuildContext context, ClassRun run) {
  final colors = Theme.of(context).colorScheme;
  final drift = run.drift(run.segmentEnds.last);
  if (isOnTime(drift)) {
    return Pill(label: 'On time'.tr, color: colors.secondary, icon: Icons.check_circle_rounded);
  }
  final n = {'n': minutesOff(drift)};
  return drift.isNegative
      ? Pill(label: '{n} min early'.trf(n), color: colors.tertiary, icon: Icons.fast_forward_rounded)
      : Pill(label: '{n} min over'.trf(n), color: colors.error, icon: Icons.schedule_rounded);
}

/// Lists the professor's lesson plans and past classes.
class LessonPlansPage extends StatefulWidget {
  const LessonPlansPage({super.key});

  @override
  State<LessonPlansPage> createState() => _LessonPlansPageState();
}

class _LessonPlansPageState extends State<LessonPlansPage> {
  List<LessonPlan>? _plans;
  List<ClassRun> _history = const [];
  ClassRun? _activeRun;
  Set<String> _dismissed = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await LessonStore.plans();
    final history = await LessonStore.history();
    final activeRun = await LessonStore.activeRun();
    final dismissed = await LessonStore.dismissedSuggestions();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _history = history;
      _activeRun = activeRun;
      _dismissed = dismissed;
    });
  }

  List<PlanSuggestion> _suggestions(LessonPlan plan) =>
      [for (final s in suggestionsFor(plan, _history)) if (!_dismissed.contains(s.key)) s];

  Future<void> _apply(LessonPlan plan, PlanSuggestion suggestion) async {
    await LessonStore.applySuggestion(plan, suggestion);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('{title} is now {time}'.trf({'title': suggestion.title, 'time': formatMinutes(suggestion.suggestedMinutes)})),
    ));
  }

  Future<void> _dismiss(PlanSuggestion suggestion) async {
    await LessonStore.dismissSuggestion(suggestion);
    await _load();
  }

  Future<void> _edit(LessonPlan? plan) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlanEditorPage(plan: plan)));
    await _load();
  }

  Future<void> _openTimer(ClassRun run) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassTimerPage(run: run)));
    await _load();
  }

  Future<void> _start(LessonPlan plan) async {
    final run = ClassRun.start(plan, DateTime.now());
    await LessonStore.saveActiveRun(run);
    if (mounted) await _openTimer(run);
  }

  Future<void> _openReport(ClassRun run) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassReportPage(run: run)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final activeRun = _activeRun;

    return Scaffold(
      appBar: AppBar(
        title: Text('Class timer'.tr),
        actions: const [SettingsButton(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: Text('New plan'.tr),
      ),
      body: plans == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              // Leaves room for the button so it never covers the last row.
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
              children: [
                if (activeRun != null) _activeBanner(activeRun),
                if (plans.isEmpty)
                  EmptyState(
                    icon: Icons.view_timeline_outlined,
                    title: 'Plan your first class'.tr,
                    message: ('No lesson plans yet. Build your lecture as timed segments, then run the '
                        'timer during class to see how the time really goes.').tr,
                  )
                else ...[
                  SectionLabel('Lesson plans'.tr, padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
                  for (final plan in plans) ...[
                    _PlanCard(
                      plan: plan,
                      suggestions: _suggestions(plan),
                      onApply: (s) => _apply(plan, s),
                      onDismiss: _dismiss,
                      // Only one class can run at a time.
                      onStart: activeRun == null ? () => _start(plan) : null,
                      onTap: () => _edit(plan),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
                if (_history.isNotEmpty) ...[
                  SectionLabel('Past classes'.tr, padding: EdgeInsets.fromLTRB(4, 16, 4, 10)),
                  Panel(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0; i < _history.length; i++) ...[
                          if (i > 0) const Divider(indent: 20, endIndent: 20),
                          _historyRow(_history[i]),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _activeBanner(ClassRun run) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        onTap: () => _openTimer(run),
        borderColor: colors.primary.withValues(alpha: 0.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary.withValues(alpha: 0.22), colors.primary.withValues(alpha: 0.05)],
        ),
        child: Row(
          children: [
            IconBadge(Icons.timer_rounded, color: colors.primary, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PulseDot(color: colors.primary, size: 7),
                      const SizedBox(width: 4),
                      Text('CLASS IN PROGRESS'.tr, style: textTheme.labelSmall?.copyWith(color: colors.primary)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(run.planName, style: textTheme.titleLarge),
                  Text('Class in progress · {segment}'.trf({'segment': run.current.title}), style: textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _historyRow(ClassRun run) {
    final l10n = MaterialLocalizations.of(context);
    return ListTile(
      title: Text(run.planName),
      subtitle: Text('${l10n.formatMediumDate(run.startedAt)} · ${formatCountdown(run.totalActual)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          finishPill(context, run),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: () => _openReport(run),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.suggestions,
    required this.onApply,
    required this.onDismiss,
    required this.onStart,
    required this.onTap,
  });

  final LessonPlan plan;
  final List<PlanSuggestion> suggestions;
  final ValueChanged<PlanSuggestion> onApply;
  final ValueChanged<PlanSuggestion> onDismiss;
  final VoidCallback? onStart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name, style: textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      '{n} segments · {time}'.trf({'n': plan.segments.length, 'time': formatMinutes(plan.totalMinutes)}),
                      style: tabular(textTheme.bodySmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 18)),
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('Start'.tr),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentStrip(minutes: [for (final s in plan.segments) s.minutes]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (var i = 0; i < plan.segments.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: segmentColor(context, i), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(plan.segments[i].title, style: textTheme.bodySmall),
                  ],
                ),
            ],
          ),
          for (final suggestion in suggestions) ...[
            const SizedBox(height: 14),
            _SuggestionBox(
              suggestion: suggestion,
              onApply: () => onApply(suggestion),
              onDismiss: () => onDismiss(suggestion),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Concept ran about 4 min over in your last 3 classes." with a one-tap fix.
class _SuggestionBox extends StatelessWidget {
  const _SuggestionBox({required this.suggestion, required this.onApply, required this.onDismiss});

  final PlanSuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tint = colors.tertiary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_outlined, size: 20, color: tint),
              const SizedBox(width: 10),
              Expanded(child: Text(suggestion.message, style: textTheme.bodyMedium)),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 4,
              children: [
                TextButton(onPressed: onDismiss, child: Text('Not now'.tr)),
                TextButton(
                  onPressed: onApply,
                  style: TextButton.styleFrom(foregroundColor: tint),
                  child: Text('Make it {time}'.trf({'time': formatMinutes(suggestion.suggestedMinutes)})),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable row. Owns its text controllers so they survive reordering.
class _SegmentRow {
  _SegmentRow(String title, int minutes)
      : title = TextEditingController(text: title),
        minutes = TextEditingController(text: '$minutes');

  final TextEditingController title;
  final TextEditingController minutes;

  int? get parsedMinutes => int.tryParse(minutes.text);

  void dispose() {
    title.dispose();
    minutes.dispose();
  }
}

/// Creates a plan, or edits [plan] if one is given.
class PlanEditorPage extends StatefulWidget {
  const PlanEditorPage({super.key, this.plan});

  final LessonPlan? plan;

  /// A typical lecture, so a new plan only needs its times adjusted.
  static const starterSegments = [
    LessonSegment(title: 'Recap', minutes: 5),
    LessonSegment(title: 'Concept', minutes: 20),
    LessonSegment(title: 'Worked example', minutes: 15),
    LessonSegment(title: 'Activity', minutes: 10),
    LessonSegment(title: 'Q&A', minutes: 5),
  ];

  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends State<PlanEditorPage> {
  late final TextEditingController _name;
  late final List<_SegmentRow> _rows;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.plan?.name);
    _rows = [
      for (final segment in widget.plan?.segments ?? PlanEditorPage.starterSegments)
        _SegmentRow(segment.title, segment.minutes),
    ];
  }

  @override
  void dispose() {
    _name.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String? get _problem {
    if (_name.text.trim().isEmpty) return 'Give the plan a name.'.tr;
    if (_rows.isEmpty) return 'Add at least one segment.'.tr;
    if (_rows.any((row) => row.title.text.trim().isEmpty)) return 'Every segment needs a title.'.tr;
    final allValid = _rows.every((row) {
      final minutes = row.parsedMinutes;
      return minutes != null && minutes >= 1 && minutes <= maxMinutes;
    });
    if (!allValid) return 'Each segment must be 1–{max} minutes.'.trf({'max': maxMinutes});
    return null;
  }

  int get _totalMinutes => _rows.fold(0, (sum, row) => sum + (row.parsedMinutes ?? 0));

  Future<void> _save() async {
    await LessonStore.savePlan(LessonPlan(
      id: widget.plan?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      segments: [
        for (final row in _rows)
          LessonSegment(title: row.title.text.trim(), minutes: row.parsedMinutes!),
      ],
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
        title: Text('Delete this plan?'.tr),
        content: Text('Reports from classes you already taught will be kept.'.tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete'.tr)),
        ],
      ),
    );
    if (confirmed != true) return;
    await LessonStore.deletePlan(widget.plan!.id);
    if (mounted) Navigator.pop(context);
  }

  void _addRow() => setState(() => _rows.add(_SegmentRow('', 10)));

  void _removeRow(_SegmentRow row) {
    setState(() => _rows.remove(row));
    // The field may still be on screen until this frame is done with it.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      _rows.insert(newIndex, _rows.removeAt(oldIndex));
    });
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.plan == null ? 'New plan'.tr : 'Edit plan'.tr),
        actions: [
          if (widget.plan != null)
            IconButton(tooltip: 'Delete'.tr, icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(child: Text(problem, textAlign: TextAlign.center, style: textTheme.bodySmall)),
                  ],
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: problem == null ? _save : null,
                  child: Text('Save · {time}'.trf({'time': formatMinutes(_totalMinutes)})),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              style: textTheme.titleLarge,
              decoration: InputDecoration(labelText: 'Plan name'.tr, hintText: 'For example, Physics 101'.tr),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Panel(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Running order'.tr, style: textTheme.titleSmall),
                      const Spacer(),
                      Text(formatMinutes(_totalMinutes), style: tabular(textTheme.titleSmall)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SegmentStrip(minutes: [for (final row in _rows) row.parsedMinutes ?? 0], height: 12),
                ],
              ),
            ),
            SectionLabel('Segments'.tr, padding: EdgeInsets.fromLTRB(4, 20, 4, 10)),
          ],
        ),
        footer: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add_rounded),
              label: Text('Add segment'.tr),
            ),
          ),
        ),
        itemCount: _rows.length,
        onReorder: _reorder,
        proxyDecorator: (child, index, animation) => Material(
          color: Colors.transparent,
          elevation: 8 * animation.value,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(20),
          child: child,
        ),
        itemBuilder: (context, index) => _segmentRow(_rows[index], index),
      ),
    );
  }

  Widget _segmentRow(_SegmentRow row, int index) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      key: ObjectKey(row),
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
        decoration: BoxDecoration(
          color: dark ? colors.surfaceContainerLow : colors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          children: [
            // Matches this segment's colour in the running order above.
            Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(color: segmentColor(context, index), borderRadius: BorderRadius.circular(4)),
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(Icons.drag_indicator_rounded, color: colors.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: TextField(
                controller: row.title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: 'Segment'.tr),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
              child: TextField(
                controller: row.minutes,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 3,
                style: tabular(Theme.of(context).textTheme.titleMedium),
                decoration: InputDecoration(labelText: 'Min'.tr, counterText: ''),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(
              tooltip: 'Remove segment'.tr,
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _removeRow(row),
            ),
          ],
        ),
      ),
    );
  }
}
