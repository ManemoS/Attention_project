import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'ask_page.dart';
import 'lectures.dart';
import 'model_store.dart';
import 'notes_ai.dart';
import 'settings.dart';
import 'transcriber.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'ui.dart';
import 'l10n.dart';

/// "42 min", "1 h 5 min", or "45 s" for a short clip.
String formatDuration(Duration d) {
  if (d < const Duration(minutes: 1)) return '{n} s'.trf({'n': d.inSeconds});
  final minutes = (d.inSeconds + 30) ~/ 60;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return h == 0
      ? '{n} min'.trf({'n': m})
      : m == 0
          ? '{n} h'.trf({'n': h})
          : '{h} h {m} min'.trf({'h': h, 'm': m});
}

String _formatDate(BuildContext context, DateTime date) {
  final l10n = MaterialLocalizations.of(context);
  // Thai reads times on a 24-hour clock ("13:30"), and its AM/PM form comes out as "AM 5:00".
  final time = l10n.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: isThai);
  return '${l10n.formatMediumDate(date)}, $time';
}

String _recordings(int n) => n == 1 ? '1 recording'.tr : '{n} recordings'.trf({'n': n});

/// Lets the user enter or change their Claude API key. Returns true if a key was saved.
Future<bool> showApiKeyDialog(BuildContext context) async {
  final controller = TextEditingController(text: await Claude.apiKey());
  if (!context.mounted) return false;
  final key = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Claude API key'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(('Create a key at console.anthropic.com under "API keys", then paste it here. '
              'It stays on this phone.').tr),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            decoration: InputDecoration(labelText: 'API key'.tr, hintText: 'sk-ant-...'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Save'.tr)),
      ],
    ),
  );
  controller.dispose();
  if (key == null || key.trim().isEmpty) return false;
  await Claude.setApiKey(key);
  return true;
}

void _showSnack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel'.tr)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
        ],
      ),
    ) ==
    true;

/// Asks for a folder name, checking it as the user types. Returns null if cancelled.
Future<String?> _askFolderName(BuildContext context, LectureLibrary library, {String? renaming}) {
  final controller = TextEditingController(text: renaming);
  String? problem;
  return showDialog<String>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void submit() {
          final found = library.folderNameProblem(controller.text, renaming: renaming);
          if (found != null) {
            setState(() => problem = found);
          } else {
            Navigator.pop(context, controller.text.trim());
          }
        }

        return AlertDialog(
          title: Text(renaming == null ? 'New folder'.tr : 'Rename folder'.tr),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: LectureLibrary.maxFolderNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Folder name'.tr,
              hintText: 'For example, Physics 101'.tr,
              errorText: problem,
            ),
            onChanged: (_) {
              if (problem != null) setState(() => problem = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel'.tr)),
            FilledButton(onPressed: submit, child: Text(renaming == null ? 'Create'.tr : 'Rename'.tr)),
          ],
        );
      },
    ),
  );
}

Future<void> _openAsk(BuildContext context, LectureLibrary library) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => AskNotesPage(library: library)));

/// Opens [lecture], then re-reads the library so word counts and summaries are up to date.
Future<void> _openLecture(BuildContext context, LectureLibrary library, Lecture lecture) async {
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => LecturePage(lecture: lecture, library: library)),
  );
  await library.refresh();
}

/// Lets the user pick a folder for [lecture], or make a new one.
Future<void> _moveLecture(BuildContext context, LectureLibrary library, Lecture lecture) async {
  final current = library.isTrashed(lecture) ? null : library.folderOf(lecture);
  final unsorted = !library.isTrashed(lecture) && current == null;
  const check = Icon(Icons.check);

  final choice = await showModalBottomSheet<({String? folder, bool create})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Move to'.tr, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final folder in library.folders)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(folder),
              trailing: folder == current ? check : null,
              onTap: () => Navigator.pop(context, (folder: folder, create: false)),
            ),
          ListTile(
            leading: const Icon(Icons.inbox_outlined),
            title: Text('Unsorted'.tr),
            trailing: unsorted ? check : null,
            onTap: () => Navigator.pop(context, (folder: null, create: false)),
          ),
          ListTile(
            leading: const Icon(Icons.create_new_folder_outlined),
            title: Text('New folder…'.tr),
            onTap: () => Navigator.pop(context, (folder: null, create: true)),
          ),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  var folder = choice.folder;
  if (choice.create) {
    folder = await _askFolderName(context, library);
    if (folder == null) return;
    await library.createFolder(folder);
  }
  await library.moveTo(lecture, folder);
  if (context.mounted) _showSnack(context, folder == null ? 'Moved to Unsorted'.tr : 'Moved to {folder}'.trf({'folder': folder}));
}

