import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// One part of a lecture, such as "Concept, 20 minutes".
class LessonSegment {
  const LessonSegment({required this.title, required this.minutes});

  factory LessonSegment.fromJson(Map<String, dynamic> json) =>
      LessonSegment(title: json['title'] as String, minutes: json['minutes'] as int);

  final String title;
  final int minutes;

  Duration get planned => Duration(minutes: minutes);

  Map<String, dynamic> toJson() => {'title': title, 'minutes': minutes};
}

class LessonPlan {
  const LessonPlan({required this.id, required this.name, required this.segments});

  factory LessonPlan.fromJson(Map<String, dynamic> json) => LessonPlan(
        id: json['id'] as String,
        name: json['name'] as String,
        segments: _segmentsFromJson(json['segments']),
      );

  final String id;
  final String name;
  final List<LessonSegment> segments;

  int get totalMinutes => segments.fold(0, (sum, segment) => sum + segment.minutes);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'segments': [for (final s in segments) s.toJson()]};
}

List<LessonSegment> _segmentsFromJson(Object? json) =>
    [for (final s in json as List) LessonSegment.fromJson(s as Map<String, dynamic>)];

/// One class taught from a plan.
///
/// The professor moves from segment to segment by hand, which is what makes planned and actual
/// times differ. Everything is worked out from timestamps, so a run carries on correctly if the
/// app is closed part-way through. It keeps its own copy of the segments so that editing the plan
/// later doesn't change past reports.
class ClassRun {
  const ClassRun({
    required this.planId,
    required this.planName,
    required this.segments,
    required this.startedAt,
    this.segmentEnds = const [],
  });

  factory ClassRun.start(LessonPlan plan, DateTime now) => ClassRun(
        planId: plan.id,
        planName: plan.name,
        segments: plan.segments,
        startedAt: now,
      );

  factory ClassRun.fromJson(Map<String, dynamic> json) => ClassRun(
        planId: json['planId'] as String,
        planName: json['planName'] as String,
        segments: _segmentsFromJson(json['segments']),
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
        segmentEnds: [
          for (final end in json['segmentEnds'] as List) DateTime.fromMillisecondsSinceEpoch(end as int),
        ],
      );

  final String planId;
  final String planName;
  final List<LessonSegment> segments;
  final DateTime startedAt;

  /// When each finished segment ended, in order.
  final List<DateTime> segmentEnds;

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'planName': planName,
        'segments': [for (final s in segments) s.toJson()],
        'startedAt': startedAt.millisecondsSinceEpoch,
        'segmentEnds': [for (final end in segmentEnds) end.millisecondsSinceEpoch],
      };

  bool get isFinished => segmentEnds.length >= segments.length;

  int get currentIndex => segmentEnds.length;
  LessonSegment get current => segments[currentIndex];
  LessonSegment? get next => currentIndex + 1 < segments.length ? segments[currentIndex + 1] : null;
  LessonSegment? get previous => currentIndex > 0 ? segments[currentIndex - 1] : null;

  DateTime get currentStart => segmentEnds.isEmpty ? startedAt : segmentEnds.last;

  /// When the current segment's planned time runs out.
  DateTime get currentDueAt => currentStart.add(current.planned);

  /// Time left in the current segment. Negative once it has run over.
  Duration remaining(DateTime now) => currentDueAt.difference(now);

  /// How long a finished segment actually took.
  Duration actual(int index) =>
      segmentEnds[index].difference(index == 0 ? startedAt : segmentEnds[index - 1]);

  /// How far the class is from its plan: positive is behind, negative is ahead.
  ///
  /// The segment in progress only counts once it has run over. Until then it may still finish on
  /// time, so it doesn't make the class look ahead.
  Duration drift(DateTime now) {
    var total = Duration.zero;
    for (var i = 0; i < segmentEnds.length; i++) {
      total += actual(i) - segments[i].planned;
    }
    if (!isFinished) {
      final left = remaining(now);
      if (left.isNegative) total -= left;
    }
    return total;
  }

  Duration get totalPlanned => segments.fold(Duration.zero, (sum, segment) => sum + segment.planned);

  /// Time from the start to the end of the last finished segment.
  Duration get totalActual =>
      segmentEnds.isEmpty ? Duration.zero : segmentEnds.last.difference(startedAt);

  /// Ends the current segment and moves on to the next.
  ClassRun advanced(DateTime now) => _withEnds([
        ...segmentEnds,
        // Guards against the phone's clock being set back during class.
        now.isBefore(currentStart) ? currentStart : now,
      ]);

  /// Goes back to the previous segment, as if it had never ended.
  ClassRun undone() => _withEnds(segmentEnds.sublist(0, segmentEnds.length - 1));

  ClassRun _withEnds(List<DateTime> ends) => ClassRun(
        planId: planId,
        planName: planName,
        segments: segments,
        startedAt: startedAt,
        segmentEnds: ends,
      );

  /// Identifies each segment across runs of a plan: by title, ignoring case, numbered so that a
  /// plan with two "Activity" segments keeps them apart.
  List<String> get segmentKeys {
    final seen = <String, int>{};
    return [
      for (final segment in segments)
        () {
          final title = segment.title.trim().toLowerCase();
          final occurrence = seen[title] = (seen[title] ?? 0) + 1;
          return '$title#$occurrence';
        }(),
    ];
  }
}

