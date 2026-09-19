import 'dart:io';

import 'package:ai_pronote_app/notes/file_note_repository.dart';
import 'package:ai_pronote_app/notes/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('앱을 다시 열어도 노트와 필기 획이 남아 있다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-notes-');
    addTearDown(() => directory.delete(recursive: true));
    final note = NoteDocument(
      id: 'persisted-note',
      title: '현장 스케치',
      updatedAt: DateTime.utc(2026, 9, 19),
      strokes: const [
        InkStroke(
          id: 'ink-1',
          tool: InkTool.pen,
          color: 0xff1c1d1a,
          width: 4,
          points: [InkPoint(x: 10, y: 12, pressure: .7)],
        ),
      ],
    );

    await FileNoteRepository(directory).save(note);
    final reopened = await FileNoteRepository(directory).list();

    expect(reopened, [note]);
    expect(File('${directory.path}/notes.json').existsSync(), isTrue);
  });
}
