import 'dart:html' as html;
import 'dart:typed_data';

import 'package:record/record.dart' as rec;

import 'audio_recorder.dart';

/// Web recording via [package:record], using **WAV** (AudioWorklet path).
/// Avoids raw `MediaRecorder` flaky/empty blobs on Edge for short clips.
AudioRecorder createAudioRecorder() => _RecordPackageWebRecorder();

class _RecordPackageWebRecorder implements AudioRecorder {
  final rec.AudioRecorder _recorder = rec.AudioRecorder();
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<void> start() async {
    if (_recording) return;

    final permitted = await _recorder.hasPermission();
    if (!permitted) {
      throw StateError('Microphone permission denied.');
    }

    const config = rec.RecordConfig(
      encoder: rec.AudioEncoder.wav,
      sampleRate: 44100,
      numChannels: 1,
      bitRate: 128000,
    );

    if (!await _recorder.isEncoderSupported(config.encoder)) {
      throw StateError('WAV recording is not supported in this browser.');
    }

    await _recorder.start(config, path: 'clip.wav');
    _recording = true;
  }

  @override
  Future<RecordedAudio> stop() async {
    if (!_recording) {
      return const RecordedAudio(bytes: <int>[], mimeType: 'application/octet-stream');
    }
    _recording = false;

    final String? blobUrl = await _recorder.stop();
    if (blobUrl == null || blobUrl.isEmpty) {
      return const RecordedAudio(bytes: <int>[], mimeType: 'application/octet-stream');
    }

    try {
      final bytes = await _blobUrlToBytes(blobUrl);
      return RecordedAudio(bytes: bytes, mimeType: 'audio/wav');
    } finally {
      html.Url.revokeObjectUrl(blobUrl);
    }
  }

  @override
  Future<void> dispose() async {
    _recording = false;
    await _recorder.dispose();
  }

  static Future<Uint8List> _blobUrlToBytes(String blobUrl) async {
    final request = await html.HttpRequest.request(
      blobUrl,
      responseType: 'arraybuffer',
    );
    final dynamic response = request.response;
    if (response is ByteBuffer) {
      return Uint8List.view(response);
    }
    return Uint8List(0);
  }
}