/// A segment that keeps running over (or finishing early), with a better time for it.
class PlanSuggestion {
  const PlanSuggestion({
    required this.planId,
    required this.index,
    required this.title,
    required this.currentMinutes,
    required this.suggestedMinutes,
    required this.classes,
  });

  final String planId;

  /// Which segment of the plan, by position.
  final int index;
  final String title;
  final int currentMinutes;
  final int suggestedMinutes;

  /// How many recent classes this is based on.
  final int classes;

  bool get isOver => suggestedMinutes > currentMinutes;
  int get differenceMinutes => (suggestedMinutes - currentMinutes).abs();

  /// Identifies this exact suggestion, so dismissing it doesn't hide a different one later.
  String get key => '$planId:$index:$suggestedMinutes';

  /// "Concept ran about 4 min over in your last 3 classes."
  String get message => (isOver
          ? '{title} ran about {n} min over in your last {classes} classes.'
          : '{title} finished about {n} min early in your last {classes} classes.')
      .trf({'title': title, 'n': differenceMinutes, 'classes': classes});
}

/// Classes needed before a segment's timing is trusted enough to suggest a change.
const _suggestAfterClasses = 3;

/// How far off each of those classes must be, so one slow week doesn't count.
const _suggestMinimumMiss = Duration(seconds: 90);

