import 'package:attention_project/focus_stats.dart';
import 'package:attention_project/focus_stats_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wednesday 5 Nov 2026, 6 pm.
final now = DateTime(2026, 11, 5, 18);

FocusSession session(DateTime start, Duration length, {int lock = 30, int free = 10, bool startLocked = true}) =>
    FocusSession(
      start: start,
      end: start.add(length),
      lockMinutes: lock,
      unlockMinutes: free,
      startLocked: startLocked,
      repeat: true,
    );

FocusStats stats(List<FocusSession> sessions, {Map<String, Map<String, int>> blocked = const {}}) =>
    FocusStats(sessions: sessions, blocked: blocked, appNames: const {'com.ig': 'Instagram'}, now: now);

void main() {
  group('lockedBetween', () {
    test('counts only the locked parts of each cycle', () {
      // 30 locked + 10 free, twice, then 20 more locked: 80 minutes in all.
      final s = session(DateTime(2026, 11, 5, 9), const Duration(minutes: 100));
      expect(s.lockedBetween(DateTime(2026, 11, 5), DateTime(2026, 11, 6)), const Duration(minutes: 80));
    });

    test('starting free puts the locked part second', () {
      final s = session(DateTime(2026, 11, 5, 9), const Duration(minutes: 25), startLocked: false);
      expect(s.lockedBetween(DateTime(2026, 11, 5), DateTime(2026, 11, 6)), const Duration(minutes: 15));
    });

    test('a session over midnight is split between the days', () {
      final s = session(DateTime(2026, 11, 4, 23, 40), const Duration(minutes: 30), lock: 60);
      expect(s.lockedBetween(DateTime(2026, 11, 4), DateTime(2026, 11, 5)), const Duration(minutes: 20));
      expect(s.lockedBetween(DateTime(2026, 11, 5), DateTime(2026, 11, 6)), const Duration(minutes: 10));
    });
  });

  group('FocusStats', () {
    test('adds up the week and finds the best day', () {
      final s = stats([
        session(DateTime(2026, 11, 5, 9), const Duration(minutes: 30)),
        session(DateTime(2026, 11, 3, 9), const Duration(minutes: 70)),
        // Two weeks ago: not this week.
        session(DateTime(2026, 10, 22, 9), const Duration(minutes: 30)),
      ]);
      expect(s.days.last, DateTime(2026, 11, 5));
      expect(s.today, const Duration(minutes: 30));
      expect(s.week, const Duration(minutes: 90));
      expect(s.best, const Duration(minutes: 60));
      expect(s.sessionsThisWeek, 2);
    });

    test('a streak counts days in a row, and today without focus yet does not break it', () {
      final days = [4, 3, 2];
      final s = stats([for (final d in days) session(DateTime(2026, 11, d, 9), const Duration(minutes: 20))]);
      expect(s.streak, 3);
      final broken = stats([
        session(DateTime(2026, 11, 4, 9), const Duration(minutes: 20)),
        session(DateTime(2026, 11, 2, 9), const Duration(minutes: 20)),
      ]);
      expect(broken.streak, 1);
    });

    test('ranks the apps tried most while locked this week', () {
      final s = stats([], blocked: {
        '2026-11-05': {'com.ig': 3, 'com.tt': 1},
        '2026-11-04': {'com.tt': 4},
        '2026-10-01': {'com.ig': 50},
      });
      expect(s.topBlocked.first, (name: 'com.tt', count: 5));
      expect(s.topBlocked[1], (name: 'Instagram', count: 3));
      expect(s.blockedThisWeek, 8);
    });

    test('formats totals for people', () {
      expect(formatFocus(const Duration(minutes: 260)), '4 h 20 min');
      expect(formatFocus(Duration.zero), '0 min');
    });
  });

  testWidgets('the stats page shows the week, a table, and the most tried apps', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final s = stats(
      [session(DateTime(2026, 11, 5, 9), const Duration(minutes: 30))],
      blocked: {'2026-11-05': {'com.ig': 2}},
    );
    await tester.pumpWidget(MaterialApp(home: FocusStatsPage(stats: s)));

    expect(find.text('Your focus'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('2 tries'), findsOneWidget);
    expect(find.bySemanticsLabel('Today, Thu, Nov 5: 30 min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
