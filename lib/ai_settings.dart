import 'package:flutter/material.dart';

import 'model_store.dart';
import 'notes_ai.dart';
import 'settings.dart';
import 'theme.dart';
import 'transcriber.dart';
import 'ui.dart';
import 'l10n.dart';

/// One model the user can pick, download and delete.
class _ModelOption {
  const _ModelOption({
    required this.key,
    required this.value,
    required this.label,
    required this.megabytes,
    required this.description,
    required this.download,
    required this.delete,
  });

  final String key;
  final String value;
  final String label;
  final int megabytes;
  final String description;
  final Future<void> Function() download;
  final Future<void> Function() delete;
}

/// The "Speech to text".tr and "Notes AI".tr sections of Settings.
class AiSettings extends StatefulWidget {
  const AiSettings({super.key});

  @override
  State<AiSettings> createState() => _AiSettingsState();
}

class _AiSettingsState extends State<AiSettings> {
  final _store = ModelStore.instance;
  final _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _store.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: Listenable.merge([_store, _settings]),
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('Speech to text'.tr),
          _Group(
            intro: 'Turns lecture recordings into text on this phone with Whisper. Nothing is uploaded.'.tr,
            icon: Icons.graphic_eq_rounded,
            color: colors.primary,
            selected: _settings.speechModel,
            onSelect: _settings.setSpeechModel,
            options: [
              for (final m in SpeechModel.values)
                _ModelOption(
                  key: ModelStore.speechKey(m),
                  value: m.name,
                  label: m.label.tr,
                  megabytes: m.megabytes,
                  description: m.description.tr,
                  download: () => _store.downloadSpeech(m),
                  delete: () => _store.deleteSpeech(m),
                ),
            ],
          ),
          SectionLabel('Notes AI'.tr),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'phone', icon: Icon(Icons.smartphone_rounded), label: Text('On this phone'.tr)),
                  ButtonSegment(value: 'claude', icon: Icon(Icons.cloud_outlined), label: Text('Claude')),
                ],
                selected: {_settings.notesEngine},
                onSelectionChanged: (value) => _settings.setNotesEngine(value.first),
              ),
            ),
          ),
          if (_settings.notesEngine == 'phone')
            _Group(
              intro: ('Writes summaries and flashcards, and answers questions about your lectures, '
                  'offline. Everything stays on this phone.').tr,
              icon: Icons.auto_awesome_rounded,
              color: colors.tertiary,
              selected: _settings.notesModel,
              onSelect: _settings.setNotesModel,
              options: [
                for (final m in NotesModel.values)
                  _ModelOption(
                    key: ModelStore.notesKey(m),
                    value: m.name,
                    label: m.label.tr,
                    megabytes: m.megabytes,
                    description: m.description.tr,
                    download: () => _store.downloadNotes(m),
                    delete: () => _store.deleteNotes(m),
                  ),
              ],
            )
          else
            Text(
              ('Claude writes better notes but needs internet, and the transcript is sent to Anthropic. '
              'Add your API key below.').tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.intro,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onSelect,
    required this.options,
  });

  final String intro;
  final IconData icon;
  final Color color;
  final String selected;
  final ValueChanged<String> onSelect;
  final List<_ModelOption> options;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(icon, color: color),
              const SizedBox(width: 14),
              Expanded(child: Text(intro, style: textTheme.bodySmall)),
            ],
          ),
          const SizedBox(height: 8),
          for (final option in options)
            _OptionRow(option: option, selected: option.value == selected, color: color, onSelect: () => onSelect(option.value)),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.selected, required this.color, required this.onSelect});

  final _ModelOption option;
  final bool selected;
  final Color color;
  final VoidCallback onSelect;

  String _size(int mb) => mb >= 1000 ? '${(mb / 1000).toStringAsFixed(1)} GB' : '$mb MB';

  @override
  Widget build(BuildContext context) {
    final store = ModelStore.instance;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final installed = store.isInstalled(option.key);
    final progress = store.progress(option.key);
    final error = store.error(option.key);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected ? color.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: selected ? color : colors.outline,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${option.label} · ${_size(option.megabytes)}', style: textTheme.titleSmall),
                          Text(option.description, style: textTheme.bodySmall),
                        ],
                      ),
                    ),
                    if (progress != null)
                      IconButton(
                        tooltip: 'Pause download'.tr,
                        icon: const Icon(Icons.pause_rounded),
                        onPressed: () => store.cancel(option.key),
                      )
                    else if (installed)
                      PopupMenuButton<void>(
                        tooltip: 'More'.tr,
                        itemBuilder: (_) => [
                          PopupMenuItem(onTap: option.delete, child: Text('Delete from phone'.tr)),
                        ],
                      )
                    else
                      IconButton(
                        tooltip: 'Download {name}'.trf({'name': option.label}),
                        icon: Icon(Icons.download_rounded, color: color),
                        onPressed: option.download,
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 36, right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: progress, minHeight: 6, color: color),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text('${(progress * 100).round()}%', style: tabular(textTheme.labelMedium)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 36, top: 4),
                    child: Text('Keep the app open until it finishes.'.tr, style: textTheme.bodySmall),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(left: 36, top: 6),
                    child: installed
                        ? Pill(label: 'On this phone'.tr, color: colors.secondary, icon: Icons.check_circle_rounded)
                        : Text('Not downloaded'.tr, style: textTheme.bodySmall),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 36, top: 6, right: 8),
                    child: Text(error, style: textTheme.bodySmall?.copyWith(color: colors.error)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
