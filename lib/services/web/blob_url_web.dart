import 'dart:html' as html;
import 'dart:typed_data';

import 'blob_url.dart';

BlobUrl createBlobUrl() => _WebBlobUrl();

class _WebBlobUrl implements BlobUrl {
  @override
  String createObjectUrl({required List<int> bytes, required String mimeType}) {
    // Important: pass real binary bytes to the Blob constructor.
    // A plain List<int> can end up as a JS Array of numbers (not bytes),
    // which breaks media decoding in some browsers.
    final Uint8List u8 = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = html.Blob(<dynamic>[u8], mimeType);
    return html.Url.createObjectUrlFromBlob(blob);
  }

  @override
  void revokeObjectUrl(String url) {
    html.Url.revokeObjectUrl(url);
  }
}