/// Moves [lecture] to the trash, with an Undo button in case it was a mistake.
Future<void> _trashLecture(BuildContext context, LectureLibrary library, Lecture lecture) async {
  // Look up the messenger first: the page may close before the save finishes.
  final messenger = ScaffoldMessenger.of(context);
  await library.moveToTrash(lecture);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text('Moved to trash'.tr),
      action: SnackBarAction(label: 'Undo'.tr, onPressed: () => library.restore(lecture)),
    ));
}

/// Returns true if the lecture was deleted.
Future<bool> _deleteForever(BuildContext context, LectureLibrary library, Lecture lecture) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete forever?'.tr,
    message: 'The transcript and summary will be removed from this phone. This can’t be undone.'.tr,
    action: 'Delete'.tr,
  );
  if (confirmed) await library.deleteForever(lecture);
  return confirmed;
}

enum _LectureAction { move, trash, restore, deleteForever }

PopupMenuItem<_LectureAction> _menuItem(_LectureAction value, IconData icon, String label) =>
    PopupMenuItem(
      value: value,
      child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(label)]),
    );

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SectionLabel(text);
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.lightbulb_outline_rounded, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      );
}

/// Rows grouped in one card, with hairlines between them.
class _TileGroup extends StatelessWidget {
  const _TileGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(indent: 76, endIndent: 16),
              children[i],
            ],
          ],
        ),
      );
}

/// A folder as a small card with its own colour, for the two-column grid.
class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.name, required this.count, required this.color, required this.onTap});

  final String name;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0.03)],
      ),
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.folder_rounded, color: color, size: 30),
          const SizedBox(height: 14),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.titleMedium),
          Text(_recordings(count), style: tabular(textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// The dashed-looking "add" card that sits at the end of the folder grid.
class _NewFolderCard extends StatelessWidget {
  const _NewFolderCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      color: Colors.transparent,
      borderColor: colors.outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.create_new_folder_outlined, color: colors.onSurfaceVariant, size: 30),
          const SizedBox(height: 14),
          Text('New folder'.tr, style: textTheme.titleMedium),
          Text('For a course or topic'.tr, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// A recording in a list. Swipe left to move it to the trash, or use its three-dot menu.
class _LectureTile extends StatelessWidget {
  const _LectureTile({required this.library, required this.lecture});

  final LectureLibrary library;
  final Lecture lecture;

  Future<void> _run(BuildContext context, _LectureAction action) async {
    switch (action) {
      case _LectureAction.move:
        await _moveLecture(context, library, lecture);
      case _LectureAction.trash:
        await _trashLecture(context, library, lecture);
      case _LectureAction.restore:
        await library.restore(lecture);
        if (context.mounted) _showSnack(context, 'Restored'.tr);
      case _LectureAction.deleteForever:
        await _deleteForever(context, library, lecture);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = library.info[lecture.id] ?? const LectureInfo();
    final words = info.words;
    final summarized = info.summarized;
    final trashed = library.isTrashed(lecture);
    final colors = Theme.of(context).colorScheme;

    final tile = ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
      leading: IconBadge(
        info.recording
            ? Icons.mic_rounded
            : summarized
                ? Icons.auto_awesome_rounded
                : info.transcribed
                    ? Icons.notes_rounded
                    : Icons.graphic_eq_rounded,
        color: trashed
            ? colors.onSurfaceVariant
            : info.recording
                ? colors.error
                : summarized
                    ? colors.tertiary
                    : colors.primary,
      ),
      title: Text(_formatDate(context, lecture.startedAt)),
      subtitle: Text([
        if (info.recording)
          'Recording now'.tr
        else if (info.transcribed)
          '{n} words'.trf({'n': words})
        else if (info.hasAudio)
          info.duration == null ? 'Recording'.tr : '{time} recording'.trf({'time': formatDuration(info.duration!)})
        else
          'Nothing recorded yet'.tr,
        if (!info.recording && info.hasAudio && !info.transcribed) 'Not transcribed yet'.tr,
        if (info.transcribed) summarized ? 'Summarized'.tr : 'Not summarized'.tr,
        if (info.marks > 0) info.marks == 1 ? '1 mark'.tr : '{n} marks'.trf({'n': info.marks}),
        if (trashed) 'Deleted in {n} days'.trf({'n': library.daysLeftInTrash(lecture)}),
      ].join(' · ')),
      onTap: () => _openLecture(context, library, lecture),
      trailing: PopupMenuButton<_LectureAction>(
        tooltip: 'More'.tr,
        onSelected: (action) => _run(context, action),
        itemBuilder: (_) => trashed
            ? [
                _menuItem(_LectureAction.restore, Icons.restore_from_trash, 'Restore'.tr),
                _menuItem(_LectureAction.deleteForever, Icons.delete_forever, 'Delete forever'.tr),
              ]
            : [
                _menuItem(_LectureAction.move, Icons.drive_file_move_outline, 'Move to folder'.tr),
                _menuItem(_LectureAction.trash, Icons.delete_outline, 'Move to trash'.tr),
              ],
      ),
    );
    if (trashed) return tile;

    return Dismissible(
      key: ValueKey(lecture.id),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(18)),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Trash'.tr, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.onErrorContainer)),
            const SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: colors.onErrorContainer),
          ],
        ),
      ),
      onDismissed: (_) => _trashLecture(context, library, lecture),
      child: tile,
    );
  }
}

