import 'package:shared_preferences/shared_preferences.dart';

/// Типы согласия на куки
enum CookieType { analyse, personalisation }

class ConsentService {
  static const _legalKey       = 'agreed_legal';
  static const _cookiesDoneKey = 'agreed_cookies';
  static const _analyseKey     = 'consent_analyse';
  static const _personalisationKey = 'consent_personalisation';

  /// Согласие с AGB/Datenschutz (прошёл WelcomeScreen)
  static Future<bool> hasAgreedLegal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_legalKey) ?? false;
  }
  static Future<void> agreeLegal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_legalKey, true);
  }

  /// Признак того, что прошли экран куки
  static Future<bool> hasAgreedCookies() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_cookiesDoneKey) ?? false;
  }
  static Future<void> agreeCookies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cookiesDoneKey, true);
  }

  /// Получить/сохранить согласие по конкретному типу куки
  static Future<bool> hasConsent(CookieType type) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFor(type)) ?? false;
  }
  static Future<void> setConsent(CookieType type, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFor(type), value);
  }

  static String _keyFor(CookieType type) {
    switch (type) {
      case CookieType.analyse:
        return _analyseKey;
      case CookieType.personalisation:
        return _personalisationKey;
    }
  }
}
