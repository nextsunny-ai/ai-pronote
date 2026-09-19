import 'package:record/record.dart';

import 'audio_recorder_gateway.dart';

class DeviceAudioRecorderGateway implements AudioRecorderGateway {
  DeviceAudioRecorderGateway({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

  @override
  Future<String?> stop() => _recorder.stop();
}
