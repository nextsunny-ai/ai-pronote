import 'dart:io';

import 'package:ai_pronote_app/processing/file_processing_job_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('앱을 다시 열어도 받아쓰기 작업번호와 원본 경로를 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-jobs-');
    addTearDown(() => directory.delete(recursive: true));
    final record = ProcessingJobRecord(
      jobId: 'job-123',
      recordingPath: 'C:/recordings/meeting.m4a',
      createdAt: DateTime.utc(2026, 9, 19),
    );

    await FileProcessingJobRepository(directory).save(record);
    final reopened = await FileProcessingJobRepository(directory).list();

    expect(reopened, [record]);
  });

  test('같은 작업번호를 다시 저장해도 한 건만 최신 상태로 보존한다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-jobs-');
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileProcessingJobRepository(directory);
    final first = ProcessingJobRecord(
      jobId: 'job-123',
      recordingPath: 'meeting.m4a',
      createdAt: DateTime.utc(2026, 9, 19),
    );
    final updated = first.copyWith(status: 'done');

    await repository.save(first);
    await repository.save(updated);

    expect(await repository.list(), [updated]);
  });

  test('주 작업 목록이 손상되면 정상 백업을 보존하며 복구한다', () async {
    final directory = await Directory.systemTemp.createTemp('pronote-jobs-');
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileProcessingJobRepository(directory);
    final first = ProcessingJobRecord(
      jobId: 'job-safe',
      recordingPath: 'meeting.m4a',
      createdAt: DateTime.utc(2026, 9, 19),
    );
    await repository.save(first);
    await repository.save(first.copyWith(status: 'running'));

    final main = File(
      '${directory.path}${Platform.pathSeparator}processing_jobs.json',
    );
    await main.writeAsString('{손상된 JSON', flush: true);

    final recovered = await FileProcessingJobRepository(directory).list();

    expect(recovered, [first]);
    expect(
      directory.listSync().whereType<File>().any(
        (file) => file.path.contains('processing_jobs.json.corrupt.'),
      ),
      isTrue,
    );
  });
}
