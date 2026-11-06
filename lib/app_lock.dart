import 'package:flutter/services.dart';

import 'l10n.dart';

/// Longest a lock or unlock period can be set to.
const int maxMinutes = 120;

class InstalledApp {
  const InstalledApp({required this.packageName, required this.name, this.icon});

  factory InstalledApp.fromMap(Map<Object?, Object?> map) => InstalledApp(
        packageName: map['package'] as String,
        name: map['name'] as String,
        icon: map['icon'] as Uint8List?,
      );

  final String packageName;
  final String name;
  final Uint8List? icon;
}

class LockStatus {
  const LockStatus({
    required this.active,
    required this.locked,
    required this.remaining,
    required this.apps,
    required this.lockMinutes,
    required this.unlockMinutes,
    required this.startLocked,
    required this.repeat,
    required this.record,
    required this.recording,
    this.strict = false,
    this.recordingStartedAt,
  });

  factory LockStatus.fromMap(Map<String, dynamic> map) => LockStatus(
        active: map['active'] as bool? ?? false,
        locked: map['locked'] as bool? ?? false,
        remaining: Duration(milliseconds: map['remainingMs'] as int? ?? 0),
        apps: (map['apps'] as List? ?? const [])
            .map((app) => InstalledApp.fromMap(app as Map<Object?, Object?>))
            .toList(),
        lockMinutes: map['lockMinutes'] as int? ?? 30,
        unlockMinutes: map['unlockMinutes'] as int? ?? 15,
        startLocked: map['startLocked'] as bool? ?? true,
        repeat: map['repeat'] as bool? ?? true,
        record: map['record'] as bool? ?? false,
        recording: map['recording'] as bool? ?? false,
        strict: map['strict'] as bool? ?? false,
        recordingStartedAt: (map['recordingStartedAt'] as int? ?? 0) > 0
            ? DateTime.fromMillisecondsSinceEpoch(map['recordingStartedAt'] as int)
            : null,
      );

  final bool active;
  final bool locked;

  /// Time left in the current phase.
  final Duration remaining;

  /// The apps chosen for the current (or most recent) session.
  final List<InstalledApp> apps;
  final int lockMinutes;
  final int unlockMinutes;
  final bool startLocked;
  final bool repeat;

  /// Whether the session was set to record the lecture.
  final bool record;

  /// Whether the microphone is listening right now.
  final bool recording;

  /// Whether Settings and uninstalling are blocked too while locked.
  final bool strict;

  /// When the recording in progress started, if one is.
  final DateTime? recordingStartedAt;

  /// True when the current phase is the last one before a non-repeating session ends.
  bool get isFinalPhase => !repeat && locked != startLocked;
}

/// Talks to the Android side (see MainActivity.kt).
class AppLock {
  static const _channel = MethodChannel('attention_project/app_lock');

  static Future<List<InstalledApp>> installedApps() async {
    final apps = await _channel.invokeListMethod<Map<Object?, Object?>>('getInstalledApps');
    return (apps ?? const []).map(InstalledApp.fromMap).toList();
  }

  static Future<bool> isAccessibilityEnabled() async =>
      await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod<void>('openAccessibilitySettings');

  /// Asks for the microphone permission if needed. Returns true once it is granted.
  static Future<bool> requestMicPermission() async =>
      await _channel.invokeMethod<bool>('requestMicPermission') ?? false;

  /// Folder holding one transcript per recorded session (see LectureRecorderService.kt).
  static Future<String> lecturesDir() async => (await _channel.invokeMethod<String>('getLecturesDir'))!;

  static Future<LockStatus> status() async =>
      LockStatus.fromMap(await _channel.invokeMapMethod<String, dynamic>('getState') ?? const {});

