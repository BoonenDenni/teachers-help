import 'dart:async';
import 'dart:html' as html;

import 'app_audio_player.dart';

AppAudioPlayer createAppAudioPlayer() => _WebAudioPlayer();

class _WebAudioPlayer implements AppAudioPlayer {
  html.AudioElement? _audio;
  StreamSubscription<html.Event>? _endedSub;
  final StreamController<void> _ended = StreamController<void>.broadcast();
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<void> get onEnded => _ended.stream;

  Future<void> _disposeAudio() async {
    _endedSub?.cancel();
    _endedSub = null;
    _audio?.pause();
    _audio?.src = '';
    _audio = null;
    _playing = false;
  }

  @override
  Future<void> load(String url) async {
    await _disposeAudio();

    final audio = html.AudioElement(url);
    audio.preload = 'auto';
    _endedSub = audio.onEnded.listen((_) {
      _playing = false;
      _ended.add(null);
    });
    _audio = audio;

    final completer = Completer<void>();
    late StreamSubscription<html.Event> loadedSub;
    late StreamSubscription<html.Event> errorSub;
    void cleanup() {
      loadedSub.cancel();
      errorSub.cancel();
    }

    void completeOk() {
      if (completer.isCompleted) return;
      cleanup();
      completer.complete();
    }

    loadedSub = audio.onLoadedData.listen((_) => completeOk());
    errorSub = audio.onError.listen((_) {
      if (completer.isCompleted) return;
      cleanup();
      final err = audio.error;
      final code = err?.code;
      final src = audio.src;
      completer.completeError(
        StateError(
          'Audio failed to load (code: ${code ?? 'unknown'}, src: ${src.startsWith('blob:') ? 'blob:' : src.startsWith('data:') ? 'data:' : src}).',
        ),
      );
    });

    audio.load();
    await completer.future.timeout(const Duration(seconds: 10));

    final d = audio.duration;
    if (d.isNaN || d <= 0) {
      await _disposeAudio();
      throw StateError('Audio has no playable duration (file may be empty or corrupt).');
    }
  }

  @override
  Future<void> play() async {
    final audio = _audio;
    if (audio == null) return;

    Future<void> doPlay() async {
      await audio.play();
      _playing = true;
    }

    try {
      await doPlay();
    } catch (e) {
      final msg = e.toString();
      // Chrome/Edge: very short clips can end before play()'s Future completes.
      if (msg.contains('AbortError')) {
        if (audio.ended) {
          _playing = false;
          return;
        }
        audio.currentTime = 0;
        try {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          await doPlay();
          return;
        } catch (e2) {
          final m2 = e2.toString();
          if (m2.contains('AbortError') && audio.ended) {
            _playing = false;
            return;
          }
        }
      }
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _audio?.pause();
    _playing = false;
  }

  @override
  Future<void> stop() async {
    _audio?.pause();
    if (_audio != null) _audio!.currentTime = 0;
    _playing = false;
  }
}
