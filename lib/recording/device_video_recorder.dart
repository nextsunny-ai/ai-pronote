import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'video_recorder_gateway.dart';

class DeviceVideoRecorderGateway implements VideoRecorderGateway {
  CameraController? _controller;

  CameraController get _readyController {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('카메라가 준비되지 않았습니다.');
    }
    return controller;
  }

  @override
  double get aspectRatio => _readyController.value.aspectRatio;

  @override
  Widget buildPreview() => CameraPreview(_readyController);

  @override
  Future<void> initialize() async {
    await dispose();
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('사용할 수 있는 카메라가 없습니다.');
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    _controller = controller;
    await controller.initialize();
  }

  @override
  Future<void> start() => _readyController.startVideoRecording();

  @override
  Future<String> stop(String destinationPath) async {
    final recorded = await _readyController.stopVideoRecording();
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    await recorded.saveTo(destinationPath);
    return destinationPath;
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }
}
