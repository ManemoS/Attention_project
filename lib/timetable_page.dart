import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'theme.dart';
import 'timetable.dart';
import 'ui.dart';
import 'l10n.dart';

/// The weekly timetable: classes that lock apps (and offer to record) by themselves.
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key, required this.packages, required this.strict});

  /// The apps chosen on the Focus tab, which a class locks.
  final List<String> packages;
  final bool strict;

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> with WidgetsBindingObserver {
  List<TimetableEntry>? _entries;
  bool _enabled = false;
  TimetableInfo _info = const TimetableInfo(hasCode: false, exactAlarms: true);
  final _code = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the exact-alarm settings screen.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final entries = await TimetableStore.entries();
    final enabled = await TimetableStore.enabled();
    final info = await TimetableStore.info();
    if (mounted) {
      setState(() {
        _entries = entries;
        _enabled = enabled;
        _info = info;
      });
    }
  }

  String? get _codeProblem {
    if (_info.hasCode && _code.text.isEmpty) return null;
    if (_code.text.length < 4) return 'Set a 4–8 digit code to end a class lock early.'.tr;
    if (_code.text != _confirm.text) return 'The codes don\'t match.'.tr;
    return null;
  }

  Future<void> _save({List<TimetableEntry>? entries, bool? enabled}) async {
    final code = _code.text.isNotEmpty && _codeProblem == null ? _code.text : null;
    await TimetableStore.save(
      entries: entries ?? _entries!,
      enabled: enabled ?? _enabled,
      packages: widget.packages,
      strict: widget.strict,
      code: code,
    );
    if (code != null) {
      _code.clear();
      _confirm.clear();
    }
    await _load();
  }

  Future<void> _toggle(bool on) async {
    if (on && widget.packages.isEmpty) {
      _snack('Choose the apps to lock on the Focus tab first.'.tr);
      return;
    }
    if (on && _codeProblem != null) {
      _snack(_codeProblem!);
      return;
    }
    if (on) await AppLock.requestMicPermission();
    await _save(enabled: on);
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit(TimetableEntry? entry) async {
    final result = await showModalBottomSheet<TimetableEntry>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EntryEditor(entry: entry, others: _entries!),
    );
    if (result == null) return;
    await _save(entries: [
      for (final e in _entries!)
        if (e.id != result.id) e,
      result,
    ]);
  }

  Future<void> _delete(TimetableEntry entry) => _save(entries: [for (final e in _entries!) if (e.id != entry.id) e]);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final entries = _entries;
    return Scaffold(
      appBar: AppBar(title: Text('Timetable'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: entries == null ? null : () => _edit(null),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add class'.tr),
      ),
      body: entries == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
              children: [
                Panel(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  onTap: () => _toggle(!_enabled),
                  child: Row(
                    children: [
                      IconBadge(Icons.event_available_rounded, color: colors.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lock apps in class'.tr, style: textTheme.titleMedium),
                            Text(
                              widget.packages.isEmpty
                                  ? 'Choose apps on the Focus tab first.'.tr
                                  : 'Locks the {apps} chosen on the Focus tab, for up to 2 hours of each class.'.trf({
                                      'apps': widget.packages.length == 1
                                          ? 'app'.tr
                                          : '{n} apps'.trf({'n': widget.packages.length}),
                                    }),
                              style: textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Switch(value: _enabled, onChanged: _toggle),
                    ],
                  ),
                ),
                if (_enabled && _info.nextCourse != null && _info.nextStart != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Pill(
                      label: 'Next: {course} · {day} {time}'.trf({
                        'course': _info.nextCourse,
                        'day': shortWeekday(_info.nextStart!.weekday),
                        'time': formatTimeOfDay(_info.nextStart!.hour * 60 + _info.nextStart!.minute),
                      }),
                      color: colors.primary,
                      icon: Icons.schedule_rounded,
                    ),
                  ),
                ],
                if (_enabled && !_info.exactAlarms) ...[
                  const SizedBox(height: 12),
                  Panel(
                    borderColor: colors.error.withValues(alpha: 0.4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Locks may start a few minutes late'.tr, style: textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'Allow APLS to set exact alarms so the lock starts right on time.'.tr,
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: TimetableStore.openExactAlarmSettings,
                          child: Text('Allow exact alarms'.tr),
                        ),
                      ],
                    ),
                  ),
                ],
                SectionLabel(_info.hasCode ? 'Change code'.tr : 'Class code'.tr),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _info.hasCode
                            ? 'A code is set. Enter a new one here to change it.'.tr
                            : 'Like the Focus code: enter it on the lock screen to end a class lock early.'.tr,
                        style: textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _codeField(_code, 'Code'.tr)),
                          const SizedBox(width: 12),
                          Expanded(child: _codeField(_confirm, 'Confirm'.tr)),
                        ],
                      ),
                      if (_info.hasCode && _code.text.isNotEmpty && _codeProblem == null) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonal(onPressed: () => _save(), child: Text('Save new code'.tr)),
                      ],
                    ],
                  ),
                ),
                if (entries.isEmpty)
                  EmptyState(
                    icon: Icons.calendar_month_rounded,
                    title: 'Add your classes'.tr,
                    message: ('Enter each weekly class once. APLS locks your apps when it starts and offers to '
                        'record the lecture into that course\'s folder.').tr,
                  )
                else
                  for (var day = 1; day <= 7; day++)
                    if (entries.any((e) => e.weekday == day)) ...[
                      SectionLabel(weekdayName(day)),
                      Panel(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            for (final e in entries.where((e) => e.weekday == day))
                              ListTile(
                                onTap: () => _edit(e),
                                leading: Container(
                                  width: 64,
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(formatTimeOfDay(e.start), style: tabular(textTheme.labelLarge)),
                                      Text(formatTimeOfDay(e.end), style: tabular(textTheme.labelSmall)),
                                    ],
                                  ),
                                ),
                                title: Text(e.course),
                                subtitle: Text([
                                  formatMinutes(e.minutes),
                                  if (e.record) 'Offers to record'.tr,
                                ].join(' · ')),
                                trailing: PopupMenuButton<void>(
                                  tooltip: 'More'.tr,
                                  itemBuilder: (_) => [
                                    PopupMenuItem(onTap: () => _edit(e), child: Text('Edit'.tr)),
                                    PopupMenuItem(onTap: () => _delete(e), child: Text('Delete'.tr)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                const SizedBox(height: 8),
                Text(
                  'A class that starts while another lock is running leaves that lock as it is.'.tr,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
    );
  }

  Widget _codeField(TextEditingController controller, String label) => TextField(
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

/// Adds or changes one class.
class _EntryEditor extends StatefulWidget {
  const _EntryEditor({required this.entry, required this.others});

  final TimetableEntry? entry;
  final List<TimetableEntry> others;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final _course = TextEditingController(text: widget.entry?.course);
  late int _weekday = widget.entry?.weekday ?? DateTime.now().weekday;
  late int _start = widget.entry?.start ?? 9 * 60;
  late int _end = widget.entry?.end ?? 10 * 60 + 30;
  late bool _record = widget.entry?.record ?? true;

  @override
  void dispose() {
    _course.dispose();
    super.dispose();
  }

  TimetableEntry get _entry => TimetableEntry(
        id: widget.entry?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        weekday: _weekday,
        start: _start,
        end: _end,
        course: _course.text.trim(),
        record: _record,
      );

  Future<void> _pick(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (start) {
        // Keep the class the same length when its start moves.
        final length = _end - _start;
        _start = minutes;
        _end = (minutes + length).clamp(minutes + 1, 24 * 60 - 1);
      } else {
        _end = minutes;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final problem = timetableProblem(_entry, widget.others);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.entry == null ? 'Add class'.tr : 'Edit class'.tr, style: textTheme.headlineSmall),
            const SizedBox(height: 16),
            TextField(
              controller: _course,
              autofocus: widget.entry == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Class'.tr, hintText: 'For example, Physics 101'.tr),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text(shortWeekday(d)),
                    selected: _weekday == d,
                    onSelected: (_) => setState(() => _weekday = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _timeButton('Starts'.tr, _start, () => _pick(true))),
                const SizedBox(width: 12),
                Expanded(child: _timeButton('Ends'.tr, _end, () => _pick(false))),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Offer to record'.tr),
              subtitle: Text('A notification lets you start recording with one tap'.tr),
              value: _record,
              onChanged: (v) => setState(() => _record = v),
            ),
            if (problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(problem, textAlign: TextAlign.center, style: textTheme.bodySmall),
              ),
            FilledButton(
              onPressed: problem == null ? () => Navigator.pop(context, _entry) : null,
              child: Text('Save class'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeButton(String label, int minutes, VoidCallback onTap) {
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodySmall),
          Text(formatTimeOfDay(minutes), style: tabular(textTheme.headlineSmall)),
        ],
      ),
    );
  }
}
