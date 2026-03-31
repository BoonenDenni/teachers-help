import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/teachers_class.dart';
import '../../services/appwrite/auth_controller.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/drive/drive_api.dart';
import '../../services/appwrite/appwrite_providers.dart';
import '../../services/drive/drive_picker.dart';
import 'drive_restore_screen.dart';
import 'teacher_class_screen.dart';
import 'teacher_navigation.dart';

class TeacherDashboardScreen extends ConsumerStatefulWidget {
  const TeacherDashboardScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends ConsumerState<TeacherDashboardScreen> {
  Future<bool>? _connectionFuture;
  Future<String>? _rootFolderFuture;
  final DrivePickerService _drivePicker = DrivePickerService.create();

  @override
  void initState() {
    super.initState();
    _connectionFuture = ref.read(driveApiProvider).getConnectionStatus();
    _rootFolderFuture = ref.read(driveApiProvider).getRootFolderId();
  }

  void _refreshConnection() {
    setState(() {
      _connectionFuture = ref.read(driveApiProvider).getConnectionStatus();
    });
  }

  void _refreshRootFolder() {
    setState(() {
      _rootFolderFuture = ref.read(driveApiProvider).getRootFolderId();
    });
  }

  Future<String?> _promptFolderId(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Drive-map instellen'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Folder ID of Drive-link',
              hintText: 'Bijv. https://drive.google.com/drive/folders/<id>',
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
    final raw = result?.trim();
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'/folders/([a-zA-Z0-9_-]+)').firstMatch(raw);
    final id = (m != null) ? m.group(1) : raw;
    return (id == null || id.trim().isEmpty) ? null : id.trim();
  }

