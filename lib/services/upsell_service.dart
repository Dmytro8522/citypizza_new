// lib/services/upsell_service.dart

import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_service.dart';

class UpSellService {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Правила UpSell по ТЗ: upsell_rules с condition_json и offer_item_ids.
  /// Возвращает до 8 карточек (с учётом offer_limit и дедупликации) для legacy каналов,
  /// уже отфильтрованных: не предлагать товары, которые есть в корзине.
  /// Если передан itemId (экран деталей позиции), отдаются группы в формате
  /// [{group_id, group_name, items: [...] }], без глобального лимита и с учётом max_items
  /// каждой группы. Поддержаны условия: any_of_categories, missing_categories,
  /// only_categories, contains_item_ids, has_any_size_ids; item_added_in_categories
  /// учитывается только если channel == 'post_add' и передан itemAddedCategoryId.
  static Future<List<Map<String, dynamic>>> fetchUpsell({
    required String channel,
    required double subtotal,
    String? userId,
    int? itemAddedCategoryId, // для post_add, если нужно
    int? itemId, // текущая позиция для экрана деталей (v2 по группам)
  }) async {
    // Ветка v2: если известен текущий itemId (экран деталей), берём допродажи из привязанных upsell-групп
    if (itemId != null) {
      // 1) Получаем категорию позиции
      final itRow = await _client
          .from('menu_v2_item')
          .select('id, category_id')
          .eq('id', itemId)
          .maybeSingle();
      if (itRow == null) return [];
      final int catId = (itRow['category_id'] as int?) ?? 0;

      // 2) Берём групповые привязки от категории и оверрайды позиции
      final catGroupsRaw = await _client
          .from('menu_v2_category_upsell_group')
          .select('upsell_group_id, sort_order')
          .eq('category_id', catId)
          .order('sort_order');
      final itemOvRaw = await _client
          .from('menu_v2_item_upsell_group_override')
          .select('upsell_group_id, enabled, sort_order')
          .eq('item_id', itemId);

      final catGroups = (catGroupsRaw as List).cast<Map<String, dynamic>>();
      final itemOvrs = (itemOvRaw as List).cast<Map<String, dynamic>>();
      final ovByGroup = {for (final o in itemOvrs) ((o['upsell_group_id'] as int?) ?? 0): o};

      // 3) Собираем итоговый упорядоченный список групп
      final merged = <Map<String, dynamic>>[];
      for (final cg in catGroups) {
        final gid = (cg['upsell_group_id'] as int?) ?? 0;
        if (gid == 0) continue;
        final ov = ovByGroup[gid];
        final enabled = ov == null ? true : ((ov['enabled'] as bool?) ?? true);
        if (!enabled) continue;
        final sort = ov != null
            ? ((ov['sort_order'] as int?) ?? (cg['sort_order'] as int? ?? 0))
            : ((cg['sort_order'] as int?) ?? 0);
        merged.add({'id': gid, 'sort_order': sort});
      }
      for (final ov in itemOvrs) {
        final gid = (ov['upsell_group_id'] as int?) ?? 0;
        if (gid == 0) continue;
        final enabled = (ov['enabled'] as bool?) ?? true;
        if (!enabled) continue;
        final already = merged.any((m) => m['id'] == gid);
        if (!already) {
          merged.add({'id': gid, 'sort_order': (ov['sort_order'] as int?) ?? 0});
        }
      }
      merged.sort((a, b) => ((a['sort_order'] as int?) ?? 0).compareTo(((b['sort_order'] as int?) ?? 0)));
      if (merged.isEmpty) return [];

      final groupIds = merged.map((m) => (m['id'] as int)).toList();

      // 4) Получаем ограничения групп и их названия
      final ugRows = await _client
          .from('menu_v2_upsell_group')
          .select('id, name, max_items')
          .filter('id', 'in', '(${groupIds.join(',')})');
      final ugList = (ugRows as List).cast<Map<String, dynamic>>();
      final maxItemsByGroup = {
        for (final m in ugList) ((m['id'] as int?) ?? 0): (m['max_items'] as int?)
      };
      final nameByGroup = {
        for (final m in ugList) ((m['id'] as int?) ?? 0): (m['name'] as String?) ?? ''
      };

      // Список товаров в корзине для исключения, и сам товар, чтобы не рекомендовать его же
      final cartItemIds = CartService.items.map((e) => e.itemId).toSet();

      final groupsToItemIds = <int, List<int>>{};
      final idsToFetch = <int>{};

      // 5) Для каждой группы собираем источники карточек
      for (final g in merged) {
        final gid = (g['id'] as int);
        final srcRows = await _client
            .from('menu_v2_upsell_group_source')
            .select('include_type, category_id, item_id')
            .eq('upsell_group_id', gid);
        final srcList = (srcRows as List).cast<Map<String, dynamic>>();

        final ids = <int>{};
        final directItemIds = <int>{
          for (final s in srcList)
            if ((s['include_type'] as String?) == 'item' && s['item_id'] != null)
              (s['item_id'] as int)
        };
        ids.addAll(directItemIds);

        final catIds = <int>{
          for (final s in srcList)
            if ((s['include_type'] as String?) == 'category' && s['category_id'] != null)
              (s['category_id'] as int)
        };
        if (catIds.isNotEmpty) {
          final itemsByCat = await _client
              .from('menu_v2_item')
              .select('id')
              .filter('category_id', 'in', '(${catIds.join(',')})')
              .eq('is_active', true);
          for (final r in (itemsByCat as List).cast<Map<String, dynamic>>()) {
            final iid = (r['id'] as int?) ?? 0;
            if (iid != 0) ids.add(iid);
          }
        }

        // Убираем сам товар и позиции уже в корзине
        ids.remove(itemId);
        ids.removeWhere((iid) => cartItemIds.contains(iid));
        ids.remove(0);

        if (ids.isEmpty) continue;

        final groupLimit = maxItemsByGroup[gid] ?? 0;
        final limitedList = groupLimit <= 0
            ? ids.toList()
            : ids.take(groupLimit).toList();
        if (limitedList.isEmpty) continue;

        groupsToItemIds[gid] = limitedList;
        idsToFetch.addAll(limitedList);
      }

      if (groupsToItemIds.isEmpty) return [];

      final ids = idsToFetch.toList();

      // 6) Цены из menu_v2_item_prices — берём минимальную
      final priceRows = await _client
          .from('menu_v2_item_prices')
          .select('item_id, size_id, price, is_single_size')
          .filter('item_id', 'in', '(${ids.join(',')})');
      final minPriceByItem = <int, double>{};
      for (final r in (priceRows as List).cast<Map<String, dynamic>>()) {
        final iid = (r['item_id'] as int?) ?? 0;
        final price = (r['price'] as num?)?.toDouble() ?? 0.0;
        if (!minPriceByItem.containsKey(iid) || price < minPriceByItem[iid]!) {
          minPriceByItem[iid] = price;
        }
      }

      final rawItems = await _client
          .from('menu_v2_item')
          .select('id, name, sku, image_url')
          .filter('id', 'in', '(${ids.join(',')})');
      final itemsList = (rawItems as List).cast<Map<String, dynamic>>();

      final byId = <int, Map<String, dynamic>>{};
      for (final m in itemsList) {
        final id = (m['id'] as int?) ?? 0;
        byId[id] = {
          'id': id,
          'name': m['name'] as String? ?? '',
          'article': m['sku'] as String?,
          'image_url': m['image_url'] as String?,
          'price': minPriceByItem[id] ?? 0.0,
        };
      }

      final groupedResult = <Map<String, dynamic>>[];
      for (final g in merged) {
        final gid = (g['id'] as int);
        final itemIds = groupsToItemIds[gid];
        if (itemIds == null || itemIds.isEmpty) continue;

        final items = <Map<String, dynamic>>[];
        for (final iid in itemIds) {
          final itemData = byId[iid];
          if (itemData != null) {
            items.add(itemData);
          }
        }
        if (items.isEmpty) continue;

        groupedResult.add({
          'group_id': gid,
          'group_name': nameByGroup[gid] ?? '',
          'items': items,
        });
      }

      return groupedResult;
    }

    // 1) Загрузка активных правил по каналу, приоритет ASC
    final rulesRes = await _client
        .from('upsell_rules')
        .select('id, name, priority, condition_json, offer_item_ids, offer_limit')
        .eq('active', true)
        .eq('channel', channel)
        .order('priority', ascending: true);
    final rules = (rulesRes as List).cast<Map<String, dynamic>>();
    if (rules.isEmpty) return [];

    // 2) Готовим контекст корзины: itemIds, sizeIds, categoryIds
  final cartItems = CartService.items;

    final cartItemIds = cartItems.map((e) => e.itemId).toSet();
    final cartSizeIds = cartItems.map((e) => e.sizeId).where((e) => e != null).cast<int>().toSet();

    // Получим категории для всех уникальных itemId в корзине
    final uniqueItemIds = cartItemIds.toList();
    final Map<int, int> itemIdToCategory = {};
    if (uniqueItemIds.isNotEmpty) {
      final catRows = await _client
          .from('menu_item')
          .select('id, category_id')
          .filter('id', 'in', uniqueItemIds);
      for (final r in (catRows as List).cast<Map<String, dynamic>>()) {
        itemIdToCategory[(r['id'] as int?) ?? 0] = (r['category_id'] as int?) ?? 0;
      }
    }
    final cartCategoryIds = itemIdToCategory.values.where((v) => v != 0).toSet();

    // Функция разрешения имён категорий в id для condition_json (если заданы строками)
    Future<Set<int>> resolveCategoryNamesToIds(List<dynamic> names) async {
      if (names.isEmpty) return <int>{};
      final rows = await _client
          .from('menu_category')
          .select('id, name')
          .filter('name', 'in', names.cast<String>());
      final set = <int>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final id = (r['id'] as int?) ?? 0;
        if (id != 0) set.add(id);
      }
      return set;
    }

