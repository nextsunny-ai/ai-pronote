import 'dart:io';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/processing/local_meeting_processing_gateway.dart';
import 'package:ai_pronote_app/processing/file_processing_job_repository.dart';
import 'package:ai_pronote_app/recording/audio_recorder_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAudioRecorderGateway implements AudioRecorderGateway {
  bool recording = false;
  bool paused = false;
  String? savedPath;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(String path) async {
    recording = true;
    savedPath = path;
    File(path).writeAsBytesSync([1, 2, 3]);
  }

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> resume() async {
    paused = false;
  }

  @override
  Future<String?> stop() async {
    recording = false;
    return savedPath;
  }
}

class FakeMeetingProcessingGateway implements MeetingProcessingGateway {
  String? submittedPath;

  @override
  Future<MeetingProcessingJob> submitTranscription(String recordingPath) async {
    submittedPath = recordingPath;
    return const MeetingProcessingJob(id: 'job-123', status: 'queued');
  }

  @override
  Future<MeetingProcessingJob> readJob(String jobId) async =>
      const MeetingProcessingJob(
        id: 'job-123',
        status: 'done',
        phase: '완료',
        progress: 100,
      );

  @override
  Future<MeetingProcessingResult> readResult(String jobId) async =>
      const MeetingProcessingResult(
        id: 'job-123',
        filename: 'meeting.m4a',
        transcript: '테스트 받아쓰기',
      );
}

class FakeProcessingJobRepository implements ProcessingJobRepository {
  final List<ProcessingJobRecord> records = [];

  @override
  Future<List<ProcessingJobRecord>> list() async => List.of(records);

  @override
  Future<void> save(ProcessingJobRecord record) async {
    records.removeWhere((item) => item.jobId == record.jobId);
    records.add(record);
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
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('meeting-audio-mode')));
    await tester.pumpAndSettle();
    expect(find.text('녹음 시작'), findsOneWidget);

    await tester.tap(find.text('녹음 시작'));
    await tester.pumpAndSettle();
    expect(recorder.recording, isTrue);
    expect(find.text('녹음 중'), findsOneWidget);

    await tester.tap(find.text('녹음 정지'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    expect(recorder.recording, isFalse);
    expect(find.textContaining('녹음이 기기에 저장되었습니다.'), findsOneWidget);
  });

  testWidgets('회의 녹음을 일시정지하고 다시 이어서 녹음한다', (tester) async {
    final recorder = FakeAudioRecorderGateway();
    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        recorder: recorder,
        recordingDirectoryProvider: () async => Directory.systemTemp,
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('meeting-audio-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('pause-recording')));
    await tester.pump();
    expect(recorder.paused, isTrue);
    expect(find.text('계속 녹음'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pause-recording')));
    await tester.pump();
    expect(recorder.paused, isFalse);
    expect(find.text('일시정지'), findsOneWidget);
  });

  testWidgets('저장된 녹음을 로그인 없이 받아쓰기 작업으로 보낸다', (tester) async {
    final recorder = FakeAudioRecorderGateway();
    final processing = FakeMeetingProcessingGateway();
    final jobs = FakeProcessingJobRepository();
    final notes = MemoryNoteRepository();
    await tester.pumpWidget(
      PronoteApp(
        repository: notes,
        recorder: recorder,
        processingGateway: processing,
        processingJobRepository: jobs,
        recordingDirectoryProvider: () async => Directory.systemTemp,
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('meeting-audio-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    await tester.tap(find.text('녹음 정지'));
    await tester.pumpAndSettle();

    expect(find.text('받아쓰기 시작'), findsOneWidget);
    await tester.tap(find.text('받아쓰기 시작'));
    await tester.pumpAndSettle();

    expect(processing.submittedPath, recorder.savedPath);
    expect(find.text('받아쓰기 결과'), findsOneWidget);
    expect(find.text('테스트 받아쓰기'), findsOneWidget);
    expect(jobs.records.single.jobId, 'job-123');
    expect(jobs.records.single.recordingPath, recorder.savedPath);
    expect(find.text('노트로 저장'), findsOneWidget);
    await tester.tap(find.text('노트로 저장'));
    await tester.pumpAndSettle();
    expect((await notes.list()).single.body, '테스트 받아쓰기');
  });

  testWidgets('녹음 중 회의 노트를 열어 필기를 계속할 수 있다', (tester) async {
    final recorder = FakeAudioRecorderGateway();
    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        recorder: recorder,
        recordingDirectoryProvider: () async => Directory.systemTemp,
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 기록'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('meeting-audio-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('녹음 시작'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('open-meeting-note')));
    await tester.pumpAndSettle();

    expect(find.textContaining('회의 노트 '), findsOneWidget);
    expect(recorder.recording, isTrue);
  });

  testWidgets('앱을 다시 열면 저장된 받아쓰기 작업을 홈에서 복구한다', (tester) async {
    final processing = FakeMeetingProcessingGateway();
    final jobs = FakeProcessingJobRepository()
      ..records.add(
        ProcessingJobRecord(
          jobId: 'job-123',
          recordingPath: 'meeting.m4a',
          createdAt: DateTime.utc(2026, 9, 19),
        ),
      );

    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        processingGateway: processing,
        processingJobRepository: jobs,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('지난 받아쓰기 작업'), findsOneWidget);
    expect(find.text('meeting.m4a'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('resume-job-job-123')));
    await tester.pumpAndSettle();

    expect(find.text('받아쓰기 결과'), findsOneWidget);
    expect(find.text('테스트 받아쓰기'), findsOneWidget);
  });
}
