import 'dart:io';

import 'local_meeting_processing_gateway.dart';

class TranscriptExporter {
  const TranscriptExporter(this.directoryProvider);

  final Future<Directory> Function() directoryProvider;

  Future<String> export(MeetingProcessingResult result) async {
    final directory = await directoryProvider();
    await directory.create(recursive: true);
    final sourceName = result.summaryTitle.trim().isNotEmpty
        ? result.summaryTitle.trim()
        : result.filename.replaceAll('\\', '/').split('/').last;
    final withoutExtension = sourceName.replaceFirst(
      RegExp(r'\.[^.]{1,8}$'),
      '',
    );
    final safeName = _safeFilename(withoutExtension);
    final stamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    final destination = File(
      '${directory.path}${Platform.pathSeparator}${safeName}_$stamp.txt',
    );
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(_content(result), flush: true);
    await temporary.rename(destination.path);
    return destination.path;
  }

  String _safeFilename(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    return sanitized.isEmpty ? 'AI_PRONOTE_받아쓰기' : sanitized;
  }

  String _content(MeetingProcessingResult result) {
    final title = result.summaryTitle.trim().isNotEmpty
        ? result.summaryTitle.trim()
        : 'AI PRONOTE 받아쓰기';
    final sections = <String>[title];
    if (result.summary.trim().isNotEmpty) {
      sections.add('AI 회의록\n\n${result.summary.trim()}');
    }
    sections.add(
      '받아쓰기\n\n${result.transcript.trim().isEmpty ? '인식된 말소리가 없습니다.' : result.transcript.trim()}',
    );
    return '${sections.join('\n\n========================================\n\n')}\n';
  }
}
