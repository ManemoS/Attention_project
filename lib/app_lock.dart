import 'package:flutter/services.dart';

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
  }) =>
      _channel.invokeMethod<void>('startSession', {
        'packages': packages,
        'lockMinutes': lockMinutes,
        'unlockMinutes': unlockMinutes,
        'startLocked': startLocked,
        'repeat': repeat,
        'record': record,
        'code': code,
      });

  /// Ends the session. Returns false if [code] is wrong.
  static Future<bool> stop(String code) async =>
      await _channel.invokeMethod<bool>('stopSession', {'code': code}) ?? false;
}

/// "45 min", "2 h", "1 h 30 min".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
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
