import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock.dart';
import 'l10n.dart';

/// A stretch of the transcript and when it was said, from Whisper.
class TranscriptSegment {
  const TranscriptSegment({required this.from, required this.to, required this.text});

  factory TranscriptSegment.fromJson(Map<String, dynamic> json) => TranscriptSegment(
        from: Duration(milliseconds: json['from'] as int),
        to: Duration(milliseconds: json['to'] as int),
        text: json['text'] as String,
      );

  final Duration from;
  final Duration to;
  final String text;

  Map<String, dynamic> toJson() => {'from': from.inMilliseconds, 'to': to.inMilliseconds, 'text': text};
}

/// What LectureRecorderService.kt writes beside each recording.
class LectureMeta {
  const LectureMeta({this.marks = const [], this.duration, this.course, this.recording = false});

  factory LectureMeta.fromJson(Map<String, dynamic> json) => LectureMeta(
        marks: [for (final m in json['marks'] as List? ?? const []) Duration(milliseconds: (m as num).toInt())],
        duration: json['durationMs'] == null ? null : Duration(milliseconds: (json['durationMs'] as num).toInt()),
        course: json['course'] as String?,
        recording: json['recording'] as bool? ?? false,
      );

  /// Moments marked important during the lecture, from the start of the recording.
  final List<Duration> marks;

  /// Null while recording, or for lectures from before audio was kept.
  final Duration? duration;

  /// The timetable course it was recorded for, if any.
  final String? course;

  /// True while the microphone is still on.
  final bool recording;
}

/// One recorded lecture. Its files share an id (the time recording started) in the lectures folder:
/// the audio, its bookmarks, and later the transcript, its timings, a summary and flashcards.
class Lecture {
  Lecture(this.dir, this.id) : startedAt = DateTime.fromMillisecondsSinceEpoch(int.tryParse(id) ?? 0);

  /// The lecture whose transcript is [transcript].
  Lecture.fromTranscript(File transcript)
      : this(transcript.parent.path, transcript.uri.pathSegments.last.split('.').first);

  final String dir;
  final String id;
  final DateTime startedAt;

  File _file(String suffix) => File('$dir/$id$suffix');

  File get audioFile => _file('.m4a');
  File get metaFile => _file('.json');
  File get transcriptFile => _file('.txt');
  File get segmentsFile => _file('.segments.json');
  File get summaryFile => _file('.summary.txt');
  File get cardsFile => _file('.cards.json');

  /// Every file that belongs to this lecture, including leftovers from an interrupted transcription.
  List<File> get _allFiles => [
        audioFile, metaFile, transcriptFile, segmentsFile, summaryFile, cardsFile,
        _file('.m4a.wav'), _file('.part.wav'), _file('.part.wav.wav'),
      ];

  /// The transcript, or '' if it hasn't been made yet.
  Future<String> readTranscript() async =>
      await transcriptFile.exists() ? await transcriptFile.readAsString() : '';

  Future<String?> readSummary() async =>
      await summaryFile.exists() ? await summaryFile.readAsString() : null;

  Future<void> saveSummary(String summary) => summaryFile.writeAsString(summary);

  Future<LectureMeta> readMeta() async {
    if (!await metaFile.exists()) return const LectureMeta();
    try {
      return LectureMeta.fromJson(jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>);
    } on FormatException {
      return const LectureMeta();
    }
  }

