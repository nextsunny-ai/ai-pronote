import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class MeetingProcessingJob {
  const MeetingProcessingJob({
    required this.id,
    required this.status,
    this.phase = '',
    this.progress = 0,
    this.summaryStatus = 'none',
  });

  factory MeetingProcessingJob.fromJson(Map<String, dynamic> json) {
    final id = json['job_id']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('받아쓰기 작업 번호가 없습니다.');
    }
    final rawProgress = json['progress'];
    return MeetingProcessingJob(
      id: id,
      status: json['status']?.toString() ?? 'unknown',
      phase: json['phase']?.toString() ?? '',
      progress: rawProgress is num ? rawProgress.toInt() : 0,
      summaryStatus: json['summary_status']?.toString() ?? 'none',
    );
  }

  final String id;
  final String status;
  final String phase;
  final int progress;
  final String summaryStatus;
}

class MeetingProcessingResult {
  const MeetingProcessingResult({
    required this.id,
    required this.filename,
    required this.transcript,
    this.summaryTitle = '',
    this.summary = '',
  });

  factory MeetingProcessingResult.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
  }) {
    final summaryResult = json['summary_result'];
    final summaryMap = summaryResult is Map<String, dynamic>
        ? summaryResult
        : const <String, dynamic>{};
    return MeetingProcessingResult(
      id: json['job_id']?.toString() ?? fallbackId,
      filename: json['filename']?.toString() ?? '',
      transcript:
          json['speaker_text']?.toString() ??
          json['full_text']?.toString() ??
          '',
      summaryTitle: summaryMap['title']?.toString() ?? '',
      summary: summaryMap['summary']?.toString() ?? '',
    );
  }

  final String id;
  final String filename;
  final String transcript;
  final String summaryTitle;
  final String summary;
}

class MeetingProcessingException implements Exception {
  const MeetingProcessingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class MeetingProcessingGateway {
  Future<MeetingProcessingJob> submitTranscription(String recordingPath);

  Future<MeetingProcessingJob> readJob(String jobId);

  Future<MeetingProcessingResult> readResult(String jobId);
}

class LocalMeetingProcessingGateway implements MeetingProcessingGateway {
  LocalMeetingProcessingGateway({
    required this.baseUri,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri baseUri;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<MeetingProcessingJob> submitTranscription(String recordingPath) async {
    final file = File(recordingPath);
    if (!await file.exists()) {
      throw const MeetingProcessingException('저장된 녹음 파일을 찾을 수 없습니다.');
    }

    final request =
        http.MultipartRequest('POST', baseUri.resolve('/api/transcribe'))
          ..fields.addAll(const {
            'language': 'ko',
            'model': 'medium',
            'beam_size': '1',
            'diarize': 'false',
            'auto_summarize': 'false',
          })
          ..files.add(await http.MultipartFile.fromPath('file', recordingPath));

    try {
      final streamed = await _client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed)
          .timeout(timeout);
      return MeetingProcessingJob.fromJson(_decodeResponse(response));
    } on MeetingProcessingException {
      rethrow;
    } on TimeoutException {
      throw const MeetingProcessingException(
        '받아쓰기 연결 시간이 초과되었습니다. 녹음 원본은 기기에 그대로 보존되어 있습니다.',
      );
    } on SocketException {
      throw const MeetingProcessingException(
        '받아쓰기 엔진에 연결할 수 없습니다. 녹음 원본은 기기에 그대로 보존되어 있습니다.',
      );
    } on http.ClientException {
      throw const MeetingProcessingException(
        '받아쓰기 엔진과 통신하지 못했습니다. 녹음 원본은 기기에 그대로 보존되어 있습니다.',
      );
    }
  }

  @override
  Future<MeetingProcessingJob> readJob(String jobId) async {
    final safeId = Uri.encodeComponent(jobId);
    try {
      final response = await _client
          .get(baseUri.resolve('/api/jobs/$safeId'))
          .timeout(timeout);
      return MeetingProcessingJob.fromJson(_decodeResponse(response));
    } on MeetingProcessingException {
      rethrow;
    } on TimeoutException {
      throw const MeetingProcessingException('받아쓰기 진행 상태 확인 시간이 초과되었습니다.');
    } on SocketException {
      throw const MeetingProcessingException(
        '받아쓰기 엔진에 연결할 수 없습니다. 작업 결과는 삭제되지 않습니다.',
      );
    } on http.ClientException {
      throw const MeetingProcessingException('받아쓰기 진행 상태를 확인하지 못했습니다.');
    }
  }

  @override
  Future<MeetingProcessingResult> readResult(String jobId) async {
    final safeId = Uri.encodeComponent(jobId);
    try {
      final response = await _client
          .get(baseUri.resolve('/api/results/$safeId'))
          .timeout(timeout);
      return MeetingProcessingResult.fromJson(
        _decodeResponse(response),
        fallbackId: jobId,
      );
    } on MeetingProcessingException {
      rethrow;
    } on TimeoutException {
      throw const MeetingProcessingException('받아쓰기 결과 확인 시간이 초과되었습니다.');
    } on SocketException {
      throw const MeetingProcessingException(
        '받아쓰기 엔진에 연결할 수 없습니다. 완성된 결과는 삭제되지 않습니다.',
      );
    } on http.ClientException {
      throw const MeetingProcessingException('받아쓰기 결과를 불러오지 못했습니다.');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? detail = decoded is Map<String, dynamic>
          ? decoded['detail']
          : null;
      if (detail is Map<String, dynamic>) {
        detail = detail['message'] ?? detail['detail'];
      }
      final message = detail?.toString().trim();
      throw MeetingProcessingException(
        message == null || message.isEmpty ? '받아쓰기 요청을 처리하지 못했습니다.' : message,
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MeetingProcessingException('받아쓰기 엔진의 응답 형식이 올바르지 않습니다.');
    }
    return decoded;
  }

  void close() => _client.close();
}
