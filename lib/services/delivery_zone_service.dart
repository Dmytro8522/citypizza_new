import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for retrieving minimum order amounts per postal code.
/// Uses in-memory caching with a short TTL to reduce network traffic.
class DeliveryZoneService {
  static final SupabaseClient _client = Supabase.instance.client;

  static final Map<String, _CacheEntry> _cache = {};
  static Duration ttl = const Duration(minutes: 5);

  /// Returns minimum order amount for the given postal code or null if not found.
  static Future<double?> getMinOrderForPostal({required String postalCode, bool forceRefresh = false}) async {
    final key = postalCode.trim();
    if (key.isEmpty) return null;

    final now = DateTime.now();
    final cached = _cache[key];
    if (!forceRefresh && cached != null && now.difference(cached.storedAt) <= ttl) {
      return cached.minOrder;
    }

    try {
      final row = await _client
          .from('delivery_postal_code')
          .select('postal_code, min_order')
          .eq('postal_code', key)
          .maybeSingle();
      if (row == null) {
        _cache[key] = _CacheEntry(minOrder: null, storedAt: now);
        return null;
      }
      final moRaw = row['min_order'];
      double? minOrder;
      if (moRaw is num) {
        minOrder = moRaw.toDouble();
      } else if (moRaw is String) {
        minOrder = double.tryParse(moRaw);
      }
      _cache[key] = _CacheEntry(minOrder: minOrder, storedAt: now);
      return minOrder;
    } catch (_) {
      // On error do not poison cache; let future retries happen.
      return cached?.minOrder;
    }
  }

  /// Clears in-memory cache (e.g. when user changes postal code decisively).
  static void clear() => _cache.clear();
}

class _CacheEntry {
  final double? minOrder;
  final DateTime storedAt;
  _CacheEntry({required this.minOrder, required this.storedAt});
}
