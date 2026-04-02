import 'package:shared_preferences/shared_preferences.dart';

import 'app_config_service.dart';

class RestaurantContext {
  static const _prefsKey = 'restaurant_id';
  static String _current = '';

  static String get current => _current;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null && stored.trim().isNotEmpty) {
      _current = stored.trim();
      return;
    }

    final fromConfig = AppConfigService.string('restaurantId', fallback: '').trim();
    _current = fromConfig;
    if (_current.isNotEmpty) {
      await prefs.setString(_prefsKey, _current);
    }
  }

  static Future<void> set(String restaurantId) async {
    final value = restaurantId.trim();
    _current = value;
    final prefs = await SharedPreferences.getInstance();
    if (value.isNotEmpty) {
      await prefs.setString(_prefsKey, value);
    } else {
      await prefs.remove(_prefsKey);
    }
  }
}
