import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/card_item.dart';
import '../../domain/models/tab_category.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/audio/app_audio_player.dart';
import '../../services/audio/audio_recorder.dart';
import '../../services/appwrite/appwrite_providers.dart';
import '../../services/drive/drive_api.dart';
import '../../services/drive/drive_picker.dart';
import '../../services/web/blob_url.dart';
import '../../utils/tab_color.dart';
import '../../widgets/tab_color_picker_dialog.dart';
import 'teacher_navigation.dart';

class TeacherTabScreen extends ConsumerStatefulWidget {
  const TeacherTabScreen({super.key, required this.userId, required this.tab});

  final String userId;
  final TabCategory tab;

  @override
  ConsumerState<TeacherTabScreen> createState() => _TeacherTabScreenState();
}

/// Same parsing as [CardViewerScreen]: Drive downloads return `data:...;base64,...`
/// which often fails on [html.AudioElement]; blob URLs decode reliably.
({String mimeType, List<int> bytes})? _parseAudioDataUrl(String dataUrl) {
  const prefix = 'data:';
  if (!dataUrl.startsWith(prefix)) return null;
  final comma = dataUrl.indexOf(',');
  if (comma <= 0) return null;
  final meta = dataUrl.substring(prefix.length, comma);
  final isBase64 = meta.endsWith(';base64');
  if (!isBase64) return null;
  final mimeType = meta.substring(0, meta.length - ';base64'.length);
  final b64 = dataUrl.substring(comma + 1);
  try {
    return (
      mimeType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      bytes: base64Decode(b64),
    );
  } catch (_) {
    return null;
  }
}

class _TeacherTabScreenState extends ConsumerState<TeacherTabScreen> {
  late TabCategory _tab;
  final AppAudioPlayer _listAudio = AppAudioPlayer.create();
  final BlobUrl _listAudioBlob = BlobUrl.create();
  final Map<String, String> _listAudioObjectUrlsByFileId = <String, String>{};
  StreamSubscription<void>? _audioEndedSub;
  String? _playingCardId;
  bool _listAudioPaused = false;

  bool _cardsLoading = true;
  Object? _cardsLoadError;
  List<CardItem> _cards = <CardItem>[];
  bool _orderSaving = false;

  @override
  void initState() {
    super.initState();
    _tab = widget.tab;
    // ignore: unawaited_futures
    _reloadCards();
    _audioEndedSub = _listAudio.onEnded.listen((_) {
      if (!mounted) return;
      setState(() {
        _playingCardId = null;
        _listAudioPaused = false;
      });
    });
  }

