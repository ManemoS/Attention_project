import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'downloads.dart';
import 'lectures.dart';
import 'l10n.dart';

/// The Whisper models the app offers. English-only models, since lectures are in English.
enum SpeechModel {
  fast(WhisperModel.baseEn, 'Fast', 141, 'Quicker. Fine when the lecturer is clear and close.'),
  accurate(WhisperModel.smallEn, 'Accurate', 465, 'Slower, but copes better with distance, noise and accents.');

  const SpeechModel(this.whisper, this.label, this.megabytes, this.description);

  final WhisperModel whisper;
  final String label;
  final int megabytes;
  final String description;
}

class TranscribeException implements Exception {
  const TranscribeException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Turns lecture recordings into text on the phone, with whisper.cpp.
///
/// Long recordings are cut into ten-minute pieces and done one at a time, which keeps memory low
/// on a phone and means an interrupted transcription carries on from the last finished piece.
class Transcriber {
  static const chunk = Duration(minutes: 10);

  /// Silero voice detection, so long silences aren't decoded into made-up words.
  static final _vadUrl = Uri.parse('https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin');

  static final _controller = WhisperController();

  static Future<File> _modelFile(SpeechModel model) async => File(await _controller.getPath(model.whisper));

  static Future<File> _vadFile() async => File('${await WhisperController.getModelDir()}/ggml-silero-v5.1.2.bin');

  static Future<bool> isInstalled(SpeechModel model) async =>
      await (await _modelFile(model)).exists() && await (await _vadFile()).exists();

  /// Downloads [model] (and the small voice detector it uses) once. Can be run again to resume.
  static Future<void> install(SpeechModel model, {void Function(double)? onProgress, bool Function()? isCancelled}) async {
    final vad = await _vadFile();
    if (!await vad.exists()) await downloadFile(_vadUrl, vad, isCancelled: isCancelled);
    await downloadFile(model.whisper.modelUri, await _modelFile(model), onProgress: onProgress, isCancelled: isCancelled);
  }

  static Future<void> uninstall(SpeechModel model) async {
    for (final file in [await _modelFile(model), File('${(await _modelFile(model)).path}.part')]) {
      if (await file.exists()) await file.delete();
    }
  }

  /// Transcribes [lecture]'s recording into its transcript and segment files.
  ///
  /// [onProgress] gets 0 to 1. Checks [isCancelled] between pieces; work done so far is kept.
  static Future<void> transcribe(
    Lecture lecture,
    SpeechModel model, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await lecture.audioFile.exists()) throw TranscribeException('This lecture has no recording.'.tr);
    if (!await isInstalled(model)) throw TranscribeException('Download the speech model first.'.tr);

    final length = await _length(lecture);
    final pieces = (length.inMilliseconds / chunk.inMilliseconds).ceil().clamp(1, 1000);
    final saved = await _readProgress(lecture, model);
    final segments = [...saved.segments];
    final part = File('${lecture.dir}/${lecture.id}.part.wav');

    for (var i = saved.done; i < pieces; i++) {
      if (isCancelled?.call() ?? false) return;
      onProgress?.call(i / pieces);

      // Cut straight to the 16 kHz mono WAV Whisper reads, whatever the recording's format.
      final cut = await FFmpegKit.executeWithArguments([
        '-y', '-ss', '${i * chunk.inSeconds}', '-t', '${chunk.inSeconds}',
        '-i', lecture.audioFile.path, '-ar', '16000', '-ac', '1', '-c:a', 'pcm_s16le', part.path,
      ]);
      if (!ReturnCode.isSuccess(await cut.getReturnCode())) {
        throw TranscribeException('Couldn\'t read the recording. It may be damaged.'.tr);
      }

      final result = await _controller.transcribe(
        model: model.whisper,
        audioPath: part.path,
        lang: 'en',
        withSegments: true,
        suppressNonSpeechTokens: true,
        vadModelPath: (await _vadFile()).path,
        initialPrompt: 'A university lecture.',
        onProgress: (percent) => onProgress?.call((i + percent / 100) / pieces),
      );
      for (final leftover in [part, File('${part.path}.wav')]) {
        if (await leftover.exists()) await leftover.delete();
      }
      if (result == null) throw TranscribeException('Transcription failed. Try again, or try the other speech model.'.tr);

      final offset = chunk * i;
      for (final s in result.transcription.segments ?? const <WhisperTranscribeSegment>[]) {
        final text = s.text.trim();
        if (text.isEmpty || _isNoise(text)) continue;
        segments.add(TranscriptSegment(from: offset + s.fromTs, to: offset + s.toTs, text: text));
      }
      await _writeProgress(lecture, model, i + 1, segments, complete: i + 1 == pieces);
    }

