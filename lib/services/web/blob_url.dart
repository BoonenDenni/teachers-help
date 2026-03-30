import 'blob_url_stub.dart' if (dart.library.html) 'blob_url_web.dart';

abstract class BlobUrl {
  static BlobUrl create() => createBlobUrl();

  /// Returns a `blob:` URL for in-memory bytes.
  String createObjectUrl({required List<int> bytes, required String mimeType});

  /// Releases a previously created `blob:` URL.
  void revokeObjectUrl(String url);
}

