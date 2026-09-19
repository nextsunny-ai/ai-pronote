import 'package:ai_pronote_app/notes/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('텍스트 본문이 JSON 왕복 뒤에도 보존되고 구형 노트는 빈 본문으로 열린다', () {
    final note = NoteDocument(
      id: 'text-note',
      title: '받아쓰기 노트',
      body: '회의에서 확정한 텍스트 본문',
      updatedAt: DateTime.utc(2026, 9, 19),
    );

    final restored = NoteDocument.fromJson(note.toJson());
    final legacy = NoteDocument.fromJson({
      'id': 'legacy-note',
      'title': '구형 노트',
      'updatedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
      'strokes': <Object?>[],
    });

    expect(restored.body, '회의에서 확정한 텍스트 본문');
    expect(legacy.body, isEmpty);
  });

  test('필기 좌표와 압력값이 JSON 왕복 뒤에도 보존된다', () {
    final note = NoteDocument(
      id: 'note-1',
      title: '제품 회의',
      updatedAt: DateTime.utc(2026, 9, 19),
      strokes: const [
        InkStroke(
          id: 'stroke-1',
          tool: InkTool.pen,
          color: 0xff1c1d1a,
          width: 4,
          points: [
            InkPoint(x: 12, y: 24, pressure: .35),
            InkPoint(x: 40, y: 62, pressure: .9),
          ],
        ),
      ],
    );

    final restored = NoteDocument.fromJson(note.toJson());

    expect(restored, note);
    expect(restored.strokes.single.points.last.pressure, .9);
  });

  test('구형 단일 페이지 노트는 첫 페이지를 보존하며 새 형식으로 열린다', () {
    final restored = NoteDocument.fromJson({
      'schemaVersion': 1,
      'id': 'legacy-note',
      'title': '예전 노트',
      'updatedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
      'strokes': [
        {
          'id': 'legacy-ink',
          'tool': 'pen',
          'color': 0xff1c1d1a,
          'width': 4,
          'points': [
            {'x': 10, 'y': 20, 'pressure': .5},
          ],
        },
      ],
    });

    expect(restored.pages, hasLength(1));
    expect(restored.pages.single.strokes.single.id, 'legacy-ink');
    expect(restored.toJson()['pages'], isA<List<Object?>>());
  });

  test('여러 페이지의 필기 획이 JSON 왕복 뒤에도 보존된다', () {
    final note = NoteDocument(
      id: 'multi-page',
      title: '두 페이지 노트',
      updatedAt: DateTime.utc(2026, 9, 19),
      pages: const [
        NotePage(id: 'page-1'),
        NotePage(
          id: 'page-2',
          strokes: [
            InkStroke(
              id: 'ink-2',
              tool: InkTool.highlighter,
              color: 0xffffff00,
              width: 12,
              points: [InkPoint(x: 30, y: 40, pressure: .8)],
            ),
          ],
        ),
      ],
    );

    final restored = NoteDocument.fromJson(note.toJson());

    expect(restored, note);
    expect(restored.pages[1].strokes.single.id, 'ink-2');
  });

  test('페이지별 종이 종류와 배경색이 저장되고 구형 노트는 안전한 기본값을 쓴다', () {
    final note = NoteDocument(
      id: 'paper-note',
      title: '종이 설정 노트',
      updatedAt: DateTime.utc(2026, 9, 19),
      pages: const [
        NotePage(
          id: 'page-1',
          paperStyle: PaperStyle.grid,
          paperColor: 0xfff1f7f3,
        ),
        NotePage(
          id: 'page-2',
          paperStyle: PaperStyle.manuscript,
          paperColor: 0xfffff7ed,
        ),
      ],
    );

    final restored = NoteDocument.fromJson(note.toJson());
    final legacy = NoteDocument.fromJson({
      'schemaVersion': 2,
      'id': 'legacy-paper-note',
      'title': '예전 종이 노트',
      'updatedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
      'pages': [
        {'id': 'page-1', 'strokes': <Object?>[]},
      ],
    });

    expect(restored, note);
    expect(restored.pages[0].paperStyle, PaperStyle.grid);
    expect(restored.pages[1].paperColor, 0xfffff7ed);
    expect(legacy.pages.single.paperStyle, PaperStyle.blank);
    expect(legacy.pages.single.paperColor, 0xfffffdf8);
  });

  test('즐겨찾기 상태는 저장되고 구형 노트는 기본 해제 상태다', () {
    final favorite = NoteDocument(
      id: 'favorite-note',
      title: '중요 노트',
      updatedAt: DateTime.utc(2026, 9, 19),
      isFavorite: true,
    );
    final restored = NoteDocument.fromJson(favorite.toJson());
    final legacy = NoteDocument.fromJson({
      'id': 'legacy',
      'title': '구형 노트',
      'updatedAt': DateTime.utc(2026, 9, 18).toIso8601String(),
      'strokes': <Object?>[],
    });

    expect(restored.isFavorite, isTrue);
    expect(legacy.isFavorite, isFalse);
  });
}
