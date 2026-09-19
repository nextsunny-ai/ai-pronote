import 'dart:convert';
import 'dart:io';

import 'note_document.dart';
import 'note_repository.dart';

class FileNoteRepository implements NoteRepository {
  FileNoteRepository(this.directory);

  final Directory directory;
  Future<void> _writeQueue = Future.value();

  File get _file =>
      File('${directory.path}${Platform.pathSeparator}notes.json');
  File get _backupFile => File('${_file.path}.bak');

  @override
  Future<List<NoteDocument>> list() async {
    await _writeQueue;
    return _readWithRecovery();
  }

  @override
  Future<void> save(NoteDocument note) {
    _writeQueue = _writeQueue.then((_) => _saveNow(note));
    return _writeQueue;
  }

  Future<void> _saveNow(NoteDocument note) async {
    await directory.create(recursive: true);
    final existing = await _readWithRecovery();
    final byId = {for (final row in existing) row.id: row, note.id: note};
    final payload = jsonEncode({
      'schemaVersion': 1,
      'notes': byId.values.map((row) => row.toJson()).toList(),
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

  Future<List<NoteDocument>> _readWithRecovery() async {
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

  Future<List<NoteDocument>> _readFile(File file) async {
    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
        throw const FormatException('지원하지 않는 노트 저장 형식입니다.');
      }
      final rows = decoded['notes'];
      if (rows is! List<Object?>) {
        throw const FormatException('노트 목록이 손상되었습니다.');
      }
      final notes = rows
          .map((row) => NoteDocument.fromJson(row as Map<String, Object?>))
          .toList(growable: false);
      notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return notes;
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('노트 목록이 손상되었습니다.', error);
    }
  }
}
