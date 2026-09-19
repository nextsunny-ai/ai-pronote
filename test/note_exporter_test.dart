import 'dart:convert';
import 'dart:io';

import 'package:ai_pronote_app/notes/note_document.dart';
import 'package:ai_pronote_app/notes/note_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Markdown 문서와 전체 필기 복구용 원본을 함께 내보낸다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pronote-note-export-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final note = NoteDocument(
      id: 'note-1',
      title: '제품 / 회의',
      body: '결정 사항\n- 다음 주 출시',
      updatedAt: DateTime.utc(2026, 9, 19, 9, 30),
      pages: const [
        NotePage(
          id: 'page-1',
          strokes: [
            InkStroke(
              id: 'ink-1',
              tool: InkTool.pen,
              color: 0xff111111,
              width: 4,
              points: [InkPoint(x: 10, y: 20, pressure: .8)],
            ),
          ],
        ),
      ],
    );

    final result = await NoteExporter(() async => directory).export(note);

    expect(result.markdownPath, endsWith('.md'));
    expect(result.archivePath, endsWith('.pronote.json'));
    final markdown = await File(result.markdownPath).readAsString();
    expect(markdown, contains('# 제품 / 회의'));
    expect(markdown, contains('결정 사항'));
    expect(markdown, contains('필기 1획'));
    final archive = jsonDecode(
      await File(result.archivePath).readAsString(),
    ) as Map<String, Object?>;
    expect(NoteDocument.fromJson(archive), note);
    expect(File(result.markdownPath).uri.pathSegments.last, isNot(contains('/')));
  });

  test('빈 제목과 본문도 안전한 파일 이름으로 내보낸다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pronote-empty-export-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final note = NoteDocument(
      id: 'empty-note',
      title: '   ',
      updatedAt: DateTime.utc(2026, 9, 19),
    );

    final result = await NoteExporter(() async => directory).export(note);

    expect(File(result.markdownPath).uri.pathSegments.last, startsWith('제목 없는 노트_'));
    expect(await File(result.markdownPath).readAsString(), contains('작성된 텍스트가 없습니다.'));
  });
}
