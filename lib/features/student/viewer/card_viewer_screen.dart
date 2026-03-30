import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/audio/app_audio_player.dart';
import '../../../services/appwrite/student_repository.dart';
import '../../../services/drive/drive_api.dart';
import '../../../domain/models/card_item.dart';
import '../../../services/web/blob_url.dart';
import '../../../utils/tab_color.dart';

class CardViewerScreen extends ConsumerStatefulWidget {
  const CardViewerScreen({
    super.key,
    required this.publicToken,
    required this.tabId,
    required this.tabTitle,
    this.tabColorHex,
  });

  final String publicToken;
  final String tabId;
  final String tabTitle;
  final String? tabColorHex;

  @override
  ConsumerState<CardViewerScreen> createState() => _CardViewerScreenState();
}

class _CardViewerScreenState extends ConsumerState<CardViewerScreen> {
  int _index = 0;
  final AppAudioPlayer _player = AppAudioPlayer.create();
  bool _isPlaying = false;
  final FocusNode _focusNode = FocusNode();
  final BlobUrl _blobUrl = BlobUrl.create();

  bool _loading = true;
  Object? _loadError;
  List<CardItem> _cards = const <CardItem>[];

  final Map<String, String> _dataUrlCache = <String, String>{};
  final Map<String, String> _objectUrlCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _load();

    // Avoid `autofocus: true` on web: it can trigger focus traversal while this
    // element is being detached (inactive), causing findRenderObject errors.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repo = ref.read(studentRepositoryProvider);
      final cards = await repo.listCards(widget.tabId);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        _index = 0;
        _loading = false;
      });
      await _primeForIndex(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _primeForIndex(int idx) async {
    if (idx < 0 || idx >= _cards.length) return;
    final drive = ref.read(driveApiProvider);

    Future<void> ensure(String fileId) async {
      if (_dataUrlCache.containsKey(fileId)) return;
      final url = await drive.publicDownloadDataUrl(
        publicToken: widget.publicToken,
        fileId: fileId,
      );
      if (!mounted) return;
      setState(() => _dataUrlCache[fileId] = url);
    }

    final current = _cards[idx];
    await ensure(current.imageDriveFileId);
    await ensure(current.audioDriveFileId);

    // Preload adjacent images for smoother navigation.
    if (idx - 1 >= 0) {
      final prev = _cards[idx - 1];
      // Fire-and-forget.
      // ignore: unawaited_futures
      ensure(prev.imageDriveFileId);
    }
    if (idx + 1 < _cards.length) {
      final next = _cards[idx + 1];
      // ignore: unawaited_futures
      ensure(next.imageDriveFileId);
    }
  }

  @override
  void dispose() {
    _player.stop();
    _focusNode.dispose();
    for (final url in _objectUrlCache.values) {
      if (kIsWeb) _blobUrl.revokeObjectUrl(url);
    }
    super.dispose();
  }

  ({String mimeType, List<int> bytes})? _parseDataUrl(String dataUrl) {
    final prefix = 'data:';
    if (!dataUrl.startsWith(prefix)) return null;
    final comma = dataUrl.indexOf(',');
    if (comma <= 0) return null;
    final meta = dataUrl.substring(prefix.length, comma); // e.g. audio/mpeg;base64
    final isBase64 = meta.endsWith(';base64');
    if (!isBase64) return null;
    final mimeType = meta.substring(0, meta.length - ';base64'.length);
    final b64 = dataUrl.substring(comma + 1);
    try {
      return (mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType, bytes: base64Decode(b64));
    } catch (_) {
      return null;
    }
  }

  void _go(int next) {
    if (next < 0 || next >= _cards.length) return;
    setState(() {
      _index = next;
    });
    _stopAudio();
    _primeForIndex(next);
  }

  void _stopAudio() {
    _player.stop();
    setState(() => _isPlaying = false);
  }

  Future<void> _togglePlay() async {
    final card = _cards[_index];
    final String? audioUrl = _dataUrlCache[card.audioDriveFileId];
    if (audioUrl == null) return;

    if (!kIsWeb) return;

    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    try {
      var urlToPlay = audioUrl;
      if (audioUrl.startsWith('data:')) {
        final cached = _objectUrlCache[card.audioDriveFileId];
        if (cached != null) {
          urlToPlay = cached;
        } else {
          final parsed = _parseDataUrl(audioUrl);
          if (parsed != null) {
            final fromCard = card.audioMimeType.split(';').first.trim();
            final fromData = parsed.mimeType.split(';').first.trim();
            final mimeForPlay =
                fromCard.startsWith('audio/') ? fromCard : fromData;
            final objectUrl = _blobUrl.createObjectUrl(
              bytes: parsed.bytes,
              mimeType: mimeForPlay,
            );
            _objectUrlCache[card.audioDriveFileId] = objectUrl;
            urlToPlay = objectUrl;
          }
        }
      }

      await _player.load(urlToPlay);
      await _player.play();
      if (!mounted) return;
      setState(() => _isPlaying = true);

      _player.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPlaying = false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Afspelen van audio mislukt: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: Center(child: Text('Kaarten laden mislukt: $_loadError')),
      );
    }
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: widget.tabTitle,
          tabColorHex: widget.tabColorHex,
        ),
        body: const Center(child: Text('Nog geen kaarten.')),
      );
    }

    final CardItem card = _cards[_index];
    final String? imageUrl = _dataUrlCache[card.imageDriveFileId];
    final bool hasPrev = _index > 0;
    final bool hasNext = _index < _cards.length - 1;

    final Color? accent = parseTabColorHex(widget.tabColorHex);
    final TextStyle? counterStyle = accent != null
        ? TextStyle(color: foregroundOnTabColor(accent))
        : null;

    return Scaffold(
      appBar: buildTabColoredAppBar(
        context,
        title: widget.tabTitle,
        tabColorHex: widget.tabColorHex,
        actions: <Widget>[
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_index + 1} / ${_cards.length}',
                style: counterStyle,
              ),
            ),
          ),
        ],
      ),
      body: Focus(
        focusNode: _focusNode,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (hasPrev) _go(_index - 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            if (hasNext) _go(_index + 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: <Widget>[
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: imageUrl == null
                          ? const Center(child: CircularProgressIndicator())
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Text('Afbeelding laden mislukt'),
                                );
                              },
                            ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: <Widget>[
                  IconButton.filledTonal(
                    onPressed: hasPrev ? () => _go(_index - 1) : null,
                    icon: const Icon(Icons.arrow_left),
                    tooltip: 'Vorige',
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _dataUrlCache[card.audioDriveFileId] == null
                          ? null
                          : _togglePlay,
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                      label: Text(_isPlaying ? 'Pauze' : 'Geluid afspelen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: hasNext ? () => _go(_index + 1) : null,
                    icon: const Icon(Icons.arrow_right),
                    tooltip: 'Volgende',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