  /// Transcript timings, if Whisper has finished with this lecture.
  Future<List<TranscriptSegment>> readSegments() async {
    if (!await segmentsFile.exists()) return const [];
    try {
      final json = jsonDecode(await segmentsFile.readAsString()) as Map<String, dynamic>;
      if (json['complete'] != true) return const [];
      return [for (final s in json['segments'] as List) TranscriptSegment.fromJson(s as Map<String, dynamic>)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> delete() async {
    for (final file in _allFiles) {
      if (await file.exists()) await file.delete();
    }
  }
}

/// All recorded lectures, newest first.
Future<List<Lecture>> loadLectures() async {
  final dir = Directory(await AppLock.lecturesDir());
  final name = RegExp(r'^(\d+)\.(m4a|txt)$');
  final ids = <String>{
    await for (final entity in dir.list())
      if (entity is File) ?name.firstMatch(entity.uri.pathSegments.last)?.group(1),
  };
  final lectures = [for (final id in ids) Lecture(dir.path, id)];
  lectures.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return lectures;
}

int wordCount(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// What the lecture lists show about a recording, read once per refresh.
class LectureInfo {
  const LectureInfo({
    this.words = 0,
    this.summarized = false,
    this.hasAudio = false,
    this.duration,
    this.marks = 0,
    this.recording = false,
  });

  final int words;
  final bool summarized;
  final bool hasAudio;
  final Duration? duration;
  final int marks;
  final bool recording;

  bool get transcribed => words > 0;
}

/// Folders and the trash bin for recorded lectures.
///
/// Transcripts never move on disk, because the recorder keeps appending to its file while a
/// session runs. Which folder a lecture is in, and whether it's in the trash, is kept in
/// lectures/library.json instead. There is one library for the whole app, so every screen sees
/// the same state and rebuilds when it changes.
class LectureLibrary extends ChangeNotifier {
  LectureLibrary._(this._file, this.folders, this._folderOf, this._trashedAt, this._autoFiled);

  /// How long a lecture stays in the trash before it is deleted for good.
  static const trashDays = 30;
  static const maxFolderNameLength = 40;

  static Future<LectureLibrary>? _opening;

  /// The app's library, with the lecture list freshly read from disk.
  static Future<LectureLibrary> open() async {
    final library = await (_opening ??= _read());
    await library.refresh();
    return library;
  }

  /// Forgets the loaded library so the next [open] reads library.json again, as after a restart
  /// (or a restored backup).
  static void forget() => _opening = null;

  @visibleForTesting
  static void resetForTest() => forget();

  static Future<LectureLibrary> _read() async {
    final file = File('${await AppLock.lecturesDir()}/library.json');
    var folders = <String>[];
    var folderOf = <String, String>{};
    var trashedAt = <String, int>{};
    var autoFiled = <String>{};
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        folders = [for (final f in json['folders'] as List? ?? const []) f as String];
        folderOf = {
          for (final e in (json['folderOf'] as Map? ?? const {}).entries) e.key as String: e.value as String,
        };
        trashedAt = {
          for (final e in (json['trashedAt'] as Map? ?? const {}).entries) e.key as String: e.value as int,
        };
        autoFiled = {for (final id in json['autoFiled'] as List? ?? const []) id as String};
      } on FormatException {
        // A damaged library file only loses the sorting; the transcripts themselves are untouched.
      }
    }
    return LectureLibrary._(file, folders, folderOf, trashedAt, autoFiled);
  }

  final File _file;
  Future<void> _saving = Future.value();

  /// Every lecture on the phone, newest first, including those in the trash.
  List<Lecture> lectures = [];

  /// What each lecture's tile shows, by lecture id, as of the last [refresh].
  Map<String, LectureInfo> info = {};

  /// Folder names in the order they were created.
  final List<String> folders;

  final Map<String, String> _folderOf;
  final Map<String, int> _trashedAt;

  /// Lectures already filed into their timetable course's folder, so moving one out sticks.
  final Set<String> _autoFiled;

  /// The folder [lecture] is filed in, or null if it is unsorted.
  String? folderOf(Lecture lecture) => _folderOf[lecture.id];

  bool isTrashed(Lecture lecture) => _trashedAt.containsKey(lecture.id);

  /// Whole days until a trashed lecture is deleted for good (at least 1).
  int daysLeftInTrash(Lecture lecture) {
    final trashed = DateTime.fromMillisecondsSinceEpoch(_trashedAt[lecture.id]!);
    final left = trashed.add(const Duration(days: trashDays)).difference(DateTime.now()).inDays + 1;
    return left.clamp(1, trashDays);
  }

  /// Lectures in [folder] (null for unsorted), leaving out the trash.
  List<Lecture> inFolder(String? folder) =>
      [for (final l in lectures) if (!isTrashed(l) && folderOf(l) == folder) l];

  /// Lectures in the trash, most recently trashed first.
  List<Lecture> get trash => [for (final l in lectures) if (isTrashed(l)) l]
    ..sort((a, b) => _trashedAt[b.id]!.compareTo(_trashedAt[a.id]!));

  /// Re-reads the lecture files, deletes lectures that have been in the trash too long, and
  /// forgets entries for lectures or folders that no longer exist.
  Future<void> refresh() async {
    final all = await loadLectures();
    final cutoff = DateTime.now().subtract(const Duration(days: trashDays)).millisecondsSinceEpoch;
    final kept = <Lecture>[];
    for (final lecture in all) {
      final trashed = _trashedAt[lecture.id];
      if (trashed != null && trashed < cutoff) {
        await lecture.delete();
      } else {
        kept.add(lecture);
      }
    }

    lectures = kept;
    final metas = {for (final l in kept) l.id: await l.readMeta()};
    info = {
      for (final l in kept)
        l.id: LectureInfo(
          words: wordCount(await l.readTranscript()),
          summarized: await l.summaryFile.exists(),
          hasAudio: await l.audioFile.exists(),
          duration: metas[l.id]!.duration,
          marks: metas[l.id]!.marks.length,
          recording: metas[l.id]!.recording,
        ),
    };

    // Recordings started by the timetable go into their course's folder, once.
    var filed = false;
    for (final l in kept) {
      final course = metas[l.id]!.course?.trim();
      if (course == null || course.isEmpty || _autoFiled.contains(l.id)) continue;
      final existing = folders.where((f) => f.toLowerCase() == course.toLowerCase());
      final folder = existing.isEmpty ? course : existing.first;
      if (existing.isEmpty) folders.add(folder);
      _folderOf.putIfAbsent(l.id, () => folder);
      _autoFiled.add(l.id);
      filed = true;
    }

    final ids = {for (final l in kept) l.id};
    final before = (_folderOf.length, _trashedAt.length, _autoFiled.length);
    _folderOf.removeWhere((id, folder) => !ids.contains(id) || !folders.contains(folder));
    _trashedAt.removeWhere((id, _) => !ids.contains(id));
    _autoFiled.removeWhere((id) => !ids.contains(id));
    if (filed || before != (_folderOf.length, _trashedAt.length, _autoFiled.length)) await _changed();
    notifyListeners();
  }

  /// Why [name] can't be used for a new or renamed folder, or null if it can.
  String? folderNameProblem(String name, {String? renaming}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name'.tr;
    if (trimmed.length > maxFolderNameLength) return 'Use {n} characters or fewer'.trf({'n': maxFolderNameLength});
    final taken = folders.any((f) => f != renaming && f.toLowerCase() == trimmed.toLowerCase());
    return taken ? 'There is already a folder called "{name}"'.trf({'name': trimmed}) : null;
  }

  Future<void> createFolder(String name) {
    folders.add(name.trim());
    return _changed();
  }

  Future<void> renameFolder(String from, String to) {
    final name = to.trim();
    folders[folders.indexOf(from)] = name;
    _folderOf.updateAll((_, folder) => folder == from ? name : folder);
    return _changed();
  }

  /// Removes [folder]. Its lectures go back to unsorted rather than being deleted.
  Future<void> deleteFolder(String folder) {
    folders.remove(folder);
    _folderOf.removeWhere((_, f) => f == folder);
    return _changed();
  }

  /// Files [lecture] in [folder] (null for unsorted). Takes it out of the trash too.
  Future<void> moveTo(Lecture lecture, String? folder) {
    if (folder == null) {
      _folderOf.remove(lecture.id);
    } else {
      _folderOf[lecture.id] = folder;
    }
    _trashedAt.remove(lecture.id);
    return _changed();
  }

  Future<void> moveToTrash(Lecture lecture) {
    _trashedAt[lecture.id] = DateTime.now().millisecondsSinceEpoch;
    return _changed();
  }

  /// Takes [lecture] out of the trash, back into the folder it was in.
  Future<void> restore(Lecture lecture) {
    _trashedAt.remove(lecture.id);
    return _changed();
  }

  Future<void> deleteForever(Lecture lecture) async {
    _forget(lecture);
    await _changed();
    await lecture.delete();
  }

  Future<void> emptyTrash() async {
    final doomed = trash;
    doomed.forEach(_forget);
    await _changed();
    for (final lecture in doomed) {
      await lecture.delete();
    }
  }

  void _forget(Lecture lecture) {
    lectures.remove(lecture);
    info.remove(lecture.id);
    _folderOf.remove(lecture.id);
    _trashedAt.remove(lecture.id);
  }

  /// Tells listeners straight away, so lists update before the file is written, then saves.
  /// Saves run one after another so an older state can never overwrite a newer one.
  Future<void> _changed() {
    notifyListeners();
    final json = jsonEncode({
      'folders': folders,
      'folderOf': _folderOf,
      'trashedAt': _trashedAt,
      'autoFiled': _autoFiled.toList(),
    });
    return _saving = _saving.then((_) => _file.writeAsString(json));
  }
}

class SummaryException implements Exception {
  const SummaryException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Summarizes transcripts with the Claude API.
class Claude {
  static const _apiKeyPref = 'claude_api_key';
  static const _model = 'claude-opus-5-5';

  static Future<String?> apiKey() async {
    final key = (await SharedPreferences.getInstance()).getString(_apiKeyPref);
    return key == null || key.isEmpty ? null : key;
  }

  static Future<void> setApiKey(String key) async =>
      (await SharedPreferences.getInstance()).setString(_apiKeyPref, key.trim());

  /// Turns a lecture transcript into study notes. Throws [SummaryException] with a message
  /// that can be shown to the user.
  static Future<String> summarize(String transcript) async {
    final key = await apiKey();
    if (key == null) throw SummaryException('Add your Claude API key first.'.tr);

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              // If Claude's safety check wrongly declines, retry on another model instead of failing.
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': _model,
              'max_tokens': 16000,
              'output_config': {'effort': 'medium'},
              'fallbacks': 'default',
              'system': 'You turn lecture transcripts into study notes for a university student '
                  'who wants to know what the professor said.',
              'messages': [
                {'role': 'user', 'content': _prompt(transcript)},
              ],
            }),
          )
          .timeout(const Duration(minutes: 5));
    } on SocketException {
      throw SummaryException('No internet connection. Connect and try again.'.tr);
    } on TimeoutException {
      throw SummaryException('Claude took too long to answer. Try again.'.tr);
    }

