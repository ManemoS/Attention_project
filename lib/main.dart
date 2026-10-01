import 'package:flutter/material.dart';

import 'home_page.dart';

void main() {
  runApp(const AppLockApp());
}

class AppLockApp extends StatelessWidget {
  const AppLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Lock',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark),
      home: const HomePage(),
    );
  }
}