  @override
  void dispose() {
    _audioEndedSub?.cancel();
    // ignore: unawaited_futures
    _listAudio.stop();
    if (kIsWeb) {
      for (final objectUrl in _listAudioObjectUrlsByFileId.values) {
        _listAudioBlob.revokeObjectUrl(objectUrl);
      }
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(TeacherTabScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id) {
      _tab = widget.tab;
      // ignore: unawaited_futures
      _reloadCards();
    } else if (oldWidget.tab.title != widget.tab.title ||
        oldWidget.tab.tabColorHex != widget.tab.tabColorHex) {
      _tab = widget.tab;
    }
  }

  Future<void> _reloadCards() async {
    if (!mounted) return;
    setState(() {
      _cardsLoading = true;
      _cardsLoadError = null;
    });
    try {
      final list = await ref.read(teacherRepositoryProvider).listCards(tabId: _tab.id);
      if (!mounted) return;
      setState(() {
        _cards = list;
        _cardsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardsLoadError = e;
        _cardsLoading = false;
      });
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _cards.length) return;
    if (newIndex < 0 || newIndex > _cards.length) return;
    if (oldIndex < newIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    setState(() {
      final item = _cards.removeAt(oldIndex);
      _cards.insert(newIndex, item);
      _cards = List<CardItem>.generate(
        _cards.length,
        (i) => _cards[i].copyWith(sortOrder: i),
      );
    });
    // ignore: unawaited_futures
    _persistCardOrder();
  }

  Future<void> _persistCardOrder() async {
    if (!mounted) return;
    setState(() => _orderSaving = true);
    try {
      final repo = ref.read(teacherRepositoryProvider);
      await Future.wait<void>(
        <Future<void>>[
          for (var i = 0; i < _cards.length; i++)
            repo.updateCardSortOrder(cardId: _cards[i].id, sortOrder: i),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Volgorde opslaan mislukt: $e')),
        );
        await _reloadCards();
      }
    } finally {
      if (mounted) setState(() => _orderSaving = false);
    }
  }

  Future<void> _openEditCard(BuildContext context, CardItem card) async {
    final updated = await Navigator.of(context).push<CardItem?>(
      MaterialPageRoute<CardItem?>(
        builder: (_) => _CreateCardScreen(
          userId: widget.userId,
          tabId: _tab.id,
          sortOrder: card.sortOrder,
          existing: card,
        ),
      ),
    );
    if (updated == null || !context.mounted) return;
    setState(() {
      final idx = _cards.indexWhere((c) => c.id == updated.id);
      if (idx >= 0) _cards[idx] = updated;
    });
  }

  Future<void> _toggleListAudio(CardItem card) async {
    final same = _playingCardId == card.id;
    if (same && _listAudio.isPlaying) {
      await _listAudio.pause();
      if (mounted) setState(() => _listAudioPaused = true);
      return;
    }
    if (same && _listAudioPaused) {
      await _listAudio.play();
      if (mounted) setState(() => _listAudioPaused = false);
      return;
    }
    await _listAudio.stop();
    if (!mounted) return;
    setState(() {
      _playingCardId = card.id;
      _listAudioPaused = false;
    });
    try {
      final drive = ref.read(driveApiProvider);
      final url = await drive.downloadDataUrl(fileId: card.audioDriveFileId);
      if (!mounted) return;

      var urlToPlay = url;
      if (kIsWeb && url.startsWith('data:')) {
        final cached = _listAudioObjectUrlsByFileId[card.audioDriveFileId];
        if (cached != null) {
          urlToPlay = cached;
        } else {
          final parsed = _parseAudioDataUrl(url);
          if (parsed != null) {
            final fromCard = card.audioMimeType.split(';').first.trim();
            final fromData = parsed.mimeType.split(';').first.trim();
            final mimeForPlay =
                fromCard.startsWith('audio/') ? fromCard : fromData;
            urlToPlay = _listAudioBlob.createObjectUrl(
              bytes: parsed.bytes,
              mimeType: mimeForPlay,
            );
            _listAudioObjectUrlsByFileId[card.audioDriveFileId] = urlToPlay;
          }
        }
      }

      await _listAudio.load(urlToPlay);
      await _listAudio.play();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _playingCardId = null;
        _listAudioPaused = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio afspelen mislukt: $e')),
      );
    }
  }

  Future<String?> _promptTabTitle(
    BuildContext context, {
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Tabblad hernoemen'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Titel tabblad',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Opslaan'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final t = result?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> _renameThisTab(BuildContext context) async {
    final title = await _promptTabTitle(context, initial: _tab.title);
    if (title == null) return;
    try {
      final updated =
          await ref.read(teacherRepositoryProvider).updateTabTitle(tabId: _tab.id, title: title);
      if (!context.mounted) return;
      setState(() => _tab = updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabblad hernoemen mislukt: $e')),
      );
    }
  }

  Future<void> _pickTabColor(BuildContext context) async {
    final String? picked =
        await showTabColorPickerDialog(context, currentHex: _tab.tabColorHex);
    if (picked == null || !context.mounted) return;
    try {
      final TabCategory updated = await ref.read(teacherRepositoryProvider).updateTabColor(
            tabId: _tab.id,
            tabColorHex: picked.isEmpty ? null : picked,
          );
      if (!context.mounted) return;
      setState(() => _tab = updated);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabbladkleur bijwerken mislukt: $e')),
      );
    }
  }

  Future<void> _deleteThisTab(BuildContext context) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Tabblad verwijderen?'),
            content: Text(
              'Verwijdert „${_tab.title}” en alle bijbehorende kaarten. Drive-bestanden blijven staan.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Verwijderen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await ref.read(teacherRepositoryProvider).deleteTabCascade(tabId: _tab.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tabblad verwijderen mislukt: $e')),
      );
    }
  }

  Future<void> _confirmDeleteCard(CardItem card) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kaart verwijderen?'),
            content: Text(
              card.title == null || card.title!.isEmpty
                  ? 'Deze kaart verwijderen? Drive-bestanden worden niet gewist.'
                  : '„${card.title}” verwijderen? Drive-bestanden worden niet gewist.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Verwijderen'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      if (_playingCardId == card.id) {
        await _listAudio.stop();
        _playingCardId = null;
        _listAudioPaused = false;
      }
      await ref.read(teacherRepositoryProvider).deleteCard(cardId: card.id);
      if (!mounted) return;
      _listAudioObjectUrlsByFileId.remove(card.audioDriveFileId);
      await _reloadCards();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaart verwijderen mislukt: $e')),
      );
    }
  }

  List<Widget> _tabAppBarActions(BuildContext context) {
    final Color? accent = parseTabColorHex(_tab.tabColorHex);
    final Color? classesBtnColor =
        accent != null ? foregroundOnTabColor(accent) : null;
    return <Widget>[
      Tooltip(
        message: 'Startpagina Lerarenhulp — leerlingtoegang, ping, leraar inloggen',
        child: TextButton.icon(
          onPressed: () => goToTeachersHelpStart(context),
          icon: const Icon(Icons.home_rounded),
          label: const Text('Startpagina'),
          style: classesBtnColor != null
              ? TextButton.styleFrom(foregroundColor: classesBtnColor)
              : null,
        ),
      ),
      Tooltip(
        message:
            'Terug naar je klassen — open daar de leerlinglink om de klas te proberen',
        child: TextButton.icon(
          onPressed: () => popToTeacherClassList(context),
          icon: const Icon(Icons.grid_view_rounded),
          label: const Text('Klassen'),
          style: classesBtnColor != null
              ? TextButton.styleFrom(foregroundColor: classesBtnColor)
              : null,
        ),
      ),
      PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'color') {
            await _pickTabColor(context);
          } else if (value == 'rename') {
            await _renameThisTab(context);
          } else if (value == 'delete') {
            await _deleteThisTab(context);
          }
        },
        itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'color',
            child: Text('Tabbladkleur'),
          ),
          const PopupMenuItem<String>(
            value: 'rename',
            child: Text('Tabblad hernoemen'),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            child: Text(
              'Tabblad verwijderen',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_cardsLoading) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: _tab.title,
          tabColorHex: _tab.tabColorHex,
          actions: _tabAppBarActions(context),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cardsLoadError != null) {
      return Scaffold(
        appBar: buildTabColoredAppBar(
          context,
          title: _tab.title,
          tabColorHex: _tab.tabColorHex,
          actions: _tabAppBarActions(context),
        ),
        body: Center(child: Text('Fout: $_cardsLoadError')),
      );
    }

    return Scaffold(
      appBar: buildTabColoredAppBar(
        context,
        title: _tab.title,
        tabColorHex: _tab.tabColorHex,
        actions: _tabAppBarActions(context),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Kaarten',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _orderSaving
                          ? null
                          : () async {
                              final created = await Navigator.of(context).push<CardItem?>(
                                MaterialPageRoute<CardItem?>(
                                  builder: (_) => _CreateCardScreen(
                                    userId: widget.userId,
                                    tabId: _tab.id,
                                    sortOrder: _cards.length,
                                  ),
                                ),
                              );
                              if (created == null) return;
                              if (!context.mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => TeacherTabScreen(userId: widget.userId, tab: _tab),
                                ),
                              );
                            },
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text('Kaart toevoegen'),
                    ),
                  ],
                ),
                if (_cards.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Sleep om de volgorde te wijzigen (ook zichtbaar voor leerlingen).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (_orderSaving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _cards.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Nog geen kaarten. Voeg je eerste afbeelding + audio toe.'),
                  )
                : AbsorbPointer(
                    absorbing: _orderSaving,
                    child: ReorderableListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      onReorder: _onReorder,
                      children: <Widget>[
                        for (var i = 0; i < _cards.length; i++)
                          ReorderableDragStartListener(
                            index: i,
                            key: ValueKey<String>(_cards[i].id),
                            child: _TeacherCardRow(
                              card: _cards[i],
                              isPlayingAudio: _playingCardId == _cards[i].id &&
                                  (_listAudio.isPlaying || _listAudioPaused),
                              audioIsPaused: _playingCardId == _cards[i].id && _listAudioPaused,
                              onAudioToggle: () => _toggleListAudio(_cards[i]),
                              onEdit: _orderSaving
                                  ? null
                                  : () => _openEditCard(context, _cards[i]),
                              onDelete: _orderSaving
                                  ? null
                                  : () => _confirmDeleteCard(_cards[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TeacherCardRow extends ConsumerStatefulWidget {
  const _TeacherCardRow({
    required this.card,
    required this.isPlayingAudio,
    required this.audioIsPaused,
    required this.onAudioToggle,
    this.onEdit,
    this.onDelete,
  });

  final CardItem card;
  final bool isPlayingAudio;
  final bool audioIsPaused;
  final VoidCallback onAudioToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  ConsumerState<_TeacherCardRow> createState() => _TeacherCardRowState();
}

class _TeacherCardRowState extends ConsumerState<_TeacherCardRow> {
  String? _imageDataUrl;
  Object? _imageError;
  bool _imageLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _TeacherCardRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.imageDriveFileId != widget.card.imageDriveFileId) {
      setState(() {
        _imageLoading = true;
        _imageError = null;
        _imageDataUrl = null;
      });
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      final drive = ref.read(driveApiProvider);
      final url = await drive.downloadDataUrl(fileId: widget.card.imageDriveFileId);
      if (!mounted) return;
      setState(() {
        _imageDataUrl = url;
        _imageLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _imageError = e;
        _imageLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (_imageLoading) {
      leading = const SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_imageError != null) {
      leading = SizedBox(
        width: 72,
        height: 72,
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      );
    } else {
      leading = SizedBox(
        width: 72,
        height: 72,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Image.network(
              _imageDataUrl!,
              fit: BoxFit.cover,
              width: 72,
              height: 72,
              errorBuilder: (context, error, stackTrace) {
                return const Center(child: Icon(Icons.broken_image_outlined));
              },
            ),
          ),
        ),
      );
    }

    final bool showPause = widget.isPlayingAudio && !widget.audioIsPaused;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: leading,
      title: Text(widget.card.title ?? '(zonder titel)'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton.filledTonal(
            onPressed: widget.onEdit,
            tooltip: 'Kaart bewerken',
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton.filledTonal(
            onPressed: widget.onDelete,
            tooltip: 'Kaart verwijderen',
            icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
          ),
          IconButton.filledTonal(
            onPressed: widget.onAudioToggle,
            tooltip: showPause ? 'Pauze' : 'Audio-voorbeeld afspelen',
            icon: Icon(showPause ? Icons.pause : Icons.play_arrow),
          ),
          Icon(
            Icons.drag_handle,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _CreateCardScreen extends ConsumerStatefulWidget {
  const _CreateCardScreen({
    required this.userId,
    required this.tabId,
    required this.sortOrder,
    this.existing,
  });

  final String userId;
  final String tabId;
  final int sortOrder;
  final CardItem? existing;

  @override
  ConsumerState<_CreateCardScreen> createState() => _CreateCardScreenState();
}

class _CreateCardScreenState extends ConsumerState<_CreateCardScreen> {
  final TextEditingController _title = TextEditingController();
  Uint8List? _imageBytes;
  String? _imageMime;
  String? _imageName;
  String? _imageDriveFileId;

  Uint8List? _audioBytes;
  String? _audioMime;
  String? _audioName;
  String? _audioDriveFileId;
  String? _audioPreviewObjectUrl;
  bool _audioDrivePreviewLoading = false;

  bool _saving = false;
  bool _recordStarting = false;
  bool _recording = false;
  final AudioRecorder _recorder = AudioRecorder.create();
  final AppAudioPlayer _player = AppAudioPlayer.create();
  final BlobUrl _blobUrl = BlobUrl.create();
  bool _isPreviewPlaying = false;
  final DrivePickerService _drivePicker = DrivePickerService.create();

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title.text = existing.title ?? '';
      _imageDriveFileId = existing.imageDriveFileId;
      _imageMime = existing.imageMimeType;
      _imageName = 'Huidige afbeelding';
      _audioDriveFileId = existing.audioDriveFileId;
      _audioMime = existing.audioMimeType;
      _audioName = 'Huidige audio';
      // ignore: unawaited_futures
      _primeExistingAudioPreview();
    }
  }

  Future<void> _primeExistingAudioPreview() async {
    if (!kIsWeb) return;
    final existing = widget.existing;
    if (existing == null) return;
    setState(() => _audioDrivePreviewLoading = true);
    try {
      final drive = ref.read(driveApiProvider);
      final downloaded = await drive.downloadBytes(fileId: existing.audioDriveFileId);
      if (!mounted) return;
      final mimeForPreview = _normalizeAudioMime(
        name: _audioName,
        mimeType: downloaded.mimeType,
      );
      _setPreviewObjectUrl(bytes: downloaded.bytes, mimeType: mimeForPreview);
      setState(() {
        _audioMime = mimeForPreview;
        _audioDrivePreviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioDrivePreviewLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audio voor voorbeeld laden mislukt: $e')),
      );
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _player.stop();
    // Best-effort cleanup to release the microphone if it was opened.
    // ignore: unawaited_futures
    _recorder.dispose();
    final url = _audioPreviewObjectUrl;
    if (url != null && kIsWeb) _blobUrl.revokeObjectUrl(url);
    super.dispose();
  }

  String? get _effectivePreviewUrl => _audioPreviewObjectUrl;

  String _normalizeAudioMime({required String? name, required String mimeType}) {
    final raw = mimeType.trim();
    final mt = raw.split(';').first.trim(); // strip params like charset/codecs
    if (mt.startsWith('audio/')) return mt;
    final lower = (name ?? '').toLowerCase();
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.aac')) return 'audio/aac';
    if (lower.endsWith('.ogg')) return 'audio/ogg';
    if (lower.endsWith('.webm')) return 'audio/webm';
    return mt.isEmpty ? 'application/octet-stream' : mt;
  }

  void _stopPreview() {
    _player.stop();
    if (mounted) setState(() => _isPreviewPlaying = false);
  }

  void _setPreviewObjectUrl({required List<int> bytes, required String mimeType}) {
    if (!kIsWeb) return;
    final old = _audioPreviewObjectUrl;
    if (old != null) _blobUrl.revokeObjectUrl(old);
    final normalized = _normalizeAudioMime(name: _audioName, mimeType: mimeType);
    _audioPreviewObjectUrl = _blobUrl.createObjectUrl(bytes: bytes, mimeType: normalized);
  }

  Future<void> _togglePreviewPlay() async {
    if (!kIsWeb) return;
    if (_recordStarting || _recording || _saving) return;
    final url = _effectivePreviewUrl;
    if (url == null) return;

    if (_isPreviewPlaying) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _isPreviewPlaying = false);
      return;
    }

    try {
      await _player.load(url);
      await _player.play();
      if (!mounted) return;
      setState(() => _isPreviewPlaying = true);
      _player.onEnded.listen((_) {
        if (!mounted) return;
        setState(() => _isPreviewPlaying = false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Afspelen van audio mislukt: $e')),
      );
    }
  }

  Future<void> _pickImageFromDrive() async {
    if (!kIsWeb) return;
    final config = ref.read(appConfigProvider);
    final drive = ref.read(driveApiProvider);
    final token = await drive.getAccessToken();
    final picked = await _drivePicker.pick(
      googleApiKey: config.googleApiKey,
      oauthAccessToken: token,
      isImage: true,
    );
    if (picked == null) return;
    setState(() {
      _imageDriveFileId = picked.id;
      _imageName = picked.name;
      _imageMime = picked.mimeType;
      _imageBytes = null;
    });
  }

  Future<void> _pickAudioFromDrive() async {
    if (!kIsWeb) return;
    final config = ref.read(appConfigProvider);
    final drive = ref.read(driveApiProvider);
    final token = await drive.getAccessToken();
    final picked = await _drivePicker.pick(
      googleApiKey: config.googleApiKey,
      oauthAccessToken: token,
      isImage: false,
    );
    if (picked == null) return;
    _stopPreview();
    setState(() {
      _audioDriveFileId = picked.id;
      _audioName = picked.name;
      _audioMime = picked.mimeType;
      _audioBytes = null;
      _audioDrivePreviewLoading = true;
    });

    try {
      final downloaded = await drive.downloadBytes(fileId: picked.id);
      if (!mounted) return;
      final mimeForPreview = _normalizeAudioMime(
        name: picked.name,
        mimeType: downloaded.mimeType,
      );
      _setPreviewObjectUrl(bytes: downloaded.bytes, mimeType: mimeForPreview);
      setState(() {
        // Keep the picker MIME if Drive returns application/octet-stream.
        _audioMime = mimeForPreview;
        _audioDrivePreviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _audioDrivePreviewLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voorbeeld downloaden mislukt: $e')),
      );
    }
  }

  Future<void> _toggleRecord() async {
    if (!kIsWeb) return;
    if (_saving) return;
    if (_recordStarting) return;
    if (_recording) {
      final rec = await _recorder.stop();
      if (!mounted) return;
      if (rec.bytes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opname was leeg. Probeer het opnieuw.')),
        );
        setState(() => _recording = false);
        return;
      }

      final normalized = _normalizeAudioMime(
        name: _audioName ?? 'recording.wav',
        mimeType: rec.mimeType,
      );
      _setPreviewObjectUrl(bytes: rec.bytes, mimeType: normalized);
      setState(() {
        _recording = false;
        _audioBytes = Uint8List.fromList(rec.bytes);
        _audioMime = normalized;
        _audioName = 'recording_${DateTime.now().millisecondsSinceEpoch}.wav';
        _audioDriveFileId = null;
      });
      return;
    }

    try {
      _stopPreview();
      setState(() => _recordStarting = true);
      await _recorder.start();
      if (!mounted) return;
      setState(() {
        _recordStarting = false;
        _recording = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordStarting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opnemen mislukt: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    _stopPreview();
    final hasImage = (_imageDriveFileId != null) || (_imageBytes != null);
    if (!hasImage || _imageMime == null || _imageName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies eerst een afbeelding.')),
      );
      return;
    }
    final hasAudio = (_audioDriveFileId != null) || (_audioBytes != null);
    if (!hasAudio || _audioMime == null || _audioName == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies of neem eerst audio op.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final drive = ref.read(driveApiProvider);
      final repo = ref.read(teacherRepositoryProvider);

      final img = _imageDriveFileId != null
          ? DriveUploadedFile(id: _imageDriveFileId!, name: _imageName!, mimeType: _imageMime!)
          : await drive.uploadBytes(
              name: _imageName!,
              mimeType: _imageMime!,
              bytes: _imageBytes!,
            );

      final aud = _audioDriveFileId != null
          ? DriveUploadedFile(id: _audioDriveFileId!, name: _audioName!, mimeType: _audioMime!)
          : await drive.uploadBytes(
              name: _audioName!,
              mimeType: _audioMime!,
              bytes: _audioBytes!,
            );

      final String? titleText =
          _title.text.trim().isEmpty ? null : _title.text.trim();

      final CardItem result;
      if (widget.existing != null) {
        result = await repo.updateCard(
          cardId: widget.existing!.id,
          title: titleText,
          imageDriveFileId: img.id,
          audioDriveFileId: aud.id,
          imageMimeType: img.mimeType,
          audioMimeType: aud.mimeType,
        );
      } else {
        result = await repo.createCard(
          teacherId: widget.userId,
          tabId: widget.tabId,
          title: titleText,
          imageDriveFileId: img.id,
          audioDriveFileId: aud.id,
          imageMimeType: img.mimeType,
          audioMimeType: aud.mimeType,
          sortOrder: widget.sortOrder,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop<CardItem>(result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opslaan mislukt: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _effectivePreviewUrl != null && !_audioDrivePreviewLoading;
    final bool isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Kaart bewerken' : 'Nieuwe kaart')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Titel (optioneel)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Afbeelding'),
              subtitle: Text(_imageName ?? 'Niet gekozen'),
              trailing: Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: _saving ? null : _pickImageFromDrive,
                    child: const Text('Uit Drive'),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Audio'),
              subtitle: Text(_audioName ?? 'Niet gekozen'),
              trailing: Wrap(
                spacing: 8,
                children: <Widget>[
                  FilledButton.tonal(
                    onPressed: _saving ? null : _pickAudioFromDrive,
                    child: const Text('Uit Drive'),
                  ),
                  FilledButton(
                    onPressed: (_saving || _recordStarting) ? null : _toggleRecord,
                    child: _recordStarting
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('Starten...'),
                            ],
                          )
                        : Text(_recording ? 'Stoppen' : 'Opnemen'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: (_saving || _recordStarting || _recording || !canPreview)
                        ? null
                        : _togglePreviewPlay,
                    icon: _audioDrivePreviewLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_isPreviewPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(_audioDrivePreviewLoading ? 'Laden...' : 'Voorbeeld'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Opslaan...' : (isEdit ? 'Wijzigingen opslaan' : 'Kaart opslaan')),
          ),
        ],
      ),
    );
  }
}

