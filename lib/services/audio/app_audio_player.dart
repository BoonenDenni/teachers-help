import 'app_audio_player_stub.dart'
    if (dart.library.html) 'app_audio_player_web.dart';

abstract class AppAudioPlayer {
  static AppAudioPlayer create() => createAppAudioPlayer();

  Future<void> load(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  Stream<void> get onEnded;
  bool get isPlaying;
}

