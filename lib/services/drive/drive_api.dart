import 'dart:convert';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../appwrite/appwrite_providers.dart';

final driveApiProvider = Provider<DriveApi>((ref) {
  final functions = ref.watch(appwriteFunctionsProvider);
  final config = ref.watch(appConfigProvider);
  return DriveApi(functions: functions, functionId: config.driveFunctionId);
});

class DriveApi {
  DriveApi({required this.functions, required this.functionId});

  final Functions functions;
  final String functionId;

  Map<String, dynamic> _decodeJsonObject(String responseBody, {required String context}) {
    final body = responseBody.trim();
    if (body.isEmpty) {
      throw StateError('$context: lege antwoordtekst.');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw StateError('$context: verwachte een JSON-object, kreeg ${decoded.runtimeType}. Body: $body');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Uri> getOAuthStartUrl() async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.gET,
      path: '/oauth/start',
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive OAuth-start');
    return Uri.parse(data['url'] as String);
  }

  Future<bool> getConnectionStatus() async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.gET,
      path: '/status',
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive-status');
    return data['connected'] == true;
  }

  Future<void> disconnect() async {
    await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/disconnect',
    );
  }

  Future<String> getRootFolderId() async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.gET,
      path: '/drive/root',
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive root');
    final id = data['rootFolderId'];
    return (id is String) ? id : '';
  }

  Future<void> setRootFolderId(String rootFolderId) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/root',
      body: jsonEncode(<String, dynamic>{'rootFolderId': rootFolderId}),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive root set');
    if (data['ok'] != true) {
      throw StateError('Rootmap instellen mislukt.');
    }
  }

  Future<String> ensureFolder({String? parentId, required String name}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/folder/ensure',
      body: jsonEncode(<String, dynamic>{
        if (parentId != null && parentId.trim().isNotEmpty) 'parentId': parentId.trim(),
        'name': name,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive folder ensure');
    final id = data['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Drive folder ensure: ontbrekende id.');
    }
    return id;
  }

  Future<void> renameFolder({required String folderId, required String newName}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/folder/rename',
      body: jsonEncode(<String, dynamic>{
        'folderId': folderId,
        'newName': newName,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive folder rename');
    if (data['ok'] != true) throw StateError('Drive map hernoemen mislukt.');
  }

  Future<void> trashItem({required String fileId}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/item/trash',
      body: jsonEncode(<String, dynamic>{'fileId': fileId}),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive item trash');
    if (data['ok'] != true) throw StateError('Drive item verwijderen (prullenbak) mislukt.');
  }

  Future<void> restoreItem({required String fileId}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/item/restore',
      body: jsonEncode(<String, dynamic>{'fileId': fileId}),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive item restore');
    if (data['ok'] != true) throw StateError('Drive item herstellen mislukt.');
  }

  Future<void> trashAndLog({
    required String fileId,
    required String name,
    required String kind,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/item/trash_and_log',
      body: jsonEncode(<String, dynamic>{
        'fileId': fileId,
        'name': name,
        'kind': kind,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive item trash+log');
    if (data['ok'] != true) throw StateError('Verwijderen (Drive + log) mislukt.');
  }

  Future<void> restoreAndMark({
    required String fileId,
    required String deletedItemId,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/item/restore_and_mark',
      body: jsonEncode(<String, dynamic>{
        'fileId': fileId,
        'deletedItemId': deletedItemId,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive item restore+mark');
    if (data['ok'] != true) throw StateError('Herstellen (Drive + log) mislukt.');
  }

  Future<String> getAccessToken() async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.gET,
      path: '/oauth/token',
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive OAuth-token');
    final token = data['accessToken'];
    if (token is! String || token.isEmpty) {
      throw StateError('Geen toegangstoken ontvangen.');
    }
    return token;
  }

  Future<DriveUploadedFile> uploadBytes({
    required String name,
    required String mimeType,
    required Uint8List bytes,
    List<String>? parents,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/upload',
      body: jsonEncode(<String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'base64': base64Encode(bytes),
        if (parents != null) 'parents': parents,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive-upload');
    final fileAny = data['file'];
    if (fileAny is! Map) {
      final err = data['error'];
      final apiMsg = data['message'];
      if (apiMsg is String && apiMsg.isNotEmpty) {
        throw StateError('Drive-upload mislukt${err is String ? ' ($err)' : ''}: $apiMsg');
      }
      throw StateError('Drive-upload: ontbreekt of ongeldig veld „file” in antwoord. Body: ${result.responseBody}');
    }
    final file = Map<String, dynamic>.from(fileAny);
    return DriveUploadedFile(
      id: file['id'] as String,
      name: (file['name'] as String?) ?? name,
      mimeType: (file['mimeType'] as String?) ?? mimeType,
    );
  }

  Future<String> publicDownloadDataUrl({
    required String publicToken,
    required String fileId,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/public/download',
      body: jsonEncode(<String, dynamic>{
        'publicToken': publicToken,
        'fileId': fileId,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Openbare Drive-download');
    final mimeType = data['mimeType'] as String? ?? 'application/octet-stream';
    final base64 = data['base64'] as String;
    return 'data:$mimeType;base64,$base64';
  }

  Future<String> downloadDataUrl({required String fileId}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/download',
      body: jsonEncode(<String, dynamic>{
        'fileId': fileId,
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive-download');
    final mimeType = data['mimeType'] as String? ?? 'application/octet-stream';
    final base64 = data['base64'] as String;
    return 'data:$mimeType;base64,$base64';
  }

  Future<DriveDownloadedBytes> downloadBytes({required String fileId}) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/download',
      body: jsonEncode(<String, dynamic>{'fileId': fileId}),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive-download (bytes)');
    final mimeType = data['mimeType'] as String? ?? 'application/octet-stream';
    final base64 = data['base64'] as String;
    return DriveDownloadedBytes(
      mimeType: mimeType,
      bytes: base64Decode(base64),
    );
  }

  Future<DriveCreatedShortcut> createShortcut({
    required String parentId,
    required String targetFileId,
    String? name,
  }) async {
    final result = await functions.createExecution(
      functionId: functionId,
      method: ExecutionMethod.pOST,
      path: '/drive/shortcut/create',
      body: jsonEncode(<String, dynamic>{
        'parentId': parentId,
        'targetFileId': targetFileId,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
      headers: <String, String>{'content-type': 'application/json'},
    );
    final data = _decodeJsonObject(result.responseBody, context: 'Drive shortcut create');
    final fileAny = data['file'];
    if (fileAny is! Map) {
      throw StateError(
        'Drive shortcut create: ontbreekt of ongeldig veld „file” in antwoord. Body: ${result.responseBody}',
      );
    }
    final file = Map<String, dynamic>.from(fileAny);
    final id = file['id'];
    if (id is! String || id.isEmpty) {
      throw StateError('Drive shortcut create: ontbrekende id.');
    }
    return DriveCreatedShortcut(
      id: id,
      name: (file['name'] as String?) ?? (name ?? 'Shortcut'),
      mimeType: (file['mimeType'] as String?) ?? 'application/vnd.google-apps.shortcut',
    );
  }
}

class DriveDownloadedBytes {
  const DriveDownloadedBytes({required this.mimeType, required this.bytes});

  final String mimeType;
  final Uint8List bytes;
}

class DriveUploadedFile {
  const DriveUploadedFile({
    required this.id,
    required this.name,
    required this.mimeType,
  });

  final String id;
  final String name;
  final String mimeType;
}

class DriveCreatedShortcut {
  const DriveCreatedShortcut({
    required this.id,
    required this.name,
    required this.mimeType,
  });

  final String id;
  final String name;
  final String mimeType;
}

