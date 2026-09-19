import 'dart:io';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/processing/local_meeting_processing_gateway.dart';
import 'package:ai_pronote_app/recording/video_recorder_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVideoRecorderGateway implements VideoRecorderGateway {
  bool initialized = false;
  bool recording = false;
  bool disposed = false;

  @override
  double get aspectRatio => 16 / 9;

  @override
  Widget buildPreview() => const ColoredBox(
    key: ValueKey('fake-camera-preview'),
    color: Colors.black,
  );

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> start() async {
    recording = true;
  }

  @override
  Future<String> stop(String destinationPath) async {
    recording = false;
    File(destinationPath).writeAsBytesSync([1, 2, 3]);
    return destinationPath;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakeVideoProcessingGateway implements MeetingProcessingGateway {
  String? submittedPath;

  @override
  Future<MeetingProcessingJob> submitTranscription(String recordingPath) async {
    submittedPath = recordingPath;
    return const MeetingProcessingJob(id: 'video-job', status: 'queued');
  }

  @override
  Future<MeetingProcessingJob> readJob(String jobId) async =>
      const MeetingProcessingJob(
        id: 'video-job',
        status: 'done',
        phase: '완료',
        progress: 100,
      );

  @override
  Future<MeetingProcessingResult> readResult(String jobId) async =>
      const MeetingProcessingResult(
        id: 'video-job',
        filename: 'meeting.mp4',
        transcript: '영상 회의 받아쓰기',
      );

  @override
  Future<MeetingProcessingJob> requestSummary(
    String jobId, {
    required String provider,
  }) async => const MeetingProcessingJob(
    id: 'video-job',
    status: 'done',
    summaryStatus: 'done',
  );
}

void main() {
  testWidgets('회의 기록에서 영상과 음성 모드를 선택할 수 있다', (tester) async {
    final recorder = FakeVideoRecorderGateway();
    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        videoRecorderFactory: () => recorder,
      ),
    );

    await tester.tap(find.text('회의 기록'));
    await tester.pumpAndSettle();
    expect(find.text('음성 녹음'), findsOneWidget);
    expect(find.text('영상 + 음성 녹화'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('meeting-video-mode')));
    await tester.pumpAndSettle();
    expect(recorder.initialized, isTrue);
    expect(find.byKey(const ValueKey('fake-camera-preview')), findsOneWidget);
  });

  testWidgets('영상과 음성을 녹화하며 회의 노트를 연다', (tester) async {
    final recorder = FakeVideoRecorderGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoRecordingScreen(
          recorder: recorder,
          repository: MemoryNoteRepository(),
          directoryProvider: () async => Directory.systemTemp,
          recordingValidator: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('toggle-video-recording')));
    await tester.pump();
    expect(recorder.recording, isTrue);
    expect(find.text('녹화하며 필기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-video-meeting-note')));
    await tester.pumpAndSettle();
    expect(find.textContaining('영상 회의 노트 '), findsOneWidget);
    expect(recorder.recording, isTrue);
  });

  testWidgets('영상 정지 뒤 저장 성공을 확인한다', (tester) async {
    final recorder = FakeVideoRecorderGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoRecordingScreen(
          recorder: recorder,
          repository: MemoryNoteRepository(),
          directoryProvider: () async => Directory.systemTemp,
          recordingValidator: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-video-recording')));
    await tester.pump();
    await tester.tap(find.text('녹화 정지'));
    await tester.pumpAndSettle();

    expect(recorder.recording, isFalse);
    expect(find.textContaining('영상과 음성이 기기에 저장되었습니다.'), findsOneWidget);
  });

  testWidgets('저장된 영상과 음성을 받아쓰기 작업으로 보낸다', (tester) async {
    final recorder = FakeVideoRecorderGateway();
    final processing = FakeVideoProcessingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: VideoRecordingScreen(
          recorder: recorder,
          repository: MemoryNoteRepository(),
          processingGateway: processing,
          directoryProvider: () async => Directory.systemTemp,
          recordingValidator: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-video-recording')));
    await tester.pump();
    await tester.tap(find.text('녹화 정지'));
    await tester.pumpAndSettle();

    expect(find.text('받아쓰기 시작'), findsOneWidget);
    await tester.tap(find.text('받아쓰기 시작'));
    await tester.pumpAndSettle();

    expect(processing.submittedPath, isNotNull);
    expect(find.text('받아쓰기 결과'), findsOneWidget);
    expect(find.text('영상 회의 받아쓰기'), findsOneWidget);
  });
}
