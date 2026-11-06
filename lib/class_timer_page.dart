import 'dart:async';

import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'class_report_page.dart';
import 'lesson_plan.dart';
import 'settings.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// What the professor looks at during class: the current segment, the time left in it, and
/// whether the class is ahead or behind.
///
/// Leaving this page doesn't end the class. It keeps running, and buzzes, until it is finished.
class ClassTimerPage extends StatefulWidget {
  const ClassTimerPage({super.key, required this.run});

  final ClassRun run;

  @override
  State<ClassTimerPage> createState() => _ClassTimerPageState();
}

class _ClassTimerPageState extends State<ClassTimerPage> with WidgetsBindingObserver {
  late ClassRun _run = widget.run;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppLock.setKeepScreenOn(true);
    _syncService();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    AppLock.setKeepScreenOn(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Restarts the buzz in case Android stopped the service while the app was in the background.
    if (state == AppLifecycleState.resumed && !_run.isFinished) _syncService();
  }

  void _syncService() {
    final next = _run.next;
    AppLock.updateClassTimer(
      title: _run.current.title,
      detail: next == null
          ? 'Last segment of {plan}'.trf({'plan': _run.planName})
          : 'Next: {segment}'.trf({'segment': next.title}),
      dueAt: _run.currentDueAt,
      // A 2-minute warning on a 3-minute segment would come almost straight away, so skip it.
      warnBefore: AppSettings.instance.buzzBeforeEnd && _run.current.planned > AppSettings.buzzWarning * 1.5
          ? AppSettings.buzzWarning
          : Duration.zero,
    );
  }

  Future<void> _setRun(ClassRun run) async {
    setState(() => _run = run);
    _syncService();
    await LessonStore.saveActiveRun(run);
  }

  Future<void> _next() async {
    if (_run.next != null) return _setRun(_run.advanced(DateTime.now()));

    final confirmed = await _confirm(
      icon: Icons.flag_rounded,
      title: 'Finish class?'.tr,
      message: 'This ends the timer and saves the report.'.tr,
      action: 'Finish'.tr,
    );
    if (!confirmed) return;
    // The class ends when the button was confirmed, which is close enough to when it was tapped.
    final finished = _run.advanced(DateTime.now());
    await LessonStore.finishRun(finished);
    await AppLock.stopClassTimer();
    if (!mounted) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => ClassReportPage(run: finished)),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await _confirm(
      icon: Icons.close_rounded,
      title: 'Cancel this class?'.tr,
      message: "The timer stops and this class's timing won't be saved.".tr,
      action: 'Cancel class'.tr,
    );
    if (!confirmed) return;
    await LessonStore.cancelActiveRun();
    await AppLock.stopClassTimer();
    if (mounted) Navigator.pop(context);
  }

  Future<bool> _confirm({
    required IconData icon,
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Keep going'.tr)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final previous = _run.previous;
    final next = _run.next;

    return Scaffold(
      appBar: AppBar(
        title: Text(_run.planName),
        actions: [
          IconButton(tooltip: 'Cancel class'.tr, icon: const Icon(Icons.close_rounded), onPressed: _cancel),
          const SizedBox(width: 8),
        ],
      ),
      // Kept at the bottom so it's always under the thumb, however long the plan is.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (previous != null)
                TextButton.icon(
                  onPressed: () => _setRun(_run.undone()),
                  icon: const Icon(Icons.undo_rounded),
                  label: Text('Back to {segment}'.trf({'segment': previous.title})),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
                onPressed: _next,
                icon: Icon(next == null ? Icons.flag_rounded : Icons.skip_next_rounded),
                label: Text(next == null ? 'Finish class'.tr : 'Next: {segment}'.trf({'segment': next.title})),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _currentSegment(now),
          const SizedBox(height: 8),
          Center(child: _driftPill(now)),
          SectionLabel('Running order'.tr),
          Panel(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [for (var i = 0; i < _run.segments.length; i++) _segmentTile(i)]),
          ),
        ],
      ),
    );
  }

  Widget _currentSegment(DateTime now) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final remaining = _run.remaining(now);
    final over = remaining.isNegative;
    final color = over ? colors.error : colors.primary;
    final progress = over ? 1.0 : remaining.inMilliseconds / _run.current.planned.inMilliseconds;
    final ringSize = (MediaQuery.sizeOf(context).width - 72).clamp(220.0, 320.0);

    return Column(
      children: [
        const SizedBox(height: 4),
        Text(
          'Segment {n} of {total}'.trf({'n': _run.currentIndex + 1, 'total': _run.segments.length}),
          style: textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        SegmentStrip(
          minutes: [for (final s in _run.segments) s.minutes],
          highlight: _run.currentIndex,
          height: 8,
        ),
        Glow(
          color: color,
          strength: over ? 0.28 : 0.2,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: CountdownRing(
                progress: progress,
                color: color,
                size: ringSize,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: ringSize * 0.14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _run.current.title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        over ? 'Over by'.tr : 'Time left'.tr,
                        style: textTheme.labelLarge?.copyWith(color: color),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatCountdown(remaining.abs()),
                          style: tabular(textTheme.displayLarge?.copyWith(
                            fontSize: ringSize * 0.21,
                            color: over ? color : null,
                          )),
                        ),
                      ),
                      Text('of {time}'.trf({'time': formatMinutes(_run.current.minutes)}), style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _driftPill(DateTime now) {
    final colors = Theme.of(context).colorScheme;
    final drift = _run.drift(now);
    final label = describeDrift(drift);
    if (isOnTime(drift)) {
      return Pill(label: label, color: colors.secondary, icon: Icons.check_circle_rounded);
    }
    return drift.isNegative
        ? Pill(label: label, color: colors.tertiary, icon: Icons.fast_forward_rounded)
        : Pill(label: label, color: colors.error, icon: Icons.schedule_rounded);
  }

  Widget _segmentTile(int index) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final segment = _run.segments[index];
    final done = index < _run.currentIndex;
    final current = index == _run.currentIndex;
    final over = done && _run.actual(index) > segment.planned + const Duration(seconds: 30);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: current ? colors.primary.withValues(alpha: 0.12) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          done
              ? Icons.check_circle_rounded
              : current
                  ? Icons.play_circle_rounded
                  : Icons.circle_outlined,
          color: done
              ? colors.secondary
              : current
                  ? colors.primary
                  : colors.outline,
        ),
        title: Text(
          segment.title,
          style: textTheme.titleMedium?.copyWith(
            fontSize: 15,
            color: done ? colors.onSurfaceVariant : null,
          ),
        ),
        trailing: Text(
          done
              ? '{actual} of {planned}'.trf({'actual': formatCountdown(_run.actual(index)), 'planned': formatMinutes(segment.minutes)})
              : formatMinutes(segment.minutes),
          style: tabular(textTheme.bodySmall?.copyWith(
            color: over ? colors.error : null,
            fontWeight: current ? FontWeight.w700 : null,
          )),
        ),
      ),
    );
  }
}