  static Future<void> start({
    required List<String> packages,
    required int lockMinutes,
    required int unlockMinutes,
    required bool startLocked,
    required bool repeat,
    required bool record,
    required String code,
    bool strict = false,
  }) =>
      _channel.invokeMethod<void>('startSession', {
        'packages': packages,
        'lockMinutes': lockMinutes,
        'unlockMinutes': unlockMinutes,
        'startLocked': startLocked,
        'repeat': repeat,
        'record': record,
        'code': code,
        'strict': strict,
      });

  /// Finished sessions and blocked opens, for the Focus stats (see focus_stats.dart).
  static Future<Map<String, dynamic>> focusHistory() async =>
      await _channel.invokeMapMethod<String, dynamic>('getFocusHistory') ?? const {};

  /// Ends the session. Returns false if [code] is wrong.
  static Future<bool> stop(String code) async =>
      await _channel.invokeMethod<bool>('stopSession', {'code': code}) ?? false;

  /// Shows the current lesson segment in a notification and buzzes at [dueAt] (see
  /// ClassTimerService.kt). Starts the service if needed; call again when the segment changes.
  ///
  /// With [warnBefore], it also buzzes once that long before [dueAt].
  static Future<void> updateClassTimer({
    required String title,
    required String detail,
    required DateTime dueAt,
    Duration warnBefore = Duration.zero,
  }) =>
      _channel.invokeMethod<void>('updateClassTimer', {
        'title': title,
        'detail': detail,
        'dueAtMillis': dueAt.millisecondsSinceEpoch,
        'warnBeforeMillis': warnBefore.inMilliseconds,
      });

  static Future<void> stopClassTimer() => _channel.invokeMethod<void>('stopClassTimer');

  /// Bookmarks this moment of the lecture being recorded. Returns false if nothing is recording.
  static Future<bool> markMoment() async => await _channel.invokeMethod<bool>('markMoment') ?? false;

  /// Opens a recording for playback and returns its length.
  static Future<Duration> playerLoad(String path) async =>
      Duration(milliseconds: await _channel.invokeMethod<int>('playerLoad', {'path': path}) ?? 0);

  static Future<void> playerPlay() => _channel.invokeMethod<void>('playerPlay');
  static Future<void> playerPause() => _channel.invokeMethod<void>('playerPause');

  static Future<void> playerSeek(Duration position) =>
      _channel.invokeMethod<void>('playerSeek', {'ms': position.inMilliseconds});

  static Future<({Duration position, bool playing})> playerState() async {
    final state = await _channel.invokeMapMethod<String, dynamic>('playerState') ?? const {};
    return (
      position: Duration(milliseconds: state['position'] as int? ?? 0),
      playing: state['playing'] as bool? ?? false,
    );
  }

  static Future<void> playerRelease() => _channel.invokeMethod<void>('playerRelease');

  /// Starts recording a spoken question. Returns false if the microphone is busy.
  static Future<bool> startQuestion() async => await _channel.invokeMethod<bool>('startQuestion') ?? false;

  /// Stops the question recording and returns its file, or null if nothing was recorded.
  static Future<String?> stopQuestion() => _channel.invokeMethod<String>('stopQuestion');

  /// Reads [text] aloud with the phone's text-to-speech.
  static Future<void> speak(String text) => _channel.invokeMethod<void>('speak', {'text': text});
  static Future<void> stopSpeaking() => _channel.invokeMethod<void>('stopSpeaking');

  /// Keeps the screen awake while this app is on screen.
  static Future<void> setKeepScreenOn(bool on) =>
      _channel.invokeMethod<void>('setKeepScreenOn', {'on': on});
}

/// "45 min", "2 h", "1 h 30 min".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '{n} min'.trf({'n': m});
  if (m == 0) return '{n} h'.trf({'n': h});
  return '{h} h {m} min'.trf({'h': h, 'm': m});
}

/// "4:05" or "1:04:05", rounding up so it never shows 0:00 early.
String formatCountdown(Duration d) {
  final totalSeconds = (d.inMilliseconds + 999) ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
