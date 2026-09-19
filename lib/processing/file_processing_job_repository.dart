import 'dart:convert';
import 'dart:io';

class ProcessingJobRecord {
  const ProcessingJobRecord({
    required this.jobId,
    required this.recordingPath,
    required this.createdAt,
    this.status = 'queued',
  });

  factory ProcessingJobRecord.fromJson(Map<String, Object?> json) {
    final jobId = json['jobId'];
    final recordingPath = json['recordingPath'];
    final createdAt = json['createdAt'];
    if (jobId is! String ||
        jobId.isEmpty ||
        recordingPath is! String ||
        createdAt is! String) {
      throw const FormatException('받아쓰기 작업 기록이 손상되었습니다.');
    }
    return ProcessingJobRecord(
      jobId: jobId,
      recordingPath: recordingPath,
      createdAt: DateTime.parse(createdAt),
      status: json['status']?.toString() ?? 'queued',
    );
  }

  final String jobId;
  final String recordingPath;
  final DateTime createdAt;
  final String status;

  ProcessingJobRecord copyWith({String? status}) => ProcessingJobRecord(
    jobId: jobId,
    recordingPath: recordingPath,
    createdAt: createdAt,
    status: status ?? this.status,
  );

  Map<String, Object?> toJson() => {
    'jobId': jobId,
    'recordingPath': recordingPath,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'status': status,
  };

  @override
  bool operator ==(Object other) =>
      other is ProcessingJobRecord &&
      other.jobId == jobId &&
      other.recordingPath == recordingPath &&
      other.createdAt == createdAt &&
      other.status == status;

  @override
  int get hashCode => Object.hash(jobId, recordingPath, createdAt, status);
}

abstract interface class ProcessingJobRepository {
  Future<List<ProcessingJobRecord>> list();

  Future<void> save(ProcessingJobRecord record);
}

class FileProcessingJobRepository implements ProcessingJobRepository {
  FileProcessingJobRepository(this.directory);

  final Directory directory;
  Future<void> _writeQueue = Future.value();

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}processing_jobs.json');
  File get _backupFile => File('${_file.path}.bak');

  @override
  Future<List<ProcessingJobRecord>> list() async {
    await _writeQueue;
    return _readWithRecovery();
  }

  @override
  Future<void> save(ProcessingJobRecord record) {
    _writeQueue = _writeQueue.then((_) => _saveNow(record));
    return _writeQueue;
  }

  Future<void> _saveNow(ProcessingJobRecord record) async {
    await directory.create(recursive: true);
    final existing = await _readWithRecovery();
    final byId = {
      for (final item in existing) item.jobId: item,
      record.jobId: record,
    };
    final payload = jsonEncode({
      'schemaVersion': 1,
      'jobs': byId.values.map((item) => item.toJson()).toList(),
    });
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await _backupFile.exists()) await _backupFile.delete();
    if (await _file.exists()) await _file.rename(_backupFile.path);
    try {
      await temporary.rename(_file.path);
    } catch (_) {
      if (!await _file.exists() && await _backupFile.exists()) {
        await _backupFile.copy(_file.path);
      }
      rethrow;
    }
  }

  Future<List<ProcessingJobRecord>> _readWithRecovery() async {
    if (!await _file.exists()) {
      if (!await _backupFile.exists()) return [];
      await _backupFile.copy(_file.path);
    }
    try {
      return await _readFile(_file);
    } on FormatException {
      if (!await _backupFile.exists()) rethrow;
      final recovered = await _readFile(_backupFile);
      final corrupt = File(
        '${_file.path}.corrupt.${DateTime.now().toUtc().microsecondsSinceEpoch}',
      );
      await _file.rename(corrupt.path);
      await _backupFile.copy(_file.path);
      return recovered;
    }
  }

  Future<List<ProcessingJobRecord>> _readFile(File file) async {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
        throw const FormatException('지원하지 않는 받아쓰기 작업 저장 형식입니다.');
      }
      final rows = decoded['jobs'];
      if (rows is! List<Object?>) {
        throw const FormatException('받아쓰기 작업 목록이 손상되었습니다.');
      }
      final records = rows
          .map(
            (row) => ProcessingJobRecord.fromJson(
              (row as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false);
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('받아쓰기 작업 목록이 손상되었습니다.', error);
    }
  }
}
