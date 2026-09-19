import 'dart:io';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/recording/audio_recorder_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAudioRecorderGateway implements AudioRecorderGateway {
  bool recording = false;
  String? savedPath;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    recording = true;
    savedPath = path;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    return savedPath;
  }
}

void main() {
  testWidgets('iPad 단독으로 회의 녹음을 시작하고 저장한다', (tester) async {
    final recorder = FakeAudioRecorderGateway();
    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        recorder: recorder,
        recordingDirectoryProvider: () async => Directory.systemTemp,
      ),
    );

    await tester.tap(find.text('회의 녹음'));
    await tester.pumpAndSettle();
    expect(find.text('녹음 시작'), findsOneWidget);

    await tester.tap(find.text('녹음 시작'));
    await tester.pumpAndSettle();
    expect(recorder.recording, isTrue);
    expect(find.text('녹음 중'), findsOneWidget);

    await tester.tap(find.text('녹음 정지'));
    await tester.pumpAndSettle();
    expect(recorder.recording, isFalse);
    expect(find.text('녹음이 기기에 저장되었습니다.'), findsOneWidget);
  });
}