/// Folders, unsorted recordings and the trash.
class LecturesPage extends StatefulWidget {
  const LecturesPage({super.key});

  @override
  State<LecturesPage> createState() => _LecturesPageState();
}

class _LecturesPageState extends State<LecturesPage> {
  late final Future<LectureLibrary> _library = LectureLibrary.open();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Lecture notes'.tr),
        actions: [
          // The Claude API key lives in Settings now.
          const SettingsButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<LectureLibrary>(
        future: _library,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              title: 'Could not load lectures'.tr,
              message: '${snapshot.error}',
            );
          }
          final library = snapshot.data;
          if (library == null) return const Center(child: CircularProgressIndicator());
          return ListenableBuilder(
            listenable: library,
            builder: (context, _) => RefreshIndicator(
              onRefresh: library.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: _items(context, library),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _items(BuildContext context, LectureLibrary library) {
    final colors = Theme.of(context).colorScheme;
    final unsorted = library.inFolder(null);
    final trashCount = library.trash.length;
    final folderColors = [colors.primary, colors.secondary, colors.tertiary, colors.error];

    final cards = [
      for (var i = 0; i < library.folders.length; i++)
        _FolderCard(
          name: library.folders[i],
          count: library.inFolder(library.folders[i]).length,
          color: folderColors[i % folderColors.length],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LectureFolderPage(library: library, folder: library.folders[i])),
          ),
        ),
      _NewFolderCard(
        onTap: () async {
          final name = await _askFolderName(context, library);
          if (name != null) await library.createFolder(name);
        },
      ),
    ];

    final anyTranscribed = library.info.values.any((i) => i.transcribed);

    return [
      if (anyTranscribed) ...[
        const SizedBox(height: 8),
        Panel(
          onTap: () => _openAsk(context, library),
          borderColor: colors.tertiary.withValues(alpha: 0.4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.tertiary.withValues(alpha: 0.18), colors.tertiary.withValues(alpha: 0.04)],
          ),
          child: Row(
            children: [
              IconBadge(Icons.forum_rounded, color: colors.tertiary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ask your notes'.tr, style: Theme.of(context).textTheme.titleMedium),
                    Text('"What will be on the exam?" Type or say it.'.tr, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.mic_rounded, color: colors.tertiary),
            ],
          ),
        ),
      ],
      _Header('Folders'.tr),
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final width = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final card in cards) SizedBox(width: width, child: card)],
          );
        },
      ),
      _Header('Unsorted'.tr),
      if (library.lectures.isEmpty)
        EmptyState(
          icon: Icons.graphic_eq_rounded,
          title: 'No lectures yet'.tr,
          message: 'Turn on "Record lecture" when you start a lock session, and the transcript lands here.'.tr,
        )
      else if (unsorted.isEmpty)
        _Hint('Everything is sorted into folders.'.tr)
      else ...[
        _TileGroup(children: [for (final lecture in unsorted) _LectureTile(library: library, lecture: lecture)]),
        _Hint('Swipe a recording left to move it to the trash, or use its three-dot menu to move it to a folder.'.tr),
      ],
      const SizedBox(height: 24),
      Panel(
        padding: EdgeInsets.zero,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrashPage(library: library))),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
          leading: IconBadge(Icons.delete_outline_rounded, color: colors.onSurfaceVariant),
          title: Text('Trash'.tr),
          subtitle: Text(trashCount == 0
              ? 'Empty'.tr
              : '{count} · deleted for good after {days} days'
                  .trf({'count': _recordings(trashCount), 'days': LectureLibrary.trashDays})),
          trailing: Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
        ),
      ),
    ];
  }
}

/// The recordings filed in one folder.
class LectureFolderPage extends StatefulWidget {
  const LectureFolderPage({super.key, required this.library, required this.folder});

  final LectureLibrary library;
  final String folder;

  @override
  State<LectureFolderPage> createState() => _LectureFolderPageState();
}

class _LectureFolderPageState extends State<LectureFolderPage> {
  late String _folder = widget.folder;

