import 'dart:math';

import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'lesson_plan.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// How many classes the "across weeks" comparison shows, ending with the one being viewed.
const _maxWeeks = 8;

/// Chart colors, from the app's palette. Marks use these; all text stays in the theme's text colors.
class _ChartColors {
  _ChartColors(BuildContext context) : _c = Theme.of(context).colorScheme;

  final ColorScheme _c;

  Color get actual => _c.primary;
  Color get earlier => _c.onSurfaceVariant.withValues(alpha: 0.45);
  Color get baseline => _c.outlineVariant;
  Color get planned => _c.onSurface;
  Color get track => _c.surfaceContainerHigh;
}

/// "+2:14", "-0:30". Rounds to the second like the timer does.
String _formatDifference(Duration d) =>
    '${d.isNegative ? '-' : '+'}${formatCountdown(d.abs())}';

/// After class: how the planned time compared with what really happened, this week and over time.
class ClassReportPage extends StatefulWidget {
  const ClassReportPage({super.key, required this.run});

  final ClassRun run;

  @override
  State<ClassReportPage> createState() => _ClassReportPageState();
}

class _ClassReportPageState extends State<ClassReportPage> {
  /// Classes from the same plan up to and including this one, oldest first.
  List<ClassRun> _weeks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final run = widget.run;
    final samePlan = (await LessonStore.history())
        .where((r) => r.planId == run.planId && !r.startedAt.isAfter(run.startedAt))
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final weeks = samePlan.sublist(max(0, samePlan.length - _maxWeeks));
    if (mounted) setState(() => _weeks = weeks);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete this report?'.tr),
        content: Text("This class's timing will be removed from this phone.".tr),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete'.tr)),
        ],
      ),
    );
    if (confirmed != true) return;
    await LessonStore.deleteFromHistory(widget.run);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.run;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l10n = MaterialLocalizations.of(context);
    final colors = _ChartColors(context);
    final drift = run.drift(run.segmentEnds.last);
    final finish = describeFinish(drift);
    final mood = isOnTime(drift)
        ? scheme.secondary
        : drift.isNegative
            ? scheme.tertiary
            : scheme.error;

    return Scaffold(
      appBar: AppBar(
        title: Text(run.planName),
        actions: [
          IconButton(tooltip: 'Delete'.tr, icon: const Icon(Icons.delete_outline_rounded), onPressed: _delete),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Panel(
            borderColor: mood.withValues(alpha: 0.45),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [mood.withValues(alpha: 0.18), mood.withValues(alpha: 0.03)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.formatFullDate(run.startedAt).toUpperCase(),
                  style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(finish, style: textTheme.headlineMedium),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: _Stat(label: 'Took'.tr, value: formatCountdown(run.totalActual))),
                    Expanded(child: _Stat(label: 'Planned'.tr, value: formatMinutes(run.totalPlanned.inMinutes))),
                    Expanded(
                      child: _Stat(
                        label: drift.isNegative ? 'Early by'.tr : 'Over by'.tr,
                        value: formatCountdown(drift.abs()),
                        color: mood,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Planned vs. actual'.tr, style: textTheme.titleLarge),
                const SizedBox(height: 10),
                _Legend(items: [
                  _LegendItem.bar(colors.actual, 'Actual'.tr),
                  _LegendItem.line(colors.planned, 'Planned'.tr),
                ]),
                const SizedBox(height: 20),
                _SegmentBars(run: run, colors: colors),
              ],
            ),
          ),
          if (_weeks.length >= 2) ...[
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Across weeks'.tr, style: textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    ('Bars are drawn relative to each segment\'s planned time, so anything above the '
                    'line ran over. Press and hold a bar for its time.').tr,
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  _Legend(items: [
                    _LegendItem.bar(colors.actual, 'This class'.tr),
                    _LegendItem.bar(colors.earlier, 'Earlier classes'.tr),
                    _LegendItem.line(colors.planned, 'Planned'.tr),
                  ]),
                  const SizedBox(height: 20),
                  _WeeklyComparison(run: run, weeks: _weeks, colors: colors),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Show as table'.tr, style: textTheme.titleSmall),
                    children: [_WeeklyTable(run: run, weeks: _weeks)],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small labelled number in the summary card.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: textTheme.bodySmall),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: tabular(textTheme.titleLarge?.copyWith(color: color))),
        ),
      ],
    );
  }
}

class _LegendItem {
  const _LegendItem.bar(this.color, this.label) : isLine = false;
  const _LegendItem.line(this.color, this.label) : isLine = true;

