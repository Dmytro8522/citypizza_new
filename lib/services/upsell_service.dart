// lib/services/upsell_service.dart

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_service.dart';

class UpSellService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Возвращает до 3 позиций для каналов 'cart' и 'checkout'
  /// Учитывает:
  ///   - starts_at ≤ now
  ///   - (ends_at ≥ now OR ends_at IS NULL)
  /// Для канала 'cart' проверяет, есть ли в корзине хотя бы один из condition_json.contains_item_ids.
  /// Для 'checkout' эта проверка пропускается.
  /// Логика цен:
  ///   минимальная для multi-size или single_size_price.
  static Future<List<Map<String, dynamic>>> fetchUpsell({
    required String channel,
    required double subtotal,
    String? userId,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();

    // 1) Выбираем активное правило сразу для обоих каналов
    final rule = await _client
        .from('upsell_rules')
        .select('id, condition_json')
        .filter('channel', 'in', ['cart', 'checkout'])
        .eq('active', true)
        .lte('starts_at', now)
        .or('ends_at.gte.$now,ends_at.is.null')
        .order('priority', ascending: false)
        .limit(1)
        .maybeSingle();

    if (rule == null) {
      return [];
    }

    // 2) Достаём условие из JSON
    final condJson = rule['condition_json'];
    final Map<String, dynamic> cond = condJson is String
        ? jsonDecode(condJson)
        : (condJson as Map<String, dynamic>);

    // 3) Список обязательных ID (contains_item_ids)
    final rawList = cond['contains_item_ids'];
    final requiredIds = <int>{
      if (rawList is List<dynamic>) ...rawList.cast<int>()
    };

    // 4) Для канала 'cart' проверяем наличие в корзине
    if (channel == 'cart' && requiredIds.isNotEmpty) {
      final cartIds = CartService.items.map((it) => it.itemId).toSet();
      if (requiredIds.intersection(cartIds).isEmpty) {
        return [];
      }
    }
    // Для 'checkout' — пропускаем проверку

    final ruleId = rule['id'] as int;

    // 5) Берём до трёх позиций из upsell_items
    final upsellRows = await _client
        .from('upsell_items')
        .select('menu_item_id, rank')
        .eq('rule_id', ruleId)
        .order('rank', ascending: true)
        .limit(3);
    final ids = (upsellRows as List)
        .map((e) => (e as Map<String, dynamic>)['menu_item_id'] as int)
        .toList();
    if (ids.isEmpty) {
      return [];
    }

    // 6) Собираем минимальные цены для multi-size
    final priceRows = await _client
        .from('menu_item_price')
        .select('menu_item_id, price')
        .filter('menu_item_id', 'in', ids);
    final multiMin = <int, double>{};
    for (final row in (priceRows as List).cast<Map<String, dynamic>>()) {
      final mid = row['menu_item_id'] as int;
      final p = (row['price'] as num).toDouble();
      if (!multiMin.containsKey(mid) || p < multiMin[mid]!) {
        multiMin[mid] = p;
      }
    }

    // 7) Загружаем сами menu_item
    final rawItems = await _client
        .from('menu_item')
        .select('''
          id,
          name,
          article,
          image_url,
          has_multiple_sizes,
          single_size_price
        ''')
        .filter('id', 'in', ids);
    final itemsList = (rawItems as List).cast<Map<String, dynamic>>();

    // 8) Формируем карту по ID
    final byId = <int, Map<String, dynamic>>{};
    for (final m in itemsList) {
      final id = m['id'] as int;
      final hasMulti = m['has_multiple_sizes'] as bool? ?? false;
      final singlePrice = m['single_size_price'] != null
          ? (m['single_size_price'] as num).toDouble()
          : 0.0;
      final price = hasMulti ? (multiMin[id] ?? singlePrice) : singlePrice;
      byId[id] = {
        'id': id,
        'name': m['name'] as String? ?? '',
        'article': m['article'] as String?,
        'image_url': m['image_url'] as String?,
        'price': price,
      };
    }

    // 9) Возвращаем в порядке upsell_items
    return ids.where(byId.containsKey).map((id) => byId[id]!).toList();
  }
}