    // 3) Пробегаем по правилам по приоритету и собираем офферы
    final resultIds = <int>{};
    final orderedOffers = <int>[];

    for (final rule in rules) {
      // condition_json может быть Map или String
      final rawCond = rule['condition_json'];
      final Map<String, dynamic> cond = rawCond == null
          ? <String, dynamic>{}
          : (rawCond is String ? jsonDecode(rawCond) : (rawCond as Map<String, dynamic>));

      // Парсим поля условия
      final anyOfCats = (cond['any_of_categories'] as List?) ?? const [];
      final missingCats = (cond['missing_categories'] as List?) ?? const [];
      final onlyCats = (cond['only_categories'] as List?) ?? const [];
      final containsIds = (cond['contains_item_ids'] as List?) ?? const [];
      final addedInCats = (cond['item_added_in_categories'] as List?) ?? const [];
      final hasAnySizeIds = (cond['has_any_size_ids'] as List?) ?? const [];

      // Разрешаем категории-строки в id
      final anyOfCatIds = await resolveCategoryNamesToIds(anyOfCats);
      final missingCatIds = await resolveCategoryNamesToIds(missingCats);
      final onlyCatIds = await resolveCategoryNamesToIds(onlyCats);
      final addedInCatIds = await resolveCategoryNamesToIds(addedInCats);

      bool matches = true;

      // any_of_categories: есть хотя бы одна категория из списка
      if (anyOfCatIds.isNotEmpty) {
        if (cartCategoryIds.intersection(anyOfCatIds).isEmpty) matches = false;
      }

      // missing_categories: таких категорий не должно быть в корзине
      if (matches && missingCatIds.isNotEmpty) {
        if (cartCategoryIds.intersection(missingCatIds).isNotEmpty) matches = false;
      }

      // only_categories: все категории корзины должны входить в список
      if (matches && onlyCatIds.isNotEmpty) {
        if (cartCategoryIds.isEmpty || !cartCategoryIds.every((c) => onlyCatIds.contains(c))) {
          matches = false;
        }
      }

      // contains_item_ids: в корзине должны быть указанные товары
      if (matches && containsIds.isNotEmpty) {
        final req = containsIds.cast<int>().toSet();
        if (!cartItemIds.containsAll(req)) matches = false;
      }

      // has_any_size_ids: в корзине есть товары с этими size_id
      if (matches && hasAnySizeIds.isNotEmpty) {
        final reqSizes = hasAnySizeIds.cast<int>().toSet();
        if (cartSizeIds.intersection(reqSizes).isEmpty) matches = false;
      }

      // item_added_in_categories: только для post_add
      if (matches && addedInCatIds.isNotEmpty) {
        if (channel != 'post_add') {
          matches = false; // условие применимо только для post_add
        } else if (itemAddedCategoryId == null || !addedInCatIds.contains(itemAddedCategoryId)) {
          matches = false;
        }
      }

      if (!matches) continue;

      // Список офферов из правила
      final offerIds = (rule['offer_item_ids'] as List?)?.cast<int>() ?? const <int>[];
      if (offerIds.isEmpty) continue;

      // 4) Фильтруем те, что уже в корзине
      final filtered = offerIds.where((id) => !cartItemIds.contains(id));

      // 5) Лимит по правилу
      final offerLimit = (rule['offer_limit'] as int?) ?? 8;
      final limited = filtered.take(offerLimit);

      // 6) Дедупликация и глобальный лимит 8
      for (final id in limited) {
        if (resultIds.length >= 8) break;
        if (resultIds.add(id)) orderedOffers.add(id);
      }

      if (resultIds.length >= 8) break;
    }

