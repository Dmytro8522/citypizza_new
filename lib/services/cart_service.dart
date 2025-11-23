// lib/services/cart_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Модель одного пункта в корзине
class CartItem {
  final int itemId;
  final String name;
  final String size;
  final double basePrice;
  final Map<int, int> extras; // extraId -> quantity
  // Новые опции (menu_option_item): optionId -> quantity (для radio/checkbox qty=1, для counter — произвольное)
  final Map<int, int> options;
  final String? article;
  final int? sizeId; // nullable sizeId
  // Дополнительные метаданные для сложных типов (например, bundle):
  // Пример структуры: { type: 'bundle', bundleId: 123, slots: [ {slotId:1, items:[{itemId:10,sizeId:2}]} ] }
  final Map<String, dynamic>? meta;

  CartItem({
    required this.itemId,
    required this.name,
    required this.size,
    required this.basePrice,
    required this.extras,
    required this.options,
    this.article,
    this.sizeId,
    this.meta,
  });

  /// Десериализация из JSON
  factory CartItem.fromJson(Map<String, dynamic> json) {
    final dynamic rawExtras = json['extras'];
    Map<int, int> parsedExtras;
    if (rawExtras is String) {
      if (rawExtras.isEmpty) {
        parsedExtras = <int, int>{};
      } else {
        final decoded = jsonDecode(rawExtras);
        if (decoded is Map) {
          parsedExtras = Map<int, int>.fromEntries(
            decoded.entries.map((e) =>
                MapEntry(int.parse(e.key.toString()), (e.value as int?) ?? 0)),
          );
        } else {
          parsedExtras = <int, int>{};
        }
      }
    } else if (rawExtras is Map) {
      parsedExtras = Map<int, int>.fromEntries(
        rawExtras.entries.map((e) =>
            MapEntry(int.parse(e.key.toString()), (e.value as int?) ?? 0)),
      );
    } else {
      parsedExtras = <int, int>{};
    }

    // options
    final dynamic rawOptions = json['options'];
    Map<int, int> parsedOptions;
    if (rawOptions is String) {
      if (rawOptions.isEmpty) {
        parsedOptions = <int, int>{};
      } else {
        final decoded = jsonDecode(rawOptions);
        if (decoded is Map) {
          parsedOptions = Map<int, int>.fromEntries(
            decoded.entries.map((e) =>
                MapEntry(int.parse(e.key.toString()), (e.value as int?) ?? 0)),
          );
        } else {
          parsedOptions = <int, int>{};
        }
      }
    } else if (rawOptions is Map) {
      parsedOptions = Map<int, int>.fromEntries(
        rawOptions.entries.map((e) =>
            MapEntry(int.parse(e.key.toString()), (e.value as int?) ?? 0)),
      );
    } else {
      parsedOptions = <int, int>{};
    }

    return CartItem(
      itemId: (json['itemId'] as int?) ?? 0,
      name: (json['name'] as String?) ?? '',
      size: (json['size'] as String?) ?? '',
      basePrice: (json['basePrice'] as num).toDouble(),
      extras: parsedExtras,
      options: parsedOptions,
      article: json['article'] as String?,
      sizeId: json['sizeId'] as int?,
      meta: _parseMeta(json['meta']),
    );
  }

  static Map<String, dynamic>? _parseMeta(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is String) {
        if (raw.isEmpty) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return null;
      }
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Сериализация в JSON
  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'name': name,
      'size': size,
      'basePrice': basePrice,
      // сериализуем extras как Map<String, int>
      'extras': jsonEncode(
        extras.map((key, value) => MapEntry(key.toString(), value)),
      ),
      'options': jsonEncode(
        options.map((key, value) => MapEntry(key.toString(), value)),
      ),
      'article': article,
      'sizeId': sizeId,
      'meta': meta == null ? null : jsonEncode(meta),
    };
  }
}

/// Сервис «Корзина»
class CartService {
  static const _storageKey = 'cart_items';
  static SharedPreferences? _prefs;
  static final List<CartItem> _items = [];

  // ValueNotifier для подписки на изменения корзины
  static final ValueNotifier<int> cartCountNotifier =
      ValueNotifier<int>(_items.length);

  /// Инициализация: загрузка из SharedPreferences
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_storageKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(
          list
              .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
              .toList(),
        );

      // Миграция: нормализуем старые записи, где size == 'Standard' или sizeId == null
      for (var i = 0; i < _items.length; i++) {
        final it = _items[i];
        bool changed = false;
        String newSize = it.size;
        int? newSizeId = it.sizeId;

        if (it.size.toLowerCase() == 'standard') {
          newSize = 'Normal';
          newSizeId = newSizeId ?? 2;
          changed = true;
        }

        // Если sizeId отсутствует, но позиция имеет basePrice equal to single_size_price? Мы не знаем.
        // Безопасно: если sizeId == null и название размера пустое или неизвестное, выставим Normal/2
        if (newSizeId == null &&
            (newSize.isEmpty || newSize.toLowerCase() == 'standard')) {
          newSize = 'Normal';
          newSizeId = 2;
          changed = true;
        }

        if (changed) {
          _items[i] = CartItem(
            itemId: it.itemId,
            name: it.name,
            size: newSize,
            basePrice: it.basePrice,
            extras: it.extras,
            options: it.options,
            article: it.article,
            sizeId: newSizeId,
          );
        }
      }

