import 'dart:async';

import 'app_audio_player.dart';

AppAudioPlayer createAppAudioPlayer() => _StubAudioPlayer();

class _StubAudioPlayer implements AppAudioPlayer {
  final StreamController<void> _ended = StreamController<void>.broadcast();
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<void> get onEnded => _ended.stream;

  @override
  Future<void> load(String url) async {
    // No-op on non-web platforms in this repo’s current target.
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> play() async {
    _playing = true;
  }

  @override
  Future<void> stop() async {
    _playing = false;
  }
}