    // Decode as UTF-8 explicitly so non-English lectures come through intact.
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } on FormatException {
      throw SummaryException('Claude returned an error (${response.statusCode}). Try again.');
    }

    if (response.statusCode != 200) {
      final message = (body['error'] as Map<String, dynamic>?)?['message'] as String?;
      throw SummaryException(switch (response.statusCode) {
        401 => 'Your Claude API key is not valid. Check it in Lecture notes → API key.'.tr,
        429 => 'Too many requests. Wait a minute and try again.'.tr,
        >= 500 => 'Claude is busy right now. Try again in a minute.'.tr,
        _ => message ?? 'Claude returned an error (${response.statusCode}).',
      });
    }

    if (body['stop_reason'] == 'refusal') {
      throw SummaryException('Claude declined to summarize this recording.'.tr);
    }

    final summary = [
      for (final block in body['content'] as List)
        if (block['type'] == 'text') block['text'] as String,
    ].join().trim();
    if (summary.isEmpty) throw SummaryException('Claude returned an empty summary. Try again.'.tr);
    return summary;
  }

  static String _prompt(String transcript) => '''
Below is a transcript of a lecture, written down automatically by a phone's speech recognition from somewhere in the lecture room. Expect recognition mistakes, missing words, no punctuation, and occasional speech from other people in the room. Work out what the professor most likely meant, and leave out anything that clearly isn't part of the lecture.

<transcript>
$transcript
</transcript>

Write study notes in the same language the lecture was given in, with these parts:
- Topic: one or two sentences on what the lecture was about.
- Key points: the main ideas, in the order they were taught, each explained in a sentence or two.
- Terms and definitions: important terms the professor introduced.
- Announcements: anything about exams, homework, deadlines or what to prepare.
- Unclear parts: places where the recording was too garbled to follow, so the student knows to check them.

Use plain text that reads well on a phone: put each part's name on its own line and use "- " for bullets. Don't use Markdown symbols such as # or **. Leave out a part if there's nothing for it. If the transcript is too short or garbled to summarize, say so in a sentence instead.''';
}