  Future<String?> _pickDriveFolderId() async {
    // Folder picker requires web + api key + oauth token.
    final config = ref.read(appConfigProvider);
    final drive = ref.read(driveApiProvider);
    final token = await drive.getAccessToken();
    final picked = await _drivePicker.pickFolder(
      googleApiKey: config.googleApiKey,
      oauthAccessToken: token,
    );
    return picked?.id;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(teacherRepositoryProvider);
    final drive = ref.watch(driveApiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jouw klassen'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Startpagina Lerarenhulp (leerlingentoegang)',
            onPressed: () => goToTeachersHelpStart(context),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: 'Uitloggen',
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: FutureBuilder<List<TeachersClass>>(
        future: repo.listClasses(teacherId: widget.userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fout: ${snapshot.error}'));
          }
          final classes = snapshot.data ?? <TeachersClass>[];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Google Drive',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<bool>(
                        future: _connectionFuture,
                        builder: (context, s) {
                          final loading = s.connectionState != ConnectionState.done;
                          final hasError = s.hasError;
                          final connected = s.data == true;

                          final Color statusColor;
                          final IconData statusIcon;
                          final String statusText;
                          if (loading) {
                            statusColor = Theme.of(context).colorScheme.primary;
                            statusIcon = Icons.hourglass_top;
                            statusText = 'Controleren…';
                          } else if (hasError) {
                            statusColor = Theme.of(context).colorScheme.error;
                            statusIcon = Icons.warning_amber;
                            statusText = 'Status onbekend';
                          } else if (connected) {
                            statusColor = Colors.green;
                            statusIcon = Icons.check_circle;
                            statusText = 'Verbonden';
                          } else {
                            statusColor = Theme.of(context).colorScheme.error;
                            statusIcon = Icons.error;
                            statusText = 'Nog niet verbonden';
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Icon(statusIcon, color: statusColor),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(statusText)),
                                  if (loading)
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else if (hasError)
                                    FilledButton.tonal(
                                      onPressed: _refreshConnection,
                                      child: const Text('Opnieuw'),
                                    )
                                  else if (!connected)
                                    FilledButton.tonal(
                                      onPressed: () async {
                                        final url = await drive.getOAuthStartUrl();
                                        if (!context.mounted) return;
                                        await Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) => _OAuthLaunchScreen(url: url),
                                          ),
                                        );
                                        if (!mounted) return;
                                        _refreshConnection();
                                        _refreshRootFolder();
                                      },
                                      child: const Text('Verbinden'),
                                    )
                                  else
                                    FilledButton.tonal(
                                      style: FilledButton.styleFrom(
                                        foregroundColor: Theme.of(context).colorScheme.error,
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Google Drive loskoppelen?'),
                                                content: const Text(
                                                  'Hiermee wordt je opgeslagen verbinding verwijderd. Je kunt later opnieuw verbinden.',
                                                ),
                                                actions: <Widget>[
                                                  TextButton(
                                                    onPressed: () => Navigator.of(context).pop(false),
                                                    child: const Text('Annuleren'),
                                                  ),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(
                                                      backgroundColor: Theme.of(context).colorScheme.error,
                                                      foregroundColor: Theme.of(context).colorScheme.onError,
                                                    ),
                                                    onPressed: () => Navigator.of(context).pop(true),
                                                    child: const Text('Loskoppelen'),
                                                  ),
                                                ],
                                              ),
                                            ) ??
                                            false;
                                        if (!ok) return;
                                        try {
                                          await drive.disconnect();
                                          if (!mounted) return;
                                          _refreshConnection();
                                          _refreshRootFolder();
                                        } catch (e) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Loskoppelen mislukt: $e')),
                                          );
                                        }
                                      },
                                      child: const Text('Loskoppelen'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              FutureBuilder<String>(
                                future: _rootFolderFuture,
                                builder: (context, r) {
                                  final loadingRoot = r.connectionState != ConnectionState.done;
                                  final root = (r.data ?? '').trim();
                                  if (!connected) {
                                    return const Text('Koppel Drive om een uploadmap in te stellen.');
                                  }
                                  return Row(
                                    children: <Widget>[
                                      Expanded(
                                        child: Text(
                                          root.isEmpty
                                              ? 'Uploadmap: niet ingesteld'
                                              : 'Uploadmap: ingesteld',
                                        ),
                                      ),
                                      if (loadingRoot)
                                        const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      else
                                        FilledButton.tonal(
                                          onPressed: () async {
                                            String? id;
                                            try {
                                              id = await _pickDriveFolderId();
                                            } catch (_) {
                                              id = null;
                                            }
                                            id ??= await _promptFolderId(context);
                                            if (id == null || !context.mounted) return;
                                            try {
                                              await drive.setRootFolderId(id);
                                              if (!context.mounted) return;
                                              _refreshRootFolder();
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Uploadmap ingesteld.')),
                                              );
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(content: Text('Uploadmap instellen mislukt: $e')),
                                              );
                                            }
                                          },
                                          child: Text(root.isEmpty ? 'Instellen' : 'Wijzigen'),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              if (connected)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => DriveRestoreScreen(userId: widget.userId),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Herstel Drive items'),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Klassen',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      final name = await _askName(
                        context,
                        title: 'Nieuwe klas',
                        label: 'Klasnaam',
                        initial: null,
                        confirmLabel: 'Aanmaken',
                      );
                      if (name == null) return;
                      final authUser = ref.read(authControllerProvider).value;
                      final teacherLabel = (authUser?.name ?? 'Leraar').trim();
                      final created = await repo.createClass(
                        teacherId: widget.userId,
                        name: name,
                        teacherNameForToken: teacherLabel.isEmpty ? 'Leraar' : teacherLabel,
                      );
                      try {
                        final root = await drive.getRootFolderId();
                        if (root.trim().isNotEmpty) {
                          final appFolder = await drive.ensureFolder(parentId: root, name: 'Teachers Help');
                          final classesFolder = await drive.ensureFolder(parentId: appFolder, name: 'Klassen');
                          final classFolder = await drive.ensureFolder(parentId: classesFolder, name: created.name);
                          await repo.setClassDriveFolderId(classId: created.id, driveFolderId: classFolder);
                        }
                      } catch (_) {
                        // Best effort: class can exist without a Drive folder mapping.
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => TeacherDashboardScreen(userId: widget.userId),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Nieuwe klas'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (classes.isEmpty)
                const Text('Nog geen klassen. Maak je eerste klas aan.'),
              ...classes.map(
                (c) => ListTile(
                  title: Text(c.name),
                  subtitle: Text('Leerlinglink-token: ${c.publicToken}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) async {
                          if (value == 'edit') {
                            final newName = await _askName(
                              context,
                              title: 'Klas hernoemen',
                              label: 'Klasnaam',
                              initial: c.name,
                              confirmLabel: 'Opslaan',
                            );
                            if (newName == null) return;
                            try {
                              final updated = await repo.updateClassName(classId: c.id, name: newName);
                              final folderId = updated.driveFolderId?.trim();
                              if (folderId != null && folderId.isNotEmpty) {
                                await drive.renameFolder(folderId: folderId, newName: updated.name);
                              }
                              if (!context.mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => TeacherDashboardScreen(userId: widget.userId),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hernoemen mislukt: $e')),
                              );
                            }
                          } else if (value == 'delete') {
                            final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Klas verwijderen?'),
                                    content: Text(
                                      'Hiermee worden permanent "${c.name}", alle tabbladen en alle kaarten verwijderd. '
                                      'Bestanden in Google Drive blijven staan.',
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
                              final folderId = c.driveFolderId?.trim();
                              if (folderId != null && folderId.isNotEmpty) {
                                await drive.trashAndLog(
                                  fileId: folderId,
                                  name: c.name,
                                  kind: 'class-folder',
                                );
                              }
                              await repo.deleteClassCascade(classId: c.id);
                              if (!context.mounted) return;
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute<void>(
                                  builder: (_) => TeacherDashboardScreen(userId: widget.userId),
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Verwijderen mislukt: $e')),
                              );
                            }
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Text('Klas hernoemen'),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Text(
                              'Klas verwijderen',
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => TeacherClassScreen(userId: widget.userId, clazz: c),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String label,
    required String? initial,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController(text: initial ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuleren'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final name = result?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }
}

class _OAuthLaunchScreen extends StatelessWidget {
  const _OAuthLaunchScreen({required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive verbinden')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Klik hieronder om Google-aanmelding te openen en toegang tot Drive te geven.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Kon browser niet openen. Kopieer de URL hieronder.')),
                      );
                    }
                  },
                  child: const Text('Google-aanmelding openen'),
                ),
                const SizedBox(height: 12),
                SelectableText(url.toString()),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Klaar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

