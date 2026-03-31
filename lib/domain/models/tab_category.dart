import 'package:flutter/foundation.dart';

@immutable
class TabCategory {
  const TabCategory({
    required this.id,
    required this.classId,
    required this.title,
    required this.sortOrder,
    required this.driveFolderId,
    this.tabColorHex,
  });

  final String id;
  final String classId;
  final String title;
  final int sortOrder;
  final String? driveFolderId;

  /// Optional `#RRGGBB` accent for student UI and tab list.
  final String? tabColorHex;

  static TabCategory fromDoc(Map<String, dynamic> doc) {
    final dynamic rawHex = doc['tabColorHex'];
    final String? hex = rawHex is String && rawHex.trim().isNotEmpty ? rawHex.trim() : null;
    return TabCategory(
      id: doc['\$id'] as String,
      classId: doc['classId'] as String,
      title: doc['title'] as String,
      sortOrder: (doc['sortOrder'] as num).toInt(),
      driveFolderId: (doc['driveFolderId'] as String?)?.trim().isEmpty == true
          ? null
          : (doc['driveFolderId'] as String?),
      tabColorHex: hex,
    );
  }
}

