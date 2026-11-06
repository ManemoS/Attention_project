import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'app_picker_page.dart';
import 'focus_stats.dart';
import 'focus_stats_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'timetable.dart';
import 'timetable_page.dart';
import 'ui.dart';
import 'l10n.dart';

/// The Focus tab: set up a lock session, or watch the one that's running.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  LockStatus? _status;
  bool _accessibilityOn = false;
  Timer? _timer;

  // Setup form.
  Map<String, String> _selectedApps = {};
  int _lockMinutes = 30;
  int _unlockMinutes = 15;
  bool _startLocked = true;
  bool _repeat = true;
  bool _record = false;
  bool _strict = false;
  final _codeController = TextEditingController();
  final _confirmController = TextEditingController();

  /// This week's focus, refreshed when a session starts or ends rather than every second.
  FocusStats? _stats;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _loadStats();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _loadStats() async {
    final stats = await FocusStats.load();
    final timetable = await TimetableStore.info();
    final timetableOn = await TimetableStore.enabled();
    if (mounted) {
      setState(() {
        _stats = stats;
        _timetable = timetableOn ? timetable : null;
      });
    }
  }

  /// The timetable's next class, or null when the timetable is off.
  TimetableInfo? _timetable;

  Future<void> _openTimetable() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TimetablePage(packages: _selectedApps.keys.toList(), strict: _strict)),
    );
    await _loadStats();
  }

  Future<void> _openStats() async {
    await _loadStats();
    if (!mounted || _stats == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FocusStatsPage(stats: _stats!)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _codeController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Picks up the accessibility switch as soon as the user comes back from Settings.
    if (state == AppLifecycleState.resumed) {
      _refresh();
      _loadStats();
    }
  }

  Future<void> _refresh() async {
    final status = await AppLock.status();
    final accessibilityOn = await AppLock.isAccessibilityEnabled();
    if (!mounted) return;
    final ended = _status?.active == true && !status.active;
    setState(() {
      // Fill the form from the last session the first time we load.
      if (_status == null) {
        _selectedApps = {for (final app in status.apps) app.packageName: app.name};
        _lockMinutes = status.lockMinutes;
        _unlockMinutes = status.unlockMinutes;
        _startLocked = status.startLocked;
        _repeat = status.repeat;
        _record = status.record;
        _strict = status.strict;
      }
      _status = status;
      _accessibilityOn = accessibilityOn;
    });
    if (ended) _loadStats();
  }

  String? get _codeProblem {
    final code = _codeController.text;
    if (code.length < 4) return 'Code must be 4–8 digits'.tr;
    if (code != _confirmController.text) return 'Codes do not match'.tr;
    return null;
  }

  bool get _canStart => _accessibilityOn && _selectedApps.isNotEmpty && _codeProblem == null;

  Future<void> _pickApps() async {
    final picked = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => AppPickerPage(initial: _selectedApps)),
    );
    if (picked != null) setState(() => _selectedApps = picked);
  }

  Future<void> _start() async {
    if (_record && !await AppLock.requestMicPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(('Recording needs the microphone. Allow it in Settings → Apps → APLS → Permissions, '
            'or turn off "Record lecture".').tr),
      ));
      return;
    }
    await AppLock.start(
      packages: _selectedApps.keys.toList(),
      lockMinutes: _lockMinutes,
      unlockMinutes: _unlockMinutes,
      startLocked: _startLocked,
      repeat: _repeat,
      record: _record,
      code: _codeController.text,
      strict: _strict,
    );
    _codeController.clear();
    _confirmController.clear();
    if (mounted) FocusScope.of(context).unfocus();
    await _refresh();
  }

  Future<void> _mark() async {
    final marked = await AppLock.markMoment();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(marked ? 'Marked. You\'ll find it starred in Notes.'.tr : 'Nothing is recording right now.'.tr),
    ));
  }

  Future<void> _stopWithCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.key_rounded, color: Theme.of(context).colorScheme.primary),
        title: Text('Enter your code'.tr),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('The code you chose when you started this session.'.tr, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              style: tabular(Theme.of(context).textTheme.headlineSmall)?.copyWith(letterSpacing: 8),
              decoration: const InputDecoration(hintText: '••••', counterText: ''),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text('End lock'.tr),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    final stopped = await AppLock.stop(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(stopped ? 'Lock ended'.tr : 'Wrong code'.tr)),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final active = status?.active ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(active ? 'Focus session'.tr : 'Focus'.tr),
        actions: [
          if (status != null && !active)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Pill(
                label: _accessibilityOn ? 'Ready'.tr : 'Setup needed'.tr,
                color: _accessibilityOn
                    ? Theme.of(context).colorScheme.secondary
                    : Theme.of(context).colorScheme.error,
                icon: _accessibilityOn ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              ),
            ),
          const SettingsButton(),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: status == null ? null : _bottomBar(status),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(animation), child: child),
              ),
              child: ListView(
                key: ValueKey(active),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (!_accessibilityOn) _accessibilityCard(),
                  if (active) ..._activeView(status) else ..._setupView(),
                ],
              ),
            ),
    );
  }

  Widget _bottomBar(LockStatus status) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: status.active
            ? OutlinedButton.icon(
                onPressed: _stopWithCode,
                icon: const Icon(Icons.key_rounded),
                label: Text('End early with code'.tr),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: _canStart
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    !_accessibilityOn
                                        ? 'Turn on Accessibility access first.'.tr
                                        : _selectedApps.isEmpty
                                            ? 'Choose at least one app.'.tr
                                            : _codeProblem!,
                                    style: textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  FilledButton.icon(
                    onPressed: _canStart ? _start : null,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Start session'.tr),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _accessibilityCard() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Panel(
        borderColor: colors.primary.withValues(alpha: 0.4),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary.withValues(alpha: 0.16), colors.primary.withValues(alpha: 0.04)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(Icons.accessibility_new_rounded, color: colors.primary),
                const SizedBox(width: 14),
                Expanded(child: Text('One-time setup'.tr, style: textTheme.titleLarge)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              ('APLS needs Accessibility access to see which app is open. In Settings, open '
              '"Installed apps" (or "Downloaded apps"), tap APLS and turn it on.').tr,
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: AppLock.openAccessibilitySettings,
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text('Open Accessibility settings'.tr),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _setupView() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final names = _selectedApps.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    const shown = 6;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
        child: Text(
          'Close the apps that pull you away, on a rhythm that suits you.'.tr,
          style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
      if (_stats != null) WeekCard(stats: _stats!, onTap: _openStats),
      const SizedBox(height: 12),
      Panel(
        padding: EdgeInsets.zero,
        onTap: _openTimetable,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
          leading: IconBadge(Icons.calendar_month_rounded, color: colors.secondary),
          title: Text('Timetable'.tr),
          subtitle: Text(_timetable?.nextCourse != null && _timetable?.nextStart != null
              ? 'Next: {course}, {day} {time}'.trf({
                  'course': _timetable!.nextCourse,
                  'day': shortWeekday(_timetable!.nextStart!.weekday),
                  'time': formatTimeOfDay(_timetable!.nextStart!.hour * 60 + _timetable!.nextStart!.minute),
                })
              : 'Lock apps by themselves when each class starts'.tr),
          trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ),
      ),
      SectionLabel('Apps'.tr),
      Panel(
        onTap: _pickApps,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(Icons.apps_rounded, color: colors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Apps to lock'.tr, style: textTheme.titleMedium),
                      Text(
                        names.isEmpty
                            ? 'None chosen yet'.tr
                            : names.length == 1
                                ? '1 app'.tr
                                : '{n} apps'.trf({'n': names.length}),
                        style: textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ],
            ),
            if (names.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in names.take(shown)) _miniChip(name),
                  if (names.length > shown) _miniChip('+{n} more'.trf({'n': names.length - shown}), muted: true),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      Panel(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        onTap: () => setState(() => _strict = !_strict),
        child: Row(
          children: [
            IconBadge(Icons.shield_rounded, color: colors.error),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Strict mode'.tr, style: textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    ('Also blocks Settings and uninstalling while locked, so the lock can\'t be '
                    'switched off. Your code still ends it.').tr,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(value: _strict, onChanged: (value) => setState(() => _strict = value)),
          ],
        ),
      ),
      SectionLabel('Rhythm'.tr),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CyclePreview(
              lockMinutes: _lockMinutes,
              unlockMinutes: _unlockMinutes,
              startLocked: _startLocked,
              repeat: _repeat,
            ),
            const SizedBox(height: 20),
            _durationControl(
              label: 'Lock for'.tr,
              icon: Icons.lock_rounded,
              color: colors.primary,
              minutes: _lockMinutes,
              onChanged: (value) => setState(() => _lockMinutes = value),
            ),
            const SizedBox(height: 8),
            _durationControl(
              label: 'Free for'.tr,
              icon: Icons.lock_open_rounded,
              color: colors.secondary,
              minutes: _unlockMinutes,
              onChanged: (value) => setState(() => _unlockMinutes = value),
            ),
            const SizedBox(height: 16),
            Text('Start with'.tr, style: textTheme.titleSmall),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: true, icon: Icon(Icons.lock_rounded), label: Text('Locked'.tr)),
                  ButtonSegment(value: false, icon: Icon(Icons.lock_open_rounded), label: Text('Free'.tr)),
                ],
                selected: {_startLocked},
                onSelectionChanged: (value) => setState(() => _startLocked = value.first),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Repeat'.tr),
              subtitle: Text(_repeat
                  ? 'Keep switching between locked and free until you end it with your code'.tr
                  : 'Stop after one locked and one free period'.tr),
              value: _repeat,
              onChanged: (value) => setState(() => _repeat = value),
            ),
          ],
        ),
      ),
      SectionLabel('Lecture'.tr),
      Panel(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        onTap: () => setState(() => _record = !_record),
        child: Row(
          children: [
            IconBadge(Icons.mic_rounded, color: colors.tertiary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Record lecture'.tr, style: textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    ('Records the lecture until the session ends. Afterwards, turn it into text and '
                    'notes in Notes, all on this phone.').tr,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(value: _record, onChanged: (value) => setState(() => _record = value)),
          ],
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: _record ? const _RecordingTips() : const SizedBox(width: double.infinity),
      ),
      SectionLabel('Cancel code'.tr),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(Icons.key_rounded, color: colors.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'If you set the timer too long, enter this code to end the lock early.'.tr,
                    style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _codeField(_codeController, 'Code'.tr)),
                const SizedBox(width: 12),
                Expanded(child: _codeField(_confirmController, 'Confirm'.tr)),
              ],
            ),
            const SizedBox(height: 10),
            Text('4–8 digits. Pick one you will remember.'.tr, style: textTheme.bodySmall),
          ],
        ),
      ),
    ];
  }

  Widget _miniChip(String label, {bool muted = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: muted ? Colors.transparent : colors.surfaceContainerHigh,
        border: muted ? Border.all(color: colors.outlineVariant) : null,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: 13,
              color: muted ? colors.onSurfaceVariant : colors.onSurface,
            ),
      ),
    );
  }

  Widget _durationControl({
    required String label,
    required IconData icon,
    required Color color,
    required int minutes,
    required ValueChanged<int> onChanged,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Text(label, style: textTheme.titleSmall),
            const Spacer(),
            BigValue(formatMinutes(minutes), color: color),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            overlayColor: color.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: minutes.toDouble(),
            min: 1,
            max: maxMinutes.toDouble(),
            divisions: maxMinutes - 1,
            label: formatMinutes(minutes),
            onChanged: (value) => onChanged(value.round()),
          ),
        ),
      ],
    );
  }

  Widget _codeField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      obscureText: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      maxLength: 8,
      style: tabular(Theme.of(context).textTheme.titleLarge)?.copyWith(letterSpacing: 4),
      decoration: InputDecoration(labelText: label, counterText: ''),
      onChanged: (_) => setState(() {}),
    );
  }

  List<Widget> _activeView(LockStatus status) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = status.locked ? colors.primary : colors.secondary;
    final phaseMinutes = status.locked ? status.lockMinutes : status.unlockMinutes;
    final progress = status.remaining.inMilliseconds / Duration(minutes: phaseMinutes).inMilliseconds;
    final nextEvent = status.isFinalPhase
        ? 'until the session ends'.tr
        : status.locked
            ? 'until your apps open'.tr
            : 'until your apps lock'.tr;
    final ringSize = (MediaQuery.sizeOf(context).width - 72).clamp(220.0, 320.0);
    final names = [for (final app in status.apps) app.name]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [
      const SizedBox(height: 8),
      Glow(
        color: color,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Semantics(
              liveRegion: false,
              label: '${status.locked ? 'Locked'.tr : 'Free time'.tr}, ${formatCountdown(status.remaining)} $nextEvent',
              child: ExcludeSemantics(
                child: CountdownRing(
                  progress: progress,
                  color: color,
                  size: ringSize,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(status.locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: color, size: 30),
                      const SizedBox(height: 6),
                      Text(
                        status.locked ? 'LOCKED'.tr : 'FREE TIME'.tr,
                        style: textTheme.labelSmall?.copyWith(color: color, letterSpacing: 2.4, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          formatCountdown(status.remaining),
                          style: tabular(textTheme.displayLarge?.copyWith(fontSize: ringSize * 0.22)),
                        ),
                      ),
                      Text(nextEvent, style: textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          Pill(
            label: 'Locked {time}'.trf({'time': formatMinutes(status.lockMinutes)}),
            color: colors.primary,
            icon: Icons.lock_rounded,
          ),
          Pill(
            label: 'Free {time}'.trf({'time': formatMinutes(status.unlockMinutes)}),
            color: colors.secondary,
            icon: Icons.lock_open_rounded,
          ),
          if (status.repeat) Pill(label: 'Repeats'.tr, color: colors.onSurfaceVariant, icon: Icons.repeat_rounded),
          if (status.strict) Pill(label: 'Strict'.tr, color: colors.error, icon: Icons.shield_rounded),
          if (status.recording)
            Pill(label: 'Recording lecture'.tr, color: colors.error, leading: PulseDot(color: colors.error)),
        ],
      ),
      if (status.recording) ...[
        SectionLabel('Lecture'.tr),
        Panel(
          child: Row(
            children: [
              PulseDot(color: colors.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recording'.tr, style: textTheme.titleMedium),
                    if (status.recordingStartedAt != null)
                      Text(
                        '{time} so far'.trf({'time': formatCountdown(DateTime.now().difference(status.recordingStartedAt!))}),
                        style: tabular(textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _mark,
                icon: const Icon(Icons.star_rounded),
                label: Text('Mark this moment'.tr),
              ),
            ],
          ),
        ),
      ],
      SectionLabel('Locked apps'.tr),
      Panel(
        child: names.isEmpty
            ? Text('No apps chosen'.tr, style: textTheme.bodyMedium)
            : Wrap(spacing: 8, runSpacing: 8, children: [for (final name in names) _miniChip(name)]),
      ),
    ];
  }
}

/// How to get a recording Whisper can make sense of in a big room.
class _RecordingTips extends StatelessWidget {
  const _RecordingTips();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tips = [
      (Icons.event_seat_rounded, 'Sit near the front, as close to the lecturer as you can.'.tr),
      (Icons.stay_current_portrait_rounded, 'Put the phone face up on the desk, not in a bag or pocket.'.tr),
      (Icons.mic_external_on_rounded, 'For the clearest sound, a clip-on wireless mic on the lecturer.'.tr),
      (Icons.star_rounded, 'Tap Mark important in the notification at key moments.'.tr),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        decoration: BoxDecoration(
          color: colors.tertiary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('For a clear recording'.tr, style: textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final (icon, text) in tips)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: colors.tertiary),
                    const SizedBox(width: 10),
                    Expanded(child: Text(text, style: textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The session at a glance: locked and free time drawn to scale, in the order they'll happen.
class _CyclePreview extends StatelessWidget {
  const _CyclePreview({
    required this.lockMinutes,
    required this.unlockMinutes,
    required this.startLocked,
    required this.repeat,
  });

  final int lockMinutes;
  final int unlockMinutes;
  final bool startLocked;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final lock = (minutes: lockMinutes, color: colors.primary, label: 'Locked'.tr, icon: Icons.lock_rounded);
    final free = (minutes: unlockMinutes, color: colors.secondary, label: 'Free'.tr, icon: Icons.lock_open_rounded);
    final order = startLocked ? [lock, free] : [free, lock];
    final total = lockMinutes + unlockMinutes;

    return Semantics(
      label: '${order[0].label} ${formatMinutes(order[0].minutes)}, then ${order[1].label.toLowerCase()} '
          '${formatMinutes(order[1].minutes)}${repeat ? ', repeating' : ''}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Each cycle'.tr, style: textTheme.titleSmall),
                const Spacer(),
                Text(
                  (repeat ? '{time} · repeats' : '{time} · once').trf({'time': formatMinutes(total)}),
                  style: tabular(textTheme.bodySmall),
                ),
                if (repeat) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.repeat_rounded, size: 14, color: colors.onSurfaceVariant),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (var i = 0; i < order.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    // Never thinner than a fifth of the bar, so a 1-minute break still shows its icon.
                    flex: order[i].minutes < total / 5 ? (total / 5).ceil() : order[i].minutes,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 36,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: order[i].color.withValues(alpha: 0.18),
                        border: Border.all(color: order[i].color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(order[i].icon, size: 16, color: order[i].color),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
