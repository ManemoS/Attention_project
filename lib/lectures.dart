import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock.dart';

/// One recorded lock session: its transcript, and a summary once Claude has written one.
class Lecture {
  Lecture(this.transcriptFile)
      : startedAt = DateTime.fromMillisecondsSinceEpoch(
            int.tryParse(transcriptFile.uri.pathSegments.last.split('.').first) ?? 0);

  final File transcriptFile;
  final DateTime startedAt;

  File get summaryFile => File(transcriptFile.path.replaceFirst(RegExp(r'\.txt$'), '.summary.txt'));

  Future<String> readTranscript() => transcriptFile.readAsString();

  Future<String?> readSummary() async =>
      await summaryFile.exists() ? await summaryFile.readAsString() : null;

  Future<void> saveSummary(String summary) => summaryFile.writeAsString(summary);

  Future<void> delete() async {
    await transcriptFile.delete();
    if (await summaryFile.exists()) await summaryFile.delete();
  }
}

/// All recorded lectures, newest first.
Future<List<Lecture>> loadLectures() async {
  final dir = Directory(await AppLock.lecturesDir());
  final lectures = <Lecture>[
    await for (final entity in dir.list())
      if (entity is File && entity.path.endsWith('.txt') && !entity.path.endsWith('.summary.txt'))
        Lecture(entity),
  ];
  lectures.sort((a, b) => b.startedAt.compareTo(a.startedAt));
  return lectures;
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
    if (key == null) throw const SummaryException('Add your Claude API key first.');

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
      throw const SummaryException('No internet connection. Connect and try again.');
    } on TimeoutException {
      throw const SummaryException('Claude took too long to answer. Try again.');
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
        401 => 'Your Claude API key is not valid. Check it in Lecture notes → API key.',
        429 => 'Too many requests. Wait a minute and try again.',
        >= 500 => 'Claude is busy right now. Try again in a minute.',
        _ => message ?? 'Claude returned an error (${response.statusCode}).',
      });
    }

    if (body['stop_reason'] == 'refusal') {
      throw const SummaryException('Claude declined to summarize this recording.');
    }

    final summary = [
      for (final block in body['content'] as List)
        if (block['type'] == 'text') block['text'] as String,
    ].join().trim();
    if (summary.isEmpty) throw const SummaryException('Claude returned an empty summary. Try again.');
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
