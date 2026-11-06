import 'package:flutter/foundation.dart';

import 'app_lock.dart';
import 'downloads.dart';
import 'notes_ai.dart';
import 'settings.dart';
import 'transcriber.dart';

/// Which AI models are on the phone, and downloads in progress. Downloads keep going when the
/// user leaves the Settings page, so their progress lives here rather than in the page.
class ModelStore extends ChangeNotifier {
  ModelStore._();

  static final instance = ModelStore._();

  final Map<String, bool> _installed = {};
  final Map<String, double> _progress = {};
  final Map<String, String> _errors = {};
  final Set<String> _cancelled = {};

  static String speechKey(SpeechModel m) => 'speech:${m.name}';
  static String notesKey(NotesModel m) => 'notes:${m.name}';

  bool isInstalled(String key) => _installed[key] ?? false;

  /// 0 to 1 while downloading, otherwise null.
  double? progress(String key) => _progress[key];
  String? error(String key) => _errors[key];

  /// The models chosen in Settings.
  static SpeechModel get speech => SpeechModel.values.byName(AppSettings.instance.speechModel);
  static NotesModel get notes => NotesModel.values.byName(AppSettings.instance.notesModel);

  Future<void> refresh() async {
    for (final m in SpeechModel.values) {
      _installed[speechKey(m)] = await Transcriber.isInstalled(m);
    }
    for (final m in NotesModel.values) {
      _installed[notesKey(m)] = await NotesAi.isInstalled(m);
    }
    notifyListeners();
  }

  Future<void> downloadSpeech(SpeechModel m) => _download(
        speechKey(m),
        (onProgress, isCancelled) => Transcriber.install(m, onProgress: onProgress, isCancelled: isCancelled),
      );

  Future<void> downloadNotes(NotesModel m) =>
      _download(notesKey(m), (onProgress, _) => NotesAi.install(m, onProgress: onProgress));

  void cancel(String key) => _cancelled.add(key);

  Future<void> deleteSpeech(SpeechModel m) async {
    await Transcriber.uninstall(m);
    await refresh();
  }

  Future<void> deleteNotes(NotesModel m) async {
    await NotesAi.uninstall(m);
    await refresh();
  }

  Future<void> _download(
    String key,
    Future<void> Function(void Function(double) onProgress, bool Function() isCancelled) run,
  ) async {
    if (_progress.containsKey(key)) return;
    _cancelled.remove(key);
    _errors.remove(key);
    _progress[key] = 0;
    notifyListeners();
    // The download stops if the phone sleeps, so keep the screen on while one runs.
    await AppLock.setKeepScreenOn(true);
    try {
      await run((p) {
        _progress[key] = p;
        notifyListeners();
      }, () => _cancelled.contains(key));
    } on DownloadCancelled {
      // Kept as a partial file; downloading again carries on from there.
    } on Object catch (e) {
      _errors[key] = '$e';
    } finally {
      _progress.remove(key);
      if (_progress.isEmpty) await AppLock.setKeepScreenOn(false);
      await refresh();
    }
  }
}
