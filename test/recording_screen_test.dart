import 'dart:io';

import 'package:ai_pronote_app/main.dart';
import 'package:ai_pronote_app/notes/note_repository.dart';
import 'package:ai_pronote_app/processing/local_meeting_processing_gateway.dart';
import 'package:ai_pronote_app/processing/transcript_exporter.dart';
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
  String? requestedSummaryProvider;

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
      MeetingProcessingResult(
        id: 'job-123',
        filename: 'meeting.m4a',
        transcript: '테스트 받아쓰기',
        summaryTitle: requestedSummaryProvider == null ? '' : '주간 회의',
        summary: requestedSummaryProvider == null ? '' : '결정 사항과 다음 할 일',
      );

  @override
  Future<MeetingProcessingJob> requestSummary(
    String jobId, {
    required String provider,
  }) async {
    requestedSummaryProvider = provider;
    return const MeetingProcessingJob(
      id: 'job-123',
      status: 'done',
      summaryStatus: 'done',
    );
  }
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

    await tester.tap(find.text('회의 시작'));
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

    await tester.tap(find.text('회의 시작'));
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

  testWidgets('기존 녹음 파일을 가져와 받아쓰기 결과로 연다', (tester) async {
    final processing = FakeMeetingProcessingGateway();
    final jobs = FakeProcessingJobRepository();
    var pickerCalled = false;
    final source = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}imported-meeting.m4a',
    )..writeAsBytesSync([1, 2, 3]);
    addTearDown(() async {
      if (await source.exists()) await source.delete();
    });
    await tester.pumpWidget(
      PronoteApp(
        repository: MemoryNoteRepository(),
        recorder: FakeAudioRecorderGateway(),
        processingGateway: processing,
        processingJobRepository: jobs,
        importRecordingPicker: () async {
          pickerCalled = true;
          return source.path;
        },
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 시작'));
    await tester.pumpAndSettle();
    expect(find.text('기존 녹음·영상 가져오기'), findsOneWidget);
    await tester.ensureVisible(find.text('기존 녹음·영상 가져오기'));
    await tester.tap(find.text('기존 녹음·영상 가져오기'));
    await tester.pump();
    expect(pickerCalled, isTrue);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(processing.submittedPath, source.path);
    expect(jobs.records.single.recordingPath, source.path);
    expect(find.text('받아쓰기 결과'), findsOneWidget);
    expect(find.text('테스트 받아쓰기'), findsOneWidget);
  });

  testWidgets('저장된 녹음을 로그인 없이 받아쓰기 작업으로 보낸다', (tester) async {
    final recorder = FakeAudioRecorderGateway();
    final processing = FakeMeetingProcessingGateway();
    final jobs = FakeProcessingJobRepository();
    final notes = MemoryNoteRepository();
    final exports = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('pronote-export-ui-'),
    ))!;
    addTearDown(() async {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await exports.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      try {
        await exports.delete(recursive: true);
      } on FileSystemException {
        // Windows virus scanning can briefly retain a handle after file export.
      }
    });
    await tester.pumpWidget(
      PronoteApp(
        repository: notes,
        recorder: recorder,
        processingGateway: processing,
        processingJobRepository: jobs,
        transcriptExporter: TranscriptExporter(() async => exports),
        recordingDirectoryProvider: () async => Directory.systemTemp,
        recordingValidator: (_) async => true,
      ),
    );

    await tester.tap(find.text('회의 시작'));
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect((await notes.list()).single.body, '테스트 받아쓰기');
    expect(find.text('텍스트 파일 저장'), findsOneWidget);
    await tester.tap(find.text('텍스트 파일 저장'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(exports.listSync().whereType<File>(), hasLength(1));
  });

  testWidgets('Claude를 선택하고 확인한 후에만 AI 회의록을 만든다', (tester) async {
    final processing = FakeMeetingProcessingGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: TranscriptionResultScreen(
          gateway: processing,
          jobId: 'job-123',
          noteRepository: MemoryNoteRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AI 회의록 만들기'), findsOneWidget);
    await tester.tap(find.text('AI 회의록 만들기'));
    await tester.pumpAndSettle();
    expect(find.text('Claude 연결'), findsOneWidget);
    expect(find.text('ChatGPT/Codex 연결'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('summary-consent')));
    await tester.pump();
    await tester.tap(find.text('회의록 생성'));
    await tester.pumpAndSettle();

    expect(processing.requestedSummaryProvider, 'claude_cli');
    expect(find.text('결정 사항과 다음 할 일'), findsOneWidget);
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

    await tester.tap(find.text('회의 시작'));
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
