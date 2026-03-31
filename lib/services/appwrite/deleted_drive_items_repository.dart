import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'appwrite_providers.dart';

final deletedDriveItemsRepositoryProvider = Provider<DeletedDriveItemsRepository>((ref) {
  final db = ref.watch(appwriteDatabasesProvider);
  final config = ref.watch(appConfigProvider);
  return DeletedDriveItemsRepository(
    databases: db,
    databaseId: config.appwriteDatabaseId,
    collectionId: 'deleted_drive_items',
  );
});

class DeletedDriveItem {
  const DeletedDriveItem({
    required this.id,
    required this.teacherId,
    required this.driveFileId,
    required this.name,
    required this.kind,
    required this.deletedAtIso,
    required this.restoredAtIso,
  });

  final String id;
  final String teacherId;
  final String driveFileId;
  final String name;
  final String kind;
  final String deletedAtIso;
  final String? restoredAtIso;

  static DeletedDriveItem fromDoc(Map<String, dynamic> doc) {
    final restoredRaw = doc['restoredAt'] as String?;
    final restored = (restoredRaw != null && restoredRaw.trim().isNotEmpty) ? restoredRaw : null;
    return DeletedDriveItem(
      id: doc['\$id'] as String,
      teacherId: doc['teacherId'] as String,
      driveFileId: doc['driveFileId'] as String,
      name: (doc['name'] as String?) ?? 'item',
      kind: (doc['kind'] as String?) ?? 'unknown',
      deletedAtIso: doc['deletedAt'] as String,
      restoredAtIso: restored,
    );
  }
}

class DeletedDriveItemsRepository {
  DeletedDriveItemsRepository({
    required this.databases,
    required this.databaseId,
    required this.collectionId,
  });

  final Databases databases;
  final String databaseId;
  final String collectionId;

  Future<List<DeletedDriveItem>> listForTeacher(String teacherId) async {
    final models.DocumentList res = await databases.listDocuments(
      databaseId: databaseId,
      collectionId: collectionId,
      queries: <String>[
        Query.equal('teacherId', teacherId),
        Query.orderDesc('deletedAt'),
        Query.limit(100),
      ],
    );
    return res.documents.map((d) => DeletedDriveItem.fromDoc(d.data)).toList();
  }

  Future<void> logDeleted({
    required String teacherId,
    required String driveFileId,
    required String name,
    required String kind,
  }) async {
    await databases.createDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: ID.unique(),
      data: <String, dynamic>{
        'teacherId': teacherId,
        'driveFileId': driveFileId,
        'name': name,
        'kind': kind,
        'deletedAt': DateTime.now().toUtc().toIso8601String(),
        'restoredAt': '',
      },
      permissions: <String>[
        Permission.read(Role.user(teacherId)),
        Permission.update(Role.user(teacherId)),
        Permission.delete(Role.user(teacherId)),
      ],
    );
  }

  Future<void> markRestored({required String deletedItemId}) async {
    await databases.updateDocument(
      databaseId: databaseId,
      collectionId: collectionId,
      documentId: deletedItemId,
      data: <String, dynamic>{
        'restoredAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }
}

