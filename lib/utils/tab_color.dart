import 'package:flutter/material.dart';

/// Saturated, kid-friendly presets; stored as `#RRGGBB`.
const List<String> kTabColorPresets = <String>[
  '#E53935',
  '#FB8C00',
  '#FDD835',
  '#43A047',
  '#1E88E5',
  '#8E24AA',
  '#00ACC1',
  '#D81B60',
  '#6D4C41',
  '#00897B',
];

Color? parseTabColorHex(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) {
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }
  return null;
}

/// Text/icons on a solid tab accent background.
Color foregroundOnTabColor(Color background) {
  return background.computeLuminance() > 0.5 ? const Color(0xDE000000) : Colors.white;
}

String? normalizeTabColorHex(String input) {
  var s = input.trim();
  if (s.isEmpty) return '';
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6 && RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(s)) {
    return '#${s.toUpperCase()}';
  }
  return null;
}

AppBar buildTabColoredAppBar(
  BuildContext context, {
  required String title,
  String? tabColorHex,
  List<Widget>? actions,
}) {
  final accent = parseTabColorHex(tabColorHex);
  final fg = accent != null ? foregroundOnTabColor(accent) : null;
  return AppBar(
    title: Text(title),
    actions: actions,
    backgroundColor: accent,
    foregroundColor: fg,
    iconTheme: fg != null ? IconThemeData(color: fg) : null,
  );
}
