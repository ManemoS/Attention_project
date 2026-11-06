import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_shell.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (family, file) in [('Space Grotesk', 'SpaceGrotesk'), ('Manrope', 'Manrope')]) {
      yield LicenseEntryWithLineBreaks([family], await rootBundle.loadString('assets/fonts/$file-OFL.txt'));
    }
  });
  // Read before the first frame, so the right theme and tabs show straight away.
  await AppSettings.instance.load();
  runApp(const AppLockApp());
}

class AppLockApp extends StatelessWidget {
  const AppLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) => MaterialApp(
        // Wording comes from `.tr`, which screens read as they build, so changing the language
        // rebuilds the whole app.
        key: ValueKey(AppSettings.instance.isThai),
        title: 'APLS',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: AppSettings.instance.themeMode,
        locale: AppSettings.instance.locale,
        supportedLocales: const [Locale('en'), Locale('th')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const AppRoot(),
      ),
    );
  }
}
