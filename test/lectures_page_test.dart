import 'dart:io';

import 'package:attention_project/lectures.dart';
import 'package:attention_project/lectures_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lectures_page_test');
    // Two recordings: 9 Nov 2026 and 10 Nov 2026 (local time).
    File('${dir.path}/${DateTime(2026, 11, 9, 9).millisecondsSinceEpoch}.txt').writeAsStringSync('first lecture');
    File('${dir.path}/${DateTime(2026, 11, 10, 9).millisecondsSinceEpoch}.txt').writeAsStringSync('second one');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('attention_project/app_lock'),
      (call) async => call.method == 'getLecturesDir' ? dir.path : null,
    );
    LectureLibrary.resetForTest();
  });

  tearDown(() => dir.delete(recursive: true));

  /// Pumps frames while letting real file reads and writes finish.
  Future<void> settle(WidgetTester tester) async {
    // Each file step only finishes on a real event-loop turn, so alternate real waits and pumps.
    for (var i = 0; i < 60; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
    // The loading spinner never settles, so only wait for animations once it's gone.
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpAndSettle();
  }

  const nov9 = 'Mon, Nov 9, 9:00 AM';
  const nov10 = 'Tue, Nov 10, 9:00 AM';

  testWidgets('make a folder, file a recording, trash and restore one', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LecturesPage()));
    await settle(tester);
    expect(find.text(nov10), findsOneWidget);
    expect(find.text(nov9), findsOneWidget);

    // New folder.
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Physics');
    await tester.tap(find.text('Create'));
    await settle(tester);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('0 recordings'), findsOneWidget);

    // Move the 9 Nov recording into it with the ⋮ menu.
    final nov9Tile = find.ancestor(of: find.text(nov9), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: nov9Tile, matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Physics').last);
    await settle(tester);
    expect(find.text('1 recording'), findsOneWidget);
    expect(find.text(nov9), findsNothing, reason: 'it left Unsorted');

    // Swipe the other one into the trash, then undo.
    await tester.drag(find.text(nov10), const Offset(-600, 0));
    await settle(tester);
    expect(find.text('Moved to trash'), findsOneWidget);
    expect(find.text(nov10), findsNothing);
    expect(find.textContaining('1 recording · deleted for good'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text(nov10), findsOneWidget);

    // Open the folder; the recording is there.
    await tester.tap(find.text('Physics'));
    await settle(tester);
    expect(find.text(nov9), findsOneWidget);
  });
}
