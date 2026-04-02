import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_config.dart';

/// Asset-based app configuration with in-memory cache.
/// Reads config from assets/config/app_config.json.
class AppConfigService {
  static AppConfig _config = AppConfig.empty();
  static Map<String, dynamic> _raw = {};
  static final Map<String, dynamic> _cache = {};

  static AppConfig get config => _config;

  static Future<void> loadFromAssets(
      {String path = 'assets/config/app_config.json'}) async {
    try {
      final jsonStr = await rootBundle.loadString(path);
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        _raw = decoded;
        _config = AppConfig.fromMap(decoded);
      } else {
        _raw = {};
        _config = AppConfig.empty();
      }
    } catch (_) {
      _raw = {};
      _config = AppConfig.empty();
    }
  }

  static Future<T> get<T>(String key, {required T defaultValue}) async {
    if (_cache.containsKey(key)) {
      final v = _cache[key];
      if (v is T) return v;
      if (T == int && v is num) return v.toInt() as T;
      if (T == double && v is num) return v.toDouble() as T;
    }

    final raw = _config.settings[key];
    if (raw != null) {
      _cache[key] = raw;
      if (raw is T) return raw;
      if (T == int && raw is num) return raw.toInt() as T;
      if (T == double && raw is num) return raw.toDouble() as T;
    }
    return defaultValue;
  }

  static String text(String key, {String fallback = ''}) {
    return _config.texts.get(key, fallback: fallback);
  }

  static String string(String key, {String fallback = ''}) {
    final value = getByPath(_raw, key);
    return value is String ? value : fallback;
  }

  static bool flag(String key, {bool fallback = false}) {
    return _config.features.getFlag(key, fallback: fallback);
  }

  static double number(String key, {double fallback = 0}) {
    final value = getByPath(_raw, key);
    if (value is num) return value.toDouble();
    return fallback;
  }

  static Color color(String key, {required Color fallback}) {
    return parseColor(getByPath(_raw, key)) ?? fallback;
  }

  static FontsConfig get fonts => _config.fonts;
}