/// Looks at the most recent classes taught from [plan] and suggests new times for segments that
/// consistently ran over or under by a couple of minutes or more.
List<PlanSuggestion> suggestionsFor(LessonPlan plan, List<ClassRun> history) {
  final runs = [
    for (final run in history)
      if (run.planId == plan.id && run.isFinished) run,
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  if (runs.length < _suggestAfterClasses) return const [];

  final keys = ClassRun.start(plan, DateTime(2000)).segmentKeys;
  final suggestions = <PlanSuggestion>[];
  for (var i = 0; i < plan.segments.length; i++) {
    final planned = plan.segments[i].planned;
    // The newest few classes that had this segment.
    final actuals = <Duration>[];
    for (final run in runs) {
      final index = run.segmentKeys.indexOf(keys[i]);
      if (index >= 0) actuals.add(run.actual(index));
      if (actuals.length == _suggestAfterClasses) break;
    }
    if (actuals.length < _suggestAfterClasses) continue;

    final allOver = actuals.every((a) => a - planned >= _suggestMinimumMiss);
    final allUnder = actuals.every((a) => planned - a >= _suggestMinimumMiss);
    if (!allOver && !allUnder) continue;

    final sorted = [...actuals]..sort();
    final median = sorted[sorted.length ~/ 2];
    final suggested = ((median.inSeconds + 30) ~/ 60).clamp(1, 120);
    if ((suggested - plan.segments[i].minutes).abs() < 2) continue;

    suggestions.add(PlanSuggestion(
      planId: plan.id,
      index: i,
      title: plan.segments[i].title,
      currentMinutes: plan.segments[i].minutes,
      suggestedMinutes: suggested,
      classes: actuals.length,
    ));
  }
  return suggestions;
}

/// Rounds to whole minutes, but never down to zero: this is only used for 30 seconds or more.
int _roundedMinutes(Duration d) => (d.inSeconds.abs() + 30) ~/ 60;

/// Differences under this count as being on time.
const _onTimeMargin = Duration(seconds: 30);

/// Close enough to the plan to count as on time.
bool isOnTime(Duration drift) => drift.abs() < _onTimeMargin;

/// Whole minutes off the plan, for "3 min behind" and the like.
int minutesOff(Duration drift) => _roundedMinutes(drift);

/// "On schedule", "3 min behind", "2 min ahead".
String describeDrift(Duration drift) {
  if (isOnTime(drift)) return 'On schedule'.tr;
  return (drift.isNegative ? '{n} min ahead' : '{n} min behind').trf({'n': _roundedMinutes(drift)});
}

/// "Finished on time", "Ran 4 min over", "Finished 2 min early".
String describeFinish(Duration drift) {
  if (isOnTime(drift)) return 'Finished on time'.tr;
  return (drift.isNegative ? 'Finished {n} min early' : 'Ran {n} min over').trf({'n': _roundedMinutes(drift)});
}

/// Saves plans and class timings on this phone. Nothing here leaves the device.
class LessonStore {
  static const _plansKey = 'lesson_plans';
  static const _activeRunKey = 'class_active_run';
  static const _historyKey = 'class_history';
  static const _dismissedKey = 'dismissed_plan_suggestions';

  /// Suggestions the lecturer said no to, by [PlanSuggestion.key].
  static Future<Set<String>> dismissedSuggestions() async =>
      ((await SharedPreferences.getInstance()).getStringList(_dismissedKey) ?? const []).toSet();

  static Future<void> dismissSuggestion(PlanSuggestion suggestion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, [...?prefs.getStringList(_dismissedKey), suggestion.key]);
  }

  /// Changes one segment's time to the suggested one.
  static Future<void> applySuggestion(LessonPlan plan, PlanSuggestion suggestion) => savePlan(LessonPlan(
        id: plan.id,
        name: plan.name,
        segments: [
          for (var i = 0; i < plan.segments.length; i++)
            i == suggestion.index
                ? LessonSegment(title: plan.segments[i].title, minutes: suggestion.suggestedMinutes)
                : plan.segments[i],
        ],
      ));

  static Future<List<LessonPlan>> plans() async {
    final raw = (await SharedPreferences.getInstance()).getString(_plansKey);
    if (raw == null) return [];
    return [for (final p in jsonDecode(raw) as List) LessonPlan.fromJson(p as Map<String, dynamic>)];
  }

  /// Adds [plan], or replaces the plan with the same id.
  static Future<void> savePlan(LessonPlan plan) async {
    final all = await plans();
    final index = all.indexWhere((p) => p.id == plan.id);
    if (index < 0) {
      all.add(plan);
    } else {
      all[index] = plan;
    }
    await _writePlans(all);
  }

  /// Removes a plan. Past classes taught from it stay in the history.
  static Future<void> deletePlan(String id) async =>
      _writePlans((await plans()).where((p) => p.id != id).toList());

  static Future<void> _writePlans(List<LessonPlan> all) async =>
      (await SharedPreferences.getInstance()).setString(_plansKey, jsonEncode(all));

  /// The class in progress, if any.
  static Future<ClassRun?> activeRun() async {
    final raw = (await SharedPreferences.getInstance()).getString(_activeRunKey);
    return raw == null ? null : ClassRun.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> saveActiveRun(ClassRun run) async =>
      (await SharedPreferences.getInstance()).setString(_activeRunKey, jsonEncode(run));

  /// Drops the class in progress without keeping its timing.
  static Future<void> cancelActiveRun() async =>
      (await SharedPreferences.getInstance()).remove(_activeRunKey);

  /// Moves a finished class from "in progress" into the history.
  static Future<void> finishRun(ClassRun run) async {
    await _writeHistory([run, ...await history()]);
    await cancelActiveRun();
  }

  /// Finished classes, newest first.
  static Future<List<ClassRun>> history() async {
    final raw = (await SharedPreferences.getInstance()).getString(_historyKey);
    if (raw == null) return [];
    return [for (final r in jsonDecode(raw) as List) ClassRun.fromJson(r as Map<String, dynamic>)];
  }

  static Future<void> deleteFromHistory(ClassRun run) async => _writeHistory(
      (await history()).where((r) => r.startedAt != run.startedAt).toList());

  static Future<void> _writeHistory(List<ClassRun> runs) async =>
      (await SharedPreferences.getInstance()).setString(_historyKey, jsonEncode(runs));
}
