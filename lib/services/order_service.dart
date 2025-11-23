import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_service.dart';
import 'discount_service.dart';

class OrderService {
  static final SupabaseClient _db = Supabase.instance.client;
  static _OrderItemOptionSchema? _optionSchema;
  static final Map<int, int?> _legacyOptionIdCache = {};

  /// Создаёт новый заказ:
  /// 1) вставляет запись в orders,
  /// 2) CartItem → order_items (+ item_comment),
  /// 3) extras → order_item_extras,
  /// 4) очищает корзину.
  static Future<int> createOrder({
    required String name,
    required String phone,
    required bool isDelivery,
    required String paymentMethod,
    required String city,
    required String street,
    required String houseNumber,
    required String postalCode,
    required String floor,
    required String comment,
    required String courierComment,
    required Map<String, String> itemComments,
    required double totalSum,
    required bool isCustomTime,
    DateTime? scheduledTime,
    double? totalDiscount,
    List<Map<String, dynamic>>? appliedDiscounts,
  }) async {
    // 1) Insert в orders и возврат ID
    final orderInsert = await _db
        .from('orders')
        .insert({
          'user_id': _db.auth.currentUser?.id,
          'name': name,
          'phone': phone,
          'is_delivery': isDelivery,
          'payment_method': paymentMethod,
          'city': city,
          'street': street,
          'house_number': houseNumber,
          'postal_code': postalCode,
          'floor': floor,
          'order_comment': comment,
          'courier_comment': courierComment,
          'total_sum': totalSum,
          'discount_amount': totalDiscount ?? 0,
          if (appliedDiscounts != null) 'applied_discounts': appliedDiscounts,
          if (isCustomTime && scheduledTime != null)
            'scheduled_time': scheduledTime.toIso8601String(),
        })
        .select('id')
        .single();

    final int orderId = (orderInsert['id'] as int?) ?? 0;

    // 2) Вставка позиций
    final items = CartService.items;
    final promotions = await getCachedPromotions(now: DateTime.now());
    final itemIds = items.map((e) => e.itemId).toSet().toList();
    final categoryByItem = <int, int?>{};
    final itemHasSizes = <int, bool>{};
    final extrasInCart = <int>{};
    final optionsInCart = <int>{};
    if (itemIds.isNotEmpty) {
      final inList = '(${itemIds.join(',')})';
      final catRows = await _db
          .from('menu_v2_item')
          .select('id, category_id, has_sizes')
          .filter('id', 'in', inList);
      for (final row in (catRows as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] as int?) ?? 0;
        categoryByItem[id] = row['category_id'] as int?;
        itemHasSizes[id] = (row['has_sizes'] as bool?) ?? true;
      }
    }
    for (final cartItem in items) {
      extrasInCart.addAll(cartItem.extras.keys);
      optionsInCart.addAll(cartItem.options.keys);
    }
    final extraSinglePrice = <int, double>{};
    if (extrasInCart.isNotEmpty) {
      final inList = '(${extrasInCart.join(',')})';
      final rows = await _db
          .from('menu_v2_extra')
          .select('id, single_price')
          .filter('id', 'in', inList);
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final id = (row['id'] as int?) ?? 0;
        final sp = (row['single_price'] as num?)?.toDouble();
        if (id != 0 && sp != null) {
          extraSinglePrice[id] = sp;
        }
      }
    }
    final optionMeta = <int, Map<String, dynamic>>{};
    if (optionsInCart.isNotEmpty) {
      final inList = '(${optionsInCart.join(',')})';
      try {
        final rows = await _db
            .from('menu_v2_modifier_option')
            .select('id, name, group_id')
            .filter('id', 'in', inList);
        for (final row in (rows as List).cast<Map<String, dynamic>>()) {
          final id = (row['id'] as int?) ?? 0;
          if (id != 0) optionMeta[id] = row;
        }
      } catch (_) {}
    }
    final _OrderItemOptionSchema? optionSchema =
        optionsInCart.isNotEmpty ? await _ensureOrderItemOptionsSchema() : null;
    final legacyExtraIdCache = <int, int?>{};
    for (final cartItem in items) {
      // генерируем ключ для комментариев
      final commentKey =
          '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}';
      final itemComment = itemComments[commentKey] ?? '';

      // Определяем size_id (v2).
      // Логика:
      // 1) Используем уже имеющийся cartItem.sizeId если задан.
      // 2) Пытаемся найти точное совпадение по имени в menu_v2_item_size_price (если есть столбец size_name).
      // 3) Берем первую доступную запись для item_id.
      // 4) Если ничего не найдено — оставляем null (заказ всё равно создадим, опустив size_id где возможно).
      int? sizeId = cartItem.sizeId;
      if (sizeId == null) {
        try {
          if (cartItem.size.isNotEmpty) {
            final exactRow = await _db
                .from('menu_v2_item_size_price')
                .select('size_id, size_name')
                .eq('item_id', cartItem.itemId)
                .eq('size_name', cartItem.size)
                .maybeSingle();
            if (exactRow != null && exactRow['size_id'] != null) {
              sizeId = (exactRow['size_id'] as int?) ?? sizeId;
            }
          }
          if (sizeId == null) {
            final rows = (await _db
                .from('menu_v2_item_size_price')
                .select('size_id')
                .eq('item_id', cartItem.itemId)
                .eq('is_available', true)
                .order('price', ascending: true)
                .limit(1)) as List<dynamic>;
            if (rows.isNotEmpty) {
              final r = rows.first as Map<String, dynamic>;
              final sid = r['size_id'];
              if (sid != null) sizeId = sid as int?;
            }
          }
        } catch (_) {
          // Тихо игнорируем — оставим sizeId = null
        }
      }

      final promoInfo = evaluatePromotionForUnitPrice(
        promotions: promotions,
        unitPrice: cartItem.basePrice,
        itemId: cartItem.itemId,
        categoryId: categoryByItem[cartItem.itemId],
        sizeId: sizeId,
      );
      final finalUnitPrice = promoInfo.finalPrice;

      // Вставляем order_item (каждая CartItem — количество 1)
      // Переход на v2: сначала пробуем поле menu_v2_item_id, если его нет — fallback на menu_item_id
      Map<String, dynamic> itemInsert = {
        'order_id': orderId,
        'quantity': 1,
        'base_price': cartItem.basePrice,
        'price': finalUnitPrice,
        'line_total': finalUnitPrice,
        'item_name': cartItem.name,
        if (sizeId != null) 'size_id': sizeId,
        if (itemComment.isNotEmpty) 'item_comment': itemComment,
        if (cartItem.article != null) 'article': cartItem.article,
      };
      dynamic createdItem;
      try {
        // Предпочитаем новое поле
        createdItem = await _db
            .from('order_items')
            .insert({...itemInsert, 'menu_v2_item_id': cartItem.itemId})
            .select('id')
            .single();
      } catch (e) {
        // Fallback на старое имя колонки
        createdItem = await _db
            .from('order_items')
            .insert({...itemInsert, 'menu_item_id': cartItem.itemId})
            .select('id')
            .single();
      }

      final int orderItemId = (createdItem['id'] as int?) ?? 0;

      // 3) Вставка extras для позиции
      final hasSizes = itemHasSizes[cartItem.itemId] ?? true;
      for (final extraEntry in cartItem.extras.entries) {
        final extraId = extraEntry.key;
        final quantity = extraEntry.value;
        double extraPrice = 0.0;
        if (!hasSizes) {
          extraPrice = extraSinglePrice[extraId] ?? 0.0;
        } else if (sizeId != null) {
          final priceRow = await _db
              .from('menu_v2_extra_price_by_size')
              .select('price')
              .eq('size_id', sizeId)
              .eq('extra_id', extraId)
              .maybeSingle();
          extraPrice =
              priceRow != null ? (priceRow['price'] as num).toDouble() : 0.0;
        } else {
          extraPrice = extraSinglePrice[extraId] ?? 0.0;
        }
        final baseExtraInsert = <String, dynamic>{
          'order_item_id': orderItemId,
          'quantity': quantity,
          'price': extraPrice,
          if (sizeId != null) 'size_id': sizeId,
        };
        bool inserted = false;
        try {
          await _db.from('order_item_extras').insert({
            ...baseExtraInsert,
            'menu_v2_extra_id': extraId,
          });
          inserted = true;
        } catch (_) {
          // Column might be missing on legacy schema; fallback handled below.
        }
        if (!inserted) {
          int? legacyExtraId = legacyExtraIdCache[extraId];
          if (!legacyExtraIdCache.containsKey(extraId)) {
            legacyExtraId = await _resolveLegacyExtraId(extraId);
            legacyExtraIdCache[extraId] = legacyExtraId;
          }
          if (legacyExtraId == null) {
            // No legacy mapping exists; skip to avoid FK violation on legacy schema.
            continue;
          }
          await _db.from('order_item_extras').insert({
            ...baseExtraInsert,
            'extra_id': legacyExtraId,
          });
        }
      }

      if (cartItem.options.isNotEmpty) {
        final schema = optionSchema;
        for (final opt in cartItem.options.entries) {
          if (opt.value <= 0) continue;
          final optId = opt.key;
          final quantity = opt.value;
          final meta = optionMeta[optId];
          final optName = (meta?['name'] as String?)?.trim();
          final modifierGroupId = (meta?['group_id'] as int?) ?? 0;
          final displayName = (optName != null && optName.isNotEmpty)
              ? optName
              : 'Option #$optId';

          final base = <String, dynamic>{
            'order_item_id': orderItemId,
            'quantity': quantity,
          };

          int? legacyOptionId;
          if (schema?.hasOptionId == true) {
            legacyOptionId =
                await _resolveLegacyOptionId(optId, optionName: optName);
          }

          final candidates = <Map<String, dynamic>>[];
          if (schema != null) {
            final primary = Map<String, dynamic>.from(base);
            if (schema.hasModifierOptionId) {
              primary['modifier_option_id'] = optId;
            }
            if (schema.hasModifierId && modifierGroupId != 0) {
              primary['modifier_id'] = modifierGroupId;
            }
            if (schema.hasOptionName) {
              primary['option_name'] = displayName;
            }
            if (schema.hasPriceDelta) {
              primary['price_delta'] = 0.0;
            }
            if (schema.hasOptionId && legacyOptionId != null) {
              primary['option_id'] = legacyOptionId;
            }
            candidates.add(primary);

            if (schema.hasOptionId && legacyOptionId == null) {
              final withRaw = Map<String, dynamic>.from(primary);
              withRaw['option_id'] = optId;
              candidates.add(withRaw);
            }

            if (schema.hasModifierOptionId) {
              candidates.add({
                'order_item_id': orderItemId,
                'modifier_option_id': optId,
                'quantity': quantity,
              });
            }

            if (schema.hasOptionName) {
              candidates.add({
                'order_item_id': orderItemId,
                'quantity': quantity,
                'option_name': displayName,
              });
            }
          } else {
            final assumeNew = Map<String, dynamic>.from(base);
            assumeNew['modifier_option_id'] = optId;
            candidates.add(assumeNew);
          }

          candidates.add(base);

          bool inserted = false;
          for (final candidate in candidates) {
            candidate.removeWhere((key, value) => value == null);
            if (await _tryInsertOptionRow(candidate)) {
              inserted = true;
              break;
            }
          }

          if (!inserted) {
            await _tryInsertOptionRow({
              'order_item_id': orderItemId,
              'quantity': quantity,
            });
          }
        }
      }
    }

    // 4) Очистка корзины
    await CartService.clear();
    return orderId;
  }

  /// Возвращает историю заказов текущего пользователя вместе с вложением
  static Future<List<Map<String, dynamic>>> getOrderHistory() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _db
        .from('orders')
        .select(
            '*, order_items(*, order_item_extras(*), order_item_options(*))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List).cast();
  }

  static Future<bool> _tryInsertOptionRow(Map<String, dynamic> payload) async {
    try {
      await _db.from('order_item_options').insert(payload);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<_OrderItemOptionSchema> _ensureOrderItemOptionsSchema() async {
    if (_optionSchema != null) return _optionSchema!;
    Future<bool> hasColumn(String column) async {
      try {
        await _db.from('order_item_options').select(column).limit(0);
        return true;
      } catch (_) {
        return false;
      }
    }

    final schema = _OrderItemOptionSchema(
      hasModifierOptionId: await hasColumn('modifier_option_id'),
      hasOptionId: await hasColumn('option_id'),
      hasModifierId: await hasColumn('modifier_id'),
      hasOptionName: await hasColumn('option_name'),
      hasPriceDelta: await hasColumn('price_delta'),
    );
    _optionSchema = schema;
    return schema;
  }

  static Future<int?> _resolveLegacyOptionId(int optionId,
      {String? optionName}) async {
    if (_legacyOptionIdCache.containsKey(optionId)) {
      return _legacyOptionIdCache[optionId];
    }
    String? resolvedName = optionName?.trim();
    if (resolvedName == null || resolvedName.isEmpty) {
      try {
        final row = await _db
            .from('menu_v2_modifier_option')
            .select('name')
            .eq('id', optionId)
            .maybeSingle();
        resolvedName = (row?['name'] as String?)?.trim();
      } catch (_) {}
    }
    if (resolvedName == null || resolvedName.isEmpty) {
      _legacyOptionIdCache[optionId] = null;
      return null;
    }
    try {
      final exact = await _db
          .from('menu_option_item')
          .select('id')
          .eq('text', resolvedName)
          .maybeSingle();
      final exactId = exact?['id'] as int?;
      if (exactId != null) {
        _legacyOptionIdCache[optionId] = exactId;
        return exactId;
      }
    } catch (_) {}
    try {
      final approxPattern = '%${_escapeForIlike(resolvedName)}%';
      final approx = await _db
          .from('menu_option_item')
          .select('id')
          .ilike('text', approxPattern)
          .limit(1);
      final approxList = (approx as List).cast<Map<String, dynamic>>();
      if (approxList.isNotEmpty) {
        final id = approxList.first['id'] as int?;
        if (id != null) {
          _legacyOptionIdCache[optionId] = id;
          return id;
        }
      }
    } catch (_) {}
    _legacyOptionIdCache[optionId] = null;
    return null;
  }

  static Future<int?> _resolveLegacyExtraId(int extraId) async {
    try {
      final extraRow = await _db
          .from('menu_v2_extra')
          .select('name')
          .eq('id', extraId)
          .maybeSingle();
      final extraName = (extraRow?['name'] as String?)?.trim();
      if (extraName == null || extraName.isEmpty) return null;

      final exactRow = await _db
          .from('menu_extra')
          .select('id')
          .eq('name', extraName)
          .maybeSingle();
      final exactId = (exactRow?['id'] as int?);
      if (exactId != null) return exactId;

      final approxPattern = '%${_escapeForIlike(extraName)}%';
      final approxRows = (await _db
          .from('menu_extra')
          .select('id')
          .ilike('name', approxPattern)
          .limit(1)) as List<dynamic>;
      if (approxRows.isNotEmpty) {
        final row = approxRows.first as Map<String, dynamic>;
        return row['id'] as int?;
      }
    } catch (_) {}
    return null;
  }

  static String _escapeForIlike(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
  }
}

class _OrderItemOptionSchema {
  final bool hasModifierOptionId;
  final bool hasOptionId;
  final bool hasModifierId;
  final bool hasOptionName;
  final bool hasPriceDelta;

  const _OrderItemOptionSchema({
    required this.hasModifierOptionId,
    required this.hasOptionId,
    required this.hasModifierId,
    required this.hasOptionName,
    required this.hasPriceDelta,
  });
}
