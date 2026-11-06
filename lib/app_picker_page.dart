import 'package:flutter/material.dart';

import 'app_lock.dart';
import 'ui.dart';
import 'l10n.dart';

/// Lets the user tick which installed apps to lock. Pops with a package -> name map.
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.initial});

  final Map<String, String> initial;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  late final Future<List<InstalledApp>> _apps = AppLock.installedApps();
  late final Map<String, String> _selected = {...widget.initial};
  String _query = '';

  void _toggle(InstalledApp app) => setState(() {
        if (_selected.remove(app.packageName) == null) _selected[app.packageName] = app.name;
      });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = _selected.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Choose apps'.tr),
        actions: [
          if (count > 0)
            TextButton(onPressed: () => setState(_selected.clear), child: Text('Clear'.tr)),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: Text(count == 0
                ? 'Done'.tr
                : 'Done · {apps}'.trf({'apps': count == 1 ? '1 app'.tr : '{n} apps'.trf({'n': count})})),
          ),
        ),
      ),
      body: FutureBuilder<List<InstalledApp>>(
        future: _apps,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline_rounded,
              color: colors.error,
              title: 'Could not load apps'.tr,
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final query = _query.toLowerCase();
          final apps = snapshot.data!.where((app) => app.name.toLowerCase().contains(query)).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Search apps'.tr,
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: apps.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No apps match'.tr,
                        message: 'Nothing installed is called "{query}".'.trf({'query': _query}),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: apps.length,
                        itemBuilder: (context, index) => _AppRow(
                          app: apps[index],
                          selected: _selected.containsKey(apps[index].packageName),
                          onTap: () => _toggle(apps[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.selected, required this.onTap});

  final InstalledApp app;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        checked: selected,
        child: ListTile(
          onTap: onTap,
          selected: selected,
          selectedTileColor: colors.primary.withValues(alpha: 0.10),
          selectedColor: colors.onSurface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: app.icon == null
                ? IconBadge(Icons.apps_rounded, color: colors.onSurfaceVariant)
                : Image.memory(app.icon!, width: 44, height: 44, gaplessPlayback: true),
          ),
          title: Text(app.name),
          subtitle: Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? colors.primary : Colors.transparent,
              border: Border.all(color: selected ? colors.primary : colors.outline, width: 2),
            ),
            child: selected ? Icon(Icons.check_rounded, size: 18, color: colors.onPrimary) : null,
          ),
        ),
      ),
    );
  }
}
