import 'dart:convert';
import 'dart:math';

import 'app_lock.dart';

/// One focus session, as LockState.kt keeps it.
class FocusSession {
  const FocusSession({
    required this.start,
    required this.end,
    required this.lockMinutes,
    required this.unlockMinutes,
    required this.startLocked,
    required this.repeat,
  });

  factory FocusSession.fromJson(Map<String, dynamic> json) => FocusSession(
        start: DateTime.fromMillisecondsSinceEpoch(json['start'] as int),
        end: DateTime.fromMillisecondsSinceEpoch(json['end'] as int),
        lockMinutes: json['lockMinutes'] as int,
        unlockMinutes: json['unlockMinutes'] as int,
        startLocked: json['startLocked'] as bool,
        repeat: json['repeat'] as bool,
      );

  final DateTime start;
  final DateTime end;
  final int lockMinutes;
  final int unlockMinutes;
  final bool startLocked;
  final bool repeat;

  /// How long apps were locked between [from] and [to].
  Duration lockedBetween(DateTime from, DateTime to) {
    if (!end.isAfter(from) || !start.isBefore(to)) return Duration.zero;
    final lock = Duration(minutes: lockMinutes);
    final free = Duration(minutes: unlockMinutes);
    final cycle = lock + free;
    var total = Duration.zero;
    // Walk the session one cycle at a time, adding the locked part of each that falls in range.
    for (var cycleStart = start; cycleStart.isBefore(end); cycleStart = cycleStart.add(cycle)) {
      final lockStart = startLocked ? cycleStart : cycleStart.add(free);
      final lockEnd = lockStart.add(lock);
      final a = _latest([lockStart, start, from]);
      final b = _earliest([lockEnd, end, to]);
      if (b.isAfter(a)) total += b.difference(a);
      if (!cycleStart.isBefore(to)) break;
    }
    return total;
  }

  static DateTime _latest(List<DateTime> times) => times.reduce((a, b) => a.isAfter(b) ? a : b);
  static DateTime _earliest(List<DateTime> times) => times.reduce((a, b) => a.isBefore(b) ? a : b);
}

/// A week of focus, worked out from the session history and blocked opens.
class FocusStats {
  FocusStats({
    required List<FocusSession> sessions,
    required Map<String, Map<String, int>> blocked,
    required Map<String, String> appNames,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    days = [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];

    Duration lockedOn(DateTime day) {
      final next = DateTime(day.year, day.month, day.day + 1);
      return sessions.fold(Duration.zero, (sum, s) => sum + s.lockedBetween(day, next));
    }

    daily = [for (final day in days) lockedOn(day)];
    week = daily.fold(Duration.zero, (a, b) => a + b);
    sessionsThisWeek = sessions.where((s) => !s.end.isBefore(days.first)).length;

    // Days in a row with at least a minute of focus, counting back from today. A day without focus
    // yet today doesn't break the streak until it's over.
    var day = lockedOn(today) >= const Duration(minutes: 1) ? today : today.subtract(const Duration(days: 1));
    var count = 0;
    while (count < 366 && lockedOn(day) >= const Duration(minutes: 1)) {
      count++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    streak = count;

    final weekKeys = {for (final d in days) _dayKey(d)};
    final perApp = <String, int>{};
    for (final entry in blocked.entries) {
      if (!weekKeys.contains(entry.key)) continue;
      entry.value.forEach((pkg, n) => perApp[pkg] = (perApp[pkg] ?? 0) + n);
    }
    topBlocked = [
      for (final e in perApp.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        (name: appNames[e.key] ?? e.key, count: e.value),
    ];
    blockedThisWeek = perApp.values.fold(0, (a, b) => a + b);
  }

  static Future<FocusStats> load() async {
    final raw = await AppLock.focusHistory();
    return FocusStats(
      sessions: [
        for (final s in jsonDecode(raw['sessions'] as String? ?? '[]') as List)
          FocusSession.fromJson(s as Map<String, dynamic>),
      ],
      blocked: {
        for (final e in (jsonDecode(raw['blocked'] as String? ?? '{}') as Map<String, dynamic>).entries)
          e.key: {for (final c in (e.value as Map<String, dynamic>).entries) c.key: c.value as int},
      },
      appNames: {
        for (final e in (raw['names'] as Map? ?? const {}).entries) e.key as String: e.value as String,
      },
      now: DateTime.now(),
    );
  }

  /// The last seven days, oldest first, ending today.
  late final List<DateTime> days;

  /// Locked time on each of [days].
  late final List<Duration> daily;
  late final Duration week;
  late final int sessionsThisWeek;
  late final int streak;

  /// Locked apps opened this week, most tried first.
  late final List<({String name, int count})> topBlocked;
  late final int blockedThisWeek;

  Duration get today => daily.last;
  Duration get best => daily.reduce((a, b) => a > b ? a : b);
  bool get isEmpty => week == Duration.zero && blockedThisWeek == 0;

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// "4 h 20 min", "35 min", "0 min" for a focus total.
String formatFocus(Duration d) => formatMinutes(max(0, (d.inSeconds + 30) ~/ 60));
