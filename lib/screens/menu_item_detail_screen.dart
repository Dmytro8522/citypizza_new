// lib/screens/menu_item_detail_screen.dart

import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/menu_item.dart'; // MenuItem model
import '../services/cart_service.dart'; // CartItem & CartService
import '../widgets/no_internet_widget.dart';
import '../theme/theme_provider.dart';
import '../widgets/upsell_widget.dart';
import '../widgets/price_with_promotion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/delivery_zone_service.dart';
import '../services/discount_service.dart';
import '../utils/globals.dart';

class ExtraOption {
  final int id;
  final String name;
  final double price;
  int quantity;
  Key key;
  ExtraOption({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 0,
  }) : key = UniqueKey();
}

class SizeOption {
  final int? id;
  final String name;
  final double price;
  final PromotionPrice? promotion;
  SizeOption({
    required this.id,
    required this.name,
    required this.price,
    this.promotion,
  });
}

class MenuItemDetailScreen extends StatefulWidget {
  final MenuItem item;
  const MenuItemDetailScreen({super.key, required this.item});

  @override
  State<MenuItemDetailScreen> createState() => _MenuItemDetailScreenState();
}

class _MenuItemDetailScreenState extends State<MenuItemDetailScreen>
    with TickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Размеры и допы
  List<SizeOption> _sizeOptions = [];
  SizeOption? _selectedSize;
  List<ExtraOption> _extras = [];
  bool _loadingSizes = true;
  bool _loadingExtras = false;
  bool _itemHasSizes = true;

  // Аллергены/добавки (используем названия из additives.title)
  List<String> _additiveLabels = [];
  bool _loadingAdditives = true;

  // Новые опции (menu_option_group/menu_option_item)
  bool _loadingOptions = true;
  List<_OptionGroup> _optionGroups = [];
  // Состояние выбора по группам:
  // radio: groupId -> optionId
  final Map<int, int?> _selectedRadio = {};
  // checkbox: groupId -> set<optionId>
  final Map<int, Set<int>> _selectedChecks = {};
  // counter: groupId -> {optionId: qty}
  final Map<int, Map<int, int>> _selectedCounters = {};
  int? _categoryId;

  late final ScrollController _scrollController;
  final GlobalKey _cartIconKey = GlobalKey();

  String? _error;
  bool get _isAnyLoading =>
      _loadingSizes || _loadingExtras || _loadingOptions || _loadingAdditives;

  // Состояние разворота секций (для ленивого построения тяжёлого контента)
  final Map<int, bool> _groupExpanded = {}; // groupId -> expanded
  bool _extrasExpanded = false;
  bool _sizesExpanded = true; // для многомерных по умолчанию раскрыто

  // Mindestbestellwert Hinweis (Lieferung)
  double? _minOrderAmount;
  double _discountedCartTotalGlobal = 0.0; // rabattierte Gesamtsumme корзины
  bool _computingCartTotal = false;

  bool get _showMinOrderBar {
    if (_minOrderAmount == null) return false;
    if (_discountedCartTotalGlobal + 0.0001 >= _minOrderAmount!) return false;
    return true;
  }

  // Убрали искусственную задержку показа «тяжёлого» контента — показываем сразу

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initAll();
    _initMinOrderContext();
    CartService.cartCountNotifier.addListener(_recomputeCartSummary);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    CartService.cartCountNotifier.removeListener(_recomputeCartSummary);
    super.dispose();
  }

  Future<void> _initMinOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('delivery_mode');
    if (mode != 'delivery') {
      setState(() {
        _minOrderAmount = null;
        _discountedCartTotalGlobal = 0.0;
      });
      return;
    }
    final postal = prefs.getString('user_postal_code');
    if (postal == null || postal.isEmpty) return;
    final mo =
        await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    setState(() => _minOrderAmount = mo);
    await _computeDiscountedCartTotalGlobal();
  }

  void _recomputeCartSummary() {
    _computeDiscountedCartTotalGlobal();
  }

  Future<void> _computeDiscountedCartTotalGlobal() async {
    final items = CartService.items;
    if (!mounted) return;
    if (items.isEmpty) {
      setState(() => _discountedCartTotalGlobal = 0.0);
      return;
    }
    setState(() => _computingCartTotal = true);
    try {
      final supabase = Supabase.instance.client;
      final itemIds = items.map((e) => e.itemId).toSet().toList();
      final sizeIds = items
          .map((e) => e.sizeId)
          .where((e) => e != null)
          .cast<int>()
          .toSet()
          .toList();
      final extraIds = <int>{};
      for (final it in items) extraIds.addAll(it.extras.keys);
      final extraPriceMap = <String, double>{};
      if (extraIds.isNotEmpty && sizeIds.isNotEmpty) {
        final rows = await supabase
            .from('menu_v2_extra_price_by_size')
            .select('size_id, extra_id, price')
            .filter('extra_id', 'in', extraIds.toList())
            .filter('size_id', 'in', sizeIds);
        for (final r in (rows as List).cast<Map<String, dynamic>>()) {
          final sid = (r['size_id'] as int?) ?? 0;
          final eid = (r['extra_id'] as int?) ?? 0;
          final p = (r['price'] as num).toDouble();
          extraPriceMap['$sid|$eid'] = p;
        }
      }
      final Map<int, int> itemIdToCategory = {};
      if (itemIds.isNotEmpty) {
        final catRows = await supabase
            .from('menu_v2_item')
            .select('id, category_id')
            .filter('id', 'in', itemIds);
        for (final r in (catRows as List).cast<Map<String, dynamic>>()) {
          final mid = (r['id'] as int?) ?? 0;
          final cid = (r['category_id'] as int?) ?? 0;
          if (mid != 0) itemIdToCategory[mid] = cid;
        }
      }
      final grouped = <String, List<CartItem>>{};
      for (final it in items) {
        final sigExtras =
            it.extras.entries.map((e) => '${e.key}:${e.value}').join(',');
        final sigOpts =
            it.options.entries.map((e) => '${e.key}:${e.value}').join(',');
        final key = '${it.itemId}|${it.size}|$sigExtras|$sigOpts';
        grouped.putIfAbsent(key, () => []).add(it);
      }
      double rawSum = 0.0;
      final cartList = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final first = entry.value.first;
        double unit = first.basePrice;
        for (final e in first.extras.entries) {
          unit += (extraPriceMap['${first.sizeId}|${e.key}'] ?? 0.0) * e.value;
        }
        final count = entry.value.length;
        rawSum += unit * count;
        cartList.add({
          'id': first.itemId,
          'category_id': itemIdToCategory[first.itemId],
          'size_id': first.sizeId,
          'price': unit,
          'quantity': count,
        });
      }
      DiscountResult? dres;
      try {
        dres = await calculateDiscountedTotal(
            cartItems: cartList, subtotal: rawSum);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _discountedCartTotalGlobal = dres?.total ?? rawSum;
        _computingCartTotal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _computingCartTotal = false);
    }
  }

  Future<void> _initAll() async {
    try {
      // Загружаем параллельно всё, что не зависит от выбранного размера
      // (опции, аллергены). Размеры+допы зависят от size и грузятся вместе.
      final fSizesExtras = _initSizesAndExtras();
      final fAdditives = _loadAdditives();
      final fOptions = _loadOptionGroups();
      await Future.wait([fSizesExtras, fAdditives, fOptions]);
    } on SocketException {
      setState(() {
        _error = 'Keine Internetverbindung';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<int?> _ensureCategoryId() async {
    if (_categoryId != null) return _categoryId;
    final row = await _supabase
        .from('menu_v2_item')
        .select('category_id')
        .eq('id', widget.item.id)
        .maybeSingle();
    _categoryId = row != null ? row['category_id'] as int? : null;
    return _categoryId;
  }

  PromotionPrice _priceFor(SizeOption option) {
    final promo = option.promotion;
    if (promo != null) return promo;
    return PromotionPrice(
      basePrice: option.price,
      finalPrice: option.price,
      discountAmount: 0,
      promotion: null,
      target: null,
    );
  }

  Future<void> _loadOptionGroups() async {
    setState(() {
      _loadingOptions = true;
      _optionGroups = [];
    });

    try {
      // v2: модификаторы приходят от категории с оверрайдом на позиции
      // 1) получим category_id позиции
      final catId = (await _ensureCategoryId()) ?? 0;

      if (catId == 0) {
        setState(() {
          _optionGroups = [];
          _loadingOptions = false;
        });
        return;
      }

      // 2) базовые группы от категории
      final baseGroupsRaw = await _supabase
          .from('menu_v2_category_modifier_group')
          .select(
              'group_id, sort_order, menu_v2_modifier_group(id, name, min_select, max_select)')
          .eq('category_id', catId);
      final baseGroups = (baseGroupsRaw as List).cast<Map<String, dynamic>>();

      // 3) оверрайды по позиции (могут как отключать/менять порядок, так и добавлять группу)
      final overridesRaw = await _supabase
          .from('menu_v2_item_modifier_group_override')
          .select('group_id, enabled, sort_order')
          .eq('item_id', widget.item.id);
      final overrides = (overridesRaw as List).cast<Map<String, dynamic>>();
      final overrideByGroup = {
        for (final o in overrides) ((o['group_id'] as int?) ?? 0): o
      };
      // 4) соберём финальные группы: union базовых и включённых оверрайдом
      //    a) карта мета по базовым группам
      final baseMetaById = <int,
          Map<String,
              dynamic>>{}; // id -> {name,min_select,max_select, sort_order_from_cat}
      for (final b in baseGroups) {
        final gobj = b['menu_v2_modifier_group'] as Map<String, dynamic>?;
        if (gobj == null) continue;
        final gid = (gobj['id'] as int?) ?? 0;
        baseMetaById[gid] = {
          'name': (gobj['name'] as String?) ?? '',
          'min_select': gobj['min_select'] as int?,
          'max_select': gobj['max_select'] as int?,
          'cat_sort_order': (b['sort_order'] as int?) ?? 0,
        };
      }

      //    b) найдём группы, которые присутствуют в оверрайдах, но отсутствуют в базе категории
      final overrideIds = overrideByGroup.keys.where((k) => k != 0).toSet();
      final missingIds =
          overrideIds.where((id) => !baseMetaById.containsKey(id)).toList();
      if (missingIds.isNotEmpty) {
        final inList = '(${missingIds.join(',')})';
        final missRows = await _supabase
            .from('menu_v2_modifier_group')
            .select('id, name, min_select, max_select, sort_order')
            .filter('id', 'in', inList);
        for (final r in (missRows as List).cast<Map<String, dynamic>>()) {
          final gid = (r['id'] as int?) ?? 0;
          baseMetaById[gid] = {
            'name': (r['name'] as String?) ?? '',
            'min_select': r['min_select'] as int?,
            'max_select': r['max_select'] as int?,
            // если группа добавлена только оверрайдом — в качестве базового порядка возьмём 0 (переопределит override.sort_order)
            'cat_sort_order': (r['sort_order'] as int?) ?? 0,
          };
        }
      }

      //    c) финальный список групп с применением enabled и итогового sort_order
      final groups = <Map<String, dynamic>>[];
      final allIds = baseMetaById.keys.toSet().union(overrideIds);
      for (final gid in allIds) {
        final meta = baseMetaById[gid];
        if (meta == null) continue;
        final ov = overrideByGroup[gid];
        final enabled = ov == null ? true : ((ov['enabled'] as bool?) ?? true);
        if (!enabled) continue;
        final sortOrder = ov != null
            ? ((ov['sort_order'] as int?) ??
                (meta['cat_sort_order'] as int? ?? 0))
            : (meta['cat_sort_order'] as int? ?? 0);
        groups.add({
          'id': gid,
          'name': (meta['name'] as String?) ?? '',
          'min_select': meta['min_select'] as int?,
          'max_select': meta['max_select'] as int?,
          'sort_order': sortOrder,
        });
      }
      groups.sort((a, b) => ((a['sort_order'] as int?) ?? 0)
          .compareTo(((b['sort_order'] as int?) ?? 0)));

      // 5) подтянем опции для всех групп
      final groupIds = groups
          .map((g) => (g['id'] as int?) ?? 0)
          .where((id) => id != 0)
          .toList();
      Map<int, List<Map<String, dynamic>>> optsByGroup = {};
      if (groupIds.isNotEmpty) {
        final inList = '(${groupIds.join(',')})';
        final optsRaw = await _supabase
            .from('menu_v2_modifier_option')
            .select('id, group_id, name, sort_order')
            .filter('group_id', 'in', inList);
        final arr = (optsRaw as List).cast<Map<String, dynamic>>();
        for (final o in arr) {
          final gid = (o['group_id'] as int?) ?? 0;
          optsByGroup.putIfAbsent(gid, () => []).add(o);
        }
        for (final list in optsByGroup.values) {
          list.sort((a, b) {
            final sa = (a['sort_order'] as int?) ?? 0;
            final sb = (b['sort_order'] as int?) ?? 0;
            if (sa != sb) return sa.compareTo(sb);
            return ((a['id'] as int?) ?? 0).compareTo(((b['id'] as int?) ?? 0));
          });
        }
      }

      final builtGroups = <_OptionGroup>[];
      for (final g in groups) {
        final gid = (g['id'] as int?) ?? 0;
        final optItems = (optsByGroup[gid] ?? const [])
            .map((o) => _OptionItem(
                  id: (o['id'] as int?) ?? 0,
                  groupId: gid,
                  text: (o['name'] as String?) ?? '',
                  description: null,
                  priceDelta: 0.0,
                  linkedItemId: null,
                  linkedItemName: null,
                ))
            .toList();
        // Правило схемы: max_select == 0 → без ограничений (null)
        final int? maxSelRaw = g['max_select'] as int?;
        final int? maxSel = (maxSelRaw == 0) ? null : maxSelRaw;
        // Radio только если максимум строго 1, иначе — чекбоксы (или счетчики по бизнес-логике)
        final controlType = (maxSel == 1) ? 'radio' : 'checkbox';
        builtGroups.add(_OptionGroup(
          id: gid,
          menuItemId: widget.item.id,
          name: (g['name'] as String?) ?? '',
          controlType: controlType,
          isRequired: (g['min_select'] as int? ?? 0) > 0,
          minSelect: g['min_select'] as int?,
          maxSelect: maxSel,
          items: optItems,
        ));
      }

      // Сортируем так, чтобы группа с названием, содержащим "Beilage/Beilagen" (без учёта регистра), шла первой
      builtGroups.sort((a, b) {
        final an = a.name.toLowerCase();
        final bn = b.name.toLowerCase();
        // "beilag" ловит и "beilage", и "beilagen"
        final af = an.contains('beilag');
        final bf = bn.contains('beilag');
        if (af != bf) return af ? -1 : 1;
        return 0;
      });

      setState(() {
        // Сбрасываем любые прежние выборы при новой сборке групп
        _selectedRadio.clear();
        _selectedChecks.clear();
        _selectedCounters.clear();
        _optionGroups = builtGroups;
        // Не делаем автовыбор даже для обязательных radio-групп — пользователь выбирает сам.
        _loadingOptions = false;
      });
    } catch (e) {
      setState(() {
        _loadingOptions = false;
      });
    }
  }

  Future<void> _initSizesAndExtras() async {
    setState(() {
      _loadingSizes = true;
      _loadingExtras = true;
    });
    try {
      final catId = await _ensureCategoryId();
      final promotions = await getCachedPromotions(now: DateTime.now());
      // Универсально: читаем view menu_v2_item_prices
      final priceRows = await _supabase
          .from('menu_v2_item_prices')
          .select('item_id, size_id, price, is_single_size')
          .eq('item_id', widget.item.id)
          .order('is_single_size', ascending: false)
          .order('size_id', ascending: true);
      final list = (priceRows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        // Нет цен в БД — считаем товар недоступным: не позволяем выбрать размер
        _sizeOptions = [];
        _selectedSize = null;
        _itemHasSizes = true;
      } else {
        final isSingle = list.first['is_single_size'] as bool? ?? false;
        if (isSingle) {
          // одна строка без size_id
          final row = list.first;
          final price = (row['price'] as num?)?.toDouble() ?? 0.0;
          final promo = evaluatePromotionForUnitPrice(
            promotions: promotions,
            unitPrice: price,
            itemId: widget.item.id,
            categoryId: catId,
            sizeId: null,
          );
          _sizeOptions = [
            SizeOption(id: null, name: 'Normal', price: price, promotion: promo)
          ];
          _selectedSize = _sizeOptions.first;
          _itemHasSizes = false;
        } else {
          // мультиразмерные: N строк с size_id
          final sizeIds = list
              .map((r) => (r['size_id'] as int?) ?? 0)
              .where((id) => id != 0)
              .toList();
          Map<int, String> sizeNameMap = {};
          if (sizeIds.isNotEmpty) {
            final szRows = await _supabase
                .from('menu_size')
                .select('id, name')
                .filter('id', 'in', '(${sizeIds.join(',')})');
            for (final r in (szRows as List)) {
              final id = (r['id'] as int?) ?? 0;
              final name = (r['name'] as String?) ?? '';
              if (id != 0) sizeNameMap[id] = name;
            }
          }
          _sizeOptions = list
              .map((r) {
                final sid = (r['size_id'] as int?) ?? 0;
                final price = (r['price'] as num?)?.toDouble() ?? 0.0;
                if (sid == 0) {
                  return SizeOption(
                      id: sid, name: sizeNameMap[sid] ?? '', price: price);
                }
                final promo = evaluatePromotionForUnitPrice(
                  promotions: promotions,
                  unitPrice: price,
                  itemId: widget.item.id,
                  categoryId: catId,
                  sizeId: sid,
                );
                return SizeOption(
                    id: sid,
                    name: sizeNameMap[sid] ?? '',
                    price: price,
                    promotion: promo);
              })
              .where((s) => s.id != null && s.id != 0)
              .toList();
          _sizeOptions.sort((a, b) => a.price.compareTo(b.price));
          _selectedSize = _sizeOptions.isNotEmpty ? _sizeOptions.first : null;
          _itemHasSizes = true;
        }
      }
    } catch (e) {
      // В случае ошибки не подставляем фиктивную цену — лучше заблокировать добавление
      _sizeOptions = [];
      _selectedSize = null;
      _itemHasSizes = true;
    }
    setState(() {
      _loadingSizes = false;
    });
    await _loadExtras();
  }

  Future<void> _loadExtras() async {
    setState(() {
      _loadingExtras = true;
      _extras = [];
    });

    if (_selectedSize == null) {
      setState(() => _loadingExtras = false);
      return;
    }

    // v2: разрешённые экстры -> их цена зависит только от выбранного size_id
    // 1) получим category_id
    final catId = (await _ensureCategoryId()) ?? 0;

    // 2) список разрешённых extra_id: item_override или category_default
    final itemAllowedRaw = await _supabase
        .from('menu_v2_item_allowed_extras')
        .select('extra_id')
        .eq('item_id', widget.item.id);
    final itemAllowed = (itemAllowedRaw as List)
        .map((e) => ((e['extra_id'] as int?) ?? 0))
        .where((id) => id != 0)
        .toSet()
        .toList();

    List<int> allowedIds = itemAllowed;
    if (allowedIds.isEmpty && catId != 0) {
      final catAllowedRaw = await _supabase
          .from('menu_v2_category_allowed_extras')
          .select('extra_id')
          .eq('category_id', catId);
      allowedIds = (catAllowedRaw as List)
          .map((e) => ((e['extra_id'] as int?) ?? 0))
          .where((id) => id != 0)
          .toSet()
          .toList();
    }

    if (allowedIds.isEmpty) {
      setState(() => _loadingExtras = false);
      return;
    }

    // 3) Готовим данные по ценам и названиям экстр для выбранного размера или по single_price
    final priceByExtra = <int, double>{};
    int? sizeId;
    if (_itemHasSizes) {
      // Безопасное определение size_id: если в _selectedSize нет id (fallback безразмерного товара),
      // пробуем найти его по названию размера в таблице menu_size.
      sizeId = _selectedSize?.id;
      if (sizeId == null || sizeId == 0) {
        final sname = (_selectedSize != null && _selectedSize!.name.isNotEmpty)
            ? _selectedSize!.name
            : 'Normal';
        final szRow = await _supabase
            .from('menu_size')
            .select('id')
            .eq('name', sname)
            .maybeSingle();
        sizeId = szRow != null ? (szRow['id'] as int?) ?? 0 : null;
      }

      // Заберём все цены экстр для выбранного size_id одним запросом,
      // затем оставим только разрешённые ID. Это избавит от проблем с оператором IN.
      if (sizeId != null && sizeId != 0) {
        final rows = await _supabase
            .from('menu_v2_extra_price_by_size')
            .select('extra_id, price')
            .eq('size_id', sizeId);
        for (final r in (rows as List).cast<Map<String, dynamic>>()) {
          final eid = (r['extra_id'] as int?) ?? 0;
          if (!allowedIds.contains(eid)) continue;
          final p = (r['price'] as num?)?.toDouble() ?? 0.0;
          priceByExtra[eid] = p;
        }
      }
    }

    // Подтягиваем названия и single_price для всех разрешённых ID
    final extraRows = await _supabase
        .from('menu_v2_extra')
        .select('id, name, single_price')
        .filter('id', 'in', '(${allowedIds.join(",")})');
    final nameMap = <int, String>{};
    final singlePriceMap = <int, double>{};
    for (final x in (extraRows as List).cast<Map<String, dynamic>>()) {
      final eid = (x['id'] as int?) ?? 0;
      if (eid == 0) continue;
      nameMap[eid] = (x['name'] as String?) ?? '';
      final sp = (x['single_price'] as num?)?.toDouble();
      if (sp != null) singlePriceMap[eid] = sp;
    }

    // Создаём список ExtraOption: даже если цены нет, ставим fallback single_price или 0.0
    _extras = allowedIds.map((eid) {
      double price = priceByExtra[eid] ?? 0.0;
      if (!_itemHasSizes ||
          (priceByExtra[eid] == null && singlePriceMap.containsKey(eid))) {
        price = singlePriceMap[eid] ?? price;
      }
      final opt = ExtraOption(
        id: eid,
        name: nameMap[eid] ?? 'Extra #$eid',
        price: price,
      );
      opt.key = UniqueKey();
      return opt;
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    setState(() => _loadingExtras = false);
  }

  Future<void> _loadAdditives() async {
    setState(() => _loadingAdditives = true);

    final rows = await _supabase
        .from('menu_v2_item_allergen')
        .select('allergen_id')
        .eq('item_id', widget.item.id);
    final ids = (rows as List)
        .map((r) => ((r['allergen_id'] as int?) ?? 0))
        .where((id) => id != 0)
        .toSet()
        .toList();
    if (ids.isEmpty) {
      setState(() => _loadingAdditives = false);
      return;
    }

    // Получаем только названия аллергенов (без кодов)
    final adds = await _supabase
        .from('menu_v2_allergen')
        .select('title')
        .filter('id', 'in', '(${ids.join(",")})');
    _additiveLabels = (adds as List)
        .map((a) => (a['title'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    setState(() => _loadingAdditives = false);
  }

  void _onSizeChanged(SizeOption? s) async {
    if (s == null) return;
    setState(() {
      _selectedSize = s;
      _loadingExtras = true;
      _extras = [];
    });
    await _loadExtras();
  }

  void _close() => Navigator.pop(context);

  Future<void> _addToCart() async {
    // Валидация групп опций по правилам
    for (final g in _optionGroups) {
      final type = _resolveType(g);
      int selectedCount = 0;
      if (type == _OptionType.radio) {
        selectedCount = _selectedRadio[g.id] != null ? 1 : 0;
      } else if (type == _OptionType.checkbox) {
        selectedCount = _selectedChecks[g.id]?.length ?? 0;
      } else if (type == _OptionType.counter) {
        selectedCount =
            (_selectedCounters[g.id]?.values.fold<int>(0, (a, b) => a + b)) ??
                0;
      }
      final minSel = g.minSelect ?? (g.isRequired ? 1 : 0);
      final maxSel = g.maxSelect;
      if (g.isRequired && selectedCount == 0) {
        _showWarn('Bitte wählen Sie in "${g.name}" mindestens eine Option.');
        return;
      }
      if (selectedCount < minSel) {
        _showWarn('Bitte wählen Sie in "${g.name}" mindestens $minSel.');
        return;
      }
      if (maxSel != null && selectedCount > maxSel) {
        _showWarn('Maximal $maxSel Auswahl(en) in "${g.name}".');
        return;
      }
    }

    final extrasMap = <int, int>{
      for (var e in _extras)
        if (e.quantity > 0) e.id: e.quantity
    };
    // Собираем выбранные опции: optionId -> qty
    final opts = <int, int>{};
    for (final g in _optionGroups) {
      final type = _resolveType(g);
      if (type == _OptionType.radio) {
        final sel = _selectedRadio[g.id];
        if (sel != null) opts[sel] = 1;
      } else if (type == _OptionType.checkbox) {
        for (final id in (_selectedChecks[g.id] ?? const {})) {
          opts[id] = 1;
        }
      } else {
        for (final e in (_selectedCounters[g.id] ?? const {}).entries) {
          if (e.value > 0) opts[e.key] = e.value;
        }
      }
    }
    await CartService.addItem(CartItem(
      itemId: widget.item.id,
      name: widget.item.name,
      size: _selectedSize!.name,
      basePrice: _selectedSize!.price,
      extras: extrasMap,
      options: opts,
      article: widget.item.article,
      sizeId: _selectedSize!.id, // Добавлено: передаем sizeId
    ));
    if (!mounted) return;
    final total = extrasMap.values.fold<int>(0, (a, b) => a + b);
    // Показываем кастомный SnackBar с двумя кнопками
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        backgroundColor: Colors.grey[900],
        duration: const Duration(seconds: 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              // Для товаров с единственной ценой не показываем размер в скобках
              '${widget.item.name}${widget.item.hasMultipleSizes ? ' (${_selectedSize!.name})' : ''} hinzugefügt${total > 0 ? ' mit $total Extras' : ''}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      scaffold.hideCurrentSnackBar();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      navigatorKey.currentState?.pushReplacementNamed('tab_1');
                    },
                    child: Text(
                      'Weiter bestellen',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      scaffold.hideCurrentSnackBar();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      Navigator.of(context).pushNamed('/cart');
                    },
                    child: Text(
                      'Zum Warenkorb',
                      style: GoogleFonts.poppins(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showWarn(String msg) {
    final appTheme = ThemeProvider.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: appTheme.cardColor,
        content:
            Text(msg, style: GoogleFonts.poppins(color: appTheme.textColor)),
      ),
    );
  }

  Future<void> _animateAddToCart(Rect startRect) async {
    final cartContext = _cartIconKey.currentContext;
    final overlay = Overlay.maybeOf(context);
    if (cartContext == null || overlay == null) return;
    final cartBox = cartContext.findRenderObject() as RenderBox?;
    if (cartBox == null) return;

    final cartOffset = cartBox.localToGlobal(Offset.zero);
    final cartRect = cartOffset & cartBox.size;
    final controller = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this);
    final animation =
        CurvedAnimation(parent: controller, curve: Curves.easeInOutCubic);
    final startCenter = startRect.center;
    final endCenter = cartRect.center;
    final double startSize = startRect.longestSide;
    final double endSize = cartRect.longestSide * 0.6;

    late OverlayEntry entry;
    entry = OverlayEntry(builder: (ctx) {
      final t = animation.value;
      final position = Offset.lerp(startCenter, endCenter, t) ?? endCenter;
      final size = lerpDouble(startSize, endSize, t) ?? endSize;
      final opacity = lerpDouble(1.0, 0.0, t) ?? 0.0;
      final rotation = lerpDouble(0.0, -0.4, t) ?? 0.0;
      return Positioned(
        left: position.dx - size / 2,
        top: position.dy - size / 2,
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: rotation,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(size * 0.3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2 * (1 - t)),
                    blurRadius: 12 * (1 - t),
                    offset: Offset(0, 6 * (1 - t)),
                  ),
                ],
              ),
              child: const Icon(Icons.shopping_bag, color: Colors.black),
            ),
          ),
        ),
      );
    });

    overlay.insert(entry);
    controller.addListener(() {
      if (entry.mounted) entry.markNeedsBuild();
    });
    try {
      await controller.forward();
    } finally {
      entry.remove();
      controller.dispose();
    }
  }

  _OptionType _resolveType(_OptionGroup g) {
    final t = g.controlType.toLowerCase();
    if (t.contains('radio') || (g.maxSelect == 1)) return _OptionType.radio;
    if (t.contains('count') || t.contains('qty') || t.contains('step'))
      return _OptionType.counter;
    return _OptionType.checkbox;
  }

  double _computeTotalWithBase(double basePrice) {
    double total = basePrice;
    // Extras
    for (final e in _extras) {
      if (e.quantity > 0) total += e.price * e.quantity;
    }
    // Option groups
    for (final g in _optionGroups) {
      final type = _resolveType(g);
      if (type == _OptionType.radio) {
        final sel = _selectedRadio[g.id];
        if (sel != null) {
          final opt = g.items
              .firstWhere((i) => i.id == sel, orElse: () => g.items.first);
          total += opt.priceDelta;
        }
      } else if (type == _OptionType.checkbox) {
        final setSel = _selectedChecks[g.id] ?? const {};
        for (final opt in g.items) {
          if (setSel.contains(opt.id)) total += opt.priceDelta;
        }
      } else if (type == _OptionType.counter) {
        final map = _selectedCounters[g.id] ?? const {};
        for (final opt in g.items) {
          final qty = map[opt.id] ?? 0;
          if (qty > 0) total += opt.priceDelta * qty;
        }
      }
    }
    return total;
  }

  double _computeCurrentTotal() {
    final basePrice =
        _selectedSize?.price ?? (widget.item.singleSizePrice ?? 0.0);
    return _computeTotalWithBase(basePrice);
  }

  double _computeDiscountedTotal(PromotionPrice? priceInfo) {
    final basePrice = priceInfo?.finalPrice ??
        _selectedSize?.price ??
        (widget.item.singleSizePrice ?? 0.0);
    return _computeTotalWithBase(basePrice);
  }

  // Пояснение, почему кнопка "В корзину" отключена.
  // Возвращает null, если всё ок и кнопку можно активировать.
  String? _disabledReason() {
    if (_isAnyLoading)
      return null; // пока грузится — отдельной подсказки не даём
    if (_selectedSize == null) {
      // Если цен не нашли совсем — информируем, что товар недоступен
      if (!_loadingSizes && _sizeOptions.isEmpty) {
        return 'Dieser Artikel ist derzeit nicht verfügbar (Preis fehlt).';
      }
      return 'Bitte wählen Sie eine Größe.';
    }
    // Проверим обязательные группы и недобор по min_select
    final missing = <String>[];
    for (final g in _optionGroups) {
      final type = _resolveType(g);
      int selectedCount = 0;
      if (type == _OptionType.radio) {
        selectedCount = _selectedRadio[g.id] != null ? 1 : 0;
      } else if (type == _OptionType.checkbox) {
        selectedCount = _selectedChecks[g.id]?.length ?? 0;
      } else if (type == _OptionType.counter) {
        selectedCount =
            (_selectedCounters[g.id]?.values.fold<int>(0, (a, b) => a + b)) ??
                0;
      }
      final minSel = g.minSelect ?? (g.isRequired ? 1 : 0);
      if (selectedCount < minSel) missing.add(g.name);
    }
    if (missing.isEmpty) return null;
    // Если групп много — не шумим, даём обобщённую подсказку
    if (missing.length > 2) {
      return 'Bitte wählen Sie die erforderlichen Optionen, um fortzufahren.';
    }
    // Иначе перечислим, где нужно выбрать
    final list = missing.join(', ');
    return 'Bitte wählen Sie in: $list';
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    final currentPrice =
        _selectedSize != null ? _priceFor(_selectedSize!) : null;
    final baseTotal = _computeCurrentTotal();
    final discountedTotal = _computeDiscountedTotal(currentPrice);
    if (_error != null) {
      return Scaffold(
        backgroundColor: appTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: appTheme.backgroundColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: appTheme.textColor),
            onPressed: _close,
          ),
          title: Text(widget.item.name,
              style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
          centerTitle: true,
          elevation: 0,
        ),
        body: NoInternetWidget(
          onRetry: _initAll,
          errorText: _error,
        ),
      );
    }
    final item = widget.item;
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appTheme.textColor),
          onPressed: _close,
        ),
        title: Text(item.name,
            style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
        centerTitle: true,
        elevation: 0,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: CartService.cartCountNotifier,
            builder: (context, count, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    key: _cartIconKey,
                    icon: Icon(Icons.shopping_cart_outlined,
                        color: appTheme.textColor),
                    onPressed: () {
                      Navigator.of(context).pushNamed('/cart');
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        bottom: _showMinOrderBar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  height: 24,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    border: Border(
                        top: BorderSide(
                            color: Colors.redAccent.withOpacity(0.35),
                            width: 0.8)),
                  ),
                  alignment: Alignment.center,
                  child: _computingCartTotal
                      ? Text('Prüfe Mindestbestellwert…',
                          style: GoogleFonts.poppins(
                              color: Colors.redAccent, fontSize: 11))
                      : Text(
                          'Noch €${(_minOrderAmount! - _discountedCartTotalGlobal).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                          style: GoogleFonts.poppins(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              )
            : null,
      ),
      body: Scrollbar(
        controller: _scrollController,
        // Показываем всегда, но только после полной загрузки контента,
        // чтобы исключить скачки размера/позиции из-за меняющейся высоты списка
        thumbVisibility: !_isAnyLoading,
        thickness: 6,
        radius: const Radius.circular(3),
        interactive: true,
        scrollbarOrientation: ScrollbarOrientation.right,
        notificationPredicate: (notif) => notif.depth == 0,
        child: ListView(
          controller: _scrollController,
          physics: Platform.isIOS
              ? const BouncingScrollPhysics()
              : const ClampingScrollPhysics(),
          // Добавим небольшой правый отступ, чтобы ползунок не накладывался на trailing-чипы цен
          padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
          children: [
            // Фото скрыто по просьбе: оставляем чистый текстовый блок
            Text(item.name,
                style: GoogleFonts.fredokaOne(
                    fontSize: 28, color: appTheme.textColor)),
            if (item.description != null) ...[
              const SizedBox(height: 8),
              Text(
                item.description!,
                style: GoogleFonts.poppins(
                  color: appTheme.textColorSecondary,
                  fontSize: 16,
                ),
                softWrap: true,
              ),
            ],
            // Аллергены показываем только если есть загруженные метки
            if (!_loadingAdditives && _additiveLabels.isNotEmpty) ...[
              Text('Allergene:',
                  style: GoogleFonts.poppins(
                      color: appTheme.textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _additiveLabels
                    .map((label) => Chip(
                          label: Text(
                            label,
                            style: GoogleFonts.poppins(
                                color: appTheme.textColor, fontSize: 12),
                          ),
                          backgroundColor: appTheme.cardColor,
                          shape: StadiumBorder(
                            side: BorderSide(
                                color: appTheme.primaryColor
                                    .withValues(alpha: 0.2)),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 12),
            if (_loadingSizes)
              Center(
                  child:
                      CircularProgressIndicator(color: appTheme.primaryColor))
            else if (item.hasMultipleSizes)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: appTheme.cardColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: _sizesExpanded,
                  maintainState: true,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  title: Text('Größe',
                      style: GoogleFonts.poppins(
                          color: appTheme.textColor,
                          fontWeight: FontWeight.w600)),
                  subtitle: (_selectedSize != null && currentPrice != null)
                      ? Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Aktuell: ${_selectedSize!.name}',
                                style: GoogleFonts.poppins(
                                    color: appTheme.textColorSecondary),
                              ),
                            ),
                            PriceWithPromotion(
                              basePrice: currentPrice.basePrice,
                              finalPrice: currentPrice.finalPrice,
                              finalStyle: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                              baseStyle: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary
                                    .withValues(alpha: 0.7),
                              ),
                              formatter: (value) =>
                                  '${value.toStringAsFixed(2)} €',
                              alignment: MainAxisAlignment.end,
                            ),
                          ],
                        )
                      : null,
                  onExpansionChanged: (v) => setState(() => _sizesExpanded = v),
                  children: _sizesExpanded
                      ? _sizeOptions.map((opt) {
                          final priceInfo = _priceFor(opt);
                          return RadioListTile<SizeOption>(
                            activeColor: appTheme.primaryColor,
                            value: opt,
                            groupValue: _selectedSize,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    opt.name,
                                    style: GoogleFonts.poppins(
                                        color: appTheme.textColor),
                                  ),
                                ),
                                PriceWithPromotion(
                                  basePrice: priceInfo.basePrice,
                                  finalPrice: priceInfo.finalPrice,
                                  finalStyle: GoogleFonts.poppins(
                                    color: appTheme.textColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  baseStyle: GoogleFonts.poppins(
                                    color: appTheme.textColor
                                        .withValues(alpha: 0.6),
                                  ),
                                  formatter: (value) =>
                                      '${value.toStringAsFixed(2)} €',
                                  alignment: MainAxisAlignment.end,
                                ),
                              ],
                            ),
                            onChanged: _onSizeChanged,
                          );
                        }).toList()
                      : const <Widget>[],
                ),
              )
            // Товары с одной ценой: показываем статичный блок с ценой (без выбора размера)
            else
              (_selectedSize != null)
                  ? Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: appTheme.cardColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        title: Text('Preis',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColor,
                                fontWeight: FontWeight.w600)),
                        subtitle: currentPrice != null
                            ? PriceWithPromotion(
                                basePrice: currentPrice.basePrice,
                                finalPrice: currentPrice.finalPrice,
                                finalStyle: GoogleFonts.poppins(
                                  color: appTheme.textColorSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                baseStyle: GoogleFonts.poppins(
                                  color: appTheme.textColorSecondary
                                      .withValues(alpha: 0.7),
                                  fontSize: 14,
                                ),
                                formatter: (value) =>
                                    '${value.toStringAsFixed(2)} €',
                                alignment: MainAxisAlignment.end,
                              )
                            : null,
                        trailing: const Icon(Icons.check, color: Colors.green),
                      ),
                    )
                  : const SizedBox.shrink(),
            const SizedBox(height: 24),
            // Опции — без заголовка «Опции», и не показываем ничего если групп нет
            if (_loadingOptions)
              Center(
                  child:
                      CircularProgressIndicator(color: appTheme.primaryColor))
            else if (_optionGroups.isNotEmpty) ...[
              ..._optionGroups.map((g) => _buildOptionGroupWidget(g,
                      expanded: _groupExpanded[g.id] ?? false, onExpanded: (v) {
                    setState(() => _groupExpanded[g.id] = v);
                  })),
            ],
            const SizedBox(height: 24),
            // Extras (ниже модификаторов). Цены динамически зависят от выбранного размера
            if (_loadingExtras)
              Center(
                  child:
                      CircularProgressIndicator(color: appTheme.primaryColor))
            else if (_extras.isNotEmpty) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: appTheme.cardColor.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: ExpansionTile(
                  initiallyExpanded: _extrasExpanded,
                  maintainState: true,
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  title: Text('Extras',
                      style: GoogleFonts.poppins(
                          color: appTheme.textColor,
                          fontWeight: FontWeight.w600)),
                  subtitle: (() {
                    final count = _extras.where((e) => e.quantity > 0).length;
                    return count > 0
                        ? Text('Ausgewählt: $count',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary))
                        : null;
                  })(),
                  onExpansionChanged: (v) =>
                      setState(() => _extrasExpanded = v),
                  children: _extrasExpanded
                      ? [
                          const RepaintBoundary(
                            child: SizedBox.shrink(),
                          ),
                          ..._extras.map((opt) => Padding(
                                key: opt.key,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${opt.name} (+${opt.price.toStringAsFixed(2)} €)',
                                        style: TextStyle(
                                            color: appTheme.textColor),
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.remove_circle_outline,
                                          color: appTheme.iconColor),
                                      onPressed: () => setState(() {
                                        if (opt.quantity > 0) opt.quantity--;
                                      }),
                                    ),
                                    Text('${opt.quantity}',
                                        style: TextStyle(
                                            color: appTheme.textColor)),
                                    IconButton(
                                      icon: Icon(Icons.add_circle_outline,
                                          color: appTheme.iconColor),
                                      onPressed: () =>
                                          setState(() => opt.quantity++),
                                    ),
                                  ],
                                ),
                              )),
                        ]
                      : const <Widget>[],
                ),
              ),
              const SizedBox(height: 16),
              // Upsell — перемещён в самый низ, после модификаторов и экстр
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: UpSellWidget(
                  channel: 'detail',
                  subtotal: CartService.items
                      .fold<double>(0.0, (p, e) => p + e.basePrice),
                  itemId: item.id,
                  onAnimateToCart: _animateAddToCart,
                  onItemAdded: () async {
                    setState(() {});
                  },
                  autoCloseOnAdd: false,
                ),
              ),
            ],
            if (_loadingExtras || _extras.isEmpty) ...[
              // Когда экстр нет вовсе — всё равно показываем Upsell внизу
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: UpSellWidget(
                  channel: 'detail',
                  subtotal: CartService.items
                      .fold<double>(0.0, (p, e) => p + e.basePrice),
                  itemId: item.id,
                  onAnimateToCart: _animateAddToCart,
                  onItemAdded: () async {
                    setState(() {});
                  },
                  autoCloseOnAdd: false,
                ),
              ),
            ],
            const SizedBox(height: 80),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (_) {
              final reason = _disabledReason();
              if (reason == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      color: appTheme.textColorSecondary, fontSize: 13),
                ),
              );
            }),
            SizedBox(
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: appTheme.buttonColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: (_isAnyLoading ||
                        _selectedSize == null ||
                        !_allModifierRulesSatisfied())
                    ? null
                    : _addToCart,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'In den Warenkorb – ',
                        style: GoogleFonts.poppins(
                          color: appTheme.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      PriceWithPromotion(
                        basePrice: baseTotal,
                        finalPrice: discountedTotal,
                        finalStyle: GoogleFonts.poppins(
                          color: appTheme.textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        baseStyle: GoogleFonts.poppins(
                          color: appTheme.textColor.withValues(alpha: 0.7),
                          fontSize: 18,
                        ),
                        formatter: (value) => '€${value.toStringAsFixed(2)}',
                        alignment: MainAxisAlignment.end,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _allModifierRulesSatisfied() {
    for (final g in _optionGroups) {
      final type = _resolveType(g);
      int selectedCount = 0;
      if (type == _OptionType.radio) {
        selectedCount = _selectedRadio[g.id] != null ? 1 : 0;
      } else if (type == _OptionType.checkbox) {
        selectedCount = _selectedChecks[g.id]?.length ?? 0;
      } else if (type == _OptionType.counter) {
        selectedCount =
            (_selectedCounters[g.id]?.values.fold<int>(0, (a, b) => a + b)) ??
                0;
      }
      final minSel = g.minSelect ?? (g.isRequired ? 1 : 0);
      final maxSel = g.maxSelect;
      if (selectedCount < minSel) return false;
      if (maxSel != null && selectedCount > maxSel) return false;
    }
    return true;
  }

  Widget _buildOptionGroupWidget(_OptionGroup g,
      {bool expanded = false, ValueChanged<bool>? onExpanded}) {
    final appTheme = ThemeProvider.of(context);
    final type = _resolveType(g);
    final minSel = g.minSelect ?? (g.isRequired ? 1 : 0);
    final maxSel = g.maxSelect;
    String hint = '';
    if (type == _OptionType.radio) {
      hint = g.isRequired ? 'Bitte wählen Sie 1' : 'Optional, wählen Sie 0–1';
    } else if (type == _OptionType.checkbox) {
      final current = _selectedChecks[g.id]?.length ?? 0;
      if (maxSel != null && minSel > 0) {
        hint = 'Wählen Sie $minSel–$maxSel (aktuell: $current)';
      } else if (maxSel != null) {
        hint = 'Bis zu $maxSel auswählen (aktuell: $current)';
      } else if (minSel > 0) {
        hint = 'Mindestens $minSel wählen (aktuell: $current)';
      }
    } else {
      final total =
          (_selectedCounters[g.id]?.values.fold<int>(0, (a, b) => a + b)) ?? 0;
      if (maxSel != null && minSel > 0) {
        hint = 'Anzahl $minSel–$maxSel (aktuell: $total)';
      } else if (maxSel != null) {
        hint = 'Max. Anzahl: $maxSel (aktuell: $total)';
      } else if (minSel > 0) {
        hint = 'Mind. Anzahl: $minSel (aktuell: $total)';
      }
    }

    // Содержимое (контролы) внутри раскрывающегося блока
    final List<Widget> bodyChildren = [];
    if (type == _OptionType.radio) {
      bodyChildren.addAll(g.items.map((it) => RadioListTile<int>(
            activeColor: appTheme.primaryColor,
            value: it.id,
            groupValue: _selectedRadio[g.id],
            onChanged: (v) => setState(() => _selectedRadio[g.id] = v),
            title: _optionTitleColumn(it),
            secondary: _optionPriceChip(it.priceDelta),
            controlAffinity: ListTileControlAffinity.leading,
          )));
    } else if (type == _OptionType.checkbox) {
      bodyChildren.addAll(g.items.map((it) {
        final setSel = _selectedChecks.putIfAbsent(g.id, () => <int>{});
        final checked = setSel.contains(it.id);
        final disabledForMax = (g.maxSelect != null) &&
            (setSel.length >= (g.maxSelect!)) &&
            !checked;
        return CheckboxListTile(
          activeColor: appTheme.primaryColor,
          value: checked,
          onChanged: disabledForMax
              ? null
              : (val) {
                  setState(() {
                    final max = g.maxSelect;
                    if (val == true) {
                      if (max == null || setSel.length < max) {
                        setSel.add(it.id);
                      } else {
                        _showWarn('Maximal ${g.maxSelect} in "${g.name}".');
                      }
                    } else {
                      setSel.remove(it.id);
                    }
                  });
                },
          title: _optionTitleColumn(it),
          secondary: _optionPriceChip(it.priceDelta),
          controlAffinity: ListTileControlAffinity.leading,
        );
      }));
    } else {
      bodyChildren.addAll(g.items.map((it) {
        final map = _selectedCounters.putIfAbsent(g.id, () => <int, int>{});
        final cur = map[it.id] ?? 0;
        final total = map.values.fold<int>(0, (a, b) => a + b);
        final atMax = (g.maxSelect != null) && (total >= (g.maxSelect!));
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _optionNameWithChipInline(it),
                    _optionSubtitle(it),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.remove_circle_outline,
                    color: appTheme.iconColor),
                onPressed: cur <= 0
                    ? null
                    : () {
                        setState(() {
                          if ((map[it.id] ?? 0) > 0)
                            map[it.id] = (map[it.id] ?? 0) - 1;
                        });
                      },
              ),
              Text('$cur',
                  style: GoogleFonts.poppins(color: appTheme.textColor)),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: appTheme.iconColor),
                onPressed: atMax
                    ? null
                    : () {
                        setState(() {
                          final max = g.maxSelect;
                          final totalNow =
                              map.values.fold<int>(0, (a, b) => a + b);
                          if (max == null || totalNow < max) {
                            map[it.id] = (map[it.id] ?? 0) + 1;
                          } else {
                            _showWarn('Maximal $max in "${g.name}".');
                          }
                        });
                      },
              ),
            ],
          ),
        );
      }));
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: appTheme.cardColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text(g.name,
            style: GoogleFonts.poppins(
                color: appTheme.textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        subtitle: hint.isNotEmpty
            ? Text(hint,
                style: GoogleFonts.poppins(
                    color: appTheme.textColorSecondary, fontSize: 12))
            : null,
        onExpansionChanged: onExpanded,
        childrenPadding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
        children: expanded
            ? [
                const RepaintBoundary(child: SizedBox.shrink()),
                ...bodyChildren,
              ]
            : const <Widget>[],
      ),
    );
  }

  // Заголовок с переносом текста и возможным сабтайтлом — без прайса внутри
  Widget _optionTitleColumn(_OptionItem it) {
    final appTheme = ThemeProvider.of(context);
    final name = it.text.isNotEmpty ? it.text : (it.linkedItemName ?? '');
    final desc = (it.description ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: GoogleFonts.poppins(color: appTheme.textColor),
          softWrap: true,
        ),
        if (desc.isNotEmpty) _optionSubtitle(it),
      ],
    );
  }

  Widget _optionSubtitle(_OptionItem it) {
    final appTheme = ThemeProvider.of(context);
    final desc = (it.description ?? '').trim();
    if (desc.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        desc,
        style: GoogleFonts.poppins(
            color: appTheme.textColorSecondary, fontSize: 12),
      ),
    );
  }

  // Отдельный виджет прайс-чипа для trailing/secondary
  Widget? _optionPriceChip(double delta) {
    if (delta == 0) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (delta > 0
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.green.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: (delta > 0 ? Colors.orange : Colors.green)
                .withValues(alpha: 0.5)),
      ),
      child: Text(
        '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(2)} €',
        style: GoogleFonts.poppins(
          color: delta > 0 ? Colors.orange : Colors.green,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  // Для счетчиков оставляем inline-чип справа от имени
  Widget _optionNameWithChipInline(_OptionItem it) {
    final appTheme = ThemeProvider.of(context);
    final name = it.text.isNotEmpty ? it.text : (it.linkedItemName ?? '');
    final chip = _optionPriceChip(it.priceDelta);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.poppins(color: appTheme.textColor),
            softWrap: true,
          ),
        ),
        if (chip != null) ...[
          const SizedBox(width: 8),
          chip,
        ],
      ],
    );
  }

  // Модели для опций
}

class _OptionItem {
  final int id;
  final int groupId;
  final String text;
  final String? description;
  final double priceDelta;
  final int? linkedItemId;
  final String? linkedItemName;
  _OptionItem({
    required this.id,
    required this.groupId,
    required this.text,
    this.description,
    required this.priceDelta,
    this.linkedItemId,
    this.linkedItemName,
  });
}

class _OptionGroup {
  final int id;
  final int menuItemId;
  final String name;
  final String controlType; // 'radio' | 'checkbox' | 'counter' (и т.п.)
  final bool isRequired;
  final int? minSelect;
  final int? maxSelect;
  final List<_OptionItem> items;
  _OptionGroup({
    required this.id,
    required this.menuItemId,
    required this.name,
    required this.controlType,
    required this.isRequired,
    required this.minSelect,
    required this.maxSelect,
    required this.items,
  });
}

// Типы контролов групп опций
enum _OptionType { radio, checkbox, counter }
