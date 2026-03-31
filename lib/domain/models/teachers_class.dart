import 'package:flutter/foundation.dart';

@immutable
class TeachersClass {
  const TeachersClass({
    required this.id,
    required this.teacherId,
    required this.name,
    required this.publicToken,
    required this.driveFolderId,
  });

  final String id;
  final String teacherId;
  final String name;
  final String publicToken;
  final String? driveFolderId;

  static TeachersClass fromDoc(Map<String, dynamic> doc) {
    return TeachersClass(
      id: doc['\$id'] as String,
      teacherId: doc['teacherId'] as String,
      name: doc['name'] as String,
      publicToken: doc['publicToken'] as String,
      driveFolderId: (doc['driveFolderId'] as String?)?.trim().isEmpty == true
          ? null
          : (doc['driveFolderId'] as String?),
    );
  }
}

