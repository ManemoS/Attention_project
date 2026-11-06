import 'package:flutter/material.dart';

import 'class_timer_page.dart';
import 'home_page.dart';
import 'lectures_page.dart';
import 'lesson_plan.dart';
import 'lesson_plans_page.dart';
import 'settings.dart';
import 'settings_page.dart';
import 'l10n.dart';

/// Asks who's using the app the first time, then shows the tabs for that role.
class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: AppSettings.instance,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: AppSettings.instance.role == null ? const WelcomePage() : const AppShell(),
        ),
      );
}

enum _Tab { focus, notes, classes }

/// The parts of the app, one tab each, within thumb reach. Lecturers also get Class, first.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Tab? _current;

  // Bumped each time a tab is opened, so Notes and Class reload what changed while they were hidden
  // (a new recording, a class finished from the notification). Focus keeps its half-filled form.
  final _visits = {for (final tab in _Tab.values) tab: 0};

  List<_Tab> get _tabs =>
      AppSettings.instance.isLecturer ? const [_Tab.classes, _Tab.focus, _Tab.notes] : const [_Tab.focus, _Tab.notes];

  @override
  void initState() {
    super.initState();
    AppSettings.instance.addListener(_roleChanged);
    _resumeClass();
  }

  @override
  void dispose() {
    AppSettings.instance.removeListener(_roleChanged);
    super.dispose();
  }

  /// Redraws the tabs for the new role, going back to the first one if the one showing has gone.
  void _roleChanged() => setState(() {
        if (!_tabs.contains(_current)) _current = null;
      });

  /// Goes straight back to the timer if the app was closed during a class.
  Future<void> _resumeClass() async {
    if (!AppSettings.instance.isLecturer) return;
    final run = await LessonStore.activeRun();
    if (run == null || !mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClassTimerPage(run: run)));
  }

  void _select(_Tab tab) {
    if (tab == (_current ?? _tabs.first)) return;
    setState(() {
      _visits[tab] = _visits[tab]! + 1;
      _current = tab;
    });
  }

  Widget _page(_Tab tab) => switch (tab) {
        _Tab.focus => const HomePage(),
        _Tab.notes => LecturesPage(key: ValueKey('notes${_visits[tab]}')),
        _Tab.classes => LessonPlansPage(key: ValueKey('class${_visits[tab]}')),
      };

  NavigationDestination _destination(_Tab tab) => switch (tab) {
        _Tab.focus => NavigationDestination(
            icon: Icon(Icons.lock_outline),
            selectedIcon: Icon(Icons.lock),
            label: 'Focus'.tr,
          ),
        _Tab.notes => NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Notes'.tr,
          ),
        _Tab.classes => NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Class'.tr,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final current = _current ?? tabs.first;
    final index = tabs.indexOf(current);
    return PopScope(
      // Back from another tab goes to the first one before it leaves the app.
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(tabs.first);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [
            for (final tab in tabs) KeyedSubtree(key: ValueKey(tab), child: _page(tab)),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => _select(tabs[i]),
          destinations: [for (final tab in tabs) _destination(tab)],
        ),
      ),
    );
  }
}