  LectureLibrary get _library => widget.library;

  Future<void> _rename() async {
    final name = await _askFolderName(context, _library, renaming: _folder);
    if (name == null || name == _folder) return;
    final old = _folder;
    setState(() => _folder = name);
    await _library.renameFolder(old, name);
  }

  Future<void> _delete() async {
    final count = _library.inFolder(_folder).length;
    final confirmed = await _confirm(
      context,
      title: 'Delete "{folder}"?'.trf({'folder': _folder}),
      message: count == 0
          ? 'The folder is empty.'.tr
          : 'The {count} in it will go back to Unsorted. No recordings are deleted.'.trf({'count': _recordings(count)}),
      action: 'Delete folder'.tr,
    );
    if (!confirmed || !mounted) return;
    Navigator.pop(context);
    await _library.deleteFolder(_folder);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final lectures = _library.inFolder(_folder);
        return Scaffold(
          appBar: AppBar(
            title: Text(_folder),
            actions: [
              PopupMenuButton<void Function()>(
                tooltip: 'Folder options'.tr,
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _rename,
                    child: Row(children: [Icon(Icons.edit_outlined), SizedBox(width: 12), Text('Rename'.tr)]),
                  ),
                  PopupMenuItem(
                    value: _delete,
                    child: Row(
                      children: [Icon(Icons.folder_delete_outlined), SizedBox(width: 12), Text('Delete folder'.tr)],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: lectures.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'Nothing here yet'.tr,
                    message: ('No recordings in this folder yet. Open Lecture notes and use the three-dot menu on a recording '
                        'to move it here.').tr,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: Text(_recordings(lectures.length), style: Theme.of(context).textTheme.bodySmall),
                    ),
                    _TileGroup(
                      children: [for (final lecture in lectures) _LectureTile(library: _library, lecture: lecture)],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

/// Recordings that were moved to the trash. They can be restored until they expire.
class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.library});

  final LectureLibrary library;

  Future<void> _empty(BuildContext context) async {
    final count = library.trash.length;
    final confirmed = await _confirm(
      context,
      title: 'Empty the trash?'.tr,
      message: ('The {count} in the trash will be removed from this phone. '
              'This can’t be undone.')
          .trf({'count': _recordings(count)}),
      action: 'Empty trash'.tr,
    );
    if (confirmed) await library.emptyTrash();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final trash = library.trash;
        return Scaffold(
          appBar: AppBar(
            title: Text('Trash'.tr),
            actions: [
              if (trash.isNotEmpty) TextButton(onPressed: () => _empty(context), child: Text('Empty trash'.tr)),
            ],
          ),
          body: trash.isEmpty
              ? Center(
                  child: EmptyState(
                    icon: Icons.delete_sweep_outlined,
                    color: Theme.of(context).colorScheme.secondary,
                    title: 'All clear'.tr,
                    message: 'The trash is empty.'.tr,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _TileGroup(children: [for (final lecture in trash) _LectureTile(library: library, lecture: lecture)]),
                    const _Hint('Recordings here are deleted for good after '
                        '${LectureLibrary.trashDays} days. Use the three-dot menu to restore one.'),
                  ],
                ),
        );
      },
    );
  }
}

class LecturePage extends StatefulWidget {
  const LecturePage({super.key, required this.lecture, required this.library});

  final Lecture lecture;
  final LectureLibrary library;

  @override
  State<LecturePage> createState() => _LecturePageState();
}

enum _Job { none, transcribing, summarizing, flashcards }

class _LecturePageState extends State<LecturePage> {
  String? _transcript;
  String? _summary;
  LectureMeta _meta = const LectureMeta();
  List<TranscriptSegment> _segments = const [];
  List<Flashcard>? _cards;
  bool _hasAudio = false;
  double? _pausedAt;

  _Job _job = _Job.none;
  double _progress = 0;
  String _status = '';
  String? _error;
  bool _cancel = false;

  /// True while a model downloads before transcribing, which can't be paused like transcription.
  bool _downloading = false;

  Lecture get _lecture => widget.lecture;
  LectureLibrary get _library => widget.library;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel = true;
    AppLock.playerRelease();
    if (_job != _Job.none) AppLock.setKeepScreenOn(false);
    super.dispose();
  }

  Future<void> _load() async {
    final transcript = await _lecture.readTranscript();
    final summary = await _lecture.readSummary();
    final meta = await _lecture.readMeta();
    final segments = await _lecture.readSegments();
    final hasAudio = await _lecture.audioFile.exists();
    final paused = transcript.isEmpty && hasAudio ? await Transcriber.pausedProgress(_lecture) : null;
    List<Flashcard>? cards;
    if (await _lecture.cardsFile.exists()) {
      try {
        cards = [
          for (final c in jsonDecode(await _lecture.cardsFile.readAsString()) as List)
            Flashcard.fromJson(c as Map<String, dynamic>),
        ];
      } on FormatException {
        cards = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _transcript = transcript;
      _summary = summary;
      _meta = meta;
      _segments = segments;
      _hasAudio = hasAudio;
      _cards = cards;
      _pausedAt = paused;
    });
  }

  /// Runs a long job with the screen kept on, showing its progress and any error.
  Future<void> _run(_Job job, Future<void> Function() work) async {
    setState(() {
      _job = job;
      _progress = 0;
      _status = '';
      _error = null;
      _cancel = false;
    });
    await AppLock.setKeepScreenOn(true);
    try {
      await work();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      await AppLock.setKeepScreenOn(false);
      if (mounted) setState(() => _job = _Job.none);
      await _load();
    }
  }

  void _onProgress(double progress, [String? status]) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      if (status != null) _status = status;
    });
  }

  /// Offers to download a model the user hasn't got yet. Returns true if it's ready.
  Future<bool> _ensureModel({required String key, required String what, required int megabytes, required Future<void> Function() download}) async {
    final store = ModelStore.instance;
    await store.refresh();
    if (store.isInstalled(key)) return true;
    if (!mounted) return false;
    final go = await _confirm(
      context,
      title: 'Download the {what}?'.trf({'what': what}),
      message: 'It\'s $megabytes MB, downloaded once over Wi-Fi. After that it works offline and '
          'nothing leaves your phone.',
      action: 'Download'.tr,
    );
    if (!go) return false;
    await _run(_Job.transcribing, () async {
      _onProgress(0, 'Downloading the {what}…'.trf({'what': what}));
      void listener() => _onProgress(store.progress(key) ?? 1);
      store.addListener(listener);
      _downloading = true;
      try {
        await download();
      } finally {
        _downloading = false;
        store.removeListener(listener);
      }
      if (store.error(key) != null) throw Exception(store.error(key));
    });
    return store.isInstalled(key);
  }

  Future<void> _transcribe() async {
    final model = ModelStore.speech;
    final ready = await _ensureModel(
      key: ModelStore.speechKey(model),
      what: 'speech model'.tr,
      megabytes: model.megabytes,
      download: () => ModelStore.instance.downloadSpeech(model),
    );
    if (!ready || !mounted) return;
    await _run(_Job.transcribing, () async {
      _onProgress(_pausedAt ?? 0, 'Transcribing on this phone…'.tr);
      await Transcriber.transcribe(
        _lecture,
        model,
        onProgress: (p) => _onProgress(p),
        isCancelled: () => _cancel,
      );
    });
    await _library.refresh();
  }

  Future<void> _summarize() async {
    final transcript = await _lecture.readTranscript();
    if (AppSettings.instance.notesEngine == 'claude') {
      if (await Claude.apiKey() == null) {
        if (!mounted || !await showApiKeyDialog(context)) return;
      }
      await _run(_Job.summarizing, () async {
        _onProgress(0.3, 'Claude is summarizing… this can take a minute.'.tr);
        try {
          await _lecture.saveSummary(await Claude.summarize(transcript));
        } on SummaryException catch (e) {
          throw Exception(e.message);
        }
      });
    } else {
      final model = ModelStore.notes;
      final ready = await _ensureModel(
        key: ModelStore.notesKey(model),
        what: 'notes AI'.tr,
        megabytes: model.megabytes,
        download: () => ModelStore.instance.downloadNotes(model),
      );
      if (!ready || !mounted) return;
      await _run(_Job.summarizing, () async {
        _onProgress(0, 'Starting the notes AI…'.tr);
        final summary = await NotesAi.summarize(model, transcript, onProgress: _onProgress);
        await _lecture.saveSummary(summary);
      });
    }
    await _library.refresh();
  }

  Future<void> _makeFlashcards() async {
    final model = ModelStore.notes;
    final ready = await _ensureModel(
      key: ModelStore.notesKey(model),
      what: 'notes AI'.tr,
      megabytes: model.megabytes,
      download: () => ModelStore.instance.downloadNotes(model),
    );
    if (!ready || !mounted) return;
    await _run(_Job.flashcards, () async {
      _onProgress(0.2, 'Writing flashcards…'.tr);
      final source = _summary ?? await _lecture.readTranscript();
      final cards = await NotesAi.flashcards(model, source);
      await _lecture.cardsFile.writeAsString(jsonEncode([for (final c in cards) c.toJson()]));
    });
  }

  Future<void> _openCards() async {
    final cards = _cards;
    if (cards == null || cards.isEmpty) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FlashcardsPage(title: _formatDate(context, _lecture.startedAt), cards: cards)),
    );
  }

  Future<void> _trash() async {
    final trashing = _trashLecture(context, _library, _lecture);
    Navigator.pop(context);
    await trashing;
  }

  Future<void> _restore() async {
    await _library.restore(_lecture);
    if (mounted) _showSnack(context, 'Restored'.tr);
  }

  Future<void> _deleteForeverAndClose() async {
    if (await _deleteForever(context, _library, _lecture) && mounted) Navigator.pop(context);
  }

  List<Widget> _actions(bool trashed) => trashed
      ? [
          IconButton(tooltip: 'Restore'.tr, icon: const Icon(Icons.restore_from_trash), onPressed: _restore),
          IconButton(
            tooltip: 'Delete forever'.tr,
            icon: const Icon(Icons.delete_forever),
            onPressed: _deleteForeverAndClose,
          ),
        ]
      : [
          IconButton(
            tooltip: 'Move to folder'.tr,
            icon: const Icon(Icons.drive_file_move_outline),
            onPressed: () => _moveLecture(context, _library, _lecture),
          ),
          IconButton(tooltip: 'Move to trash'.tr, icon: const Icon(Icons.delete_outline), onPressed: _trash),
        ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _library,
      builder: (context, _) {
        final trashed = _library.isTrashed(_lecture);
        final folder = _library.folderOf(_lecture);
        return Scaffold(
          appBar: AppBar(
            title: Text(_formatDate(context, _lecture.startedAt)),
            actions: _actions(trashed),
          ),
          body: _transcript == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        backgroundColor: trashed ? Theme.of(context).colorScheme.errorContainer : null,
                        avatar: Icon(trashed
                            ? Icons.delete_outline
                            : folder == null
                                ? Icons.inbox_outlined
                                : Icons.folder_outlined),
                        label: Text(trashed
                            ? 'In the trash · deleted for good in {n} days'.trf({'n': _library.daysLeftInTrash(_lecture)})
                            : folder ?? 'Unsorted'.tr),
                        tooltip: trashed ? null : 'Move to folder'.tr,
                        onPressed: trashed ? null : () => _moveLecture(context, _library, _lecture),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._content(context),
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _content(BuildContext context) {
    final transcript = _transcript!;
    final summary = _summary;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final transcribed = transcript.trim().isNotEmpty;
    final busy = _job != _Job.none;

    return [
      if (_meta.recording)
        Panel(
          child: Row(
            children: [
              PulseDot(color: colors.error),
              const SizedBox(width: 12),
              Expanded(child: Text('Still recording. Come back when the session ends.'.tr)),
            ],
          ),
        )
      else if (_hasAudio) ...[
        _LecturePlayer(lecture: _lecture, marks: _meta.marks, segments: _segments),
        const SizedBox(height: 16),
      ],
      if (busy)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 3, color: colors.tertiary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _status.isEmpty ? 'Working…'.tr : _status,
                      style: textTheme.titleSmall,
                    ),
                  ),
                  Text('${(_progress * 100).round()}%', style: tabular(textTheme.labelLarge)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: _progress, minHeight: 6, color: colors.tertiary),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Keep the app open. The screen stays on until it finishes.'.tr,
                      style: textTheme.bodySmall,
                    ),
                  ),
                  if (_job == _Job.transcribing && !_downloading)
                    TextButton(
                      onPressed: () => setState(() => _cancel = true),
                      child: Text(_cancel ? 'Pausing…'.tr : 'Pause'.tr),
                    ),
                ],
              ),
            ],
          ),
        )
      else if (!transcribed && _hasAudio && !_meta.recording)
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBadge(Icons.notes_rounded, color: colors.primary),
                  const SizedBox(width: 14),
                  Expanded(child: Text('Turn this recording into text'.tr, style: textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                ('Whisper runs on this phone, so the recording never leaves it. An hour of lecture can take '
                'a while; you can pause and carry on later.').tr,
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _transcribe,
                icon: const Icon(Icons.subtitles_rounded),
                label: Text(_pausedAt == null
                    ? 'Transcribe on this phone'.tr
                    : 'Carry on transcribing ({n}% done)'.trf({'n': (_pausedAt! * 100).round()})),
              ),
            ],
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: colors.errorContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: colors.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, style: TextStyle(color: colors.onErrorContainer))),
            ],
          ),
        ),
      ],
      if (summary != null) ...[
        const SizedBox(height: 16),
        Panel(
          borderColor: colors.tertiary.withValues(alpha: 0.4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.tertiary.withValues(alpha: 0.14), colors.tertiary.withValues(alpha: 0.02)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, size: 20, color: colors.tertiary),
                  const SizedBox(width: 8),
                  Text('Summary'.tr, style: textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              // Tidied as it's shown too, so summaries saved before the tidy-up also read well.
              SelectableText(NotesAi.clean(summary), style: textTheme.bodyLarge),
            ],
          ),
        ),
      ],
      if (transcribed && !busy) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: colors.tertiary, foregroundColor: colors.onTertiary),
          onPressed: _summarize,
          icon: const Icon(Icons.auto_awesome_rounded),
          label: Text(summary == null
              ? (AppSettings.instance.notesEngine == 'claude' ? 'Summarize with Claude'.tr : 'Summarize on this phone'.tr)
              : 'Summarize again'.tr),
        ),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          onTap: _cards == null ? _makeFlashcards : _openCards,
          child: ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            leading: IconBadge(Icons.style_rounded, color: colors.secondary),
            title: Text(_cards == null ? 'Make flashcards'.tr : 'Study {n} flashcards'.trf({'n': _cards!.length})),
            subtitle: Text(_cards == null
                ? 'Questions and answers from this lecture, for revision'.tr
                : 'Tap a card to see the answer'.tr),
            trailing: _cards == null
                ? Icon(Icons.add_rounded, color: colors.onSurfaceVariant)
                : PopupMenuButton<void>(
                    tooltip: 'More'.tr,
                    itemBuilder: (_) => [PopupMenuItem(onTap: _makeFlashcards, child: Text('Make new cards'.tr))],
                  ),
          ),
        ),
      ],
      if (!transcribed && !_hasAudio && !_meta.recording)
        EmptyState(
          icon: Icons.mic_off_rounded,
          title: 'Nothing recorded'.tr,
          message: 'Nothing was recorded during this session.'.tr,
        ),
      if (transcribed) ...[
        const SizedBox(height: 16),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(Icons.notes_rounded, color: colors.onSurfaceVariant),
            title: Text('Transcript'.tr, style: textTheme.titleMedium),
            subtitle: Text('{n} words'.trf({'n': wordCount(transcript)}), style: tabular(textTheme.bodySmall)),
            childrenPadding: const EdgeInsets.only(bottom: 16),
            children: [SelectableText(transcript, style: textTheme.bodyMedium)],
          ),
        ),
      ],
    ];
  }
}

