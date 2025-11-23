// lib/screens/home_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../services/discount_service.dart';
import '../theme/theme_provider.dart';
import '../widgets/common_app_bar.dart';
import '../widgets/creative_cta_section.dart';
import '../widgets/no_internet_widget.dart';
import 'cart_screen.dart';
import 'discount_list_widget.dart';
import 'menu_item_detail_screen.dart';
import 'bundle_detail_screen.dart';
import 'menu_screen.dart';
import '../models/menu_item.dart';
import 'profile_screen.dart';
import 'profile_screen_auth.dart';
import 'recent_orders_carousel.dart';
import 'top_items_carousel.dart';
import 'bundles_carousel.dart';
import '../widgets/search_result_tile.dart';
import '../services/app_config_service.dart' as cfg;
import 'order_status_screen.dart';
import '../services/delivery_zone_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../utils/address_localization.dart';

/// Модель MenuItem вынесена в ../models/menu_item.dart

/// Главный экран с табами: «Главная», «Меню», «Профиль»
class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({super.key, this.initialIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  List<MenuItem> _allItems = [];
  List<MenuItem> _filteredItems = [];
  // Для бейджа категории в результатах поиска
  final Map<int, int> _itemToCatId = {}; // itemId -> categoryId
  final Map<int, String> _categoryNames = {}; // categoryId -> name
  final Map<int, PromotionPrice> _itemPromoSummary = {}; // itemId -> promo-aware summary
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  // Banner: current order
  int? _bannerOrderId;
  String? _bannerStatus;
  DateTime? _bannerEta;
  bool _bannerVisible = false;
  RealtimeChannel? _ordersChannel;

  // Минимальный заказ для текущего почтового индекса (если доставка)
  double? _minOrderAmountHome;
  // Текущая сумма корзины после скидок (для полоски напоминания)
  double _discountedCartTotal = 0.0;
  bool _computingCartTotal = false;

  // Флаг отображения полоски (пересчитывается)
  bool get _showMinOrderBar {
    if (_minOrderAmountHome == null) return false;
    if (_discountedCartTotal + 0.0001 >= _minOrderAmountHome!) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialIndex;
    _loadMenu(); // Загружаем меню при инициализации (с учётом кэша)
    _searchController.addListener(_onSearchChanged);
    _loadCurrentOrderBanner();
    _promptDeliveryModeIfFirstLaunch();
    _initMinOrderContext();
    // Слушаем изменения корзины (количество позиций). Для более точного
    // обновления (экстра и опции) можно расширить CartService, но пока достаточно.
    CartService.cartCountNotifier.addListener(_recomputeCartAndBar);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _ordersChannel?.unsubscribe();
    CartService.cartCountNotifier.removeListener(_recomputeCartAndBar);
    super.dispose();
  }

  Future<void> _initMinOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('delivery_mode');
    if (mode != 'delivery') {
      setState(() {
        _minOrderAmountHome = null;
        _discountedCartTotal = 0.0;
      });
      return;
    }
    final postal = prefs.getString('user_postal_code');
    if (postal == null || postal.isEmpty) return; // дождёмся ввода
    final minOrder = await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    setState(() => _minOrderAmountHome = minOrder);
    await _computeDiscountedCartTotal();
  }

  void _recomputeCartAndBar() {
    _computeDiscountedCartTotal();
  }

  Future<void> _computeDiscountedCartTotal() async {
    if (!mounted) return;
    final items = CartService.items;
    if (items.isEmpty) {
      setState(() => _discountedCartTotal = 0.0);
      return;
    }
    setState(() => _computingCartTotal = true);
    try {
      final itemIds = items.map((e) => e.itemId).toSet().toList();
      final sizeIds = items.map((e) => e.sizeId).where((e) => e != null).cast<int>().toSet().toList();
      final extraIds = <int>{};
      for (final it in items) {
        extraIds.addAll(it.extras.keys);
      }

      // Карта цен для допов по size
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

      // Получим категории
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

      // Группировка для скидок
      final grouped = <String, List<CartItem>>{};
      for (final it in items) {
        final sigExtras = it.extras.entries.map((e) => '${e.key}:${e.value}').join(',');
        final sigOpts = it.options.entries.map((e) => '${e.key}:${e.value}').join(',');
        final key = '${it.itemId}|${it.size}|$sigExtras|$sigOpts';
        grouped.putIfAbsent(key, () => []).add(it);
      }

      double rawSum = 0.0;
      final cartList = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final first = entry.value.first;
        double unit = first.basePrice;
        if (first.extras.isNotEmpty) {
          for (final e in first.extras.entries) {
            final key = '${first.sizeId}|${e.key}';
            unit += (extraPriceMap[key] ?? 0.0) * e.value;
          }
        }
        // Опции без наценок — пропускаем
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
        dres = await calculateDiscountedTotal(cartItems: cartList, subtotal: rawSum);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _discountedCartTotal = dres?.total ?? rawSum;
        _computingCartTotal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _computingCartTotal = false);
    }
  }

  PreferredSizeWidget? _buildMinOrderBar() {
    if (!_showMinOrderBar) return null;
    final remaining = (_minOrderAmountHome! - _discountedCartTotal).clamp(0, _minOrderAmountHome!);
    return PreferredSize(
      preferredSize: const Size.fromHeight(24),
      child: Container(
        height: 24,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.12),
          border: Border(top: BorderSide(color: Colors.redAccent.withOpacity(0.35), width: 0.8)),
        ),
        alignment: Alignment.center,
        child: _computingCartTotal
            ? Text('Prüfe Mindestbestellwert…', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11))
            : Text(
                'Noch €${remaining.toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmountHome!.toStringAsFixed(2)})',
                style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _promptDeliveryModeIfFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final existingMode = prefs.getString('delivery_mode');
    if (existingMode == 'pickup') return; // самовывоз — адрес не нужен
    if (existingMode == 'delivery') {
      final postal = prefs.getString('user_postal_code');
      final city = prefs.getString('user_city');
      final street = prefs.getString('user_street');
      final complete = [postal, city, street].every((e) => e != null && e.isNotEmpty);
      if (complete) return; // адрес уже заполнен
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final postalCtrl = TextEditingController();
        double? minOrder;
        bool loading = false;
        String? tempMode = existingMode; // локальное состояние выбора
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> fetchMin(String code) async {
              final trimmed = code.trim();
              if (trimmed.length < 3) {
                setStateDialog(() => minOrder = null);
                return;
              }
              setStateDialog(() => loading = true);
              final mo = await DeliveryZoneService.getMinOrderForPostal(postalCode: trimmed);
              setStateDialog(() {
                minOrder = mo;
                loading = false;
              });
            }
            return AlertDialog(
              backgroundColor: Colors.black.withOpacity(0.92),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
              title: Text(
                'Bestellmodus wählen',
                style: GoogleFonts.poppins(
                  color: Colors.orangeAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Damit wir Ihnen den richtigen Mindestbestellwert und die Verfügbarkeit anzeigen können, wählen Sie bitte, ob Sie liefern lassen oder selbst abholen. Bei Lieferung benötigen wir Ihre Postleitzahl, um den Mindestbestellwert für Ihr Gebiet zu bestimmen.\n\nDie Auswahl können Sie später jederzeit ändern.',
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (tempMode == 'pickup') ? Colors.orangeAccent : Colors.orangeAccent.withOpacity(0.7),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              tempMode = 'pickup';
                              await prefs.setString('delivery_mode', 'pickup');
                              if (mounted) Navigator.pop(context);
                            },
                            child: const Text('Abholung', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (tempMode == 'delivery') ? Colors.deepOrange : Colors.deepOrange.withOpacity(0.7),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () async {
                              tempMode = 'delivery';
                              // автоопределение
                              try {
                                final enabled = await Geolocator.isLocationServiceEnabled();
                                if (enabled) {
                                  var perm = await Geolocator.checkPermission();
                                  if (perm == LocationPermission.denied) {
                                    perm = await Geolocator.requestPermission();
                                  }
                                  if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
                                    final pos = await Geolocator.getCurrentPosition();
                                    final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude, localeIdentifier: 'de_DE');
                                    final pl = placemarks.first;
                                    final postal = pl.postalCode ?? '';
                                    final city = normalizeAddressComponent(pl.locality ?? '');
                                    final street = normalizeAddressComponent(pl.thoroughfare ?? '');
                                    final house = normalizeAddressComponent(pl.subThoroughfare ?? '');
                                    if (postal.isNotEmpty) {
                                      postalCtrl.text = postal;
                                      await fetchMin(postal);
                                      await prefs.setString('user_postal_code', postal);
                                    }
                                    if (city.isNotEmpty) await prefs.setString('user_city', city);
                                    if (street.isNotEmpty) await prefs.setString('user_street', street);
                                    if (house.isNotEmpty) await prefs.setString('user_house_number', house);
                                  }
                                }
                              } catch (_) {}
                              setStateDialog(() {});
                            },
                            child: const Text('Lieferung', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    if (tempMode == 'delivery') ...[
                      const SizedBox(height: 22),
                      Text('Postleitzahl', style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: postalCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'z.B. 60311',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: Colors.white12,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: fetchMin,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: loading
                                ? const Text('Laden…', style: TextStyle(color: Colors.white54))
                                : Text(
                                    minOrder != null
                                        ? 'Mindestbestellwert: €${minOrder!.toStringAsFixed(2)}'
                                        : 'Kein Mindestbestellwert gefunden',
                                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.my_location, color: Colors.orangeAccent),
                            tooltip: 'Standort nutzen',
                            onPressed: () async {
                              try {
                                final enabled = await Geolocator.isLocationServiceEnabled();
                                if (!enabled) return;
                                var perm = await Geolocator.checkPermission();
                                if (perm == LocationPermission.denied) {
                                  perm = await Geolocator.requestPermission();
                                }
                                if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
                                  return;
                                }
                                final pos = await Geolocator.getCurrentPosition();
                                final placemarks = await placemarkFromCoordinates(pos.latitude, pos.longitude, localeIdentifier: 'de_DE');
                                final pl = placemarks.first;
                                final pc = pl.postalCode ?? '';
                                final city = normalizeAddressComponent(pl.locality ?? '');
                                final street = normalizeAddressComponent(pl.thoroughfare ?? '');
                                final house = normalizeAddressComponent(pl.subThoroughfare ?? '');
                                if (pc.isNotEmpty) {
                                  postalCtrl.text = pc;
                                  await fetchMin(pc);
                                  await prefs.setString('user_postal_code', pc);
                                }
                                if (city.isNotEmpty) await prefs.setString('user_city', city);
                                if (street.isNotEmpty) await prefs.setString('user_street', street);
                                if (house.isNotEmpty) await prefs.setString('user_house_number', house);
                              } catch (_) {}
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final pc = postalCtrl.text.trim();
                          if (pc.isNotEmpty) {
                            await prefs.setString('user_postal_code', pc);
                          }
                          await prefs.setString('delivery_mode', 'delivery');
                          if (mounted) Navigator.pop(context);
                        },
                        child: const Text('Speichern', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: const [],
            );
          },
        );
      },
    );
  }

  /// Фильтрация списка при вводе в строке поиска
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    final base = query.isEmpty
        ? List<MenuItem>.from(_allItems)
        : _allItems.where((item) {
            final n = item.name.toLowerCase();
            final d = (item.description ?? '').toLowerCase();
            return n.contains(query) || d.contains(query);
          }).toList();
    base.sort((a, b) => _relevanceScore(b, query).compareTo(_relevanceScore(a, query)));
    setState(() => _filteredItems = base);
  }

  /// Загрузка меню из Supabase с кэшированием в SharedPreferences и обработкой ошибок сети.
  Future<void> _loadMenu({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();

    // ШАГ 1: Если не refresh и в кэше есть данные — показываем их сразу
    if (!refresh && prefs.containsKey('cached_menu')) {
      try {
        final cachedString = prefs.getString('cached_menu')!;
        final List decoded = json.decode(cachedString) as List;
        final cachedItems = decoded
            .map((e) => MenuItem.fromMap(e as Map<String, dynamic>))
            .toList();
        _itemToCatId
          ..clear()
          ..addEntries(decoded.map((raw) {
            final map = raw as Map<String, dynamic>;
            final id = (map['id'] as int?) ?? 0;
            final catId = (map['category_id'] as int?) ?? 0;
            return MapEntry(id, catId);
          }).where((entry) => entry.key > 0 && entry.value > 0));
        _allItems = cachedItems;
        _filteredItems = _showSearch && _searchController.text.trim().isNotEmpty
            ? _allItems
                .where((item) => item.name
                    .toLowerCase()
                    .contains(_searchController.text.toLowerCase()))
                .toList()
            : List.from(_allItems);
        setState(() => _loading = false);
        unawaited(_populatePromoSummary(items: _allItems));

        // Быстрое обогащение кэша: если в кэше нет minPrice для многоразмерных
        // (или он равен 0), пытаемся подтянуть минимальные цены одним батчем
        final needIds = cachedItems
            .where((it) => it.hasMultipleSizes && (it.minPrice <= 0))
            .map((it) => it.id)
            .toList();
        if (needIds.isNotEmpty) {
          try {
            final inList = '(${needIds.join(',')})';
            final priceRows = await supabase
                .from('menu_v2_item_prices')
                .select('item_id, price')
                .filter('item_id', 'in', inList);
            final minMap = <int, double>{};
            for (final r in (priceRows as List)) {
              final mid = (r['item_id'] as int?) ?? 0;
              final p = (r['price'] as num?)?.toDouble() ?? 0.0;
              final cur = minMap[mid];
              if (cur == null || p < cur) minMap[mid] = p;
            }

            if (minMap.isNotEmpty) {
              // Обновляем объекты в памяти
              _allItems = _allItems.map((it) {
                if (minMap.containsKey(it.id)) {
                  return MenuItem(
                    id: it.id,
                    name: it.name,
                    description: it.description,
                    imageUrl: it.imageUrl,
                    article: it.article,
                    klein: it.klein,
                    normal: it.normal,
                    gross: it.gross,
                    familie: it.familie,
                    party: it.party,
                    minPrice: minMap[it.id] ?? it.minPrice,
                    hasMultipleSizes: it.hasMultipleSizes,
                    singleSizePrice: it.singleSizePrice,
                  );
                }
                // Для одноразмерных с нулём тоже проставим singleSizePrice
                if (!it.hasMultipleSizes && (it.minPrice <= 0) && it.singleSizePrice != null) {
                  return MenuItem(
                    id: it.id,
                    name: it.name,
                    description: it.description,
                    imageUrl: it.imageUrl,
                    article: it.article,
                    klein: it.klein,
                    normal: it.normal,
                    gross: it.gross,
                    familie: it.familie,
                    party: it.party,
                    minPrice: it.singleSizePrice!,
                    hasMultipleSizes: it.hasMultipleSizes,
                    singleSizePrice: it.singleSizePrice,
                  );
                }
                return it;
              }).toList();

              // Переcобираем filtered под текущий режим
              _filteredItems = _showSearch && _searchController.text.trim().isNotEmpty
                  ? _allItems
                      .where((item) => item.name
                          .toLowerCase()
                          .contains(_searchController.text.toLowerCase()))
                      .toList()
                  : List.from(_allItems);

              if (mounted) setState(() {});

              // Обновим кэш: добавим/обновим minPrice в json
              final updatedJson = decoded.map((e) {
                final m = e as Map<String, dynamic>;
                final id = (m['id'] as int?) ?? 0;
                final newMin = minMap[id];
                if (newMin != null) {
                  return {...m, 'minPrice': newMin};
                }
                if ((m['has_multiple_sizes'] as bool? ?? true) == false &&
                    (m['single_size_price'] != null) &&
                    ((m['minPrice'] as num?)?.toDouble() ?? 0.0) <= 0) {
                  return {
                    ...m,
                    'minPrice': (m['single_size_price'] as num).toDouble(),
                  };
                }
                return m;
              }).toList();
              await prefs.setString('cached_menu', json.encode(updatedJson));
            }
          } catch (_) {
            // Тихо игнорируем: покажем как есть, сеть ещё обновит на шаге 2
          }
        }
      } catch (_) {
        // Если не удалось распарсить кэш — просто игнорируем
      }
    }

    // ШАГ 2: Пробуем получить актуальные данные с Supabase
    try {
    final data = await supabase
      .from('menu_v2_item')
      .select('id,category_id,name,description,image_url,sku,has_sizes,is_active,is_available')
          .order('id', ascending: true);

      // Преобразуем список в удобный вид и вычислим minPrice как в MenuScreen
      final rawItems = (data as List).cast<Map<String, dynamic>>();

      // Соберём id позиций и карту категорий
      _itemToCatId.clear();
      final itemIds = <int>[];
      final hasMulti = <int, bool>{};
      final Map<int, int> itemToCategory = {};
      for (final m in rawItems) {
        final id = (m['id'] as int?) ?? 0;
        if (id == 0) continue;
        itemIds.add(id);
        final catId = (m['category_id'] as int?) ?? 0;
        if (catId > 0) {
          _itemToCatId[id] = catId;
          itemToCategory[id] = catId;
        }
        final hm = m['has_sizes'] as bool? ?? true;
        hasMulti[id] = hm;
      }

      // подтянем имена категорий для бейджа (v2), только активные
      try {
        final cats = await supabase
            .from('menu_v2_category')
            .select('id,name')
            .eq('is_active', true)
            .order('sort_order', ascending: true)
            .order('id', ascending: true);
        for (final c in (cats as List)) {
          final cid = (c['id'] as int?) ?? 0;
          final name = (c['name'] as String?) ?? '';
          if (cid > 0) _categoryNames[cid] = name;
        }
      } catch (_) {}

      // Получим цены для всех multiIds из единого view и вычислим минимальную
      final minPriceMap = <int, double>{};
      final Map<int, List<Map<String, dynamic>>> priceRowsByItem = {};
      if (itemIds.isNotEmpty) {
        final inList = '(${itemIds.join(',')})';
        final prices = await supabase
            .from('menu_v2_item_prices')
            .select('item_id, size_id, price')
            .filter('item_id', 'in', inList);
        for (final row in (prices as List)) {
          final mid = (row['item_id'] as int?) ?? 0;
          if (mid == 0) continue;
          final p = (row['price'] as num?)?.toDouble() ?? 0.0;
          priceRowsByItem.putIfAbsent(mid, () => []).add(row);
          final cur = minPriceMap[mid];
          if (cur == null || p < cur) minPriceMap[mid] = p;
        }
      }

      // Обогатим исходные записи полем minPrice, чтобы кэш содержал готовые данные
      final enriched = rawItems.map((m) {
        final id = (m['id'] as int?) ?? 0;
        final hm = hasMulti[id] ?? true;
        final minP = minPriceMap[id] ?? 0.0;
        return {
          ...m,
          'minPrice': minP,
          // адаптация полей к старой модели
          'has_multiple_sizes': hm,
          'single_size_price': hm ? null : (minP > 0 ? minP : null),
          'article': m['sku'],
        };
      }).toList();

      // Преобразуем в объекты MenuItem уже с minPrice
      final itemsFromServer = enriched
          .map((e) => MenuItem.fromMap(e))
          .toList();

      _allItems = itemsFromServer;
      _filteredItems = List.from(_allItems);
      // если открыт поиск — сразу применим сортировку релевантности
      if (_showSearch && _searchController.text.trim().isNotEmpty) {
        _onSearchChanged();
      }

      await _populatePromoSummary(
        items: _allItems,
        priceRowsByItem: priceRowsByItem,
        itemToCategory: itemToCategory,
      );

      // ШАГ 3: Обновляем кэш в SharedPreferences готовыми enriched-данными (с minPrice)
      await prefs.setString('cached_menu', json.encode(enriched));
    } on SocketException {
      // Если нет интернета
      _error = 'Нет подключения к интернету';
    } catch (e) {
      // Любая другая ошибка
      _error = e.toString();
    } finally {
      // Проверяем mounted, чтобы не вызывать setState после dispose
      if (mounted) {
        setState(() {
          _loading = false;
        });
        // Обновим баннер актуального заказа после загрузки
        _loadCurrentOrderBanner();
      }
    }
  }

  Future<void> _populatePromoSummary({
    required List<MenuItem> items,
    Map<int, List<Map<String, dynamic>>>? priceRowsByItem,
    Map<int, int>? itemToCategory,
  }) async {
    if (items.isEmpty) {
      if (mounted) {
        setState(() => _itemPromoSummary.clear());
      } else {
        _itemPromoSummary.clear();
      }
      return;
    }

    final ids = items.map((e) => e.id).where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) {
      if (mounted) {
        setState(() => _itemPromoSummary.clear());
      } else {
        _itemPromoSummary.clear();
      }
      return;
    }

    final itemMap = {for (final item in items) item.id: item};
    Map<int, int> categoryMap;
    if (itemToCategory != null && itemToCategory.isNotEmpty) {
      categoryMap = Map<int, int>.from(itemToCategory);
    } else {
      categoryMap = {
        for (final entry in _itemToCatId.entries)
          if (entry.key > 0 && entry.value > 0) entry.key: entry.value,
      };
    }

    Map<int, List<Map<String, dynamic>>> rows;
    if (priceRowsByItem != null && priceRowsByItem.isNotEmpty) {
      rows = {
        for (final entry in priceRowsByItem.entries)
          entry.key: List<Map<String, dynamic>>.from(entry.value),
      };
    } else {
      rows = {};
      try {
        final inList = '(${ids.join(',')})';
        final fetched = await supabase
            .from('menu_v2_item_prices')
            .select('item_id, size_id, price')
            .filter('item_id', 'in', inList);
        for (final raw in (fetched as List)) {
          final row = raw as Map<String, dynamic>;
          final mid = (row['item_id'] as int?) ?? 0;
          if (mid == 0) continue;
          rows.putIfAbsent(mid, () => []).add(row);
        }
      } catch (_) {
        // silently ignore fetch issues; we'll fallback to base prices
      }
    }

    final promotions = await getCachedPromotions(now: DateTime.now());
    final summary = <int, PromotionPrice>{};

    for (final itemId in ids) {
      final menuItem = itemMap[itemId];
      if (menuItem == null) continue;
      final catId = categoryMap[itemId];
      PromotionPrice? best;
      final rowList = rows[itemId];
      if (rowList != null && rowList.isNotEmpty) {
        for (final row in rowList) {
          final price = (row['price'] as num?)?.toDouble();
          if (price == null || price <= 0) continue;
          final rawSize = row['size_id'];
          int? sizeId;
          if (rawSize is int && rawSize != 0) {
            sizeId = rawSize;
          }
          final info = evaluatePromotionForUnitPrice(
            promotions: promotions,
            unitPrice: price,
            itemId: itemId,
            categoryId: catId,
            sizeId: sizeId,
          );
          if (best == null ||
              info.finalPrice < best.finalPrice - 0.0005 ||
              ((info.finalPrice - best.finalPrice).abs() <= 0.0005 &&
                  info.discountAmount > best.discountAmount)) {
            best = info;
          }
        }
      }

      if (best == null) {
        final fallback = menuItem.minPrice > 0
            ? menuItem.minPrice
            : (menuItem.singleSizePrice ?? menuItem.minPrice);
        best = evaluatePromotionForUnitPrice(
          promotions: promotions,
          unitPrice: fallback,
          itemId: itemId,
          categoryId: catId,
        );
      }

      summary[itemId] = best;
    }

    if (mounted) {
      setState(() {
        _itemPromoSummary
          ..clear()
          ..addAll(summary);
      });
    } else {
      _itemPromoSummary
        ..clear()
        ..addAll(summary);
    }
  }

  Future<void> _loadCurrentOrderBanner() async {
    try {
  final visibleMin = await cfg.AppConfigService.get<int>('current_order_widget_minutes', defaultValue: 60);
  final etaMin = await cfg.AppConfigService.get<int>('default_eta_minutes', defaultValue: 45);
      Map<String, dynamic>? row;
      final user = supabase.auth.currentUser;
      if (user != null) {
        final rows = await supabase
            .from('orders')
            .select('id, created_at, status, is_delivery, scheduled_time')
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(1);
        if ((rows as List).isNotEmpty) {
          row = (rows as List).first as Map<String, dynamic>;
        }
      }
      // Fallback для гостя: читаем последний orderId из SharedPreferences
      if (row == null) {
        final prefs = await SharedPreferences.getInstance();
        final lastId = prefs.getInt('last_order_id');
        if (lastId != null) {
          final ord = await supabase
              .from('orders')
              .select('id, created_at, status, is_delivery, scheduled_time')
              .eq('id', lastId)
              .maybeSingle();
          if (ord != null) {
            row = ord;
          }
        }
      }
      if (row == null) {
        // Пробуем локальный снапшот для гостя
        try {
          final prefs = await SharedPreferences.getInstance();
          if (prefs.containsKey('last_order_snapshot')) {
            final snapStr = prefs.getString('last_order_snapshot');
            if (snapStr != null) {
              final snap = json.decode(snapStr) as Map<String, dynamic>;
              final id = (snap['id'] as int?) ?? prefs.getInt('last_order_id');
              final createdStr = (snap['created_at_local'] as String?);
              DateTime? createdAt;
              if (createdStr != null) { try { createdAt = DateTime.parse(createdStr); } catch (_) {} }
              bool within = true;
              if (createdAt != null) {
                final expiry = createdAt.add(Duration(minutes: visibleMin));
                within = DateTime.now().toUtc().isBefore(expiry.toUtc());
              }
              if (id != null && within) {
                // Проверяем, существует ли заказ в БД; если удалён — очищаем локальные данные и скрываем баннер.
                final exists = await supabase
                    .from('orders')
                    .select('id')
                    .eq('id', id)
                    .maybeSingle();
                if (exists == null) {
                  await prefs.remove('last_order_snapshot');
                  await prefs.remove('last_order_id');
                  if (mounted) setState(() { _bannerVisible = false; });
                  return;
                }
                DateTime? eta;
                final schedStr = (snap['scheduled_time'] as String?);
                if (schedStr != null) { try { eta = DateTime.parse(schedStr); } catch (_) {} }
                eta ??= (createdAt ?? DateTime.now()).add(Duration(minutes: etaMin));
                if (mounted) {
                  setState(() {
                    _bannerOrderId = id;
                    _bannerStatus = 'eingegangen';
                    _bannerEta = eta;
                    _bannerVisible = _bannerOrderId != null;
                  });
                  if (_bannerOrderId != null) _bindRealtimeForOrder(_bannerOrderId!);
                }
                return;
              }
            }
          }
        } catch (_) {}
        if (mounted) setState(() { _bannerVisible = false; });
        return;
      }
      
      final id = (row['id'] as int?) ?? 0;
      final createdStr = row['created_at']?.toString();
      DateTime? createdAt; if (createdStr != null) { try { createdAt = DateTime.parse(createdStr); } catch (_) {} }
      bool within = true;
      if (createdAt != null) {
        final expiry = createdAt.add(Duration(minutes: visibleMin));
        within = DateTime.now().toUtc().isBefore(expiry.toUtc());
      }
      if (!within) {
        if (mounted) setState(() { _bannerVisible = false; });
        return;
      }
      // ETA
  DateTime? eta;
      final schedStr = row['scheduled_time']?.toString();
      if (schedStr != null) { try { eta = DateTime.parse(schedStr); } catch (_) {} }
  eta ??= (createdAt ?? DateTime.now()).add(Duration(minutes: etaMin));
      final status = (row['status'] as String?) ?? 'eingegangen';

      if (mounted) {
        setState(() {
          _bannerOrderId = id;
          _bannerStatus = status;
          _bannerEta = eta;
          _bannerVisible = true;
        });
        _bindRealtimeForOrder(id);
      }
    } catch (_) {
      if (mounted) setState(() { _bannerVisible = false; });
    }
  }

  void _bindRealtimeForOrder(int id) {
    final client = supabase;
    // Перепривяжем канал, если id сменился
    _ordersChannel?.unsubscribe();
    _ordersChannel = client
        .channel('orders-status-$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id.toString()),
          callback: (payload) async {
            // Обновим баннер по актуальным данным
            await _loadCurrentOrderBanner();
          },
        )
        // Добавляем обработку удаления: если заказ удалён в админке, скрываем баннер и очищаем локальные ключи
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id.toString()),
          callback: (payload) async {
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('last_order_id');
              await prefs.remove('last_order_snapshot');
            } catch (_) {}
            if (mounted) {
              setState(() {
                _bannerVisible = false;
                _bannerOrderId = null;
                _bannerStatus = null;
                _bannerEta = null;
              });
            }
          },
        )
        .subscribe();
  }

  // Имя категории по itemId (для бейджа в выдаче)
  String? _categoryNameFor(int itemId) {
    final cid = _itemToCatId[itemId];
    if (cid == null) return null;
    return _categoryNames[cid];
  }

  // Базовая эвристика релевантности: начало строки > граница слова > подстрока
  int _relevanceScore(MenuItem item, String q) {
    if (q.isEmpty) return 0;
    final name = item.name.toLowerCase();
    final desc = (item.description ?? '').toLowerCase();
    final query = q.toLowerCase();

    int score = 0;
    if (name.startsWith(query)) score += 1000;
    // граница слова: символ до совпадения не буква/цифра
    final idx = name.indexOf(query);
    if (idx > 0) {
      final prev = name[idx - 1];
      final isBoundary = !RegExp(r'[a-z0-9]').hasMatch(prev);
      if (isBoundary) score += 500;
    }
    if (idx >= 0) score += 300;
    if (desc.contains(query)) score += 50;
    // более короткие названия немного выше при равном счёте
    score += (200 - name.length.clamp(0, 200));
    return score;
  }

  /// При выходе из профиля: переключаемся на вкладку «Профиль»
  void _handleLogout() {
    setState(() => _tabIndex = 2);
  }

  /// Переход в экран корзины. После возврата обновляем состояние, чтобы бейджик пересчитал товары.
  void _goToCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartScreen()),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        // Обновляем, чтобы значок корзины отобразил актуальное количество
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);

    // Название AppBar по текущему табу
    final title = _tabIndex == 0
        ? 'City Pizza Service'
        : _tabIndex == 1
            ? 'Menü'
            : 'Profil';

    // Определяем, какой контент показывать внутри body
    Widget bodyContent;
    if (_loading) {
      bodyContent = const Center(child: CircularProgressIndicator(color: Colors.orange));
    } else if (_error != null) {
      bodyContent = NoInternetWidget(
        onRetry: () => _loadMenu(refresh: true),
        errorText: _error == 'Нет подключения к интернету' ? 'Keine Internetverbindung' : _error,
      );
    } else {
      if (_tabIndex == 0) {
        bodyContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showSearch) ...[
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Suche Pizza…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: RefreshIndicator(
                color: Colors.orange,
                onRefresh: () => _loadMenu(refresh: true),
                child: _showSearch && _searchController.text.trim().isNotEmpty
                    ? ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
                        itemCount: _filteredItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) {
                          final item = _filteredItems[i];
                          final categoryName = _categoryNameFor(item.id);
                          return SearchResultTile(
                            item: item,
                            query: _searchController.text.trim(),
                            categoryName: categoryName,
                            priceInfo: _itemPromoSummary[item.id],
                            onTap: () {
                              final lowerName = item.name.toLowerCase();
                              final isBundle = lowerName.contains('bundle') || lowerName.contains('menü');
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => isBundle ? BundleDetailScreen(bundleId: item.id) : MenuItemDetailScreen(item: item),
                                ),
                              ).then((_) {
                                if (!mounted) return;
                                setState(() {});
                              });
                            },
                          );
                        },
                      )
                    : _buildHomeTab(),
              ),
            ),
          ],
        );
      } else if (_tabIndex == 1) {
        bodyContent = const MenuScreen();
      } else {
        final user = supabase.auth.currentUser;
        bodyContent = user != null
            ? ProfileScreenAuth(onLogout: _handleLogout)
            : const ProfileScreen();
      }
    }

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: _tabIndex == 0
          // Если мы на главной вкладке — рисуем кастомный AppBar с возможностью поиска и корзиной
            ? AppBar(
              backgroundColor: appTheme.backgroundColor,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(
                  _showSearch ? Icons.close : Icons.search,
                  color: appTheme.iconColor,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                    }
                  });
                },
              ),
              title: Text(title),
              titleTextStyle: GoogleFonts.fredokaOne(
                color: appTheme.primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              actions: [
                // Заменено: теперь используем ValueListenableBuilder для обновления бейджика корзины
                ValueListenableBuilder<int>(
                  valueListenable: CartService.cartCountNotifier,
                  builder: (context, cartCount, child) {
                    return Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.shopping_cart, color: appTheme.iconColor),
                          onPressed: _goToCart,
                        ),
                        if (cartCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                '$cartCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
              bottom: _buildMinOrderBar(),
            )
          // В остальных случаях (Меню/Профиль) используем общий AppBar
          : buildCommonAppBar(title: title, context: context),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: bodyContent,
      ),
      // Убрали дублирующее нижнее меню: глобальный BottomNav уже отрисовывается в MainScaffold
    );
  }

  /// Вспомогательный метод: строит содержимое вкладки «Главная» 
  /// с основными секциями: CTA, недавние заказы, скидки, топ-позиции
  Widget _buildHomeTab() {
    return ListView(
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      children: [
        if (_bannerVisible && _bannerOrderId != null)
          _buildCurrentOrderBanner(),
        CreativeCtaSection(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MenuScreen()),
            ).then((_) {
              if (!mounted) return;
              setState(() {});
            });
          },
        ),
        const SizedBox(height: 24),
        const RecentOrdersSection(),
        const SizedBox(height: 12),
        const DiscountListWidget(),
        const SizedBox(height: 12),
        TopItemsSection(
          onTap: (item) {
            final lowerName = item.name.toLowerCase();
            final isBundle = lowerName.contains('bundle') || lowerName.contains('menü');
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => isBundle ? BundleDetailScreen(bundleId: item.id) : MenuItemDetailScreen(item: item),
              ),
            ).then((_) {
              if (!mounted) return;
              setState(() {});
            });
          },
        ),
        const SizedBox(height: 12),
        const BundlesSection(),
      ],
    );
  }

  Widget _buildCurrentOrderBanner() {
    final appTheme = ThemeProvider.of(context);
    String statusLabel;
    switch ((_bannerStatus ?? '').toLowerCase()) {
      case 'preparing': statusLabel = 'In Vorbereitung'; break;
      case 'on_the_way': statusLabel = 'Unterwegs'; break;
      case 'delivered': statusLabel = 'Zugestellt'; break;
      default: statusLabel = 'Eingegangen';
    }
    String etaText = '';
    if (_bannerEta != null) {
      final h = _bannerEta!.hour.toString().padLeft(2, '0');
      final m = _bannerEta!.minute.toString().padLeft(2, '0');
      etaText = 'Bis ca. $h:$m';
    }
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (_bannerOrderId != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => OrderStatusScreen(orderId: _bannerOrderId!)),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.timelapse, color: appTheme.primaryColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Aktuelle Bestellung', style: GoogleFonts.poppins(color: appTheme.textColor, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('#$_bannerOrderId • $statusLabel${etaText.isNotEmpty ? ' • $etaText' : ''}',
                        style: GoogleFonts.poppins(color: appTheme.textColorSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: appTheme.iconColor),
            ],
          ),
        ),
      ),
    );
  }

}

/// Плитка результата поиска: без изображения, компактная, как на экране Меню
// локальный виджет заменён на общий SearchResultTile

// Removed unused helper widgets: _buildRecentOrders, _buildPopularDishes
