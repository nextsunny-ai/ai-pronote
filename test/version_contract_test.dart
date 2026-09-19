import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('노트 내보내기가 포함된 후보는 1.0.1 빌드 2로 식별된다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains(RegExp(r'^version: 1\.0\.1\+2$', multiLine: true)));
  });
}