      // Сохраняем нормализованные данные обратно
      await _save();
      cartCountNotifier.value = _items.length;
    }
  }

  /// Немодифицируемый доступ к списку
  static List<CartItem> get items => List.unmodifiable(_items);

  /// Добавить одну единицу CartItem
  static Future<void> addItem(CartItem item) async {
    _items.add(item);
    cartCountNotifier.value = _items.length;
    await _save();
  }

  /// Удалить ровно одну копию указанного CartItem
  static Future<void> removeItem(CartItem item) async {
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.itemId == item.itemId &&
          it.size == item.size &&
          mapEquals(it.extras, item.extras) &&
          mapEquals(it.options, item.options)) {
        _items.removeAt(i);
        break;
      }
    }
    cartCountNotifier.value = _items.length;
    await _save();
  }

  /// Полностью очистить корзину
  static Future<void> clear() async {
    _items.clear();
    cartCountNotifier.value = 0;
    await _save();
  }

  /// Сохранить текущее состояние в SharedPreferences
  static Future<void> _save() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((e) => e.toJson()).toList());
    await _prefs!.setString(_storageKey, raw);
  }

  /// Обновить элемент корзины (например, заменить опции), затем сохранить
  static Future<void> updateItem(int index, CartItem newItem) async {
    if (index < 0 || index >= _items.length) return;
    _items[index] = newItem;
    await _save();
  }

  /// Найти индекс первой копии указанного CartItem (по itemId, size, extras, options)
  static int indexOfFirst(CartItem item) {
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_isSameLogicalItem(it, item)) {
        return i;
      }
    }
    return -1;
  }

  /// Заменить первую найденную копию oldItem на newItem
  static Future<void> replaceFirst(CartItem oldItem, CartItem newItem) async {
    final idx = indexOfFirst(oldItem);
    if (idx == -1) return;
    _items[idx] = newItem;
    await _save();
    cartCountNotifier.value = _items.length;
  }

  /// Сравнение логической идентичности двух CartItem (для группировки / замены).
  /// Для bundle учитываем состав (meta.slots.items) как сигнатуру.
  static bool _isSameLogicalItem(CartItem a, CartItem b) {
    if (a.itemId != b.itemId) return false;
    if (a.size != b.size) return false;
    if (!mapEquals(a.extras, b.extras)) return false;
    if (!mapEquals(a.options, b.options)) return false;
    // Bundle: различный состав -> разные элементы
    final typeA = a.meta?['type'];
    final typeB = b.meta?['type'];
    if (typeA == 'bundle' || typeB == 'bundle') {
      if (typeA != typeB) return false;
      final slotsA =
          (a.meta?['slots'] as List?)?.cast<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[];
      final slotsB =
          (b.meta?['slots'] as List?)?.cast<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[];
      if (slotsA.length != slotsB.length) return false;
      for (int i = 0; i < slotsA.length; i++) {
        final sa = slotsA[i];
        final sb = slotsB[i];
        if ((sa['slotId'] as int?) != (sb['slotId'] as int?)) return false;
        final itemsA = (sa['items'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        final itemsB = (sb['items'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        if (itemsA.length != itemsB.length) return false;
        // сравниваем по набору itemId+sizeId+optionIds+extraIds
        List<String> sigA = itemsA.map((m) {
          final itemId = (m['itemId'] as int?) ?? 0;
          final sizeId = (m['sizeId'] as int?) ?? -1;
          final optionIds = ((m['optionIds'] as List?) ?? const <dynamic>[])
            ..sort();
          final extraIds = ((m['extraIds'] as List?) ?? const <dynamic>[])
            ..sort();
          return 'i:$itemId|s:$sizeId|o:${optionIds.join(";")}|e:${extraIds.join(";")}';
        }).toList()
          ..sort();
        List<String> sigB = itemsB.map((m) {
          final itemId = (m['itemId'] as int?) ?? 0;
          final sizeId = (m['sizeId'] as int?) ?? -1;
          final optionIds = ((m['optionIds'] as List?) ?? const <dynamic>[])
            ..sort();
          final extraIds = ((m['extraIds'] as List?) ?? const <dynamic>[])
            ..sort();
          return 'i:$itemId|s:$sizeId|o:${optionIds.join(";")}|e:${extraIds.join(";")}';
        }).toList()
          ..sort();
        if (sigA.length != sigB.length) return false;
        for (int k = 0; k < sigA.length; k++) {
          if (sigA[k] != sigB[k]) return false;
        }
      }
    }
    return true;
  }

  /// Повторить прошлый заказ: подтянуть из order_items и добавить в корзину
  static Future<void> repeatOrder(int orderId) async {
    final data = await Supabase.instance.client
        .from('order_items')
        .select() // получаем все поля
        .eq('order_id', orderId);
    final list = data as List<dynamic>;
    for (var e in list) {
      final m = e as Map<String, dynamic>;

      // Определяем размер: если есть size_id, получаем имя, иначе берём строку из m['size']
      String resolvedSize;
      int? resolvedSizeId;
      if (m['size_id'] != null) {
        final sizeRow = await Supabase.instance.client
            .from('menu_size')
            .select('name')
            .eq('id', m['size_id'])
            .maybeSingle();
        resolvedSize = sizeRow != null
            ? ((sizeRow['name'] as String?) ?? '')
            : ((m['size'] as String?) ?? '');
        resolvedSizeId = (m['size_id'] as int?);
      } else {
        resolvedSize = (m['size'] as String?) ?? '';
        resolvedSizeId = null;
      }

      // Обрабатываем extras из m['extras']
      final dynamic rawExtras = m['extras'];
      Map<int, int> parsedExtras;
      if (rawExtras is String) {
        if (rawExtras.isEmpty) {
          parsedExtras = <int, int>{};
        } else {
          final decoded = jsonDecode(rawExtras);
          parsedExtras = (decoded as Map).cast<int, int>();
        }
      } else if (rawExtras is Map) {
        parsedExtras = (rawExtras as Map<String, dynamic>).map(
            (key, value) => MapEntry(int.parse(key), (value as int?) ?? 0));
      } else {
        parsedExtras = <int, int>{};
      }

      final resolvedItemId =
          (m['menu_v2_item_id'] as int?) ?? (m['menu_item_id'] as int?) ?? 0;
      final item = CartItem(
        itemId: resolvedItemId,
        name: (m['item_name'] as String?) ?? '',
        size: resolvedSize,
        basePrice: (m['price'] as num).toDouble(),
        extras: parsedExtras,
        options: <int, int>{},
        article: m['article'] as String?,
        sizeId: resolvedSizeId,
      );
      await addItem(item);
    }
  }

  /// Добавить в корзину товар по его menu_item.id,
  /// автоматически подбирая размер с самой низкой ценой.
  static Future<void> addItemById(int itemId,
      {String defaultSize = 'Normal'}) async {
    final supabase = Supabase.instance.client;

    // 1) Получаем всю нужную информацию о товаре
    final itemRow = await supabase
        .from('menu_v2_item')
        .select('id, name, sku, has_sizes, is_active, is_available')
        .eq('id', itemId)
        .maybeSingle();

    if (itemRow == null) {
      throw Exception('Товар с id=$itemId не найден в menu_item');
    }

    final String itemName = (itemRow['name'] as String?) ?? '';
    final String? article = itemRow['sku'] as String?;

    // 2) Берём цены из представления menu_v2_item_prices
    final rows = await supabase
        .from('menu_v2_item_prices')
        .select('size_id, price, is_single_size')
        .eq('item_id', itemId)
        .order('is_single_size', ascending: false)
        .order('size_id', ascending: true);
    if (rows.isEmpty) {
      final CartItem newItem = CartItem(
        itemId: itemId,
        name: itemName,
        size: defaultSize,
        basePrice: 0.0,
        extras: <int, int>{},
        options: <int, int>{},
        article: article,
        sizeId: null,
      );
      await addItem(newItem);
      return;
    }
    final isSingle = (rows.first['is_single_size'] as bool?) ?? false;
    int? chosenSizeId;
    String chosenSizeName = defaultSize;
    double chosenPrice = 0.0;
    if (isSingle) {
      chosenSizeId = null;
      chosenSizeName = 'Normal';
      chosenPrice = (rows.first['price'] as num?)?.toDouble() ?? 0.0;
    } else {
      // ищем минимальную цену и её size_id, затем вытащим имя размера
      Map<String, dynamic>? cheapest;
      for (final r in rows) {
        if (cheapest == null ||
            ((r['price'] as num).toDouble() <
                (cheapest['price'] as num).toDouble())) {
          cheapest = r;
        }
      }
      final int sid = (cheapest?['size_id'] as int?) ?? 0;
      chosenPrice = (cheapest?['price'] as num?)?.toDouble() ?? 0.0;
      chosenSizeId = sid;
      if (sid != 0) {
        final sz = await supabase
            .from('menu_size')
            .select('name')
            .eq('id', sid)
            .maybeSingle();
        chosenSizeName = (sz?['name'] as String?) ?? defaultSize;
      }
    }

    final CartItem newItem = CartItem(
      itemId: itemId,
      name: itemName,
      size: chosenSizeName,
      basePrice: chosenPrice,
      extras: <int, int>{},
      options: <int, int>{},
      article: article,
      sizeId: chosenSizeId,
    );

    await addItem(newItem);
  }
}