/// Play, pause and scrub through a recording, with its bookmarks as stars to jump to.
class _LecturePlayer extends StatefulWidget {
  const _LecturePlayer({required this.lecture, required this.marks, required this.segments});

  final Lecture lecture;
  final List<Duration> marks;
  final List<TranscriptSegment> segments;

  @override
  State<_LecturePlayer> createState() => _LecturePlayerState();
}

class _LecturePlayerState extends State<_LecturePlayer> {
  Duration _length = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;
  bool _failed = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _poll?.cancel();
    AppLock.playerPause();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      final length = await AppLock.playerLoad(widget.lecture.audioFile.path);
      if (mounted) setState(() => _length = length);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      final state = await AppLock.playerState();
      if (!mounted) return;
      setState(() {
        _position = state.position;
        _playing = state.playing;
      });
      if (!state.playing) _poll?.cancel();
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await AppLock.playerPause();
      setState(() => _playing = false);
    } else {
      await AppLock.playerPlay();
      setState(() => _playing = true);
      _startPolling();
    }
  }

  Future<void> _seek(Duration to, {bool play = false}) async {
    await AppLock.playerSeek(to);
    setState(() => _position = to);
    if (play && !_playing) await _toggle();
  }

  /// What was being said at [at], for a bookmark's caption.
  String? _textAt(Duration at) {
    for (final s in widget.segments) {
      if (s.to >= at - const Duration(seconds: 5)) return s.text;
    }
    return null;
  }

  String _clock(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two((s % 3600) ~/ 60)}:${two(s % 60)}' : '${(s % 3600) ~/ 60}:${two(s % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    if (_failed) {
      return Panel(child: Text('This recording can\'t be played.'.tr, style: textTheme.bodyMedium));
    }
    final max = _length.inMilliseconds.toDouble();
    final value = _position.inMilliseconds.clamp(0, _length.inMilliseconds).toDouble();

    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  minimumSize: const Size(52, 52),
                ),
                tooltip: _playing ? 'Pause'.tr : 'Play'.tr,
                onPressed: _length == Duration.zero ? null : _toggle,
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 30),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 32,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Slider(
                            value: value,
                            max: max <= 0 ? 1 : max,
                            onChanged: max <= 0 ? null : (v) => setState(() => _position = Duration(milliseconds: v.round())),
                            onChangeEnd: (v) => _seek(Duration(milliseconds: v.round())),
                          ),
                          // Bookmarks drawn on the track, so they can be found by eye.
                          if (max > 0)
                            Positioned.fill(
                              left: 24,
                              right: 24,
                              child: IgnorePointer(
                                child: LayoutBuilder(
                                  builder: (context, box) => Stack(
                                    children: [
                                      for (final m in widget.marks)
                                        Positioned(
                                          left: box.maxWidth * (m.inMilliseconds / max).clamp(0.0, 1.0) - 7,
                                          top: 0,
                                          child: Icon(Icons.star_rounded, size: 14, color: colors.secondary),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          Text(_clock(_position), style: tabular(textTheme.labelMedium)),
                          const Spacer(),
                          Text(_clock(_length), style: tabular(textTheme.labelMedium)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (widget.marks.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('Marked important'.tr, style: textTheme.titleSmall),
            ),
            const SizedBox(height: 6),
            for (final mark in widget.marks)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _seek(mark - const Duration(seconds: 10), play: true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.star_rounded, size: 18, color: colors.secondary),
                      const SizedBox(width: 8),
                      Text(_clock(mark), style: tabular(textTheme.labelLarge)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _textAt(mark) ?? 'Tap to listen from just before this moment'.tr,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Revise a lecture's flashcards: tap to flip, then say whether you knew it.
class FlashcardsPage extends StatefulWidget {
  const FlashcardsPage({super.key, required this.title, required this.cards});

  final String title;
  final List<Flashcard> cards;

  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  late List<Flashcard> _deck = [...widget.cards];
  int _index = 0;
  bool _flipped = false;
  int _known = 0;
  final List<Flashcard> _again = [];

  void _answer(bool knew) {
    setState(() {
      if (knew) {
        _known++;
      } else {
        _again.add(_deck[_index]);
      }
      _index++;
      _flipped = false;
    });
  }

  void _restart({bool onlyMissed = false}) {
    setState(() {
      _deck = onlyMissed ? [..._again] : [...widget.cards];
      _again.clear();
      _index = 0;
      _known = 0;
      _flipped = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final done = _index >= _deck.length;

    return Scaffold(
      appBar: AppBar(title: Text('Flashcards · {title}'.trf({'title': widget.title}))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: done
              ? Center(
                  child: EmptyState(
                    icon: Icons.emoji_events_rounded,
                    color: colors.secondary,
                    title: 'You knew {known} of {total}'.trf({'known': _known, 'total': _deck.length}),
                    message: _again.isEmpty ? 'Every card. Nice work.'.tr : 'Go over the ones you missed once more.'.tr,
                    action: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        if (_again.isNotEmpty)
                          FilledButton(onPressed: () => _restart(onlyMissed: true), child: Text('Study missed'.tr)),
                        OutlinedButton(onPressed: _restart, child: Text('Start over'.tr)),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text('Card {n} of {total}'.trf({'n': _index + 1, 'total': _deck.length}), style: textTheme.labelLarge),
                        const Spacer(),
                        Text('{n} known'.trf({'n': _known}), style: tabular(textTheme.labelLarge?.copyWith(color: colors.secondary))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: _index / _deck.length, minHeight: 6, color: colors.secondary),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _flipped = !_flipped),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          transitionBuilder: (child, animation) => ScaleTransition(
                            scale: Tween(begin: 0.94, end: 1.0).animate(animation),
                            child: FadeTransition(opacity: animation, child: child),
                          ),
                          child: Panel(
                            key: ValueKey('$_index-$_flipped'),
                            color: _flipped ? colors.secondary.withValues(alpha: 0.10) : null,
                            borderColor: _flipped ? colors.secondary.withValues(alpha: 0.5) : null,
                            padding: const EdgeInsets.all(28),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _flipped ? 'ANSWER'.tr : 'QUESTION'.tr,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: _flipped ? colors.secondary : colors.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _flipped ? _deck[_index].answer : _deck[_index].question,
                                    textAlign: TextAlign.center,
                                    style: textTheme.headlineSmall,
                                  ),
                                  if (!_flipped) ...[
                                    const SizedBox(height: 24),
                                    Text('Tap to see the answer'.tr, style: textTheme.bodySmall),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_flipped)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _answer(false),
                              icon: const Icon(Icons.replay_rounded),
                              label: Text('Again'.tr),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: colors.secondary, foregroundColor: colors.onSecondary),
                              onPressed: () => _answer(true),
                              icon: const Icon(Icons.check_rounded),
                              label: Text('Knew it'.tr),
                            ),
                          ),
                        ],
                      )
                    else
                      FilledButton(onPressed: () => setState(() => _flipped = true), child: Text('Show answer'.tr)),
                  ],
                ),
        ),
      ),
    );
  }
}
