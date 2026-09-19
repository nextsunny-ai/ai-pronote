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

  test('주 저장 파일이 사라지면 마지막 정상 백업에서 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pronote-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileNoteRepository(directory);
    final first = NoteDocument(
      id: 'safe-note',
      title: '잃어버리면 안 되는 노트',
      updatedAt: DateTime.utc(2026, 9, 19),
    );
    await repository.save(first);
    await repository.save(first.copyWith(title: '최신 노트'));

    final main = File('${directory.path}${Platform.pathSeparator}notes.json');
    final backup = File('${main.path}.bak');
    expect(await backup.exists(), isTrue);
    await main.delete();

    final recovered = await FileNoteRepository(directory).list();

    expect(recovered, hasLength(1));
    expect(recovered.single.title, '잃어버리면 안 되는 노트');
    expect(await main.exists(), isTrue);
    expect(await backup.exists(), isTrue);
  });

  test('주 저장 파일이 손상되면 정상 백업을 보존하며 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-corrupt-');
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileNoteRepository(directory);
    final first = NoteDocument(
      id: 'safe-note',
      title: '백업 원본',
      updatedAt: DateTime.utc(2026, 9, 19),
    );
    await repository.save(first);
    await repository.save(first.copyWith(title: '두 번째 저장'));

    final main = File('${directory.path}${Platform.pathSeparator}notes.json');
    await main.writeAsString('{손상된 JSON', flush: true);

    final recovered = await FileNoteRepository(directory).list();

    expect(recovered, hasLength(1));
    expect(recovered.single.title, '백업 원본');
    expect(
      directory.listSync().whereType<File>().any(
        (file) => file.path.contains('notes.json.corrupt.'),
      ),
      isTrue,
    );
  });
}
