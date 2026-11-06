import 'dart:convert';

import 'package:attention_project/lesson_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const plan = LessonPlan(id: 'p1', name: 'Physics', segments: [
  LessonSegment(title: 'Recap', minutes: 5),
  LessonSegment(title: 'Concept', minutes: 20),
  LessonSegment(title: 'Q&A', minutes: 5),
]);

final start = DateTime(2026, 11, 5, 10);
DateTime at(int minutes, [int seconds = 0]) => start.add(Duration(minutes: minutes, seconds: seconds));

void main() {
  group('ClassRun', () {
    test('counts down, then goes negative once the segment runs over', () {
      final run = ClassRun.start(plan, start);
      expect(run.current.title, 'Recap');
      expect(run.currentDueAt, at(5));
      expect(run.remaining(at(2)), const Duration(minutes: 3));
      expect(run.remaining(at(6)), const Duration(minutes: -1));
    });

    test('a segment in progress only counts against the schedule once it runs over', () {
      final run = ClassRun.start(plan, start);
      expect(run.drift(at(2)), Duration.zero);
      expect(run.drift(at(5)), Duration.zero);
      expect(run.drift(at(7)), const Duration(minutes: 2));
    });

    test('finished segments add up, early and late', () {
      // Recap took 7 (2 over), then Concept took 15 (5 under).
      final run = ClassRun.start(plan, start).advanced(at(7)).advanced(at(22));
      expect(run.actual(0), const Duration(minutes: 7));
      expect(run.actual(1), const Duration(minutes: 15));
      expect(run.drift(at(23)), const Duration(minutes: -3));
      // Q&A is now 4 over, which outweighs the 3 ahead.
      expect(run.drift(at(31)), const Duration(minutes: 1));
    });

    test('the next segment gets its full planned time from when it really started', () {
      final run = ClassRun.start(plan, start).advanced(at(7));
      expect(run.current.title, 'Concept');
      expect(run.currentDueAt, at(27));
    });

    test('undo goes back as if the segment had never ended', () {
      final run = ClassRun.start(plan, start).advanced(at(3));
      final undone = run.undone();
      expect(undone.current.title, 'Recap');
      expect(undone.segmentEnds, isEmpty);
      expect(undone.remaining(at(4)), const Duration(minutes: 1));
    });

    test('finishing the last segment gives the totals', () {
      final run = ClassRun.start(plan, start).advanced(at(5)).advanced(at(25)).advanced(at(34));
      expect(run.isFinished, isTrue);
      expect(run.totalPlanned, const Duration(minutes: 30));
      expect(run.totalActual, const Duration(minutes: 34));
      expect(run.drift(at(99)), const Duration(minutes: 4));
    });

    test('a clock set backwards cannot make a segment negative', () {
      final run = ClassRun.start(plan, start).advanced(start.subtract(const Duration(hours: 1)));
      expect(run.actual(0), Duration.zero);
    });

    test('survives being saved and loaded', () {
      final run = ClassRun.start(plan, start).advanced(at(7));
      final loaded = ClassRun.fromJson(jsonDecode(jsonEncode(run)) as Map<String, dynamic>);
      expect(loaded.planName, 'Physics');
      expect(loaded.currentIndex, 1);
      expect(loaded.currentDueAt, run.currentDueAt);
    });

    test('segment keys match across runs and keep repeated titles apart', () {
      const repeats = LessonPlan(id: 'p', name: 'x', segments: [
        LessonSegment(title: 'Activity', minutes: 5),
        LessonSegment(title: 'Talk', minutes: 5),
        LessonSegment(title: ' activity ', minutes: 5),
      ]);
      expect(ClassRun.start(repeats, start).segmentKeys, ['activity#1', 'talk#1', 'activity#2']);
    });
  });

  group('wording', () {
    test('describeDrift', () {
      expect(describeDrift(const Duration(seconds: 29)), 'On schedule');
      expect(describeDrift(const Duration(seconds: -29)), 'On schedule');
      expect(describeDrift(const Duration(seconds: 30)), '1 min behind');
      expect(describeDrift(const Duration(minutes: 3, seconds: 10)), '3 min behind');
      expect(describeDrift(const Duration(minutes: -2)), '2 min ahead');
    });

    test('describeFinish', () {
      expect(describeFinish(Duration.zero), 'Finished on time');
      expect(describeFinish(const Duration(minutes: 4)), 'Ran 4 min over');
      expect(describeFinish(const Duration(minutes: -2)), 'Finished 2 min early');
    });
  });

  group('LessonStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('adds, replaces and deletes plans', () async {
      await LessonStore.savePlan(plan);
      await LessonStore.savePlan(const LessonPlan(id: 'p1', name: 'Renamed', segments: []));
      await LessonStore.savePlan(const LessonPlan(id: 'p2', name: 'Other', segments: []));
      expect((await LessonStore.plans()).map((p) => p.name), ['Renamed', 'Other']);

      await LessonStore.deletePlan('p1');
      expect((await LessonStore.plans()).map((p) => p.name), ['Other']);
    });

    test('finishing a class moves it to the history, newest first', () async {
      await LessonStore.saveActiveRun(ClassRun.start(plan, start));
      expect(await LessonStore.activeRun(), isNotNull);

      final first = ClassRun.start(plan, start).advanced(at(5)).advanced(at(25)).advanced(at(30));
      final later = start.add(const Duration(days: 7));
      final second = ClassRun.start(plan, later)
          .advanced(later.add(const Duration(minutes: 5)))
          .advanced(later.add(const Duration(minutes: 25)))
          .advanced(later.add(const Duration(minutes: 30)));
      await LessonStore.finishRun(first);
      await LessonStore.finishRun(second);

      expect(await LessonStore.activeRun(), isNull);
      expect((await LessonStore.history()).map((r) => r.startedAt), [later, start]);

      await LessonStore.deleteFromHistory(second);
      expect((await LessonStore.history()).map((r) => r.startedAt), [start]);
    });

    test('deleting a plan keeps the classes taught from it', () async {
      await LessonStore.savePlan(plan);
      await LessonStore.finishRun(ClassRun.start(plan, start).advanced(at(5)).advanced(at(25)).advanced(at(30)));
      await LessonStore.deletePlan(plan.id);
      expect((await LessonStore.history()).single.planName, 'Physics');
    });
  });
}
