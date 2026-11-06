import 'dart:io';

import 'package:attention_project/app_lock.dart';
import 'package:attention_project/l10n.dart';
import 'package:attention_project/lesson_plan.dart';
import 'package:attention_project/lesson_plans_page.dart';
import 'package:attention_project/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('every translated text in the app has a Thai version', () {
    final literal = RegExp(r"""(?:'((?:[^'\\\n]|\\.)*)'|"((?:[^"\\\n]|\\.)*)")\s*\.tr(?:f\b|\b)""");
    final missing = <String>[];
    final files = Directory('lib').listSync().whereType<File>().where(
          // The dictionary itself mentions `.tr` in its comments.
          (f) => f.path.endsWith('.dart') && !f.path.endsWith('l10n.dart'),
        );
    for (final file in files) {
      for (final m in literal.allMatches(file.readAsStringSync())) {
        final text = (m[1] ?? m[2]!).replaceAllMapped(RegExp(r'\\(.)'), (e) => e[1]!);
        if (!thaiKeys.contains(text)) missing.add('${file.path}: $text');
      }
    }
    expect(missing, isEmpty);
  });

  group('in Thai', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'app_language': 'th'});
      await AppSettings.instance.load();
    });
    tearDown(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.instance.load();
    });

    test('durations and class timing read in Thai', () {
      expect(formatMinutes(90), '1 ชม. 30 นาที');
      expect(formatMinutes(45), '45 นาที');
      expect(describeDrift(const Duration(minutes: 3)), 'ช้ากว่าแผน 3 นาที');
      expect(describeFinish(Duration.zero), 'จบตรงเวลา');
      expect('Nothing in the dictionary'.tr, 'Nothing in the dictionary', reason: 'missing ones stay English');
    });

    testWidgets('the Class tab shows Thai', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LessonPlansPage()));
      await tester.pumpAndSettle();
      expect(find.text('จับเวลาคลาส'), findsOneWidget);
      expect(find.text('แผนใหม่'), findsOneWidget);
      expect(find.text('วางแผนคลาสแรก'), findsOneWidget);
    });
  });

  test('English is used by default', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    expect(isThai, isFalse);
    expect('Focus'.tr, 'Focus');
  });
}
