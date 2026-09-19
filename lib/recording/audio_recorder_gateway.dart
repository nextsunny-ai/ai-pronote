abstract interface class AudioRecorderGateway {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<void> pause();
  Future<void> resume();
  Future<String?> stop();
}

class DisabledAudioRecorderGateway implements AudioRecorderGateway {
  const DisabledAudioRecorderGateway();

  @override
  Future<bool> hasPermission() async => false;

  @override
  Future<void> start(String path) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<String?> stop() async => null;
}