    await lecture.transcriptFile.writeAsString(paragraphs(segments));
    onProgress?.call(1);
  }

  /// Transcribes a short clip, such as a spoken question, and returns its text.
  static Future<String> transcribeClip(String path, SpeechModel model) async {
    if (!await isInstalled(model)) throw TranscribeException('Download the speech model first.'.tr);
    final result = await _controller.transcribe(model: model.whisper, audioPath: path, lang: 'en');
    for (final leftover in [File(path), File('$path.wav')]) {
      if (await leftover.exists()) await leftover.delete();
    }
    if (result == null) throw TranscribeException('Couldn\'t hear a question. Try again.'.tr);
    return result.transcription.text.trim();
  }

  /// Joins segments into paragraphs, starting a new one wherever the speaker paused.
  static String paragraphs(List<TranscriptSegment> segments) {
    final out = StringBuffer();
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) {
        final pause = segments[i].from - segments[i - 1].to;
        out.write(pause > const Duration(seconds: 2) ? '\n\n' : ' ');
      }
      out.write(segments[i].text);
    }
    return out.toString().trim();
  }

  /// Whisper's labels for non-speech, like "[BLANK_AUDIO]" or "(music)".
  static bool _isNoise(String text) => RegExp(r'^[\[(][^\])]*[\])]$').hasMatch(text);

  static Future<Duration> _length(Lecture lecture) async {
    final meta = await lecture.readMeta();
    if (meta.duration != null && meta.duration! > Duration.zero) return meta.duration!;
    final info = (await FFprobeKit.getMediaInformation(lecture.audioFile.path)).getMediaInformation();
    final seconds = double.tryParse(info?.getDuration() ?? '');
    if (seconds == null) throw TranscribeException('Couldn\'t read the recording. It may be damaged.'.tr);
    return Duration(milliseconds: (seconds * 1000).round());
  }

  static Future<({int done, List<TranscriptSegment> segments})> _readProgress(Lecture lecture, SpeechModel model) async {
    try {
      final json = jsonDecode(await lecture.segmentsFile.readAsString()) as Map<String, dynamic>;
      // Starting over with a different model, or after a finished run, gives a fresh transcript.
      if (json['model'] != model.name || json['complete'] == true) return (done: 0, segments: <TranscriptSegment>[]);
      return (
        done: json['done'] as int,
        segments: [for (final s in json['segments'] as List) TranscriptSegment.fromJson(s as Map<String, dynamic>)],
      );
    } on Object {
      return (done: 0, segments: <TranscriptSegment>[]);
    }
  }

  static Future<void> _writeProgress(
    Lecture lecture,
    SpeechModel model,
    int done,
    List<TranscriptSegment> segments, {
    required bool complete,
  }) =>
      lecture.segmentsFile.writeAsString(jsonEncode({
        'model': model.name,
        'done': done,
        'complete': complete,
        'segments': [for (final s in segments) s.toJson()],
      }));

  /// How far an interrupted transcription got, from 0 to 1, or null if none is waiting.
  static Future<double?> pausedProgress(Lecture lecture) async {
    try {
      final json = jsonDecode(await lecture.segmentsFile.readAsString()) as Map<String, dynamic>;
      if (json['complete'] == true) return null;
      final length = await _length(lecture);
      final pieces = (length.inMilliseconds / chunk.inMilliseconds).ceil().clamp(1, 1000);
      return (json['done'] as int) / pieces;
    } on Object {
      return null;
    }
  }
}
