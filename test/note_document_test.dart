import 'package:ai_pronote_app/notes/note_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
