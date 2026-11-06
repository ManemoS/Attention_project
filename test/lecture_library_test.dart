import 'dart:convert';
import 'dart:io';

import 'package:attention_project/lectures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  File file(String name) => File('${dir.path}/$name');

  Future<LectureLibrary> reopen() {
    LectureLibrary.resetForTest();
    return LectureLibrary.open();
  }

  Lecture byId(LectureLibrary library, String id) => library.lectures.firstWhere((l) => l.id == id);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lectures_test');
    file('1000.txt').writeAsStringSync('hello world');
    file('2000.txt').writeAsStringSync('');
    file('3000.txt').writeAsStringSync('one two three');
    file('3000.summary.txt').writeAsStringSync('notes');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('attention_project/app_lock'),
      (call) async => call.method == 'getLecturesDir' ? dir.path : null,
    );
  });

  tearDown(() => dir.delete(recursive: true));

  test('lists lectures newest first with word counts', () async {
    final library = await reopen();
    expect(library.lectures.map((l) => l.id), ['3000', '2000', '1000']);
    expect(library.info['3000']!.words, 3);
    expect(library.info['3000']!.summarized, isTrue);
    expect(library.info['1000']!.words, 2);
    expect(library.info['1000']!.summarized, isFalse);
    expect(library.inFolder(null), hasLength(3));
  });

  test('audio recordings count as lectures, with their bookmarks and length', () async {
    file('5000.m4a').writeAsBytesSync([0, 0, 0]);
    file('5000.json').writeAsStringSync(jsonEncode({'marks': [60000, 120000], 'durationMs': 2520000}));
    final library = await reopen();
    expect(library.lectures.first.id, '5000');
    final info = library.info['5000']!;
    expect(info.hasAudio, isTrue);
    expect(info.transcribed, isFalse);
    expect(info.marks, 2);
    expect(info.duration, const Duration(minutes: 42));
    expect((await byId(library, '5000').readMeta()).marks.last, const Duration(minutes: 2));
  });

  test('a timetable recording is filed into its course folder once', () async {
    file('6000.m4a').writeAsBytesSync([0]);
    file('6000.json').writeAsStringSync(jsonEncode({'course': 'Physics 101', 'durationMs': 1000}));
    var library = await reopen();
    expect(library.folders, ['Physics 101']);
    expect(library.folderOf(byId(library, '6000')), 'Physics 101');

    // Moving it out sticks: it isn't put back on the next refresh.
    await library.moveTo(byId(library, '6000'), null);
    library = await reopen();
    expect(library.folderOf(byId(library, '6000')), isNull);
  });

  test('deleting an audio lecture removes every file it has', () async {
    for (final f in ['7000.m4a', '7000.json', '7000.txt', '7000.segments.json', '7000.cards.json', '7000.part.wav']) {
      file(f).writeAsStringSync('x');
    }
    final library = await reopen();
    await library.deleteForever(byId(library, '7000'));
    expect(dir.listSync().map((e) => e.uri.pathSegments.last).where((n) => n.startsWith('7000')), isEmpty);
  });

  test('folders: move, rename, delete, and it all survives a restart', () async {
    var library = await reopen();
    await library.createFolder('  Physics ');
    expect(library.folders, ['Physics']);
    expect(library.folderNameProblem('physics'), isNotNull);
    expect(library.folderNameProblem(''), isNotNull);
    expect(library.folderNameProblem('Physics', renaming: 'Physics'), isNull);

    await library.moveTo(byId(library, '1000'), 'Physics');
    expect(library.inFolder('Physics').map((l) => l.id), ['1000']);
    expect(library.inFolder(null).map((l) => l.id), ['3000', '2000']);

    await library.renameFolder('Physics', 'Physics 101');
    library = await reopen();
    expect(library.folders, ['Physics 101']);
    expect(library.folderOf(byId(library, '1000')), 'Physics 101');

    await library.deleteFolder('Physics 101');
    expect(library.folders, isEmpty);
    expect(library.inFolder(null), hasLength(3));
    expect(file('1000.txt').existsSync(), isTrue, reason: 'deleting a folder keeps its recordings');
  });

  test('trash: restore puts a lecture back in its folder', () async {
    final library = await reopen();
    await library.createFolder('Maths');
    final lecture = byId(library, '3000');
    await library.moveTo(lecture, 'Maths');

    await library.moveToTrash(lecture);
    expect(library.trash, [lecture]);
    expect(library.inFolder('Maths'), isEmpty);
    expect(library.daysLeftInTrash(lecture), LectureLibrary.trashDays);

    await library.restore(lecture);
    expect(library.trash, isEmpty);
    expect(library.inFolder('Maths'), [lecture]);
  });

  test('delete forever and empty trash remove the files', () async {
    final library = await reopen();
    await library.deleteForever(byId(library, '3000'));
    expect(file('3000.txt').existsSync(), isFalse);
    expect(file('3000.summary.txt').existsSync(), isFalse);

    await library.moveToTrash(byId(library, '1000'));
    await library.moveToTrash(byId(library, '2000'));
    await library.emptyTrash();
    expect(library.lectures, isEmpty);
    expect(file('1000.txt').existsSync(), isFalse);
    expect(file('2000.txt').existsSync(), isFalse);
  });

  test('lectures in the trash longer than the limit are deleted on open', () async {
    final old = DateTime.now().subtract(const Duration(days: LectureLibrary.trashDays + 1));
    file('library.json').writeAsStringSync(jsonEncode({
      'folders': ['Gone'],
      'folderOf': {'1000': 'Gone', '9999': 'Gone'},
      'trashedAt': {'2000': old.millisecondsSinceEpoch, '3000': DateTime.now().millisecondsSinceEpoch},
    }));

    final library = await reopen();
    expect(file('2000.txt').existsSync(), isFalse);
    expect(library.lectures.map((l) => l.id), ['3000', '1000']);
    expect(library.trash.map((l) => l.id), ['3000']);
    expect(library.folderOf(byId(library, '1000')), 'Gone');
  });

  test('a damaged library file keeps the recordings', () async {
    file('library.json').writeAsStringSync('{not json');
    final library = await reopen();
    expect(library.lectures, hasLength(3));
    expect(library.folders, isEmpty);
  });
}
