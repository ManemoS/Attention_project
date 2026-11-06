import 'dart:convert';
import 'dart:math';

import 'package:flutter_gemma/flutter_gemma.dart';

import 'lectures.dart';
import 'l10n.dart';

/// The small language models the app can run on the phone. Both are open (no account needed).
enum NotesModel {
  standard(
    'Standard',
    'https://huggingface.co/litert-community/Qwen2.5-1.5B-Instruct/resolve/main/'
        'Qwen2.5-1.5B-Instruct_multi-prefill-seq_q8_ekv4096.task',
    1525,
    4096,
    'Better notes and answers. Needs a phone with 6 GB of memory or more.',
  ),
  light(
    'Light',
    'https://huggingface.co/litert-community/Qwen2.5-0.5B-Instruct/resolve/main/'
        'Qwen2.5-0.5B-Instruct_multi-prefill-seq_q8_ekv1280.task',
    521,
    1280,
    'Smaller and quicker, for older phones. Notes are simpler.',
  );

  const NotesModel(this.label, this.url, this.megabytes, this.contextTokens, this.description);

  final String label;
  final String url;
  final int megabytes;

  /// How much text the model can take in at once, prompt and answer together.
  final int contextTokens;
  final String description;

  String get fileName => Uri.parse(url).pathSegments.last;

  /// Words of transcript per request, leaving room for instructions and the answer.
  int get chunkWords => contextTokens >= 4096 ? 1400 : 380;
}

class NotesAiException implements Exception {
  const NotesAiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One flashcard: a question and its answer.
class Flashcard {
  const Flashcard(this.question, this.answer);

  factory Flashcard.fromJson(Map<String, dynamic> json) =>
      Flashcard(json['q'] as String, json['a'] as String);

  final String question;
  final String answer;

  Map<String, dynamic> toJson() => {'q': question, 'a': answer};
}

/// A passage of a lecture that may answer a question.
class NotesPassage {
  const NotesPassage(this.lecture, this.text);
  final Lecture lecture;
  final String text;
}

/// Summaries, flashcards and answers written by a language model running on the phone, so lecture
/// recordings never leave it.
///
/// Small on-device models only take in a few pages at a time, so a long lecture is summarized in
/// pieces and the pieces are then combined.
class NotesAi {
  static bool _initialized = false;

  static Future<void> _init() async {
    if (_initialized) return;
    await FlutterGemma.initialize();
    _initialized = true;
  }

  static Future<bool> isInstalled(NotesModel model) async {
    await _init();
    return FlutterGemma.isModelInstalled(model.fileName);
  }

  /// Downloads [model] once, then marks it as the one to use. [onProgress] gets 0 to 1.
  static Future<void> install(NotesModel model, {void Function(double)? onProgress}) async {
    await _init();
    try {
      await FlutterGemma.installModel(modelType: ModelType.qwen)
          .fromNetwork(model.url, foreground: true)
          .withProgress((percent) => onProgress?.call(percent / 100))
          .install();
    } on Object catch (e) {
      throw NotesAiException('The download failed: {error}'.trf({'error': e}));
    }
  }

  static Future<void> uninstall(NotesModel model) async {
    await _init();
    if (await FlutterGemma.isModelInstalled(model.fileName)) await FlutterGemma.uninstallModel(model.fileName);
    _loaded?.close();
    _loaded = null;
  }

  static InferenceModel? _loaded;
  static NotesModel? _loadedModel;

  /// The model, loaded into memory once and kept while the app runs.
  static Future<InferenceModel> _model(NotesModel model) async {
    if (_loaded != null && _loadedModel == model) return _loaded!;
    if (!await isInstalled(model)) throw NotesAiException('Download the notes AI in Settings first.'.tr);
    await _loaded?.close();
    // Installing an installed model only makes it the active one; nothing is downloaded.
    await FlutterGemma.installModel(modelType: ModelType.qwen).fromNetwork(model.url).install();
    try {
      _loaded = await FlutterGemma.getActiveModel(maxTokens: model.contextTokens, preferredBackend: PreferredBackend.cpu);
    } on Object catch (e) {
      throw NotesAiException("The notes AI couldn't start on this phone ({error}). Try the Compact model.".trf({'error': e}));
    }
    _loadedModel = model;
    return _loaded!;
  }

