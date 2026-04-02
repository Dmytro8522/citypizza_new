import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'cart_service.dart';
import 'restaurant_context.dart';

class CartSanitizationResult {
  final bool changed;
  final int removedItems;
  final int removedExtras;
  final int removedOptions;
  final List<int> affectedItemIds;

  const CartSanitizationResult({
    required this.changed,
    required this.removedItems,
    required this.removedExtras,
    required this.removedOptions,
    required this.affectedItemIds,
  });

  bool get hasUnavailable => changed;
}

class MenuVisibilityService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static bool isVisibleEntity(Map<String, dynamic> row) {
    final isActive = row['is_active'];
    final isDeleted = row['is_deleted'];
    return isActive != false && isDeleted != true;
  }

  static Future<bool> isMenuItemVisible(int itemId) async {
    final rows = await _fetchVisibilityRows('menu_v2_item', [itemId]);
    if (rows.isEmpty) return false;
    return isVisibleEntity(rows.first);
  }

  static Future<bool> isBundleVisible(int bundleId) async {
    final rows = await _fetchVisibilityRows('menu_v2_bundle', [bundleId]);
    if (rows.isEmpty) return false;
    return isVisibleEntity(rows.first);
  }

  static Future<void> logMenuItemUnavailable({
    required int itemId,
    String reason = 'hidden',
    String source = 'unknown',
  }) async {
    debugPrint(
      'menu_item_unavailable: itemId=$itemId reason=$reason source=$source',
    );

    try {
      await _supabase.from('client_event_log').insert({
        'restaurant_id': RestaurantContext.current,
        'event_name': 'menu_item_unavailable',
        'context': {
          'itemId': itemId,
          'reason': reason,
          'source': source,
        },
      });
    } catch (_) {
      // optional analytics sink might be absent on some deployments
    }
  }

  static Future<CartSanitizationResult> sanitizeCartHiddenEntities({
    String source = 'unknown',
  }) async {
    final current = List<CartItem>.from(CartService.items);
    if (current.isEmpty) {
      return const CartSanitizationResult(
        changed: false,
        removedItems: 0,
        removedExtras: 0,
        removedOptions: 0,
        affectedItemIds: <int>[],
      );
    }

    final itemIds = current.map((e) => e.itemId).toSet().toList();
    final itemRows = await _fetchVisibilityRows('menu_v2_item', itemIds,
        extraColumns: const ['category_id']);

    final visibleItemIds = <int>{};
    final categoryByItem = <int, int>{};
    for (final row in itemRows) {
      final id = (row['id'] as int?) ?? 0;
      if (id == 0) continue;
      if (isVisibleEntity(row)) {
        visibleItemIds.add(id);
        final cid = (row['category_id'] as int?) ?? 0;
        if (cid != 0) categoryByItem[id] = cid;
      }
    }

    final extrasInCart = <int>{};
    final optionsInCart = <int>{};
    for (final it in current) {
      extrasInCart.addAll(it.extras.keys);
      optionsInCart.addAll(it.options.keys);
    }

    final visibleExtraIds =
        await _fetchVisibleIds('menu_v2_extra', extrasInCart);
    final visibleOptionIds =
        await _fetchVisibleIds('menu_v2_modifier_option', optionsInCart);

    final categoryIds = categoryByItem.values.toSet().toList();
    final itemAllowedExtras = await _fetchAllowedExtrasByItem(itemIds);
    final categoryAllowedExtras =
        await _fetchAllowedExtrasByCategory(categoryIds);
    final allowedOptionsByItem =
        await _fetchAllowedOptionIdsByItem(itemIds, categoryByItem);

    final next = <CartItem>[];
    final affected = <int>{};
    int removedItems = 0;
    int removedExtras = 0;
    int removedOptions = 0;

    for (final it in current) {
      if (!visibleItemIds.contains(it.itemId)) {
        removedItems += 1;
        affected.add(it.itemId);
        await logMenuItemUnavailable(
          itemId: it.itemId,
          reason: 'hidden',
          source: source,
        );
        continue;
      }

      final allowedExtras = itemAllowedExtras[it.itemId];
      final fallbackAllowedExtras =
          categoryAllowedExtras[categoryByItem[it.itemId] ?? 0];
      final allowedExtrasFinal =
          (allowedExtras != null && allowedExtras.isNotEmpty)
              ? allowedExtras
              : (fallbackAllowedExtras ?? const <int>{});

      final newExtras = <int, int>{};
      for (final e in it.extras.entries) {
        final isVisible = visibleExtraIds.contains(e.key);
        final isAllowed = allowedExtrasFinal.isNotEmpty
            ? allowedExtrasFinal.contains(e.key)
            : false;
        if (isVisible && isAllowed) {
          newExtras[e.key] = e.value;
        } else {
          removedExtras += e.value;
          affected.add(it.itemId);
        }
      }

      final allowedOptions = allowedOptionsByItem[it.itemId] ?? const <int>{};
      final newOptions = <int, int>{};
      for (final o in it.options.entries) {
        final isVisible = visibleOptionIds.contains(o.key);
        final isAllowed = allowedOptions.contains(o.key);
        if (isVisible && isAllowed) {
          newOptions[o.key] = o.value;
        } else {
          removedOptions += o.value;
          affected.add(it.itemId);
        }
      }

      if (newExtras.length != it.extras.length ||
          newOptions.length != it.options.length) {
        await logMenuItemUnavailable(
          itemId: it.itemId,
          reason: 'hidden',
          source: source,
        );
      }

      next.add(CartItem(
        itemId: it.itemId,
        name: it.name,
        size: it.size,
        basePrice: it.basePrice,
        extras: newExtras,
        options: newOptions,
        article: it.article,
        sizeId: it.sizeId,
        meta: it.meta,
      ));
    }

    final changed = removedItems > 0 ||
        removedExtras > 0 ||
        removedOptions > 0 ||
        next.length != current.length;
    if (changed) {
      await CartService.replaceAll(next);
    }

    return CartSanitizationResult(
      changed: changed,
      removedItems: removedItems,
      removedExtras: removedExtras,
      removedOptions: removedOptions,
      affectedItemIds: affected.toList()..sort(),
    );
  }

  static Future<Map<int, Set<int>>> _fetchAllowedExtrasByItem(
      List<int> itemIds) async {
    final result = <int, Set<int>>{};
    if (itemIds.isEmpty) return result;

    try {
      final rows = await _supabase
          .from('menu_v2_item_allowed_extras')
          .select('item_id, extra_id')
          .eq('restaurant_id', RestaurantContext.current)
          .filter('item_id', 'in', '(${itemIds.join(',')})');
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final itemId = (row['item_id'] as int?) ?? 0;
        final extraId = (row['extra_id'] as int?) ?? 0;
        if (itemId == 0 || extraId == 0) continue;
        (result[itemId] ??= <int>{}).add(extraId);
      }
    } catch (_) {}

    return result;
  }

  static Future<Map<int, Set<int>>> _fetchAllowedExtrasByCategory(
      List<int> categoryIds) async {
    final result = <int, Set<int>>{};
    if (categoryIds.isEmpty) return result;

    try {
      final rows = await _supabase
          .from('menu_v2_category_allowed_extras')
          .select('category_id, extra_id')
          .eq('restaurant_id', RestaurantContext.current)
          .filter('category_id', 'in', '(${categoryIds.join(',')})');
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final categoryId = (row['category_id'] as int?) ?? 0;
        final extraId = (row['extra_id'] as int?) ?? 0;
        if (categoryId == 0 || extraId == 0) continue;
        (result[categoryId] ??= <int>{}).add(extraId);
      }
    } catch (_) {}

    return result;
  }

  static Future<Map<int, Set<int>>> _fetchAllowedOptionIdsByItem(
    List<int> itemIds,
    Map<int, int> categoryByItem,
  ) async {
    final result = <int, Set<int>>{};
    if (itemIds.isEmpty) return result;

    final categoryIds = categoryByItem.values.toSet().toList();

    final categoryGroupIds = <int, Set<int>>{};
    if (categoryIds.isNotEmpty) {
      try {
        final rows = await _supabase
            .from('menu_v2_category_modifier_group')
            .select('category_id, group_id')
            .eq('restaurant_id', RestaurantContext.current)
            .filter('category_id', 'in', '(${categoryIds.join(',')})');
        for (final row in (rows as List).cast<Map<String, dynamic>>()) {
          final categoryId = (row['category_id'] as int?) ?? 0;
          final groupId = (row['group_id'] as int?) ?? 0;
          if (categoryId == 0 || groupId == 0) continue;
          (categoryGroupIds[categoryId] ??= <int>{}).add(groupId);
        }
      } catch (_) {}
    }

    final overridesByItem = <int, Map<int, bool>>{};
    try {
      final rows = await _supabase
          .from('menu_v2_item_modifier_group_override')
          .select('item_id, group_id, enabled')
          .eq('restaurant_id', RestaurantContext.current)
          .filter('item_id', 'in', '(${itemIds.join(',')})');
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final itemId = (row['item_id'] as int?) ?? 0;
        final groupId = (row['group_id'] as int?) ?? 0;
        if (itemId == 0 || groupId == 0) continue;
        final enabled = (row['enabled'] as bool?) ?? true;
        (overridesByItem[itemId] ??= <int, bool>{})[groupId] = enabled;
      }
    } catch (_) {}

    final allGroupIds = <int>{};
    for (final cid in categoryIds) {
      allGroupIds.addAll(categoryGroupIds[cid] ?? const <int>{});
    }
    for (final map in overridesByItem.values) {
      allGroupIds.addAll(map.keys);
    }

    final visibleGroupIds =
        await _fetchVisibleIds('menu_v2_modifier_group', allGroupIds);
    final optionRows = <Map<String, dynamic>>[];
    if (allGroupIds.isNotEmpty) {
      try {
        final rows = await _fetchVisibilityRows(
          'menu_v2_modifier_option',
          null,
          filterColumn: 'group_id',
          filterIds: allGroupIds.toList(),
          extraColumns: const ['group_id'],
        );
        optionRows.addAll(rows);
      } catch (_) {}
    }

    final optionsByGroup = <int, Set<int>>{};
    for (final row in optionRows) {
      if (!isVisibleEntity(row)) continue;
      final optionId = (row['id'] as int?) ?? 0;
      final groupId = (row['group_id'] as int?) ?? 0;
      if (optionId == 0 || groupId == 0) continue;
      if (!visibleGroupIds.contains(groupId)) continue;
      (optionsByGroup[groupId] ??= <int>{}).add(optionId);
    }

    for (final itemId in itemIds) {
      final cid = categoryByItem[itemId] ?? 0;
      final base = <int>{...?(categoryGroupIds[cid])};
      final overrides = overridesByItem[itemId] ?? const <int, bool>{};
      final effective = <int>{...base};
      for (final entry in overrides.entries) {
        if (entry.value) {
          effective.add(entry.key);
        } else {
          effective.remove(entry.key);
        }
      }
      effective.removeWhere((gid) => !visibleGroupIds.contains(gid));

      final allowed = <int>{};
      for (final gid in effective) {
        allowed.addAll(optionsByGroup[gid] ?? const <int>{});
      }
      result[itemId] = allowed;
    }

    return result;
  }

  static Future<Set<int>> _fetchVisibleIds(
      String table, Iterable<int> ids) async {
    final normalized = ids.where((id) => id > 0).toSet().toList();
    if (normalized.isEmpty) return <int>{};
    final rows = await _fetchVisibilityRows(table, normalized);
    final out = <int>{};
    for (final row in rows) {
      final id = (row['id'] as int?) ?? 0;
      if (id != 0 && isVisibleEntity(row)) out.add(id);
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> _fetchVisibilityRows(
    String table,
    List<int>? ids, {
    String idColumn = 'id',
    List<String> extraColumns = const [],
    String? filterColumn,
    List<int>? filterIds,
  }) async {
    final filters = (filterIds ?? ids ?? const <int>[])
        .where((id) => id > 0)
        .toSet()
        .toList();
    if (ids != null && filters.isEmpty) return const <Map<String, dynamic>>[];

    final selectColumns = <String>{idColumn, ...extraColumns};

    Future<List<Map<String, dynamic>>> run(List<String> visCols) async {
      final sel = [...selectColumns, ...visCols].join(', ');
      var query = _supabase
          .from(table)
          .select(sel)
          .eq('restaurant_id', RestaurantContext.current);
      if (filters.isNotEmpty) {
        query = query.filter(
            filterColumn ?? idColumn, 'in', '(${filters.join(',')})');
      }
      final rows = await query;
      return (rows as List).cast<Map<String, dynamic>>();
    }

    try {
      return await run(const ['is_active', 'is_deleted']);
    } catch (_) {
      try {
        return await run(const ['is_active']);
      } catch (_) {
        return run(const []);
      }
    }
  }
}
