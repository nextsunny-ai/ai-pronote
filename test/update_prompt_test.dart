import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/update/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeUpdateChecker implements UpdateChecker {
  @override
  Future<UpdateInfo?> check(String currentVersion) async => const UpdateInfo(
        version: '1.1.0',
        downloadUrl: 'https://example.com/update',
        notes: '필기 안정성이 개선되었습니다.',
      );
}

void main() {
  testWidgets('새 버전이 있으면 실행 후 업데이트 팝업을 표시한다', (tester) async {
    String? openedUrl;
    await tester.pumpWidget(PronoteApp(
      repository: MemoryNoteRepository(),
      updateChecker: FakeUpdateChecker(),
      currentVersion: '1.0.0',
      openExternalUrl: (url) async => openedUrl = url,
    ));

    await tester.pumpAndSettle();
    expect(find.text('새 버전이 있습니다'), findsOneWidget);
    expect(find.text('1.1.0'), findsOneWidget);
    expect(find.text('필기 안정성이 개선되었습니다.'), findsOneWidget);

    await tester.tap(find.text('업데이트 받기'));
    await tester.pumpAndSettle();
    expect(openedUrl, 'https://example.com/update');
  });
}
