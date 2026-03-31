import 'dart:convert';

/// Stored on the card as JSON (string).
///
/// Coordinates are normalized (0..1) relative to the displayed image box.
class ImageAnnotations {
  const ImageAnnotations({required this.version, required this.items});

  final int version;
  final List<ImageAnnotationItem> items;

  static const int currentVersion = 2;

  static ImageAnnotations empty() =>
      const ImageAnnotations(version: currentVersion, items: <ImageAnnotationItem>[]);

  static ImageAnnotations? tryParse(String? json) {
    final raw = json?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final vAny = map['v'];
      final v = (vAny is num) ? vAny.toInt() : currentVersion;
      final itemsAny = map['items'];
      final List<ImageAnnotationItem> items = <ImageAnnotationItem>[];
      if (itemsAny is List) {
        for (final it in itemsAny) {
          if (it is! Map) continue;
          final m = Map<String, dynamic>.from(it);
          final parsed = ImageAnnotationItem.tryFromJson(m);
          if (parsed != null) items.add(parsed);
        }
      }
      return ImageAnnotations(version: v, items: items);
    } catch (_) {
      return null;
    }
  }

  String toJsonString() {
    return jsonEncode(<String, dynamic>{
      'v': version,
      'items': items.map((e) => e.toJson()).toList(),
    });
  }
}

sealed class ImageAnnotationItem {
  const ImageAnnotationItem();

  Map<String, dynamic> toJson();

  static ImageAnnotationItem? tryFromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type == 'arrow') {
      final from = _readPoint(json['from']);
      final to = _readPoint(json['to']);
      if (from == null || to == null) return null;
      final color = (json['color'] as String?) ?? '#FF0000';
      final widthAny = json['width'];
      final width = (widthAny is num) ? widthAny.toDouble() : 6.0;
      final widthRelAny = json['widthRel'];
      final widthRel = (widthRelAny is num) ? widthRelAny.toDouble() : null;
      return ArrowAnnotation(
        fromX: from.$1,
        fromY: from.$2,
        toX: to.$1,
        toY: to.$2,
        colorHex: color,
        width: width,
        widthRel: widthRel,
      );
    }
    if (type == 'text') {
      final at = _readPoint(json['at']);
      final text = json['text'];
      if (at == null || text is! String || text.trim().isEmpty) return null;
      final color = (json['color'] as String?) ?? '#000000';
      final sizeAny = json['size'];
      final size = (sizeAny is num) ? sizeAny.toDouble() : 28.0;
      final sizeRelAny = json['sizeRel'];
      final sizeRel = (sizeRelAny is num) ? sizeRelAny.toDouble() : null;
      return TextAnnotation(
        atX: at.$1,
        atY: at.$2,
        text: text,
        colorHex: color,
        size: size,
        sizeRel: sizeRel,
      );
    }
    return null;
  }
}

class ArrowAnnotation extends ImageAnnotationItem {
  const ArrowAnnotation({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.colorHex,
    required this.width,
    this.widthRel,
  });

  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final String colorHex;
  final double width;
  final double? widthRel;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'arrow',
        'from': <double>[fromX, fromY],
        'to': <double>[toX, toY],
        'color': colorHex,
        'width': width,
        if (widthRel != null) 'widthRel': widthRel,
      };
}

class TextAnnotation extends ImageAnnotationItem {
  const TextAnnotation({
    required this.atX,
    required this.atY,
    required this.text,
    required this.colorHex,
    required this.size,
    this.sizeRel,
  });

  final double atX;
  final double atY;
  final String text;
  final String colorHex;
  final double size;
  final double? sizeRel;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': 'text',
        'at': <double>[atX, atY],
        'text': text,
        'color': colorHex,
        'size': size,
        if (sizeRel != null) 'sizeRel': sizeRel,
      };
}

({double $1, double $2})? _readPoint(Object? any) {
  if (any is List && any.length >= 2) {
    final xAny = any[0];
    final yAny = any[1];
    if (xAny is num && yAny is num) {
      return ($1: xAny.toDouble(), $2: yAny.toDouble());
    }
  }
  return null;
}

