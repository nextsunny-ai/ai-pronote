import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 설치기는 EXE를 직접 가리키는 정상 바로가기를 만든다', () {
    final installer = File('installer/windows_setup.iss').readAsStringSync();

    expect(installer, contains('AppVersion=1.0.1'));
    expect(installer, contains('AppPublisher=㈜써니엔터테인먼트'));
    expect(installer, contains(r'DefaultDirName={localappdata}\Programs\AI PRONOTE'));
    expect(installer, contains(r'Filename: "{app}\ai_pronote_app.exe"'));
    expect(installer, contains(r'IconFilename: "{app}\ai_pronote_app.exe"'));
    expect(installer, contains('PrivilegesRequired=lowest'));
    expect(installer, isNot(contains('.vbs')));
    expect(installer, isNot(contains('Filename: "{app}\\*.lnk"')));
  });

  test('설치 제거는 사용자 문서와 회의 데이터를 삭제하지 않는다', () {
    final installer = File('installer/windows_setup.iss').readAsStringSync();

    expect(installer, isNot(contains('AI_PRONOTE_exports')));
    expect(installer, isNot(contains('Documents')));
    expect(installer, isNot(contains('[UninstallDelete]')));
  });
}
