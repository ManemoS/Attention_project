import 'package:flutter/material.dart';

import 'ai_settings.dart';
import 'backup.dart';
import 'lectures.dart';
import 'lectures_page.dart';
import 'lesson_plan.dart';
import 'settings.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// The gear in each tab's top bar.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings'.tr,
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
  );
}

/// A big tappable card for one role, used on the welcome screen and in Settings.
class RoleCard extends StatelessWidget {
  const RoleCard({super.key, required this.role, required this.selected, required this.onTap});

  final UserRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = role == UserRole.lecturer ? colors.tertiary : colors.primary;
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: selected ? accent : Colors.transparent, width: 2),
        ),
        child: Panel(
          onTap: onTap,
          borderColor: selected ? accent.withValues(alpha: 0.2) : null,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.04)],
                )
              : null,
          child: Row(
            children: [
              IconBadge(role.icon, color: accent, size: 52),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.label.tr, style: textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(role.description.tr, style: textTheme.bodySmall),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(label: 'Focus'.tr, color: colors.primary, icon: Icons.lock_rounded),
                        Pill(label: 'Notes'.tr, color: colors.secondary, icon: Icons.auto_stories_rounded),
                        if (role == UserRole.lecturer)
                          Pill(label: 'Class'.tr, color: colors.tertiary, icon: Icons.timer_rounded),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? accent : Colors.transparent,
                  border: Border.all(color: selected ? accent : colors.outline, width: 2),
                ),
                child: selected ? Icon(Icons.check_rounded, size: 16, color: colors.surface) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown on first launch: who is this app for?
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  UserRole? _choice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'You can change this any time in Settings.'.tr,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _choice == null ? null : () => AppSettings.instance.setRole(_choice!),
                child: Text(_choice == null ? 'Choose one to continue'.tr : 'Continue as {role}'.trf({'role': isThai ? _choice!.label.tr : _choice!.label.toLowerCase()})),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            Center(
              child: Glow(
                color: colors.primary,
                strength: 0.3,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colors.primary, Color.lerp(colors.primary, colors.error, 0.45)!],
                      ),
                    ),
                    child: Icon(Icons.lock_clock_rounded, size: 44, color: colors.onPrimary),
                  ),
                ),
              ),
            ),
            Text('Welcome to APLS'.tr, textAlign: TextAlign.center, style: textTheme.headlineLarge),
            const SizedBox(height: 10),
            Text(
              'Fewer distractions in class, better notes after it. How will you use it?'.tr,
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            for (final role in UserRole.values) ...[
              RoleCard(role: role, selected: _choice == role, onTap: () => setState(() => _choice = role)),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? _hasApiKey;

  AppSettings get _settings => AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _checkApiKey();
  }

  Future<void> _checkApiKey() async {
    final key = await Claude.apiKey();
    if (mounted) setState(() => _hasApiKey = key != null);
  }

  Future<void> _chooseRole(UserRole role) async {
    if (role == _settings.role) return;
    // A running class keeps buzzing, so don't hide the only way back to it.
    if (role == UserRole.student && await LessonStore.activeRun() != null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: Icon(Icons.timer_rounded, color: Theme.of(context).colorScheme.primary),
          title: Text('A class is still running'.tr),
          content: Text(
            'Finish or cancel it in Class first, then switch to student.'.tr,
            textAlign: TextAlign.center,
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text('OK'.tr))],
        ),
      );
      return;
    }
    await _settings.setRole(role);
  }

  Future<void> _editApiKey() async {
    await showApiKeyDialog(context);
    await _checkApiKey();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text('Settings'.tr)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SectionLabel('I am a'.tr, padding: EdgeInsets.fromLTRB(4, 8, 4, 10)),
            for (final role in UserRole.values) ...[
              RoleCard(role: role, selected: _settings.role == role, onTap: () => _chooseRole(role)),
              const SizedBox(height: 12),
            ],
            SectionLabel('Appearance'.tr, padding: EdgeInsets.fromLTRB(4, 12, 4, 10)),
            Row(
              children: [
                for (final (mode, label) in [
                  (ThemeMode.system, 'System'.tr),
                  (ThemeMode.light, 'Light'.tr),
                  (ThemeMode.dark, 'Dark'.tr),
                ]) ...[
                  if (mode != ThemeMode.system) const SizedBox(width: 10),
                  Expanded(
                    child: _ThemeTile(
                      mode: mode,
                      label: label,
                      selected: _settings.themeMode == mode,
                      onTap: () => _settings.setThemeMode(mode),
                    ),
                  ),
                ],
              ],
            ),
            SectionLabel('Language'.tr),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'system', icon: const Icon(Icons.smartphone_rounded), label: Text('System'.tr)),
                  // Each language is written in itself, so it can be found whichever one is showing.
                  const ButtonSegment(value: 'en', label: Text('English')),
                  const ButtonSegment(value: 'th', label: Text('ไทย')),
                ],
                selected: {_settings.language},
                onSelectionChanged: (value) => _settings.setLanguage(value.first),
              ),
            ),
            if (_settings.isLecturer) ...[
              SectionLabel('Class timer'.tr),
              Panel(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                onTap: () => _settings.setBuzzBeforeEnd(!_settings.buzzBeforeEnd),
                child: Row(
                  children: [
                    IconBadge(Icons.vibration_rounded, color: colors.primary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Buzz 2 minutes before'.tr, style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(
                            ('One soft buzz when a segment has 2 minutes left, two when time is up. '
                            'A watch paired with your phone buzzes too.').tr,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Switch(value: _settings.buzzBeforeEnd, onChanged: _settings.setBuzzBeforeEnd),
                  ],
                ),
              ),
            ],
            const AiSettings(),
            if (_settings.notesEngine == 'claude') ...[
              const SizedBox(height: 12),
              Panel(
                padding: EdgeInsets.zero,
                onTap: _editApiKey,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                  leading: IconBadge(Icons.key_rounded, color: colors.tertiary),
                  title: Text('Claude API key'.tr),
                  subtitle: Text(switch (_hasApiKey) {
                    null => 'Checking…'.tr,
                    true => 'Saved on this phone · used to summarize lectures'.tr,
                    false => 'Not set · needed to summarize lectures'.tr,
                  }),
                  trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
                ),
              ),
            ],
            SectionLabel('Backup'.tr),
            const _BackupPanel(),
            SectionLabel('About'.tr),
            Panel(
              padding: EdgeInsets.zero,
              onTap: () => showLicensePage(context: context, applicationName: 'APLS'),
              child: ListTile(
                contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                leading: IconBadge(Icons.description_outlined, color: colors.onSurfaceVariant),
                title: Text('Licenses'.tr),
                subtitle: Text('Fonts and open-source software in this app'.tr),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Save everything to a file, or bring it back from one.
class _BackupPanel extends StatefulWidget {
  const _BackupPanel();

  @override
  State<_BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<_BackupPanel> {
  bool _includeAudio = false;
  bool _busy = false;

  Future<void> _run(Future<bool> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      final ok = await job();
      if (ok && mounted) _snack(done);
    } on BackupException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _restore() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(Icons.settings_backup_restore_rounded, color: Theme.of(context).colorScheme.primary),
        title: Text('Restore a backup?'.tr),
        content: Text(
          ('Lectures, plans, class history and settings from the backup are added to this phone. '
          'Lectures with the same date are replaced. Your timetable comes back switched off; set its '
          'code again to turn it on.').tr,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Choose file'.tr)),
        ],
      ),
    );
    if (go == true) await _run(AppBackup.restore, 'Backup restored'.tr);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(Icons.cloud_upload_outlined, color: colors.secondary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  ('Save your notes, plans, timetable, stats and settings to one file, for a new phone or '
                  'just in case. Your API key is never included.').tr,
                  style: textTheme.bodySmall,
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Include recordings'.tr),
            subtitle: Text('About 15 MB per hour of lecture'.tr),
            value: _includeAudio,
            onChanged: _busy ? null : (v) => setState(() => _includeAudio = v),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _run(() => AppBackup.save(includeAudio: _includeAudio), 'Backup saved'.tr),
                  icon: _busy
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_alt_rounded),
                  label: Text('Save backup'.tr),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.settings_backup_restore_rounded),
                  label: Text('Restore'.tr),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A theme choice drawn as a tiny screen in that theme's colours.
class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.mode, required this.label, required this.selected, required this.onTap});

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final light = AppTheme.light.colorScheme;
    final dark = AppTheme.dark.colorScheme;

    Widget mini(ColorScheme c) => ColoredBox(
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.primary, width: 4),
              ),
            ),
            const Spacer(),
            FractionallySizedBox(
              widthFactor: 0.85,
              child: Container(height: 6, decoration: _bar(c.onSurface.withValues(alpha: 0.7))),
            ),
            const SizedBox(height: 4),
            FractionallySizedBox(
              widthFactor: 0.55,
              child: Container(height: 6, decoration: _bar(c.onSurfaceVariant.withValues(alpha: 0.5))),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      selected: selected,
      button: true,
      label: '{name} theme'.trf({'name': label}),
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 104,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? colors.primary : colors.outlineVariant, width: selected ? 2.5 : 1),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: switch (mode) {
                  ThemeMode.light => mini(light),
                  ThemeMode.dark => mini(dark),
                  ThemeMode.system => Row(
                    children: [
                      Expanded(child: mini(light)),
                      Expanded(child: mini(dark)),
                    ],
                  ),
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Icons.check_circle_rounded, size: 16, color: colors.primary),
                  const SizedBox(width: 4),
                ],
                Text(label, style: textTheme.labelLarge?.copyWith(color: selected ? colors.primary : null)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static BoxDecoration _bar(Color color) => BoxDecoration(color: color, borderRadius: BorderRadius.circular(3));
}
