import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n.dart';

/// One weekly class. [weekday] is 1 (Monday) to 7 (Sunday); times are minutes after midnight.
class TimetableEntry {
  const TimetableEntry({
    required this.id,
    required this.weekday,
    required this.start,
    required this.end,
    required this.course,
    this.record = false,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> json) => TimetableEntry(
        id: json['id'] as String,
        weekday: json['weekday'] as int,
        start: json['start'] as int,
        end: json['end'] as int,
        course: json['course'] as String,
        record: json['record'] as bool? ?? false,
      );

  final String id;
  final int weekday;
  final int start;
  final int end;
  final String course;
  final bool record;

  int get minutes => end - start;

  Map<String, dynamic> toJson() =>
      {'id': id, 'weekday': weekday, 'start': start, 'end': end, 'course': course, 'record': record};
}

/// "9:00", "13:30": 24-hour, which reads the same in every country this app is used in.
String formatTimeOfDay(int minutes) => '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Monday" (or "วันจันทร์") for [weekday] 1 to 7.
String weekdayName(int weekday) => _weekdays[weekday - 1].tr;

/// "Mon" (or "จ.") for [weekday] 1 to 7.
String shortWeekday(int weekday) => _shortWeekdays[weekday - 1].tr;

/// Why [entry] can't be saved, or null if it can.
String? timetableProblem(TimetableEntry entry, List<TimetableEntry> others) {
  if (entry.course.trim().isEmpty) return 'Give the class a name.'.tr;
  if (entry.end <= entry.start) return 'The class has to end after it starts.'.tr;
  if (entry.minutes > 240) return 'Classes can be up to 4 hours.'.tr;
  for (final o in others) {
    if (o.id == entry.id || o.weekday != entry.weekday) continue;
    if (entry.start < o.end && o.start < entry.end) {
      return 'It overlaps {course} ({start}–{end}).'.trf({
        'course': o.course,
        'start': formatTimeOfDay(o.start),
        'end': formatTimeOfDay(o.end),
      });
    }
  }
  return null;
}

/// What the Android side reports about the timetable.
class TimetableInfo {
  const TimetableInfo({required this.hasCode, required this.exactAlarms, this.nextCourse, this.nextStart});

  final bool hasCode;

  /// False if Android may run the lock a few minutes late (the exact-alarm permission is off).
  final bool exactAlarms;
  final String? nextCourse;
  final DateTime? nextStart;
}

/// The weekly timetable: kept here for the screens, and sent to Timetable.kt, which sets the alarms.
class TimetableStore {
  static const _entriesKey = 'timetable_entries';
  static const _enabledKey = 'timetable_enabled';
  static const _channel = MethodChannel('attention_project/app_lock');

  static Future<List<TimetableEntry>> entries() async {
    final raw = (await SharedPreferences.getInstance()).getString(_entriesKey);
    if (raw == null) return [];
    return [for (final e in jsonDecode(raw) as List) TimetableEntry.fromJson(e as Map<String, dynamic>)]
      ..sort((a, b) => a.weekday != b.weekday ? a.weekday.compareTo(b.weekday) : a.start.compareTo(b.start));
  }

  static Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? false;

  /// Saves the timetable and reschedules. [code] (4–8 digits) is needed once; null keeps it.
  static Future<void> save({
    required List<TimetableEntry> entries,
    required bool enabled,
    required List<String> packages,
    required bool strict,
    String? code,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode([for (final e in entries) e.toJson()]);
    await prefs.setString(_entriesKey, json);
    await prefs.setBool(_enabledKey, enabled);
    await _channel.invokeMethod<void>('setTimetable', {
      'entries': json,
      'packages': packages,
      'code': code,
      'strict': strict,
      'enabled': enabled,
    });
  }

  static Future<TimetableInfo> info() async {
    final map = await _channel.invokeMapMethod<String, dynamic>('getTimetableInfo') ?? const {};
    final next = map['nextStartMillis'] as int?;
    return TimetableInfo(
      hasCode: map['hasCode'] as bool? ?? false,
      exactAlarms: map['exactAlarms'] as bool? ?? true,
      nextCourse: map['nextCourse'] as String?,
      nextStart: next == null ? null : DateTime.fromMillisecondsSinceEpoch(next),
    );
  }

  static Future<void> openExactAlarmSettings() => _channel.invokeMethod<void>('openExactAlarmSettings');
}
