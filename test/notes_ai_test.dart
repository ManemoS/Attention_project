import 'dart:io';

import 'package:attention_project/lectures.dart';
import 'package:attention_project/notes_ai.dart';
import 'package:attention_project/transcriber.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('chunks', () {
    test('splits on sentence ends near the limit', () {
      final text = List.generate(30, (i) => 'Sentence number $i ends here.').join(' ');
      final pieces = NotesAi.chunks(text, 40);
      expect(pieces.length, greaterThan(1));
      for (final p in pieces.take(pieces.length - 1)) {
        expect(p.endsWith('.'), isTrue, reason: p);
        expect(p.split(' ').length, lessThanOrEqualTo(40));
      }
      expect(pieces.join(' '), text, reason: 'no words lost');
    });

    test('an empty transcript gives no pieces', () {
      expect(NotesAi.chunks('   ', 100), isEmpty);
    });
  });

  test('reads flashcards from whatever the model wrote around them', () {
    final cards = NotesAi.parseFlashcards('''
Sure! Here are your flashcards:
1. Q: What is inertia?
   A: An object's resistance to a change in motion.
- Question: What unit is force measured in?
- Answer: Newtons.
Q: Unanswered question
Some closing words.''');
    expect(cards.map((c) => c.question), ['What is inertia?', 'What unit is force measured in?']);
    expect(cards.last.answer, 'Newtons.');
  });

  test('finds the passage that shares the question\'s words', () async {
    final dir = await Directory.systemTemp.createTemp('ask');
    addTearDown(() => dir.delete(recursive: true));
    File('${dir.path}/1.txt').writeAsStringSync(
      '${'We covered vectors and scalars today. ' * 30}The midterm exam is on Friday and covers chapters one to three.',
    );
    File('${dir.path}/2.txt').writeAsStringSync('Photosynthesis turns light into chemical energy. ' * 20);
    final passages = await NotesAi.findPassages(
      [Lecture(dir.path, '1'), Lecture(dir.path, '2')],
      'When is the midterm exam?',
    );
    expect(passages, isNotEmpty);
    expect(passages.first.lecture.id, '1');
    expect(passages.first.text, contains('midterm exam is on Friday'));
  });

  test('reads flashcards written on one line', () {
    final cards = NotesAi.parseFlashcards('Q: What is inertia? A: Resistance to change. Q: Unit of force? A: Newtons.');
    expect(cards.map((c) => c.answer), ['Resistance to change.', 'Newtons.']);
  });

  test('notes run together on one line get a bullet per line', () {
    expect(
      NotesAi.clean('- **Newton\'s First Law**: inertia. - Second Law: F = ma. - Exam covers chapters 1-3.'),
      '- Newton\'s First Law: inertia.\n- Second Law: F = ma.\n- Exam covers chapters 1-3.',
    );
    expect(
      NotesAi.clean('Topic\n- Forces\nKey points\n- Inertia'),
      'Topic\n- Forces\n\nKey points\n- Inertia',
    );
  });

  test('transcript paragraphs break where the speaker paused', () {
    const s = [
      TranscriptSegment(from: Duration.zero, to: Duration(seconds: 3), text: 'Good morning.'),
      TranscriptSegment(from: Duration(seconds: 3), to: Duration(seconds: 6), text: 'Today, forces.'),
      TranscriptSegment(from: Duration(seconds: 12), to: Duration(seconds: 15), text: 'First, Newton.'),
    ];
    expect(Transcriber.paragraphs(s), 'Good morning. Today, forces.\n\nFirst, Newton.');
  });
}
