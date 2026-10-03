import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_lock.dart';
import 'app_picker_page.dart';
import 'lectures_page.dart';

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
  final _codeController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await AppLock.status();
    final accessibilityOn = await AppLock.isAccessibilityEnabled();
    if (!mounted) return;
    setState(() {
      // Fill the form from the last session the first time we load.
      if (_status == null) {
        _selectedApps = {for (final app in status.apps) app.packageName: app.name};
        _lockMinutes = status.lockMinutes;
        _unlockMinutes = status.unlockMinutes;
        _startLocked = status.startLocked;
        _repeat = status.repeat;
        _record = status.record;
      }
      _status = status;
      _accessibilityOn = accessibilityOn;
    });
  }

  String? get _codeProblem {
    final code = _codeController.text;
    if (code.length < 4) return 'Code must be 4–8 digits';
    if (code != _confirmController.text) return 'Codes do not match';
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Recording needs the microphone. Allow it in Settings → Apps → APLS → Permissions, '
            'or turn off "Record lecture".'),
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
    );
    _codeController.clear();
    _confirmController.clear();
    await _refresh();
  }

  Future<void> _stopWithCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter your code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 8,
          decoration: const InputDecoration(labelText: 'Code'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('End lock'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    final stopped = await AppLock.stop(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(stopped ? 'Lock ended' : 'Wrong code')),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Lock'),
        actions: [
          IconButton(
            tooltip: 'Lecture notes',
            icon: const Icon(Icons.notes),
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const LecturesPage())),
          ),
        ],
      ),
      body: status == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_accessibilityOn) _accessibilityCard(),
                if (status.active) ..._activeView(status) else ..._setupView(),
              ],
            ),
    );
  }

  Widget _accessibilityCard() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Permission needed',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colors.onErrorContainer)),
            const SizedBox(height: 8),
            Text(
              'App Lock needs Accessibility access to see which app is open. '
              'In Settings, open "Installed apps" (or "Downloaded apps"), tap App Lock and turn it on.',
              style: TextStyle(color: colors.onErrorContainer),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: AppLock.openAccessibilitySettings,
              child: const Text('Open Accessibility settings'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _setupView() {
    final textTheme = Theme.of(context).textTheme;
    return [
      Card(
        child: ListTile(
          leading: const Icon(Icons.apps),
          title: const Text('Apps to lock'),
          subtitle: Text(_selectedApps.isEmpty
              ? 'None chosen yet'
              : _selectedApps.values.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickApps,
        ),
      ),
      const SizedBox(height: 24),
      _durationSlider(
        label: 'Lock time',
        icon: Icons.lock,
        minutes: _lockMinutes,
        onChanged: (value) => setState(() => _lockMinutes = value),
      ),
      _durationSlider(
        label: 'Unlock time',
        icon: Icons.lock_open,
        minutes: _unlockMinutes,
        onChanged: (value) => setState(() => _unlockMinutes = value),
      ),
      const SizedBox(height: 8),
      Text('Start with', style: textTheme.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, icon: Icon(Icons.lock), label: Text('Locked')),
          ButtonSegment(value: false, icon: Icon(Icons.lock_open), label: Text('Unlocked')),
        ],
        selected: {_startLocked},
        onSelectionChanged: (value) => setState(() => _startLocked = value.first),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Repeat'),
        subtitle: Text(_repeat
            ? 'Keep switching between locked and unlocked until you end it with your code'
            : 'Stop after one locked and one unlocked period'),
        value: _repeat,
        onChanged: (value) => setState(() => _repeat = value),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Record lecture'),
        subtitle: const Text('Writes down what is said nearby until the session ends, '
            'so you can summarize it in Lecture notes'),
        value: _record,
        onChanged: (value) => setState(() => _record = value),
      ),
      const SizedBox(height: 16),
      Text('Cancel code', style: textTheme.titleSmall),
      Text(
        'If you set the timer too long, enter this code to end the lock early.',
        style: textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      _codeField(_codeController, 'Code (4–8 digits)'),
      const SizedBox(height: 8),
      _codeField(_confirmController, 'Confirm code'),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _canStart ? _start : null,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      ),
      const SizedBox(height: 8),
      if (!_canStart)
        Text(
          !_accessibilityOn
              ? 'Turn on Accessibility access first.'
              : _selectedApps.isEmpty
                  ? 'Choose at least one app.'
                  : _codeProblem!,
          textAlign: TextAlign.center,
          style: textTheme.bodySmall,
        ),
    ];
  }

  Widget _durationSlider({
    required String label,
    required IconData icon,
    required int minutes,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(formatMinutes(minutes), style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        Slider(
          value: minutes.toDouble(),
          min: 1,
          max: maxMinutes.toDouble(),
          divisions: maxMinutes - 1,
          label: formatMinutes(minutes),
          onChanged: (value) => onChanged(value.round()),
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
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), counterText: ''),
      onChanged: (_) => setState(() {}),
    );
  }

  List<Widget> _activeView(LockStatus status) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nextEvent = status.isFinalPhase
        ? 'Session ends in'
        : status.locked
            ? 'Unlocks in'
            : 'Locks in';

    return [
      Card(
        color: status.locked ? colors.errorContainer : colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(status.locked ? Icons.lock : Icons.lock_open, size: 56),
              const SizedBox(height: 8),
              Text(status.locked ? 'Locked' : 'Unlocked', style: textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(nextEvent, style: textTheme.bodyMedium),
              Text(formatCountdown(status.remaining), style: textTheme.displaySmall),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'Locked ${formatMinutes(status.lockMinutes)} · Unlocked ${formatMinutes(status.unlockMinutes)}'
        '${status.repeat ? ' · repeating' : ''}',
        textAlign: TextAlign.center,
      ),
      if (status.recording) ...[
        const SizedBox(height: 8),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(Icons.mic, size: 18), SizedBox(width: 4), Text('Recording lecture')],
        ),
      ],
      const SizedBox(height: 16),
      Text('Apps', style: textTheme.titleSmall),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final app in status.apps) Chip(label: Text(app.name))],
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: _stopWithCode,
        icon: const Icon(Icons.key),
        label: const Text('End lock with code'),
      ),
    ];
  }
}
