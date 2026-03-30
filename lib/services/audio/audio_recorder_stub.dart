import 'audio_recorder.dart';

AudioRecorder createAudioRecorder() => _StubAudioRecorder();

class _StubAudioRecorder implements AudioRecorder {
  @override
  bool get isRecording => false;

  @override
  Future<void> start() async {}

  @override
  Future<RecordedAudio> stop() async =>
      const RecordedAudio(bytes: <int>[], mimeType: 'application/octet-stream');

  @override
  Future<void> dispose() async {}
}

