import 'dart:io';

import 'package:ai_pronote_app/processing/local_meeting_processing_gateway.dart';
import 'package:ai_pronote_app/processing/transcript_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('받아쓰기와 AI 회의록을 안전한 UTF-8 텍스트 파일로 내보낸다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-export-');
    addTearDown(() => directory.delete(recursive: true));
    final exporter = TranscriptExporter(() async => directory);
    const result = MeetingProcessingResult(
      id: 'job-123',
      filename: '회의:주간?.m4a',
      transcript: '전체 받아쓰기 본문',
      summaryTitle: '주간 회의',
      summary: '결정 사항 요약',
    );

    final path = await exporter.export(result);
    final file = File(path);
    final text = await file.readAsString();

    expect(await file.exists(), isTrue);
    expect(file.path, endsWith('.txt'));
    expect(file.uri.pathSegments.last, isNot(contains(':')));
    expect(file.uri.pathSegments.last, isNot(contains('?')));
    expect(text, contains('주간 회의'));
    expect(text, contains('결정 사항 요약'));
    expect(text, contains('전체 받아쓰기 본문'));
    expect(File('$path.tmp').existsSync(), isFalse);
  });
}
