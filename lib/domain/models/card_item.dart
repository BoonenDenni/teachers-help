import 'package:flutter/foundation.dart';

@immutable
class CardItem {
  const CardItem({
    required this.id,
    required this.tabId,
    required this.title,
    required this.imageDriveFileId,
    required this.audioDriveFileId,
    required this.imageMimeType,
    required this.audioMimeType,
    required this.imageAnnotationsJson,
    required this.driveFolderId,
    required this.sortOrder,
    required this.createdAtIso,
  });

  final String id;
  final String tabId;
  final String? title;
  final String imageDriveFileId;
  final String audioDriveFileId;
  final String imageMimeType;
  final String audioMimeType;
  final String? imageAnnotationsJson;
  final String? driveFolderId;
  final int sortOrder;
  final String createdAtIso;

  CardItem copyWith({int? sortOrder}) {
    return CardItem(
      id: id,
      tabId: tabId,
      title: title,
      imageDriveFileId: imageDriveFileId,
      audioDriveFileId: audioDriveFileId,
      imageMimeType: imageMimeType,
      audioMimeType: audioMimeType,
      imageAnnotationsJson: imageAnnotationsJson,
      driveFolderId: driveFolderId,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAtIso: createdAtIso,
    );
  }

  static CardItem fromDoc(Map<String, dynamic> doc) {
    return CardItem(
      id: doc['\$id'] as String,
      tabId: doc['tabId'] as String,
      title: doc['title'] as String?,
      imageDriveFileId: doc['imageDriveFileId'] as String,
      audioDriveFileId: doc['audioDriveFileId'] as String,
      imageMimeType: doc['imageMimeType'] as String,
      audioMimeType: doc['audioMimeType'] as String,
      imageAnnotationsJson: doc['imageAnnotationsJson'] as String?,
      driveFolderId: (doc['driveFolderId'] as String?)?.trim().isEmpty == true
          ? null
          : (doc['driveFolderId'] as String?),
      sortOrder: (doc['sortOrder'] as num).toInt(),
      createdAtIso: doc['createdAt'] as String,
    );
  }
}

