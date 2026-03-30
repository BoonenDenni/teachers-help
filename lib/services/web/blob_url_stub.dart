import 'blob_url.dart';

BlobUrl createBlobUrl() => _StubBlobUrl();

class _StubBlobUrl implements BlobUrl {
  @override
  String createObjectUrl({required List<int> bytes, required String mimeType}) {
    throw UnsupportedError('BlobUrl is only supported on web.');
  }

  @override
  void revokeObjectUrl(String url) {
    // no-op
  }
}

