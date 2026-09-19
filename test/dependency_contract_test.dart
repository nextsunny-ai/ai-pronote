import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('최신 Xcode와 호환되는 objective_c 빌드 훅을 사용한다', () {
    final lockfile = File('pubspec.lock').readAsStringSync();
    final match = RegExp(
      r'objective_c:\s+dependency:.*?version: "(\d+)\.(\d+)\.(\d+)"',
      dotAll: true,
    ).firstMatch(lockfile);

    expect(match, isNotNull);
    final version = [
      int.parse(match!.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
    expect(
      version[0] > 9 || version[0] == 9 && version[1] >= 6,
      isTrue,
      reason: 'objective_c 9.5.x는 Xcode 26.6 iOS 빌드 훅에서 실패합니다.',
    );
  });
}