    if (orderedOffers.isEmpty) return [];

    // 7) Цены из нового представления menu_v2_item_prices: берём минимальную
    final ids = orderedOffers;
    final priceRows = await _client
        .from('menu_v2_item_prices')
        .select('item_id, size_id, price, is_single_size')
        .filter('item_id', 'in', '(${ids.join(',')})');
    final minPriceByItem = <int, double>{};
    for (final r in (priceRows as List).cast<Map<String, dynamic>>()) {
      final iid = (r['item_id'] as int?) ?? 0;
      final price = (r['price'] as num?)?.toDouble() ?? 0.0;
      if (!minPriceByItem.containsKey(iid) || price < minPriceByItem[iid]!) {
        minPriceByItem[iid] = price;
      }
    }

    final rawItems = await _client
        .from('menu_v2_item')
        .select('id, name, sku, image_url')
        .filter('id', 'in', ids);
    final itemsList = (rawItems as List).cast<Map<String, dynamic>>();

    final byId = <int, Map<String, dynamic>>{};
    for (final m in itemsList) {
      final id = (m['id'] as int?) ?? 0;
      byId[id] = {
        'id': id,
        'name': m['name'] as String? ?? '',
        'article': m['sku'] as String?,
        'image_url': m['image_url'] as String?,
        'price': minPriceByItem[id] ?? 0.0,
      };
    }

    return ids.where(byId.containsKey).map((id) => byId[id]!).toList();
  }
}
