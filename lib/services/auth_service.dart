import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart'; // добавляем импорт для debugPrint

class AuthService {
  static final _supabase = Supabase.instance.client;

  /// Регистрация по e-mail и паролю с передачей пользовательских метаданных
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String city,
    required String street,
    required String houseNumber,
    required String postalCode,
  }) {
    return _supabase.auth.signUp(
      email: email,
      password: password,
      // сюда передаём любые дополнительные поля
      data: {
        'first_name': name,
        'phone': phone,
        'city': city,
        'street': street,
        'house_number': houseNumber,
        'postal_code': postalCode,
      },
      // должен совпадать с Redirect URL в вашем Dashboard Supabase
      emailRedirectTo: 'com.citypizza.app://login-callback',
    );
  }

  /// Вход по e-mail и паролю
  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Выход
  static Future<void> signOut() {
    return _supabase.auth.signOut();
  }

  /// Текущий пользователь
  static User? get currentUser => _supabase.auth.currentUser;

  /// Текущая сессия
  static Session? get currentSession => _supabase.auth.currentSession;

  /// Слушатель изменений статуса аутентификации
  static Stream<AuthChangeEvent> get onAuthStateChange =>
      _supabase.auth.onAuthStateChange.map((e) => e.event);

  /// Получить профиль пользователя (user_data)
  static Future<Map<String, dynamic>?> getProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final res = await _supabase
          .from('user_data')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      
      debugPrint('📦 AuthService getProfile result: $res');
      return res;
    } catch (e) {
      debugPrint('❌ AuthService getProfile error: $e');
      return null;
    }
  }

  /// Обновить профиль пользователя (user_data)
  static Future<void> updateProfile({
    required String name,
    required String phone,
    required String city,
    required String street,
    required String houseNumber,
    required String postalCode,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('Not authenticated');
    await _supabase.from('user_data').upsert({
      'id': user.id,
      'first_name': name,
      'phone': phone,
      'city': city,
      'street': street,
      'house_number': houseNumber,
      'postal_code': postalCode,
    });
  }

  /// Удалить аккаунт через Edge Function delete_user (требует сервисную роль на сервере)
  static Future<void> deleteAccount() async {
    final user = currentUser;
    if (user == null) throw Exception('Not authenticated');
    try {
      final res = await _supabase.functions.invoke(
        'delete_user',
        body: {'user_id': user.id},
      );
      if (res.status >= 400) {
        throw Exception('Failed with status ${res.status}: ${res.data}');
      }
      // На всякий случай чистим сессию
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('❌ AuthService deleteAccount error: $e');
      rethrow;
    }
  }
}
