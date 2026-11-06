import 'package:attention_project/class_report_page.dart';
import 'package:attention_project/class_timer_page.dart';
import 'package:attention_project/lesson_plan.dart';
import 'package:attention_project/lesson_plans_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const channel = MethodChannel('attention_project/app_lock');

const plan = LessonPlan(id: 'p1', name: 'Physics', segments: [
  LessonSegment(title: 'Recap', minutes: 5),
  LessonSegment(title: 'Q&A', minutes: 10),
]);

/// A finished class whose segments took [recap] and [qa] minutes.
ClassRun pastRun(DateTime start, int recap, int qa) => ClassRun.start(plan, start)
    .advanced(start.add(Duration(minutes: recap)))
    .advanced(start.add(Duration(minutes: recap + qa)));

void main() {
  late List<MethodCall> calls;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.pump();
  }

  Iterable<MethodCall> timerUpdates() => calls.where((c) => c.method == 'updateClassTimer');

  testWidgets('runs a class from first segment to report', (tester) async {
    final run = ClassRun.start(plan, DateTime.now());
    await LessonStore.saveActiveRun(run);
    await show(tester, ClassTimerPage(run: run));

    expect(find.text('Segment 1 of 2'), findsOneWidget);
    expect(find.text('On schedule'), findsOneWidget);
    expect(calls.where((c) => c.method == 'setKeepScreenOn').single.arguments, {'on': true});
    expect(timerUpdates().single.arguments['title'], 'Recap');
    expect(timerUpdates().single.arguments['detail'], 'Next: Q&A');
    expect(timerUpdates().single.arguments['dueAtMillis'], run.currentDueAt.millisecondsSinceEpoch);

    await tester.tap(find.text('Next: Q&A'));
    await tester.pump();
    expect(find.text('Segment 2 of 2'), findsOneWidget);
    expect(timerUpdates().last.arguments['title'], 'Q&A');
    expect(timerUpdates().last.arguments['detail'], 'Last segment of Physics');
    expect((await LessonStore.activeRun())!.currentIndex, 1);

    await tester.tap(find.text('Finish class'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();

    expect(find.byType(ClassReportPage), findsOneWidget);
    expect(find.text('Planned vs. actual'), findsOneWidget);
    expect(find.text('Across weeks'), findsNothing, reason: 'only one class so far');
    expect(calls.any((c) => c.method == 'stopClassTimer'), isTrue);
    expect(await LessonStore.activeRun(), isNull);
    expect(await LessonStore.history(), hasLength(1));
  });

  testWidgets('going back to the previous segment undoes the change', (tester) async {
    final run = ClassRun.start(plan, DateTime.now()).advanced(DateTime.now());
    await LessonStore.saveActiveRun(run);
    await show(tester, ClassTimerPage(run: run));

    await tester.tap(find.text('Back to Recap'));
    await tester.pump();

    expect(find.text('Segment 1 of 2'), findsOneWidget);
    expect(timerUpdates().last.arguments['title'], 'Recap');
    expect((await LessonStore.activeRun())!.currentIndex, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a segment that has run over says so', (tester) async {
    final run = ClassRun.start(plan, DateTime.now().subtract(const Duration(minutes: 8)));
    await show(tester, ClassTimerPage(run: run));

    expect(find.text('Over by'), findsOneWidget);
    expect(find.text('3 min behind'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cancelling drops the class without saving a report', (tester) async {
    final run = ClassRun.start(plan, DateTime.now());
    await LessonStore.saveActiveRun(run);
    await show(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => ClassTimerPage(run: run))),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel class'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel class'));
    await tester.pumpAndSettle();

    expect(find.text('open'), findsOneWidget);
    expect(await LessonStore.activeRun(), isNull);
    expect(await LessonStore.history(), isEmpty);
    expect(calls.any((c) => c.method == 'stopClassTimer'), isTrue);
  });

  testWidgets('a new plan starts from the template and saves', (tester) async {
    await show(tester, const LessonPlansPage());
    await tester.pumpAndSettle();
    expect(find.textContaining('No lesson plans yet'), findsOneWidget);

    await tester.tap(find.text('New plan'));
    await tester.pumpAndSettle();
    expect(find.text('Save · 55 min'), findsOneWidget);
    expect(find.text('Give the plan a name.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Plan name'), 'Physics 101');
    await tester.pump();
    await tester.tap(find.text('Save · 55 min'));
    await tester.pumpAndSettle();

    expect(find.text('Physics 101'), findsOneWidget);
    expect(find.text('5 segments · 55 min'), findsOneWidget);
    expect((await LessonStore.plans()).single.segments.first.title, 'Recap');
  });

  testWidgets('the editor rejects a blank title and an out-of-range time', (tester) async {
    await show(tester, const PlanEditorPage(plan: plan));

    await tester.enterText(find.widgetWithText(TextField, 'Recap'), ' ');
    await tester.pump();
    expect(find.text('Every segment needs a title.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, ' '), 'Recap');
    await tester.enterText(find.widgetWithText(TextField, '5'), '0');
    await tester.pump();
    expect(find.text('Each segment must be 1–120 minutes.'), findsOneWidget);
  });

  testWidgets('the report compares classes from the same plan across weeks', (tester) async {
    final thisWeek = DateTime(2026, 11, 5, 10);
    final lastWeek = thisWeek.subtract(const Duration(days: 7));
    await LessonStore.finishRun(pastRun(lastWeek, 6, 10));
    final latest = pastRun(thisWeek, 8, 11);
    await LessonStore.finishRun(latest);

    await show(tester, ClassReportPage(run: latest));
    await tester.pumpAndSettle();

    expect(find.text('Ran 4 min over'), findsOneWidget);
    expect(find.text('8:00 of 5 min · +3:00'), findsOneWidget);
    expect(find.text('Across weeks'), findsOneWidget);
    expect(find.byTooltip('Oct 29: 6:00 of 5 min'), findsOneWidget);
    expect(find.byTooltip('Nov 5: 8:00 of 5 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long plan fits on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(960, 1600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final segments = [
      for (var i = 0; i < 8; i++) LessonSegment(title: 'A rather long segment title $i', minutes: 5),
    ];
    final long = LessonPlan(id: 'p2', name: 'Long', segments: segments);
    final start = DateTime(2026, 11, 5, 10);
    var run = ClassRun.start(long, start);
    for (var i = 1; i <= segments.length; i++) {
      run = run.advanced(start.add(Duration(minutes: i * 6)));
    }
    await LessonStore.finishRun(run);

    await tester.pumpWidget(MaterialApp(home: ClassReportPage(run: run)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
