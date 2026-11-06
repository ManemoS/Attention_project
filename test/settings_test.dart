import 'dart:io';

import 'package:attention_project/app_shell.dart';
import 'package:attention_project/lesson_plan.dart';
import 'package:attention_project/main.dart';
import 'package:attention_project/settings.dart';
import 'package:attention_project/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const plan = LessonPlan(id: 'p1', name: 'Physics', segments: [LessonSegment(title: 'Recap', minutes: 5)]);

void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('attention_project/app_lock'),
      (call) async => switch (call.method) {
        'getState' => <String, dynamic>{},
        'isAccessibilityEnabled' => false,
        'getLecturesDir' => Directory.systemTemp.path,
        _ => null,
      },
    );
  });

  Future<void> start(WidgetTester tester, Map<String, Object> prefs) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    await AppSettings.instance.load();
  }

  /// The tab labels in the bottom bar, in order.
  List<String> tabs(WidgetTester tester) => [
        for (final d in tester.widgetList<NavigationDestination>(find.byType(NavigationDestination))) d.label,
      ];

  /// Leaves the app so its once-a-second timers stop.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('first launch asks the role, and a lecturer gets Class first', (tester) async {
    await start(tester, {});
    await tester.pumpWidget(const AppLockApp());
    await tester.pump();

    expect(find.text('Welcome to APLS'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull, reason: 'nothing chosen yet');

    await tester.tap(find.text('Lecturer'));
    await tester.pump();
    await tester.tap(find.text('Continue as lecturer'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tabs(tester), ['Class', 'Focus', 'Notes']);
    expect(find.text('Class timer'), findsOneWidget, reason: 'lecturers open on Class');
    expect((await SharedPreferences.getInstance()).getString('user_role'), 'lecturer');
    await close(tester);
  });

  testWidgets('a student has no Class tab', (tester) async {
    await start(tester, {'user_role': 'student'});
    await tester.pumpWidget(const AppLockApp());
    await tester.pump();

    expect(find.text('Welcome to APLS'), findsNothing);
    expect(tabs(tester), ['Focus', 'Notes']);
    await close(tester);
  });

  testWidgets('switching from lecturer to student removes Class', (tester) async {
    await start(tester, {'user_role': 'lecturer'});
    await tester.pumpWidget(const MaterialApp(home: AppRoot()));
    await tester.pump();
    expect(tabs(tester), ['Class', 'Focus', 'Notes']);

    await AppSettings.instance.setRole(UserRole.student);
    await tester.pump();
    expect(tabs(tester), ['Focus', 'Notes']);
    expect(find.text('Focus'), findsWidgets);
    await close(tester);
  });

  testWidgets('dark mode is chosen in Settings and remembered', (tester) async {
    await start(tester, {'user_role': 'student'});
    await tester.pumpWidget(const AppLockApp());
    await tester.pump();
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);

    await tester.tap(find.byTooltip('Settings').first);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Dark theme'));
    await tester.pumpAndSettle();

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
    expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness, Brightness.dark);
    expect((await SharedPreferences.getInstance()).getString('theme_mode'), 'dark');

    await AppSettings.instance.load();
    expect(AppSettings.instance.themeMode, ThemeMode.dark, reason: 'still dark after a restart');
    await close(tester);
  });

  testWidgets("can't switch to student while a class is running", (tester) async {
    await start(tester, {'user_role': 'lecturer'});
    await LessonStore.saveActiveRun(ClassRun.start(plan, DateTime.now()));
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    expect(find.text('A class is still running'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.role, UserRole.lecturer);

    await LessonStore.cancelActiveRun();
    await tester.tap(find.text('Student'));
    await tester.pumpAndSettle();
    expect(AppSettings.instance.role, UserRole.student);
  });
}
