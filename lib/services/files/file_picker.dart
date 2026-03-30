import 'file_picker_stub.dart' if (dart.library.html) 'file_picker_web.dart';

class PickedFile {
  const PickedFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final List<int> bytes;
}

abstract class FilePickerService {
  static FilePickerService create() => createFilePickerService();

  Future<PickedFile?> pick({required List<String> acceptMimeTypes});
}

