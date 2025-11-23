/// Normalizes an address component for German UI.
/// Steps:
/// 1. Trim and collapse multiple spaces.
/// 2. Preserve German-specific characters (ä Ä ö Ö ü Ü ß) unchanged.
/// 3. If any Cyrillic letters present, transliterate only those to Latin (simple mapping).
/// 4. Apply Title Case to words (first letter uppercase, rest as-is) except house numbers.
String normalizeAddressComponent(String value) {
  if (value.isEmpty) return value;
  // Trim + collapse spaces
  value = value.trim().replaceAll(RegExp(r'\s+'), ' ');

  // Detect house number pattern (e.g. '12a', '5', '5-7') -> leave casing untouched
  final isHouseNumber = RegExp(r'^[0-9]+([a-zA-Z]?(-[0-9]+[a-zA-Z]?)?)?$').hasMatch(value);

  // Check for Cyrillic range
  final hasCyrillic = value.runes.any((r) => (r >= 0x0400 && r <= 0x04FF));
  if (hasCyrillic) {
    const map = <String, String>{
      'А': 'A','а': 'a','Б': 'B','б': 'b','В': 'V','в': 'v','Г': 'G','г': 'g','Д': 'D','д': 'd','Е': 'E','е': 'e','Ё': 'Jo','ё': 'jo','Ж': 'Zh','ж': 'zh','З': 'Z','з': 'z','И': 'I','и': 'i','Й': 'J','й': 'j','К': 'K','к': 'k','Л': 'L','л': 'l','М': 'M','м': 'm','Н': 'N','н': 'n','О': 'O','о': 'o','П': 'P','п': 'p','Р': 'R','р': 'r','С': 'S','с': 's','Т': 'T','т': 't','У': 'U','у': 'u','Ф': 'F','ф': 'f','Х': 'Ch','х': 'ch','Ц': 'Z','ц': 'z','Ч': 'Tsch','ч': 'tsch','Ш': 'Sch','ш': 'sch','Щ': 'Sch','щ': 'sch','Ъ': '','ъ': '','Ы': 'Y','ы': 'y','Ь': '','ь': '','Э': 'E','э': 'e','Ю': 'Ju','ю': 'ju','Я': 'Ja','я': 'ja'
    };
    final buffer = StringBuffer();
    for (int i = 0; i < value.length; i++) {
      final ch = value[i];
      buffer.write(map[ch] ?? ch);
    }
    value = buffer.toString();
  }

  if (isHouseNumber) return value; // skip Title Case

  // Title Case words: keep internal umlauts & ß
  final words = value.split(' ').map((w) {
    if (w.isEmpty) return w;
    final first = w[0].toUpperCase();
    final rest = w.substring(1); // keep as-is (umlauts preserved)
    return '$first$rest';
  }).join(' ');
  return words;
}