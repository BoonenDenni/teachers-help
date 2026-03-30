import 'file_picker.dart';

FilePickerService createFilePickerService() => _StubFilePicker();

class _StubFilePicker implements FilePickerService {
  @override
  Future<PickedFile?> pick({required List<String> acceptMimeTypes}) async {
    return null;
  }
}

