import 'package:attention_project/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatMinutes', () {
    expect(formatMinutes(45), '45 min');
    expect(formatMinutes(60), '1 h');
    expect(formatMinutes(90), '1 h 30 min');
    expect(formatMinutes(maxMinutes), '2 h');
  });

  test('formatCountdown rounds up to the next second', () {
    expect(formatCountdown(const Duration(seconds: 65)), '1:05');
    expect(formatCountdown(const Duration(milliseconds: 64001)), '1:05');
    expect(formatCountdown(const Duration(hours: 1, minutes: 4, seconds: 5)), '1:04:05');
  });
}
