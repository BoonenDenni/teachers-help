import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite/deleted_drive_items_repository.dart';
import '../../services/drive/drive_api.dart';

class DriveRestoreScreen extends ConsumerWidget {
  const DriveRestoreScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(deletedDriveItemsRepositoryProvider);
    final drive = ref.watch(driveApiProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Herstel Drive items')),
      body: FutureBuilder<List<DeletedDriveItem>>(
        future: repo.listForTeacher(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Laden mislukt: ${snapshot.error}'));
          }
          final items = (snapshot.data ?? <DeletedDriveItem>[])
              .where((e) => e.restoredAtIso == null)
              .toList();
          if (items.isEmpty) {
            return const Center(child: Text('Geen verwijderde items om te herstellen.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, i) {
              final it = items[i];
              return ListTile(
                title: Text(it.name),
                subtitle: Text('Type: ${it.kind} • Verwijderd: ${it.deletedAtIso}'),
                trailing: FilledButton.tonal(
                  onPressed: () async {
                    try {
                      await drive.restoreAndMark(fileId: it.driveFileId, deletedItemId: it.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Hersteld.')),
                      );
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => DriveRestoreScreen(userId: userId),
                        ),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Herstellen mislukt: $e')),
                      );
                    }
                  },
                  child: const Text('Herstellen'),
                ),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: items.length,
          );
        },
      ),
    );
  }
}