  final Color color;
  final String label;
  final bool isLine;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.items});

  final List<_LegendItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              item.isLine
                  ? Container(width: 2, height: 12, color: item.color)
                  : Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(color: item.color, borderRadius: BorderRadius.circular(2)),
                    ),
              const SizedBox(width: 6),
              Text(item.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

/// One horizontal bar per segment, with a tick where its planned time ended. Each row spells out
/// its numbers, so nothing depends on reading the chart.
class _SegmentBars extends StatelessWidget {
  const _SegmentBars({required this.run, required this.colors});

  final ClassRun run;
  final _ChartColors colors;

  @override
  Widget build(BuildContext context) {
    var longest = Duration.zero;
    for (var i = 0; i < run.segments.length; i++) {
      if (run.actual(i) > longest) longest = run.actual(i);
      if (run.segments[i].planned > longest) longest = run.segments[i].planned;
    }
    return Column(
      children: [
        for (var i = 0; i < run.segments.length; i++)
          _segmentBar(context, run.segments[i], run.actual(i), longest),
      ],
    );
  }

  Widget _segmentBar(BuildContext context, LessonSegment segment, Duration actual, Duration longest) {
    final textTheme = Theme.of(context).textTheme;
    final difference = actual - segment.planned;
    final label = '${'{actual} of {planned}'.trf({'actual': formatCountdown(actual), 'planned': formatMinutes(segment.minutes)})} · '
        '${_formatDifference(difference)}';

    return Semantics(
      container: true,
      label: '${segment.title}: $label',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(segment.title, style: textTheme.titleSmall)),
                  const SizedBox(width: 8),
                  // Wraps rather than overflowing when the title is long or the phone is narrow.
                  Flexible(child: Text(label, textAlign: TextAlign.end, style: tabular(textTheme.bodySmall))),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: LayoutBuilder(builder: (context, constraints) {
                  double x(Duration d) =>
                      constraints.maxWidth * d.inMilliseconds / longest.inMilliseconds;
                  return Stack(
                    children: [
                      Positioned.fill(
                        top: 3,
                        bottom: 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: colors.track, borderRadius: BorderRadius.circular(7)),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 3,
                        width: x(actual),
                        height: 14,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.actual.withValues(alpha: 0.7), colors.actual],
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                      ),
                      Positioned(
                        // Stays inside the row when the plan is the longest thing on the chart.
                        left: min(x(segment.planned), constraints.maxWidth - 3),
                        top: 0,
                        width: 3,
                        height: 20,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.planned,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small multiples: one plot per segment of this class, each with one column per week.
class _WeeklyComparison extends StatelessWidget {
  const _WeeklyComparison({required this.run, required this.weeks, required this.colors});

  static const _plotHeight = 56.0;

  final ClassRun run;
  final List<ClassRun> weeks;
  final _ChartColors colors;

  @override
  Widget build(BuildContext context) {
    final keys = run.segmentKeys;
    // Every plot shares this scale, so a column's height means the same thing in all of them.
    var scale = 1.25;
    for (final key in keys) {
      for (final week in weeks) {
        final ratio = _ratio(week, key);
        if (ratio != null) scale = max(scale, ratio);
      }
    }

    final l10n = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < keys.length; i++) _plot(context, run.segments[i].title, keys[i], scale),
        Row(
          children: [
            for (final week in weeks)
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.formatShortMonthDay(week.startedAt),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Actual time as a share of planned time, or null if [week] didn't have this segment.
  static double? _ratio(ClassRun week, String key) {
    final index = week.segmentKeys.indexOf(key);
    if (index < 0) return null;
    return week.actual(index).inMilliseconds / week.segments[index].planned.inMilliseconds;
  }

  Widget _plot(BuildContext context, String title, String key, double scale) {
    final plannedY = _plotHeight / scale;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          SizedBox(
            height: _plotHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Row(
                    children: [for (final week in weeks) Expanded(child: _column(week, key, scale))],
                  ),
                ),
                Positioned(left: 0, right: 0, bottom: 0, height: 1, child: ColoredBox(color: colors.baseline)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: plannedY - 1,
                  height: 2,
                  // Doesn't take touches, so a press on the line still reaches the column under it.
                  child: IgnorePointer(child: ColoredBox(color: colors.planned)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(ClassRun week, String key, double scale) {
    final ratio = _ratio(week, key);
    if (ratio == null) return const SizedBox.shrink();

    final index = week.segmentKeys.indexOf(key);
    final isThisClass = week.startedAt == run.startedAt;
    return Builder(builder: (context) {
      final date = MaterialLocalizations.of(context).formatShortMonthDay(week.startedAt);
      return Tooltip(
        message: '$date: ${'{actual} of {planned}'.trf({'actual': formatCountdown(week.actual(index)), 'planned': formatMinutes(week.segments[index].minutes)})}',
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 20,
            height: _plotHeight * ratio / scale,
            decoration: BoxDecoration(
              color: isThisClass ? colors.actual : colors.earlier,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            ),
          ),
        ),
      );
    });
  }
}

/// The same numbers as [_WeeklyComparison], for anyone who can't read the chart.
class _WeeklyTable extends StatelessWidget {
  const _WeeklyTable({required this.run, required this.weeks});

  final ClassRun run;
  final List<ClassRun> weeks;

  @override
  Widget build(BuildContext context) {
    final l10n = MaterialLocalizations.of(context);
    final keys = run.segmentKeys;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        columns: [
          DataColumn(label: Text('Class'.tr)),
          for (final segment in run.segments)
            DataColumn(label: Text('${segment.title} (${segment.minutes})'), numeric: true),
        ],
        rows: [
          for (final week in weeks)
            DataRow(cells: [
              DataCell(Text(l10n.formatShortMonthDay(week.startedAt))),
              for (final key in keys)
                DataCell(() {
                  final index = week.segmentKeys.indexOf(key);
                  return Text(index < 0 ? '–' : formatCountdown(week.actual(index)));
                }()),
            ]),
        ],
      ),
    );
  }
}
