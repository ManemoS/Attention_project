import 'package:attention_project/timetable.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimetableEntry entry(String id, int day, String start, String end, {String course = 'Physics'}) {
  int m(String t) => int.parse(t.split(':')[0]) * 60 + int.parse(t.split(':')[1]);
  return TimetableEntry(id: id, weekday: day, start: m(start), end: m(end), course: course);
}

void main() {
  test('checks a class before it is saved', () {
    final others = [entry('a', 1, '9:00', '10:30', course: 'Maths')];
    expect(timetableProblem(entry('b', 1, '11:00', '12:00'), others), isNull);
    expect(timetableProblem(entry('b', 2, '9:30', '10:00'), others), isNull, reason: 'another day');
    expect(timetableProblem(entry('b', 1, '10:00', '11:00'), others), 'It overlaps Maths (9:00–10:30).');
    expect(timetableProblem(entry('a', 1, '9:00', '11:00'), others), isNull, reason: 'editing itself');
    expect(timetableProblem(entry('b', 1, '12:00', '11:00'), others), 'The class has to end after it starts.');
    expect(timetableProblem(entry('b', 1, '11:00', '12:00', course: ' '), others), 'Give the class a name.');
  });

  test('saving keeps the classes in week order and sends them to Android', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <MethodCall>[];
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('attention_project/app_lock'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
    await TimetableStore.save(
      entries: [entry('b', 3, '14:00', '15:00'), entry('a', 1, '9:00', '10:00'), entry('c', 1, '8:00', '8:50')],
      enabled: true,
      packages: ['com.ig'],
      strict: false,
      code: '1234',
    );
    expect((await TimetableStore.entries()).map((e) => e.id), ['c', 'a', 'b']);
    expect(await TimetableStore.enabled(), isTrue);
    final sent = calls.single;
    expect(sent.method, 'setTimetable');
    expect(sent.arguments['code'], '1234');
    expect(sent.arguments['packages'], ['com.ig']);
  });

  test('formats times on a 24-hour clock', () {
    expect(formatTimeOfDay(9 * 60 + 5), '9:05');
    expect(formatTimeOfDay(13 * 60 + 30), '13:30');
  });
}
