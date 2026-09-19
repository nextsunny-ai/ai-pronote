import 'dart:ui';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/notes/note_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

void main() {
  testWidgets('첫 화면에서 노트와 회의 기록을 바로 시작한다', (tester) async {
    await tester.pumpWidget(PronoteApp(repository: MemoryNoteRepository()));

    expect(find.text('AI PRONOTE'), findsOneWidget);
    expect(find.text('버전 1.0'), findsOneWidget);
    expect(find.text('새 노트'), findsOneWidget);
    expect(find.text('회의 녹음'), findsOneWidget);
    expect(find.text('내 노트'), findsOneWidget);
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
    final gesture = await tester.createGesture(
      pointer: 7,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.down(center - const Offset(80, 40));
    await gesture.moveTo(center + const Offset(90, 60));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final notes = await repository.list();
    expect(notes, hasLength(1));
    expect(notes.single.strokes, hasLength(1));
    expect(notes.single.strokes.single.points.length, greaterThanOrEqualTo(2));
  });

  testWidgets('최근 노트를 눌러 저장된 노트를 다시 연다', (tester) async {
    final repository = MemoryNoteRepository();
    await repository.save(
      NoteDocument(
        id: 'saved-note',
        title: '제품 회의 노트',
        updatedAt: DateTime(2026, 9, 19),
      ),
    );

    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제품 회의 노트'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ink-canvas')), findsOneWidget);
    expect(find.text('제품 회의 노트'), findsOneWidget);
  });

  testWidgets('필기 획을 실행 취소하고 다시 실행한다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final gesture = await tester.createGesture(
      pointer: 8,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.down(center - const Offset(30, 10));
    await gesture.moveTo(center + const Offset(30, 10));
    await gesture.up();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('undo-ink')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.list()).single.strokes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('redo-ink')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.list()).single.strokes, hasLength(1));
  });

  testWidgets('지우개로 닿은 필기 획을 삭제한다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final pen = await tester.createGesture(
      pointer: 9,
      kind: PointerDeviceKind.stylus,
    );
    await pen.down(center - const Offset(20, 0));
    await pen.moveTo(center + const Offset(20, 0));
    await pen.up();
    await tester.tap(find.text('지우개'));
    await tester.pump();
    final eraser = await tester.createGesture(
      pointer: 10,
      kind: PointerDeviceKind.stylus,
    );
    await eraser.down(center);
    await eraser.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect((await repository.list()).single.strokes, isEmpty);
  });

  testWidgets('손가락 필기가 꺼져 있으면 터치가 필기 획으로 저장되지 않는다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final touch = await tester.createGesture(
      pointer: 11,
      kind: PointerDeviceKind.touch,
    );

    await touch.down(center - const Offset(20, 0));
    await touch.moveTo(center + const Offset(20, 0));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect((await repository.list()).single.strokes, isEmpty);
    expect(find.text('손가락 이동'), findsOneWidget);
  });

  testWidgets('손가락 필기를 켜면 터치로 필기할 수 있다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('finger-drawing-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('finger-drawing-toggle')));
    await tester.pump();
    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final touch = await tester.createGesture(
      pointer: 12,
      kind: PointerDeviceKind.touch,
    );

    await touch.down(center - const Offset(20, 0));
    await touch.moveTo(center + const Offset(20, 0));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect((await repository.list()).single.strokes, hasLength(1));
    expect(find.text('손가락 필기'), findsOneWidget);
  });

  testWidgets('새 페이지를 추가하고 각 페이지 필기를 따로 저장한다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('add-page')));
    await tester.pump();
    expect(find.text('2/2 페이지'), findsOneWidget);

    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final pencil = await tester.createGesture(
      pointer: 13,
      kind: PointerDeviceKind.stylus,
    );
    await pencil.down(center - const Offset(20, 0));
    await pencil.moveTo(center + const Offset(20, 0));
    await pencil.up();
    await tester.pump(const Duration(milliseconds: 400));

    final saved = (await repository.list()).single;
    expect(saved.pages, hasLength(2));
    expect(saved.pages.first.strokes, isEmpty);
    expect(saved.pages.last.strokes, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('duplicate-page')));
    await tester.pump(const Duration(milliseconds: 400));
    final duplicated = (await repository.list()).single;
    expect(duplicated.pages, hasLength(3));
    expect(duplicated.pages.last.strokes, hasLength(1));
    expect(find.text('3/3 페이지'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('delete-page')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.list()).single.pages, hasLength(2));
    expect(find.text('2/2 페이지'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('previous-page')));
    await tester.pump();
    expect(find.text('1/2 페이지'), findsOneWidget);
  });

  testWidgets('보관함에서 제목으로 노트를 검색한다', (tester) async {
    final repository = MemoryNoteRepository();
    await repository.save(
      NoteDocument(
        id: 'design-note',
        title: '디자인 회의',
        updatedAt: DateTime(2026, 9, 19),
      ),
    );
    await repository.save(
      NoteDocument(
        id: 'budget-note',
        title: '예산 검토',
        updatedAt: DateTime(2026, 9, 18),
      ),
    );
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('note-search')), '디자인');
    await tester.pump();

    expect(find.text('디자인 회의'), findsOneWidget);
    expect(find.text('예산 검토'), findsNothing);
  });

  testWidgets('편집기에서 바꾼 노트 제목을 자동 저장한다', (tester) async {
    final repository = MemoryNoteRepository();
    await repository.save(
      NoteDocument(
        id: 'rename-note',
        title: '제목 없는 노트',
        updatedAt: DateTime(2026, 9, 19),
      ),
    );
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제목 없는 노트'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('note-title-field')),
      '신제품 회의',
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect((await repository.list()).single.title, '신제품 회의');
  });

  testWidgets('올가미로 필기 획을 선택해 복제하고 삭제한다', (tester) async {
    final repository = MemoryNoteRepository();
    await tester.pumpWidget(PronoteApp(repository: repository));
    await tester.tap(find.text('새 노트'));
    await tester.pumpAndSettle();
    final canvas = find.byKey(const ValueKey('ink-canvas'));
    final center = tester.getCenter(canvas);
    final pencil = await tester.createGesture(
      pointer: 14,
      kind: PointerDeviceKind.stylus,
    );
    await pencil.down(center - const Offset(15, 0));
    await pencil.moveTo(center + const Offset(15, 0));
    await pencil.up();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('올가미'));
    await tester.pump();
    final lasso = await tester.createGesture(
      pointer: 15,
      kind: PointerDeviceKind.stylus,
    );
    await lasso.down(center - const Offset(40, 40));
    await lasso.moveTo(center + const Offset(40, 40));
    await lasso.up();
    await tester.pump();

    final beforeMove =
        (await repository.list()).single.strokes.single.points.first.x;
    final move = await tester.createGesture(
      pointer: 16,
      kind: PointerDeviceKind.stylus,
    );
    await move.down(center);
    await move.moveTo(center + const Offset(30, 10));
    await move.up();
    await tester.pump(const Duration(milliseconds: 400));
    final afterMove =
        (await repository.list()).single.strokes.single.points.first.x;
    expect(afterMove, greaterThan(beforeMove));

    await tester.tap(find.byKey(const ValueKey('duplicate-selection')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.list()).single.strokes, hasLength(2));

    await tester.tap(find.byKey(const ValueKey('delete-selection')));
    await tester.pump(const Duration(milliseconds: 400));
    expect((await repository.list()).single.strokes, hasLength(1));
  });
}
