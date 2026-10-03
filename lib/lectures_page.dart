import 'package:flutter/material.dart';

import 'lectures.dart';

String _formatDate(BuildContext context, DateTime date) {
  final l10n = MaterialLocalizations.of(context);
  return '${l10n.formatMediumDate(date)}, ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
}

int _wordCount(String text) => text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Lets the user enter or change their Claude API key. Returns true if a key was saved.
Future<bool> showApiKeyDialog(BuildContext context) async {
  final controller = TextEditingController(text: await Claude.apiKey());
  if (!context.mounted) return false;
  final key = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Claude API key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Create a key at console.anthropic.com under "API keys", then paste it here. '
              'It stays on this phone.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'API key', hintText: 'sk-ant-...'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
      ],
    ),
  );
  controller.dispose();
  if (key == null || key.trim().isEmpty) return false;
  await Claude.setApiKey(key);
  return true;
}

class LecturesPage extends StatefulWidget {
  const LecturesPage({super.key});

  @override
  State<LecturesPage> createState() => _LecturesPageState();
}

class _LecturesPageState extends State<LecturesPage> {
  List<({Lecture lecture, int words, bool summarized})>? _lectures;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lectures = [
      for (final lecture in await loadLectures())
        (
          lecture: lecture,
          words: _wordCount(await lecture.readTranscript()),
          summarized: await lecture.summaryFile.exists(),
        ),
    ];
    if (mounted) setState(() => _lectures = lectures);
  }

  Future<void> _open(Lecture lecture) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LecturePage(lecture: lecture)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final lectures = _lectures;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lecture notes'),
        actions: [
          IconButton(
            tooltip: 'Claude API key',
            icon: const Icon(Icons.key),
            onPressed: () => showApiKeyDialog(context),
          ),
        ],
      ),
      body: lectures == null
          ? const Center(child: CircularProgressIndicator())
          : lectures.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No lectures yet. Turn on "Record lecture" when you start a lock session.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  children: [
                    for (final item in lectures)
                      ListTile(
                        leading: Icon(item.summarized ? Icons.description : Icons.mic),
                        title: Text(_formatDate(context, item.lecture.startedAt)),
                        subtitle: Text(item.words == 0
                            ? 'Nothing recorded'
                            : '${item.words} words · ${item.summarized ? 'Summarized' : 'Not summarized yet'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(item.lecture),
                      ),
                  ],
                ),
    );
  }
}

class LecturePage extends StatefulWidget {
  const LecturePage({super.key, required this.lecture});

  final Lecture lecture;

  @override
  State<LecturePage> createState() => _LecturePageState();
}

class _LecturePageState extends State<LecturePage> {
  String? _transcript;
  String? _summary;
  bool _summarizing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final transcript = await widget.lecture.readTranscript();
    final summary = await widget.lecture.readSummary();
    if (mounted) {
      setState(() {
        _transcript = transcript;
        _summary = summary;
      });
    }
  }

  Future<void> _summarize() async {
    if (await Claude.apiKey() == null) {
      if (!mounted || !await showApiKeyDialog(context)) return;
    }
    setState(() {
      _summarizing = true;
      _error = null;
    });
    try {
      // Re-read in case the recording was still going when the page opened.
      final transcript = await widget.lecture.readTranscript();
      final summary = await Claude.summarize(transcript);
      await widget.lecture.saveSummary(summary);
      if (mounted) setState(() => _summary = summary);
    } on SummaryException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _summarizing = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this lecture?'),
        content: const Text('The transcript and summary will be removed from this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.lecture.delete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final transcript = _transcript;
    final summary = _summary;
    final textTheme = Theme.of(context).textTheme;
    final empty = transcript != null && transcript.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_formatDate(context, widget.lecture.startedAt)),
        actions: [
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: transcript == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (summary != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Summary', style: textTheme.titleMedium),
                          const SizedBox(height: 8),
                          SelectableText(summary),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                if (empty)
                  const Text('Nothing was recorded during this session.', textAlign: TextAlign.center)
                else if (_summarizing)
                  const Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Claude is summarizing… this can take a minute.'),
                    ],
                  )
                else
                  FilledButton.icon(
                    onPressed: _summarize,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(summary == null ? 'Summarize with Claude' : 'Summarize again'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                if (!empty) ...[
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Transcript (${_wordCount(transcript)} words)'),
                    children: [SelectableText(transcript)],
                  ),
                ],
              ],
            ),
    );
  }
}
