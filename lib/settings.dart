import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who is using the app. Lecturers get the Class timer on top of what students get.
enum UserRole {
  student('Student', 'Lock distracting apps during class and keep your lecture notes.', Icons.school_rounded),
  lecturer('Lecturer', 'Everything students get, plus a class timer that runs your lesson plan.',
      Icons.co_present_rounded);

  const UserRole(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// The app's own preferences, saved on this phone. Screens rebuild when they change.
class AppSettings extends ChangeNotifier {
  AppSettings._();

  static final instance = AppSettings._();

  static const _roleKey = 'user_role';
  static const _themeKey = 'theme_mode';
  static const _buzzKey = 'buzz_before_end';
  static const _speechKey = 'speech_model';
  static const _notesModelKey = 'notes_model';
  static const _notesEngineKey = 'notes_engine';
  static const _languageKey = 'app_language';

  /// 'system', 'en' or 'th'. LockActivity.kt and the notifications read this too.
  String language = 'system';

  /// Whether the app shows Thai: chosen in Settings, or the phone's language when set to system.
  bool get isThai =>
      language == 'th' || (language == 'system' && PlatformDispatcher.instance.locale.languageCode == 'th');

  /// The locale MaterialApp uses, for Thai dates and the built-in Material wording.
  Locale get locale => isThai ? const Locale('th') : const Locale('en');

  Future<void> setLanguage(String value) async {
    await _setString(_languageKey, value, () => language = value);
    // The home-screen widget is drawn natively, so tell it to redraw in the new language.
    try {
      await const MethodChannel('attention_project/app_lock').invokeMethod<void>('refreshWidget');
    } on MissingPluginException {
      // Not on Android (tests).
    }
  }

  /// Which Whisper model turns recordings into text (see transcriber.dart): 'fast' or 'accurate'.
  String speechModel = 'fast';

  /// Which on-phone model writes notes (see notes_ai.dart): 'standard' or 'light'.
  String notesModel = 'standard';

  /// Where notes are written: 'phone' (offline, private) or 'claude' (online, needs an API key).
  String notesEngine = 'phone';

  Future<void> setSpeechModel(String value) => _setString(_speechKey, value, () => speechModel = value);
  Future<void> setNotesModel(String value) => _setString(_notesModelKey, value, () => notesModel = value);
  Future<void> setNotesEngine(String value) => _setString(_notesEngineKey, value, () => notesEngine = value);

  Future<void> _setString(String key, String value, void Function() apply) async {
    apply();
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(key, value);
  }

  /// How long before a lesson segment ends the early-warning buzz comes.
  static const buzzWarning = Duration(minutes: 2);

  /// Null until the user has answered the welcome question.
  UserRole? role;
  ThemeMode themeMode = ThemeMode.system;

  /// Lecturers: one buzz [buzzWarning] before each segment ends, as well as when it ends.
  bool buzzBeforeEnd = true;

  bool get isLecturer => role == UserRole.lecturer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    role = UserRole.values.asNameMap()[prefs.getString(_roleKey)];
    themeMode = ThemeMode.values.asNameMap()[prefs.getString(_themeKey)] ?? ThemeMode.system;
    buzzBeforeEnd = prefs.getBool(_buzzKey) ?? true;
    speechModel = prefs.getString(_speechKey) ?? 'fast';
    notesModel = prefs.getString(_notesModelKey) ?? 'standard';
    notesEngine = prefs.getString(_notesEngineKey) ?? 'phone';
    language = prefs.getString(_languageKey) ?? 'system';
    notifyListeners();
  }

  Future<void> setBuzzBeforeEnd(bool value) async {
    buzzBeforeEnd = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_buzzKey, value);
  }

  Future<void> setRole(UserRole value) async {
    role = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_roleKey, value.name);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_themeKey, value.name);
  }
}
