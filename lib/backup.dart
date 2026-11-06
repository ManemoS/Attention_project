import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lectures.dart';
import 'settings.dart';
import 'timetable.dart';
import 'l10n.dart';

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Saves everything to one file the user keeps (Drive, Downloads…), and brings it back on a new
/// phone. The zip itself is made and read by Backup.kt.
class AppBackup {
  static const _channel = MethodChannel('attention_project/app_lock');

  /// Never written into a backup file.
  static const _secretKeys = {'claude_api_key'};

  /// Left out of backups: secrets, and the AI plugin's own records of which model files are on
  /// this phone, which would be wrong on another phone.
  static bool _skip(String key) => _secretKeys.contains(key) || key.startsWith('model_');

  /// Every app setting as typed JSON, leaving out secrets.
  static Future<String> settingsJson() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, Object>{};
    for (final key in prefs.getKeys()) {
      if (_skip(key)) continue;
      final value = prefs.get(key);
      final type = switch (value) {
        bool() => 'bool',
        int() => 'int',
        double() => 'double',
        String() => 'string',
        List() => 'list',
        _ => null,
      };
      if (type != null && value != null) out[key] = {'type': type, 'value': value};
    }
    return jsonEncode(out);
  }

  /// Writes settings from [json] (made by [settingsJson]) into this phone's settings.
  static Future<void> applySettings(String json) async {
    final prefs = await SharedPreferences.getInstance();
    final map = jsonDecode(json) as Map<String, dynamic>;
    for (final MapEntry(:key, :value) in map.entries) {
      if (_skip(key)) continue;
      final typed = value as Map<String, dynamic>;
      final v = typed['value'];
      switch (typed['type']) {
        case 'bool':
          await prefs.setBool(key, v as bool);
        case 'int':
          await prefs.setInt(key, (v as num).toInt());
        case 'double':
          await prefs.setDouble(key, (v as num).toDouble());
        case 'string':
          await prefs.setString(key, v as String);
        case 'list':
          await prefs.setStringList(key, [for (final s in v as List) s as String]);
      }
    }
  }

  /// Asks where to save, then saves. Returns false if the user cancelled.
  static Future<bool> save({required bool includeAudio}) async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    try {
      return await _channel.invokeMethod<bool>('createBackup', {
            'settings': await settingsJson(),
            'includeAudio': includeAudio,
            'fileName': 'APLS backup ${now.year}-${two(now.month)}-${two(now.day)}.zip',
          }) ??
          false;
    } on PlatformException catch (e) {
      throw BackupException("Couldn't save the backup: {error}".trf({'error': e.message}));
    }
  }

  /// Asks for a backup file and restores it. Returns false if the user cancelled.
  ///
  /// The timetable comes back switched off, because its code isn't in the backup.
  static Future<bool> restore() async {
    final String? settings;
    try {
      settings = await _channel.invokeMethod<String>('restoreBackup');
    } on PlatformException catch (e) {
      throw BackupException(e.message ?? 'Couldn\'t restore that file.'.tr);
    }
    if (settings == null) return false;
    await applySettings(settings);
    await AppSettings.instance.load();
    LectureLibrary.forget();
    final entries = await TimetableStore.entries();
    if (entries.isNotEmpty) {
      await TimetableStore.save(entries: entries, enabled: false, packages: const [], strict: false);
    }
    return true;
  }
}
