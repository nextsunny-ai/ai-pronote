import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_pronote_app/processing/local_meeting_processing_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late Directory tempDirectory;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    tempDirectory = await Directory.systemTemp.createTemp('pronote_gateway_');
    baseUri = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.close(force: true);
    await tempDirectory.delete(recursive: true);
  });

  test('로그인 없이 녹음 파일을 받아쓰기 작업으로 제출한다', () async {
    final audio = File(
      '${tempDirectory.path}${Platform.pathSeparator}meeting.m4a',
    );
    await audio.writeAsBytes(utf8.encode('recording-bytes'));

    final requestSeen = Completer<void>();
    unawaited(() async {
      final request = await server.first;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/transcribe');
      final body = await utf8.decoder.bind(request).join();
      expect(body, contains('name="auto_summarize"'));
      expect(body, contains('false'));
      expect(body, contains('filename="meeting.m4a"'));
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'job_id': 'job-123', 'status': 'queued'}));
      await request.response.close();
      requestSeen.complete();
    }());

    final gateway = LocalMeetingProcessingGateway(baseUri: baseUri);
    final job = await gateway.submitTranscription(audio.path);

    expect(job.id, 'job-123');
    expect(job.status, 'queued');
    await requestSeen.future;
  });

  test('작업 진행 상태를 복구해 읽는다', () async {
    unawaited(() async {
      final request = await server.first;
      expect(request.uri.path, '/api/jobs/job-123');
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'job_id': 'job-123',
            'status': 'running',
            'phase': '받아쓰기 중 42%',
            'progress': 42,
            'summary_status': 'none',
          }),
        );
      await request.response.close();
    }());

    final gateway = LocalMeetingProcessingGateway(baseUri: baseUri);
    final job = await gateway.readJob('job-123');

    expect(job.status, 'running');
    expect(job.phase, '받아쓰기 중 42%');
    expect(job.progress, 42);
  });

  test('완료된 받아쓰기 본문과 AI 회의록을 복구해 읽는다', () async {
    unawaited(() async {
      final request = await server.first;
      expect(request.uri.path, '/api/results/job-123');
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'job_id': 'job-123',
            'filename': 'meeting.m4a',
            'full_text': '회의에서 다음 일정을 확정했습니다.',
            'summary_result': {
              'title': '주간 회의',
              'summary': '# 결정 사항\n다음 일정을 확정함',
            },
          }),
        );
      await request.response.close();
    }());

    final gateway = LocalMeetingProcessingGateway(baseUri: baseUri);
    final result = await gateway.readResult('job-123');

    expect(result.id, 'job-123');
    expect(result.filename, 'meeting.m4a');
    expect(result.transcript, '회의에서 다음 일정을 확정했습니다.');
    expect(result.summaryTitle, '주간 회의');
    expect(result.summary, contains('결정 사항'));
  });

  test('서버 오류는 사용자 데이터가 남는 명확한 예외로 바꾼다', () async {
    unawaited(() async {
      final request = await server.first;
      request.response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'detail': '모델을 준비하지 못했습니다'}));
      await request.response.close();
    }());

    final gateway = LocalMeetingProcessingGateway(baseUri: baseUri);

    await expectLater(
      gateway.readJob('job-123'),
      throwsA(
        isA<MeetingProcessingException>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having(
              (error) => error.message,
              'message',
              contains('모델을 준비하지 못했습니다'),
            ),
      ),
    );
  });
}