  /// Runs one prompt in a fresh session, streaming the answer through [onText] as it's written.
  static Future<String> _ask(NotesModel model, String prompt, {void Function(String soFar)? onText}) async {
    final session = await (await _model(model)).createSession(temperature: 0.3, topK: 40, randomSeed: 7);
    final out = StringBuffer();
    try {
      await session.addQueryChunk(Message.text(text: prompt, isUser: true));
      // The streaming call in this plugin version drops the start of the reply, so wait for all of it.
      out.write(await session.getResponse());
      onText?.call(out.toString());
    } finally {
      await session.close();
    }
    return out.toString().trim();
  }

  /// Splits a transcript into pieces of about [words] words, on sentence ends where possible.
  static List<String> chunks(String text, int words) {
    final all = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = <String>[];
    var start = 0;
    while (start < all.length) {
      var end = min(start + words, all.length);
      // Look back a little for a sentence end, so pieces don't stop mid-sentence.
      for (var i = end; i > start + words * 0.8 && i < all.length; i--) {
        if (RegExp(r'[.?!]$').hasMatch(all[i - 1])) {
          end = i;
          break;
        }
      }
      out.add(all.sublist(start, end).join(' '));
      start = end;
    }
    return out;
  }

  /// Study notes for a lecture. [onProgress] gets 0 to 1 and the latest text written.
  static Future<String> summarize(
    NotesModel model,
    String transcript, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final pieces = chunks(transcript, model.chunkWords);
    if (pieces.isEmpty) throw NotesAiException('There is nothing in this transcript to summarize.'.tr);

    final notes = <String>[];
    for (var i = 0; i < pieces.length; i++) {
      onProgress?.call(i / (pieces.length + 1), 'Reading part {n} of {total}…'.trf({'n': i + 1, 'total': pieces.length}));
      notes.add(await _ask(model, _piecePrompt(pieces[i], i + 1, pieces.length)));
    }
    if (notes.length == 1) {
      onProgress?.call(1, 'Done'.tr);
      return _clean(notes.single);
    }

    onProgress?.call(pieces.length / (pieces.length + 1), 'Putting the notes together…'.tr);
    // Combining all the parts must fit in the model too; keep each part's notes short enough.
    final budget = (model.chunkWords * 1.1 / notes.length).floor();
    final combined = [
      for (var i = 0; i < notes.length; i++) 'Part ${i + 1}:\n${_firstWords(notes[i], max(40, budget))}',
    ].join('\n\n');
    final result = await _ask(model, _combinePrompt(combined));
    onProgress?.call(1, 'Done'.tr);
    return _clean(result);
  }

  static String _piecePrompt(String text, int part, int parts) => '''
You are helping a university student take notes. Below is part $part of $parts of a lecture transcript made by speech recognition, so some words may be wrong.

Transcript:
$text

Write short study notes for this part only:
- The main ideas, as bullet points starting with "- ".
- Any terms the lecturer defined, as "- Term: meaning".
- Anything about exams, homework or deadlines.
Only use what is in the transcript. Be brief.''';

  static String _combinePrompt(String notes) => '''
Below are notes from each part of one lecture, in order. Combine them into one set of study notes with these headings, each on its own line:
Topic
Key points
Terms
Announcements

Under each heading use bullet points starting with "- ". Remove repeats. Leave out a heading if there is nothing for it. Only use what is in the notes.

$notes''';

  /// Five or so question-and-answer cards from a lecture's notes (or its transcript).
  static Future<List<Flashcard>> flashcards(NotesModel model, String source) async {
    final text = _firstWords(source, (model.chunkWords * 1.2).floor());
    final reply = await _ask(model, '''
Make 6 flashcards for revising this lecture. Each flashcard is a question and a short answer, taken only from the notes.

Write them exactly like this, with nothing else:
Q: question
A: answer

Notes:
$text''');
    final cards = parseFlashcards(reply);
    if (cards.isEmpty) throw NotesAiException('The AI didn\'t write any flashcards. Try again.'.tr);
    return cards;
  }

