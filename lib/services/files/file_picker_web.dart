import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'file_picker.dart';

FilePickerService createFilePickerService() => _WebFilePicker();

class _WebFilePicker implements FilePickerService {
  @override
  Future<PickedFile?> pick({required List<String> acceptMimeTypes}) async {
    final html.FileUploadInputElement input = html.FileUploadInputElement();
    input.accept = acceptMimeTypes.join(',');
    input.multiple = false;
    input.click();

    await input.onChange.first;
    final html.File? file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) return null;

    final reader = html.FileReader();
    final completer = Completer<PickedFile?>();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is! ByteBuffer) {
        completer.complete(null);
        return;
      }
      completer.complete(
        PickedFile(
          name: file.name,
          mimeType: file.type.isEmpty ? 'application/octet-stream' : file.type,
          bytes: Uint8List.view(result).toList(growable: false),
        ),
      );
    });
    reader.onError.listen((_) => completer.complete(null));

    reader.readAsArrayBuffer(file);
    return completer.future;
  }
}

