import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';

import 'drive_picker.dart';

DrivePickerService createDrivePickerService() => _WebDrivePicker();

class _WebDrivePicker implements DrivePickerService {
  Future<void> _loadPicker() async {
    // Google APIs script is expected to be included in web/index.html.
    final gapi = js.context['gapi'];
    if (gapi == null) {
      throw StateError('Google API (gapi) not loaded. Add it to web/index.html.');
    }

    final completer = Completer<void>();
    gapi.callMethod('load', <dynamic>[
      'picker',
      js.JsObject.jsify(<String, dynamic>{
        'callback': () => completer.complete(),
      }),
    ]);
    await completer.future.timeout(const Duration(seconds: 10));
  }

  @override
  Future<DrivePickedFile?> pick({
    required String googleApiKey,
    required String oauthAccessToken,
    required bool isImage,
  }) async {
    if (!kIsWeb) throw UnsupportedError('Drive Picker is only supported on web.');
    if (googleApiKey.isEmpty) {
      throw StateError('Missing GOOGLE_API_KEY (dart-define).');
    }
    if (oauthAccessToken.isEmpty) {
      throw StateError('Missing OAuth access token.');
    }

    await _loadPicker();

    final google = js.context['google'];
    final pickerNs = google['picker'];

    // Use the generic Docs view for both, and filter by MIME types.
    // DOCUMENTS_IMAGES can miss regular .png/.jpg files in Drive.
    final viewId = pickerNs['ViewId']['DOCS'];
    final view = js.JsObject(pickerNs['View'], <dynamic>[viewId]);

    if (isImage) {
      view.callMethod('setMimeTypes', <dynamic>['image/png,image/jpeg,image/webp,image/gif,image/bmp']);
    } else {
      // "audio/" MIME types are not guaranteed for Drive items; this is best-effort.
      view.callMethod('setMimeTypes', <dynamic>['audio/mpeg,audio/wav,audio/webm,audio/ogg,audio/mp4']);
    }

    final completer = Completer<DrivePickedFile?>();

    final actionPicked = pickerNs['Action']['PICKED'];
    final actionCancel = pickerNs['Action']['CANCEL'];
    final respDocs = pickerNs['Response']['DOCUMENTS'];
    final docIdKey = pickerNs['Document']['ID'];
    final docNameKey = pickerNs['Document']['NAME'];
    final docMimeKey = pickerNs['Document']['MIME_TYPE'];

    void callback(dynamic data) {
      final action = data['action'];
      if (action == actionCancel) {
        completer.complete(null);
        return;
      }
      if (action != actionPicked) return;

      final docs = data[respDocs] as List<dynamic>?;
      if (docs == null || docs.isEmpty) {
        completer.complete(null);
        return;
      }
      final doc = docs.first;
      final id = doc[docIdKey] as String?;
      if (id == null || id.isEmpty) {
        completer.complete(null);
        return;
      }
      final name = (doc[docNameKey] as String?) ?? 'file';
      final mime = (doc[docMimeKey] as String?) ?? 'application/octet-stream';
      completer.complete(DrivePickedFile(id: id, name: name, mimeType: mime));
    }

    final builder = js.JsObject(pickerNs['PickerBuilder']);

    builder.callMethod('addView', <dynamic>[view]);
    builder.callMethod('setOAuthToken', <dynamic>[oauthAccessToken]);
    builder.callMethod('setDeveloperKey', <dynamic>[googleApiKey]);
    // dart:js callbacks are callable from JS directly.
    builder.callMethod('setCallback', <dynamic>[callback]);
    builder.callMethod('setOrigin', <dynamic>[html.window.location.origin]);

    final picker = builder.callMethod('build', const <dynamic>[]);
    picker.callMethod('setVisible', const <dynamic>[true]);

    return completer.future;
  }

  @override
  Future<DrivePickedFolder?> pickFolder({
    required String googleApiKey,
    required String oauthAccessToken,
  }) async {
    if (!kIsWeb) throw UnsupportedError('Drive Picker is only supported on web.');
    if (googleApiKey.isEmpty) {
      throw StateError('Missing GOOGLE_API_KEY (dart-define).');
    }
    if (oauthAccessToken.isEmpty) {
      throw StateError('Missing OAuth access token.');
    }

    await _loadPicker();

    final google = js.context['google'];
    final pickerNs = google['picker'];

    // Folder picker view.
    final viewId = pickerNs['ViewId']['FOLDERS'];
    final view = js.JsObject(pickerNs['View'], <dynamic>[viewId]);
    // Ensure folders are selectable.
    view.callMethod('setIncludeFolders', const <dynamic>[true]);
    view.callMethod('setSelectFolderEnabled', const <dynamic>[true]);

    final completer = Completer<DrivePickedFolder?>();

    final actionPicked = pickerNs['Action']['PICKED'];
    final actionCancel = pickerNs['Action']['CANCEL'];
    final respDocs = pickerNs['Response']['DOCUMENTS'];
    final docIdKey = pickerNs['Document']['ID'];
    final docNameKey = pickerNs['Document']['NAME'];

    void callback(dynamic data) {
      final action = data['action'];
      if (action == actionCancel) {
        completer.complete(null);
        return;
      }
      if (action != actionPicked) return;

      final docs = data[respDocs] as List<dynamic>?;
      if (docs == null || docs.isEmpty) {
        completer.complete(null);
        return;
      }
      final doc = docs.first;
      final id = doc[docIdKey] as String?;
      if (id == null || id.isEmpty) {
        completer.complete(null);
        return;
      }
      final name = (doc[docNameKey] as String?) ?? 'folder';
      completer.complete(DrivePickedFolder(id: id, name: name));
    }

    final builder = js.JsObject(pickerNs['PickerBuilder']);
    builder.callMethod('addView', <dynamic>[view]);
    builder.callMethod('setOAuthToken', <dynamic>[oauthAccessToken]);
    builder.callMethod('setDeveloperKey', <dynamic>[googleApiKey]);
    builder.callMethod('setCallback', <dynamic>[callback]);
    builder.callMethod('setOrigin', <dynamic>[html.window.location.origin]);

    final picker = builder.callMethod('build', const <dynamic>[]);
    picker.callMethod('setVisible', const <dynamic>[true]);

    return completer.future;
  }
}

