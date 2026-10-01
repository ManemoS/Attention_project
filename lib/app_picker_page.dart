import 'package:flutter/material.dart';

import 'app_lock.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose apps'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: Text('Done (${_selected.length})'),
          ),
        ],
      ),
      body: FutureBuilder<List<InstalledApp>>(
        future: _apps,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Could not load apps: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final query = _query.toLowerCase();
          final apps = snapshot.data!
              .where((app) => app.name.toLowerCase().contains(query))
              .toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search apps',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return CheckboxListTile(
                      value: _selected.containsKey(app.packageName),
                      secondary: app.icon == null
                          ? const Icon(Icons.apps, size: 40)
                          : Image.memory(app.icon!, width: 40, height: 40),
                      title: Text(app.name),
                      subtitle: Text(app.packageName, style: Theme.of(context).textTheme.bodySmall),
                      onChanged: (checked) => setState(() {
                        if (checked ?? false) {
                          _selected[app.packageName] = app.name;
                        } else {
                          _selected.remove(app.packageName);
                        }
                      }),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
