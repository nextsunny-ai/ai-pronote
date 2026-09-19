import 'dart:convert';
import 'dart:io';

import 'note_document.dart';
import 'note_repository.dart';

class FileNoteRepository implements NoteRepository {
  FileNoteRepository(this.directory);

  final Directory directory;
  Future<void> _writeQueue = Future.value();

  File get _file => File('${directory.path}${Platform.pathSeparator}notes.json');

  @override
  Future<List<NoteDocument>> list() async {
    await _writeQueue;
    if (!await _file.exists()) return [];
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?> || decoded['schemaVersion'] != 1) {
      throw const FormatException('지원하지 않는 노트 저장 형식입니다.');
    }
    final rows = decoded['notes'];
    if (rows is! List<Object?>) throw const FormatException('노트 목록이 손상되었습니다.');
    final notes = rows
        .map((row) => NoteDocument.fromJson(row as Map<String, Object?>))
        .toList(growable: false);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<void> save(NoteDocument note) {
    _writeQueue = _writeQueue.then((_) => _saveNow(note));
    return _writeQueue;
  }

  Future<void> _saveNow(NoteDocument note) async {
    await directory.create(recursive: true);
    final existing = await _readWithoutQueue();
    final byId = {for (final row in existing) row.id: row, note.id: note};
    final payload = jsonEncode({
      'schemaVersion': 1,
      'notes': byId.values.map((row) => row.toJson()).toList(),
    });
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(payload, flush: true);
    if (await _file.exists()) await _file.delete();
    await temporary.rename(_file.path);
  }

  Future<List<NoteDocument>> _readWithoutQueue() async {
    if (!await _file.exists()) return [];
    final raw = await _file.readAsString();
    if (raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    return (decoded['notes'] as List<Object?>)
        .map((row) => NoteDocument.fromJson(row as Map<String, Object?>))
        .toList(growable: false);
  }
}
