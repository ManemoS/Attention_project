import 'dart:convert';

import 'package:attention_project/backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('settings round-trip through a backup, without the API key', () async {
    SharedPreferences.setMockInitialValues({
      'user_role': 'lecturer',
      'buzz_before_end': false,
      'lesson_plans': '[{"id":"p1"}]',
      'dismissed_plan_suggestions': ['p1:1:24'],
      'claude_api_key': 'sk-ant-secret',
      'model_index': 'qwen.task',
    });
    final json = await AppBackup.settingsJson();
    expect(json, isNot(contains('sk-ant-secret')));
    expect((jsonDecode(json) as Map).keys, isNot(contains('claude_api_key')));
    expect((jsonDecode(json) as Map).keys, isNot(contains('model_index')));

    SharedPreferences.setMockInitialValues({'claude_api_key': 'kept-on-this-phone'});
    await AppBackup.applySettings(json);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('user_role'), 'lecturer');
    expect(prefs.getBool('buzz_before_end'), isFalse);
    expect(prefs.getString('lesson_plans'), '[{"id":"p1"}]');
    expect(prefs.getStringList('dismissed_plan_suggestions'), ['p1:1:24']);
    expect(prefs.getString('claude_api_key'), 'kept-on-this-phone');
  });
}
