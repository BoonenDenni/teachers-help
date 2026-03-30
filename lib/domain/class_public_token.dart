/// Builds URL-safe class link tokens for `/class/:publicToken` (max 64 chars, Appwrite).
String slugForClassPublicToken(String input) {
  var s = input.toLowerCase().trim();
  s = s.replaceAll(RegExp(r'\s+'), '_');
  s = s.replaceAll(RegExp(r'[^a-z0-9_-]'), '');
  s = s.replaceAll(RegExp(r'_+'), '_');
  while (s.startsWith('_')) {
    s = s.substring(1);
  }
  while (s.endsWith('_')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// `{teacher}_{class}` style, e.g. `jane_smith_grade3`.
String buildClassPublicToken({
  required String teacherName,
  required String className,
  int maxLength = 64,
}) {
  final a = slugForClassPublicToken(teacherName);
  final b = slugForClassPublicToken(className);
  if (a.isEmpty && b.isEmpty) return '';
  String combined;
  if (a.isEmpty) {
    combined = b;
  } else if (b.isEmpty) {
    combined = a;
  } else {
    combined = '${a}_$b';
  }
  if (combined.length > maxLength) {
    combined = combined.substring(0, maxLength);
    while (combined.endsWith('_') && combined.isNotEmpty) {
      combined = combined.substring(0, combined.length - 1);
    }
  }
  return combined;
}

/// Normalizes manual input to the same rules and length.
String normalizeClassPublicTokenInput(String input, {int maxLength = 64}) {
  final s = slugForClassPublicToken(input);
  if (s.length <= maxLength) return s;
  return s.substring(0, maxLength).replaceAll(RegExp(r'_+$'), '');
}
