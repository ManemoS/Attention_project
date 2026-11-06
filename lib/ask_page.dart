import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'lectures.dart';
import 'lectures_page.dart';
import 'model_store.dart';
import 'notes_ai.dart';
import 'transcriber.dart';
import 'ui.dart';
import 'l10n.dart';

class _Turn {
  _Turn(this.question);

  final String question;
  String answer = '';
  List<Lecture> sources = const [];
  bool done = false;
  String? error;
}

/// Ask questions about your lectures, typed or spoken. The phone AI answers from the transcripts.
class AskNotesPage extends StatefulWidget {
  const AskNotesPage({super.key, required this.library});

  final LectureLibrary library;

  @override
  State<AskNotesPage> createState() => _AskNotesPageState();
}

class _AskNotesPageState extends State<AskNotesPage> {
  static final _suggestions = [
    'What will be on the exam?'.tr,
    'What homework was set?'.tr,
    'What were the key terms?'.tr,
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Turn> _turns = [];

  /// Folder to search, or null for every lecture.
  String? _folder;
  bool _listening = false;
  bool _hearing = false;
  bool get _busy => _turns.isNotEmpty && !_turns.last.done;

  LectureLibrary get _library => widget.library;

  @override
  void dispose() {
    AppLock.stopSpeaking();
    if (_listening) AppLock.stopQuestion();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<Lecture> get _searchable => [
        for (final l in _folder == null ? [for (final l in _library.lectures) if (!_library.isTrashed(l)) l] : _library.inFolder(_folder))
          if (_library.info[l.id]?.transcribed ?? false) l,
      ];

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  Future<void> _ask(String text) async {
    final question = text.trim();
    if (question.isEmpty || _busy) return;
    _input.clear();
    final turn = _Turn(question);
    setState(() => _turns.add(turn));
    _toBottom();

    try {
      final model = ModelStore.notes;
      await ModelStore.instance.refresh();
      if (!ModelStore.instance.isInstalled(ModelStore.notesKey(model))) {
        throw NotesAiException('Download the notes AI in Settings first.'.tr);
      }
      final lectures = _searchable;
      if (lectures.isEmpty) {
        throw NotesAiException('Transcribe a lecture first, then ask about it here.'.tr);
      }
      final passages = await NotesAi.findPassages(lectures, question);
      turn.sources = {for (final p in passages) p.lecture}.toList();
      if (passages.isEmpty) {
        turn.answer = 'I couldn\'t find that in your lectures.'.tr;
      } else {
        turn.answer = await NotesAi.answer(model, question, passages, onText: (soFar) {
          if (!mounted) return;
          setState(() => turn.answer = soFar);
          _toBottom();
        });
      }
    } on Object catch (e) {
      turn.error = '$e';
    }
    if (mounted) setState(() => turn.done = true);
    _toBottom();
  }

  Future<void> _toggleVoice() async {
    if (_listening) {
      setState(() {
        _listening = false;
        _hearing = true;
      });
      final path = await AppLock.stopQuestion();
      try {
        if (path == null) throw TranscribeException('Didn\'t catch that. Try again.'.tr);
        final text = await Transcriber.transcribeClip(path, ModelStore.speech);
        if (mounted) setState(() => _hearing = false);
        await _ask(text);
      } on Object catch (e) {
        if (!mounted) return;
        setState(() => _hearing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
      return;
    }

    if (!await Transcriber.isInstalled(ModelStore.speech)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download a speech model in Settings to ask by voice.'.tr),
      ));
      return;
    }
    if (!await AppLock.requestMicPermission()) return;
    final started = await AppLock.startQuestion();
    if (!mounted) return;
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('The microphone is busy, maybe with a lecture recording.'.tr),
      ));
      return;
    }
    await AppLock.stopSpeaking();
    setState(() => _listening = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final folders = _library.folders;

    return Scaffold(
      appBar: AppBar(title: Text('Ask your notes'.tr)),
      body: Column(
        children: [
          if (folders.isNotEmpty)
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                children: [
                  for (final f in [null, ...folders]) ...[
                    ChoiceChip(
                      label: Text(f ?? 'All lectures'.tr),
                      selected: _folder == f,
                      onSelected: (_) => setState(() => _folder = f),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          Expanded(
            child: _turns.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      EmptyState(
                        icon: Icons.forum_rounded,
                        color: colors.tertiary,
                        title: 'Ask about your lectures'.tr,
                        message: ('Answers come from your transcripts, written by the AI on this phone. '
                            'Tap the microphone to ask out loud.').tr,
                      ),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final s in _suggestions) ActionChip(label: Text(s), onPressed: () => _ask(s)),
                        ],
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _turns.length,
                    itemBuilder: (context, i) => _TurnView(turn: _turns[i], library: _library),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: _listening ? colors.error : colors.tertiaryContainer,
                      foregroundColor: _listening ? colors.onError : colors.onTertiaryContainer,
                      minimumSize: const Size(52, 52),
                    ),
                    tooltip: _listening ? 'Stop and ask'.tr : 'Ask by voice'.tr,
                    onPressed: _busy || _hearing ? null : _toggleVoice,
                    icon: _hearing
                        ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !_listening,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening… tap stop when done'.tr : 'Ask a question'.tr,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Send'.tr,
                    onPressed: _busy ? null : () => _ask(_input.text),
                    icon: Icon(Icons.send_rounded, color: colors.tertiary),
                  ),
                ],
              ),
            ),
          ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PulseDot(color: colors.error),
                  const SizedBox(width: 6),
                  Text('Listening'.tr, style: textTheme.labelLarge?.copyWith(color: colors.error)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TurnView extends StatelessWidget {
  const _TurnView({required this.turn, required this.library});

  final _Turn turn;
  final LectureLibrary library;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.tertiary.withValues(alpha: 0.16),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Text(turn.question, style: textTheme.bodyLarge),
            ),
          ),
          const SizedBox(height: 10),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (turn.error != null)
                  Text(turn.error!, style: textTheme.bodyMedium?.copyWith(color: colors.error))
                else if (turn.answer.isEmpty)
                  Row(
                    children: [
                      SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: colors.tertiary),
                      ),
                      const SizedBox(width: 12),
                      Text('Looking through your lectures…'.tr, style: textTheme.bodyMedium),
                    ],
                  )
                else
                  SelectableText(turn.answer, style: textTheme.bodyLarge),
                if (turn.done && turn.error == null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final l in turn.sources)
                              ActionChip(
                                avatar: const Icon(Icons.graphic_eq_rounded, size: 16),
                                label: Text(l10n.formatMediumDate(l.startedAt)),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => LecturePage(lecture: l, library: library)),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Read aloud'.tr,
                        onPressed: () => AppLock.speak(turn.answer),
                        icon: const Icon(Icons.volume_up_rounded),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
