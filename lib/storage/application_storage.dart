import 'dart:convert';
import 'dart:io';

class ApplicationStorage {
  ApplicationStorage(this.documentsRoot);

  final Directory documentsRoot;

  Directory get root =>
      Directory('${documentsRoot.path}${Platform.pathSeparator}AI PRONOTE');

  Directory get recordings =>
      Directory('${root.path}${Platform.pathSeparator}recordings');

  Directory get videos =>
      Directory('${root.path}${Platform.pathSeparator}videos');

  Directory get exports =>
      Directory('${root.path}${Platform.pathSeparator}AI_PRONOTE_exports');

  Future<Directory> prepare() async {
    await root.create(recursive: true);
    await _copyRecognizedJson('notes.json', listKey: 'notes');
    await _copyRecognizedJson('notes.json.bak', listKey: 'notes');
    await _copyRecognizedJson('processing_jobs.json', listKey: 'jobs');
    await _copyRecognizedJson('processing_jobs.json.bak', listKey: 'jobs');
    await _copyLegacyDirectory(
      Directory('${documentsRoot.path}${Platform.pathSeparator}recordings'),
      recordings,
      (name) => RegExp(r'^meeting_\d{10,}\.m4a$').hasMatch(name),
    );
    await _copyLegacyDirectory(
      Directory('${documentsRoot.path}${Platform.pathSeparator}videos'),
      videos,
      (name) => RegExp(r'^meeting_\d{10,}\.mp4$').hasMatch(name),
    );
    await _copyLegacyDirectory(
      Directory(
        '${documentsRoot.path}${Platform.pathSeparator}AI_PRONOTE_exports',
      ),
      exports,
      (name) => name.toLowerCase().endsWith('.txt'),
    );
    return root;
  }

  Future<void> _copyRecognizedJson(
    String name, {
    required String listKey,
  }) async {
    final source = File('${documentsRoot.path}${Platform.pathSeparator}$name');
    if (!await source.exists()) return;
    try {
      final decoded = jsonDecode(await source.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['schemaVersion'] != 1 ||
          decoded[listKey] is! List) {
        return;
      }
    } on Object {
      return;
    }
    await _copyIfAbsent(
      source,
      File('${root.path}${Platform.pathSeparator}$name'),
    );
  }

  Future<void> _copyLegacyDirectory(
    Directory source,
    Directory destination,
    bool Function(String name) accepts,
  ) async {
    if (!await source.exists()) return;
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!accepts(name)) continue;
      await _copyIfAbsent(
        entity,
        File('${destination.path}${Platform.pathSeparator}$name'),
      );
    }
  }

  Future<void> _copyIfAbsent(File source, File destination) async {
    if (await destination.exists()) return;
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.migrating.${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    try {
      await source.copy(temporary.path);
      if (await destination.exists()) {
        await temporary.delete();
        return;
      }
      await temporary.rename(destination.path);
    } on FileSystemException {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
