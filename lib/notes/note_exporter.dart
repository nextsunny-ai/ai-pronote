import 'dart:convert';
import 'dart:io';

import 'note_document.dart';

class NoteExportResult {
  const NoteExportResult({
    required this.markdownPath,
    required this.archivePath,
  });

  final String markdownPath;
  final String archivePath;
}

class NoteExporter {
  const NoteExporter(this.directoryProvider);

  final Future<Directory> Function() directoryProvider;

  Future<NoteExportResult> export(NoteDocument note) async {
    final directory = await directoryProvider();
    await directory.create(recursive: true);
    final stem = '${_safeStem(note.title)}_${_timestamp(note.updatedAt)}';
    final markdown = File('${directory.path}${Platform.pathSeparator}$stem.md');
    final archive = File(
      '${directory.path}${Platform.pathSeparator}$stem.pronote.json',
    );
    final strokeCount = note.pages.fold<int>(
      0,
      (sum, page) => sum + page.strokes.length,
    );
    final title = note.title.trim().isEmpty ? '제목 없는 노트' : note.title.trim();
    final body = note.body.trim().isEmpty
        ? '_작성된 텍스트가 없습니다._'
        : note.body.trim();
    final markdownText =
        '# $title\n\n'
        '- 마지막 저장: ${note.updatedAt.toLocal().toIso8601String()}\n'
        '- 필기: ${note.pages.length}페이지 · $strokeCount획\n\n'
        '$body\n';

    await _atomicWrite(markdown, markdownText);
    await _atomicWrite(archive, jsonEncode(note.toJson()));
    return NoteExportResult(
      markdownPath: markdown.path,
      archivePath: archive.path,
    );
  }

  Future<void> _atomicWrite(File destination, String contents) async {
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(contents, flush: true);
    if (await destination.exists()) await destination.delete();
    await temporary.rename(destination.path);
  }

  String _safeStem(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    final fallback = cleaned.isEmpty ? '제목 없는 노트' : cleaned;
    return fallback.length <= 60 ? fallback : fallback.substring(0, 60).trim();
  }

  String _timestamp(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}