  /// Reads "Q: … A: …" pairs, ignoring anything else the model wrote around them.
  static List<Flashcard> parseFlashcards(String text) {
    final cards = <Flashcard>[];
    String? question;
    // Put each "Q:" and "A:" on its own line, in case the model ran them together.
    final lines = text.replaceAll(RegExp(r'\s+(?=(?:Q|A|Question|Answer)\s*:)', caseSensitive: false), '\n');
    for (final raw in const LineSplitter().convert(lines)) {
      final line = raw.trim().replaceFirst(RegExp(r'^(\d+[.)]|[-*])\s*'), '');
      final q = RegExp(r'^(?:Q|Question)\s*[:.]\s*(.+)$', caseSensitive: false).firstMatch(line);
      final a = RegExp(r'^(?:A|Answer)\s*[:.]\s*(.+)$', caseSensitive: false).firstMatch(line);
      if (q != null) {
        question = q.group(1)!.trim();
      } else if (a != null && question != null) {
        cards.add(Flashcard(question, a.group(1)!.trim()));
        question = null;
      }
    }
    return cards;
  }

  /// Finds the passages of [lectures] most likely to answer [question], by shared words.
  static Future<List<NotesPassage>> findPassages(List<Lecture> lectures, String question, {int take = 3}) async {
    final words = _keywords(question);
    if (words.isEmpty) return const [];
    final scored = <({NotesPassage passage, double score})>[];
    for (final lecture in lectures) {
      final transcript = await lecture.readTranscript();
      for (final piece in chunks(transcript, 160)) {
        final pieceWords = _keywords(piece);
        if (pieceWords.isEmpty) continue;
        var score = 0.0;
        for (final w in words) {
          final n = pieceWords.where((p) => p == w).length;
          if (n > 0) score += 1 + log(n);
        }
        if (score > 0) scored.add((passage: NotesPassage(lecture, piece), score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(take)) s.passage];
  }

  /// Answers [question] from [passages] only, streaming the answer through [onText].
  static Future<String> answer(
    NotesModel model,
    String question,
    List<NotesPassage> passages, {
    void Function(String soFar)? onText,
  }) {
    final budget = (model.chunkWords / max(1, passages.length)).floor();
    final context = [
      for (var i = 0; i < passages.length; i++) 'Passage ${i + 1}:\n${_firstWords(passages[i].text, budget)}',
    ].join('\n\n');
    return _ask(model, '''
Answer the student's question using only these passages from their lecture recordings. If the passages don't contain the answer, say "I couldn't find that in your lectures." Answer in two or three sentences.

$context

Question: $question''', onText: onText);
  }

  static const _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'is', 'are', 'was', 'were', 'be', 'it', 'this',
    'that', 'what', 'which', 'who', 'how', 'why', 'when', 'where', 'did', 'do', 'does', 'about', 'say', 'said',
    'professor', 'lecturer', 'lecture', 'with', 'as', 'at', 'by', 'from', 'we', 'you', 'i', 'they', 'he', 'she',
    'so', 'can', 'will', 'would', 'should', 'there', 'their', 'our', 'my', 'me', 'us', 'tell',
  };

  static List<String> _keywords(String text) => [
        for (final w in text.toLowerCase().split(RegExp(r"[^a-z0-9']+")))
          if (w.length > 2 && !_stopWords.contains(w)) w.endsWith('s') && w.length > 4 ? w.substring(0, w.length - 1) : w,
      ];

  static String _firstWords(String text, int words) {
    final all = text.split(RegExp(r'\s+'));
    return all.length <= words ? text : '${all.take(words).join(' ')}…';
  }

  /// Tidies model output: no Markdown symbols, one bullet per line, headings on their own lines.
  static String clean(String text) {
    var t = text
        .replaceAll(RegExp(r'\*\*|__|#+ ?'), '')
        .replaceAll(RegExp(r'^\s*[*•]\s+', multiLine: true), '- ');
    // Small models sometimes run every bullet into one line: " - Next point" starts a new one.
    t = t.replaceAllMapped(RegExp(r'[ \t]+-[ \t]+(?=[A-Z0-9"(])'), (_) => '\n- ');
    t = t.replaceAllMapped(
      RegExp(r'[ \t]*\b(Topic|Key points|Terms|Announcements)[ \t]*:?[ \t]*\n(?=- )'),
      (m) => '\n\n${m[1]}\n',
    );
    return t.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static String _clean(String text) => clean(text);
}
