import 'drive_picker.dart';

DrivePickerService createDrivePickerService() => _UnsupportedDrivePicker();

class _UnsupportedDrivePicker implements DrivePickerService {
  @override
  Future<DrivePickedFile?> pick({
    required String googleApiKey,
    required String oauthAccessToken,
    required bool isImage,
  }) {
    throw UnsupportedError('Drive Picker is only supported on Flutter Web.');
  }
}

