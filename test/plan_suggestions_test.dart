import 'dart:convert';

import 'package:attention_project/class_timer_page.dart';
import 'package:attention_project/lesson_plan.dart';
import 'package:attention_project/lesson_plans_page.dart';
import 'package:attention_project/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const plan = LessonPlan(id: 'p1', name: 'Physics', segments: [
  LessonSegment(title: 'Recap', minutes: 5),
  LessonSegment(title: 'Concept', minutes: 20),
  LessonSegment(title: 'Q&A', minutes: 10),
]);

/// A finished class whose segments took [minutes] each, [weeksAgo] weeks back.
ClassRun taught(int weeksAgo, List<num> minutes) {
  final start = DateTime(2026, 11, 5, 10).subtract(Duration(days: 7 * weeksAgo));
  var run = ClassRun.start(plan, start);
  var t = start;
  for (final m in minutes) {
    t = t.add(Duration(seconds: (m * 60).round()));
    run = run.advanced(t);
  }
  return run;
}

void main() {
  group('suggestionsFor', () {
    test('needs three classes first', () {
      expect(suggestionsFor(plan, [taught(1, [5, 25, 10]), taught(0, [5, 25, 10])]), isEmpty);
    });

    test('suggests more time for a segment that keeps running over', () {
      final s = suggestionsFor(plan, [taught(2, [5, 24, 10]), taught(1, [5, 25, 10]), taught(0, [5, 23, 10])]);
      expect(s, hasLength(1));
      expect(s.single.index, 1);
      expect(s.single.suggestedMinutes, 24);
      expect(s.single.message, 'Concept ran about 4 min over in your last 3 classes.');
    });

    test('suggests less time for a segment that keeps finishing early', () {
      final s = suggestionsFor(plan, [taught(2, [5, 20, 7]), taught(1, [5, 20, 7]), taught(0, [5, 20, 8])]);
      expect(s.single.title, 'Q&A');
      expect(s.single.suggestedMinutes, 7);
      expect(s.single.message, 'Q&A finished about 3 min early in your last 3 classes.');
    });

    test('ignores mixed results and small misses', () {
      expect(suggestionsFor(plan, [taught(2, [5, 25, 10]), taught(1, [5, 16, 10]), taught(0, [5, 25, 10])]), isEmpty);
      expect(suggestionsFor(plan, [taught(2, [6, 21, 10]), taught(1, [6, 21, 10]), taught(0, [6, 21, 10])]), isEmpty);
    });

    test('only the latest three classes count', () {
      final history = [
        taught(5, [5, 20, 10]),
        taught(4, [5, 20, 10]),
        taught(2, [5, 26, 10]),
        taught(1, [5, 26, 10]),
        taught(0, [5, 26, 10]),
      ];
      expect(suggestionsFor(plan, history).single.suggestedMinutes, 26);
    });
  });

  group('on the Class tab', () {
    Future<void> show(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'lesson_plans': jsonEncode([plan]),
        'class_history': jsonEncode([taught(0, [5, 24, 10]), taught(1, [5, 25, 10]), taught(2, [5, 23, 10])]),
      });
      await tester.pumpWidget(const MaterialApp(home: LessonPlansPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('applying a suggestion updates the plan', (tester) async {
      await show(tester);
      expect(find.text('Concept ran about 4 min over in your last 3 classes.'), findsOneWidget);

      await tester.tap(find.text('Make it 24 min'));
      await tester.pumpAndSettle();
      expect((await LessonStore.plans()).single.segments[1].minutes, 24);
      expect(find.text('3 segments · 39 min'), findsOneWidget);
      expect(find.textContaining('ran about'), findsNothing, reason: 'the plan now matches');
    });

    testWidgets('dismissing hides it for good', (tester) async {
      await show(tester);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ran about'), findsNothing);

      await tester.pumpWidget(const MaterialApp(home: LessonPlansPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('ran about'), findsNothing);
      expect((await LessonStore.plans()).single.segments[1].minutes, 20, reason: 'the plan is unchanged');
    });
  });

  group('class timer buzz', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('attention_project/app_lock'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
    });

    Future<int> warnFor(WidgetTester tester, LessonPlan plan, {required bool buzz}) async {
      SharedPreferences.setMockInitialValues({'buzz_before_end': buzz});
      await AppSettings.instance.load();
      await tester.pumpWidget(MaterialApp(home: ClassTimerPage(run: ClassRun.start(plan, DateTime.now()))));
      final update = calls.lastWhere((c) => c.method == 'updateClassTimer');
      await tester.pumpWidget(const SizedBox());
      return update.arguments['warnBeforeMillis'] as int;
    }

    testWidgets('warns 2 minutes before a long segment ends', (tester) async {
      expect(await warnFor(tester, plan, buzz: true), 120000, reason: 'Recap is 5 minutes');
    });

    testWidgets('skips the warning on a short segment, or when turned off', (tester) async {
      const short = LessonPlan(id: 'p2', name: 'Short', segments: [LessonSegment(title: 'Quiz', minutes: 3)]);
      expect(await warnFor(tester, short, buzz: true), 0);
      expect(await warnFor(tester, plan, buzz: false), 0);
    });
  });
}
