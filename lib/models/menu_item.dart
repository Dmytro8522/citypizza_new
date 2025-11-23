// lib/models/menu_item.dart

class MenuItem {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? article;
  final double? klein, normal, gross, familie, party;
  final double minPrice;
  final bool hasMultipleSizes;
  final double? singleSizePrice;

  MenuItem({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.article,
    this.klein,
    this.normal,
    this.gross,
    this.familie,
    this.party,
    required this.minPrice,
    this.hasMultipleSizes = true,
    this.singleSizePrice,
  });

  factory MenuItem.fromMap(Map<String, dynamic> m) => MenuItem(
        id: (m['id'] as int?) ?? 0,
        name: (m['name'] as String?) ?? '',
        description: m['description'] as String?,
        imageUrl: (m['image_url'] as String?) ?? (m['image'] as String?),
        article: m['article'] as String?,
        klein: (m['klein'] as num?)?.toDouble(),
        normal: (m['normal'] as num?)?.toDouble(),
        gross: (m['gross'] as num?)?.toDouble(),
        familie: (m['familie'] as num?)?.toDouble(),
        party: (m['party'] as num?)?.toDouble(),
        minPrice: m['minPrice'] is num ? (m['minPrice'] as num).toDouble() : 0.0,
        hasMultipleSizes: m['has_multiple_sizes'] as bool? ?? true,
        singleSizePrice: m['single_size_price'] != null
            ? (m['single_size_price'] as num).toDouble()
            : null,
      );
}
