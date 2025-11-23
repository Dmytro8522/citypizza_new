import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight app config reader with in-memory cache.
/// Optional table: app_settings(key text primary key, value jsonb)
/// Example rows:
/// - { key: 'current_order_widget_minutes', value: 60 }
/// - { key: 'default_eta_minutes', value: 45 }
class AppConfigService {
  static final SupabaseClient _db = Supabase.instance.client;
  static final Map<String, dynamic> _cache = {};

  static Future<T> get<T>(String key, {required T defaultValue}) async {
    if (_cache.containsKey(key)) {
      final v = _cache[key];
      if (v is T) return v;
      // Attempt cast for num → int/double
      if (T == int && v is num) return v.toInt() as T;
      if (T == double && v is num) return v.toDouble() as T;
    }
    try {
      final row = await _db
          .from('app_settings')
          .select('value')
          .eq('key', key)
          .maybeSingle();
      if (row == null) return defaultValue;
      final raw = row['value'];
      _cache[key] = raw;
      if (raw is T) return raw;
      if (T == int && raw is num) return raw.toInt() as T;
      if (T == double && raw is num) return raw.toDouble() as T;
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }
}
