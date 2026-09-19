import 'dart:convert';
import 'dart:io';

import 'package:ai_pronote_app/update/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('v 접두사가 있는 새 버전 매니페스트를 인식한다', () async {
    final request = server.first.then((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'version': 'v1.0.1',
          'download_url': 'https://example.com/ai-pronote',
          'notes': '새 버전',
        }));
      await request.response.close();
    });

    final checker = RemoteUpdateChecker(
      'http://127.0.0.1:${server.port}/mobile-update.json',
    );
    final update = await checker.check('1.0.0');

    expect(update?.version, 'v1.0.1');
    expect(update?.downloadUrl, 'https://example.com/ai-pronote');
    await request;
  });

  test('현재 버전과 같은 매니페스트에는 팝업을 만들지 않는다', () async {
    final request = server.first.then((request) async {
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'version': '1.0.0',
          'download_url': 'https://example.com/ai-pronote',
        }));
      await request.response.close();
    });

    final checker = RemoteUpdateChecker(
      'http://127.0.0.1:${server.port}/mobile-update.json',
    );

    expect(await checker.check('1.0.0'), isNull);
    await request;
  });
}
