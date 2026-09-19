import 'dart:io';

import 'package:ai_pronote_app/storage/application_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기존 AI PRONOTE 데이터만 전용 폴더로 복사하고 원본은 보존한다', () async {
    final documents = await Directory.systemTemp.createTemp(
      'pronote-storage-migration-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final legacyNotes = File('${documents.path}${Platform.pathSeparator}notes.json');
    final legacyJobs = File(
      '${documents.path}${Platform.pathSeparator}processing_jobs.json',
    );
    await legacyNotes.writeAsString('{"schemaVersion":1,"notes":[]}');
    await legacyJobs.writeAsString('{"schemaVersion":1,"jobs":[]}');
    final recordings = Directory(
      '${documents.path}${Platform.pathSeparator}recordings',
    );
    final videos = Directory('${documents.path}${Platform.pathSeparator}videos');
    final exports = Directory(
      '${documents.path}${Platform.pathSeparator}AI_PRONOTE_exports',
    );
    await recordings.create();
    await videos.create();
    await exports.create();
    final legacyAudio = File(
      '${recordings.path}${Platform.pathSeparator}meeting_1726700000000.m4a',
    );
    final unrelatedAudio = File(
      '${recordings.path}${Platform.pathSeparator}holiday.m4a',
    );
    final legacyVideo = File(
      '${videos.path}${Platform.pathSeparator}meeting_1726700000001.mp4',
    );
    final legacyExport = File(
      '${exports.path}${Platform.pathSeparator}회의_받아쓰기.txt',
    );
    await legacyAudio.writeAsBytes([1, 2, 3]);
    await unrelatedAudio.writeAsBytes([4, 5, 6]);
    await legacyVideo.writeAsBytes([7, 8, 9]);
    await legacyExport.writeAsString('회의 내용');

    final storage = ApplicationStorage(documents);
    final root = await storage.prepare();

    expect(root.path, '${documents.path}${Platform.pathSeparator}AI PRONOTE');
    expect(await File('${root.path}${Platform.pathSeparator}notes.json').exists(), isTrue);
    expect(
      await File('${root.path}${Platform.pathSeparator}processing_jobs.json').exists(),
      isTrue,
    );
    expect(
      await File(
        '${storage.recordings.path}${Platform.pathSeparator}${legacyAudio.uri.pathSegments.last}',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${storage.recordings.path}${Platform.pathSeparator}${unrelatedAudio.uri.pathSegments.last}',
      ).exists(),
      isFalse,
    );
    expect(
      await File(
        '${storage.videos.path}${Platform.pathSeparator}${legacyVideo.uri.pathSegments.last}',
      ).exists(),
      isTrue,
    );
    expect(
      await File(
        '${storage.exports.path}${Platform.pathSeparator}${legacyExport.uri.pathSegments.last}',
      ).exists(),
      isTrue,
    );
    expect(await legacyNotes.exists(), isTrue);
    expect(await legacyJobs.exists(), isTrue);
    expect(await legacyAudio.exists(), isTrue);
    expect(await legacyVideo.exists(), isTrue);
  });

  test('관련 없는 JSON은 가져오지 않고 새 데이터는 덮어쓰지 않는다', () async {
    final documents = await Directory.systemTemp.createTemp(
      'pronote-storage-safety-',
    );
    addTearDown(() => documents.delete(recursive: true));
    final legacyNotes = File('${documents.path}${Platform.pathSeparator}notes.json');
    await legacyNotes.writeAsString('{"private":"unrelated"}');
    final storage = ApplicationStorage(documents);
    await storage.root.create(recursive: true);
    final destinationJobs = File(
      '${storage.root.path}${Platform.pathSeparator}processing_jobs.json',
    );
    await destinationJobs.writeAsString('newer-data');
    await File(
      '${documents.path}${Platform.pathSeparator}processing_jobs.json',
    ).writeAsString('{"schemaVersion":1,"jobs":[]}');

    await storage.prepare();

    expect(
      await File('${storage.root.path}${Platform.pathSeparator}notes.json').exists(),
      isFalse,
    );
    expect(await destinationJobs.readAsString(), 'newer-data');
    expect(await legacyNotes.exists(), isTrue);
  });
}
