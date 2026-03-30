import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/teachers_class.dart';
import '../../services/appwrite/auth_controller.dart';
import '../../services/appwrite/teacher_repository.dart';
import '../../services/drive/drive_api.dart';
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

  @override
  void initState() {
    super.initState();
    _connectionFuture = ref.read(driveApiProvider).getConnectionStatus();
  }

  void _refreshConnection() {
    setState(() {
      _connectionFuture = ref.read(driveApiProvider).getConnectionStatus();
    });
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
            tooltip: 'Startpagina Lerarenhulp (leerlingentoegang, ping)',
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
                          final connected = s.data == true;
                          return Row(
                            children: <Widget>[
                              Icon(
                                connected ? Icons.check_circle : Icons.error,
                                color: connected
                                    ? Colors.green
                                    : Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  connected
                                      ? 'Verbonden'
                                      : 'Nog niet verbonden',
                                ),
                              ),
                              if (!connected)
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
                      await repo.createClass(
                        teacherId: widget.userId,
                        name: name,
                        teacherNameForToken: teacherLabel.isEmpty ? 'Leraar' : teacherLabel,
                      );
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
                              await repo.updateClassName(classId: c.id, name: newName);
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

