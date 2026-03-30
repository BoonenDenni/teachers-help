import 'drive_picker_stub.dart' if (dart.library.js) 'drive_picker_web.dart';

class DrivePickedFile {
  const DrivePickedFile({
    required this.id,
    required this.name,
    required this.mimeType,
  });

  final String id;
  final String name;
  final String mimeType;
}

abstract class DrivePickerService {
  static DrivePickerService create() => createDrivePickerService();

  Future<DrivePickedFile?> pick({
    required String googleApiKey,
    required String oauthAccessToken,
    required bool isImage,
  });
}

