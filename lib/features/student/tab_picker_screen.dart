import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'viewer/card_viewer_screen.dart';
import '../../services/appwrite/student_repository.dart';
import '../../domain/models/tab_category.dart';
import '../../utils/tab_color.dart';

class TabPickerScreen extends ConsumerWidget {
  const TabPickerScreen({super.key, required this.publicToken});

  final String publicToken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(studentRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kies een tabblad')),
      body: FutureBuilder(
        future: repo.getClassByPublicToken(publicToken),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fout: ${snapshot.error}'));
          }
          final clazz = snapshot.data;
          if (clazz == null) {
            return const Center(child: Text('Klas niet gevonden.'));
          }

          return FutureBuilder(
            future: repo.listTabs(clazz.id),
            builder: (context, tabsSnap) {
              if (tabsSnap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (tabsSnap.hasError) {
                return Center(child: Text('Fout: ${tabsSnap.error}'));
              }
              final tabs = tabsSnap.data ?? const <TabCategory>[];
              if (tabs.isEmpty) {
                return const Center(child: Text('Nog geen tabbladen.'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: tabs.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  final TabCategory tab = tabs[index];
                  final Color? accent = parseTabColorHex(tab.tabColorHex);
                  final theme = Theme.of(context);
                  final Color tileBg = accent ??
                      theme.colorScheme.surfaceContainerHighest;
                  final Color titleColor =
                      accent != null ? foregroundOnTabColor(accent) : theme.colorScheme.onSurface;
                  final Color subtitleColor = accent != null
                      ? foregroundOnTabColor(accent).withValues(alpha: 0.85)
                      : theme.colorScheme.onSurfaceVariant;
                  final Color iconColor =
                      accent != null ? foregroundOnTabColor(accent) : theme.colorScheme.onSurfaceVariant;
                  return ListTile(
                    tileColor: tileBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    title: Text(
                      tab.title,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    subtitle: Text(
                      'Klas: ${clazz.name}',
                      style: TextStyle(color: subtitleColor),
                    ),
                    trailing: Icon(Icons.chevron_right, color: iconColor),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CardViewerScreen(
                            publicToken: publicToken,
                            tabId: tab.id,
                            tabTitle: tab.title,
                            tabColorHex: tab.tabColorHex,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

