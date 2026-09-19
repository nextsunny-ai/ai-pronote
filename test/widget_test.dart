import 'dart:ui';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('첫 화면에서 노트와 회의 기록을 바로 시작한다', (tester) async {
    await tester.pumpWidget(PronoteApp(repository: MemoryNoteRepository()));

    expect(find.text('AI PRONOTE'), findsOneWidget);
    expect(find.text('새 노트'), findsOneWidget);
    expect(find.text('회의 녹음'), findsOneWidget);
    expect(find.text('최근 노트'), findsOneWidget);
  });

  testWidgets('새 노트에서 스타일러스 획을 그리고 자동 저장한다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();

    expect(find.text('펜'), findsOneWidget);
    expect(find.text('형광펜'), findsOneWidget);
    expect(find.text('지우개'), findsOneWidget);
    expect(find.byKey(const ValueKey('ink-canvas')), findsOneWidget);

    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final gesture = await tester.createGesture(pointer: 7, kind: PointerDeviceKind.stylus);
    await gesture.down(center - const Offset(80, 40));
    await gesture.moveTo(center + const Offset(90, 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final notes = await repository.list();
    expect(notes, hasLength(1));
    expect(notes.single.strokes, hasLength(1));
    expect(notes.single.strokes.single.points.length, greaterThanOrEqualTo(2));
  });
}
