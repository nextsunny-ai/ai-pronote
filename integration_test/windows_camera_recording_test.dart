import 'package:ai_pronote_app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows 실제 카메라와 마이크로 영상 회의를 저장한다', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.text('회의 기록'));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('meeting-video-mode')));

    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      final button = tester.widgetList<FilledButton>(
        find.byKey(const ValueKey('toggle-video-recording')),
      );
      if (button.isNotEmpty && button.single.onPressed != null) break;
    }

    final startButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('toggle-video-recording')),
    );
    expect(startButton.onPressed, isNotNull, reason: '카메라 초기화에 실패했습니다.');

    await tester.tap(find.byKey(const ValueKey('toggle-video-recording')));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('녹화 정지'), findsOneWidget);

    await tester.tap(find.text('녹화 정지'));
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 500));
      if (find.textContaining('영상과 음성이 기기에 저장되었습니다.').evaluate().isNotEmpty) {
        break;
      }
    }

    expect(find.textContaining('영상과 음성이 기기에 저장되었습니다.'), findsOneWidget);
  });
}
