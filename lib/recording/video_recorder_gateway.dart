import 'package:flutter/widgets.dart';

abstract interface class VideoRecorderGateway {
  Future<void> initialize();
  Widget buildPreview();
  double get aspectRatio;
  Future<void> start();
  Future<String> stop(String destinationPath);
  Future<void> dispose();
}

class DisabledVideoRecorderGateway implements VideoRecorderGateway {
  const DisabledVideoRecorderGateway();

  @override
  double get aspectRatio => 16 / 9;

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() =>
      Future<void>.error(UnsupportedError('이 기기에서는 영상 녹화를 사용할 수 없습니다.'));

  @override
  Future<void> start() async {}

  @override
  Future<String> stop(String destinationPath) async => destinationPath;
}
