import 'audio_recorder_stub.dart' if (dart.library.html) 'audio_recorder_web.dart';

class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.mimeType});

  final List<int> bytes;
  final String mimeType;
}

abstract class AudioRecorder {
  static AudioRecorder create() => createAudioRecorder();

  bool get isRecording;
  Future<void> start();
  Future<RecordedAudio> stop();
  Future<void> dispose();
}

