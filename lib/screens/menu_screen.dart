// lib/screens/menu_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import '../theme/theme_provider.dart';
import '../widgets/no_internet_widget.dart'; // добавлено
import '../services/discount_service.dart';
import '../models/menu_item.dart'; // модель MenuItem
import '../widgets/search_result_tile.dart';
import '../widgets/price_with_promotion.dart';
import 'menu_item_detail_screen.dart';
import 'bundle_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/delivery_zone_service.dart';
import '../services/cart_service.dart';

class Category {
  final int id;
  final String name;
  final String? description;
  Category({required this.id, required this.name, this.description});
}

// Узлы списка для рендера: заголовок категории или элемент меню
enum _NodeType { header, item }
class _VisibleNode {
  final _NodeType type;
  final int categoryId;
  final MenuItem? item;
  _VisibleNode.header(this.categoryId)
      : type = _NodeType.header,
        item = null;
  _VisibleNode.item(this.categoryId, this.item)
      : type = _NodeType.item;
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Category> _categories = [];
  Map<int, List<MenuItem>> _itemsByCat = {};
  int? _selectedCategoryId;
  final ScrollController _scrollController = ScrollController();
  DateTime? _lastScrollCheck;
  static const bool _kLog = true; // включить/выключить отладочные логи
  int _buildCount = 0;
  // removed unused scroll stats fields
  List<_VisibleNode> _visibleNodes = [];
  List<int> _visibleCategoryIds = [];
  bool _isAppending = false;
  final Map<int, PromotionPrice> _itemPromoSummary = {};
    // Mindestbestellwert / rabattierte Zwischensumme (für Liefermodus)
    double? _minOrderAmount;
    double _discountedCartTotal = 0.0;
    bool _computingCartTotal = false;

    bool get _showMinOrderBar {
      if (_minOrderAmount == null) return false;
      if (_discountedCartTotal + 0.0001 >= _minOrderAmount!) return false;
      return true;
    }
  // Горизонтальная прокрутка вкладок категорий + ключи для автопрокрутки
  final ScrollController _catScrollController = ScrollController();
  final Map<int, GlobalKey> _catKeys = {};
  // Ключи заголовков категорий для определения активной категории при скролле
  final Map<int, GlobalKey> _categoryHeaderKeys = {};
  // Ключ шапки с вкладками (для расчёта нижней границы)
  final GlobalKey _tabsRowKey = GlobalKey();

  // Поиск
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  List<MenuItem> _searchResults = [];
  // Сопоставление item -> category для бейджа категории в выдаче поиска
  final Map<int, int> _itemToCatId = {}; // itemId -> categoryId

  @override
  void initState() {
    super.initState();
    _log('initState');
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _loadMenu();
    _initMinOrderContext();
    CartService.cartCountNotifier.addListener(_recomputeCart);
  }

  // Делает поведение более дружелюбным к Hot Reload: если состояние сохранилось
  // в странном виде (loading=true при наличии данных, пустые видимые элементы),
  // аккуратно восстанавливаем его после перезагрузки кода.
  @override
  void reassemble() {
    super.reassemble();
    _log('reassemble (hot reload)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final hasData = _categories.isNotEmpty && _itemsByCat.isNotEmpty;
      if (hasData && (_loading || _visibleNodes.isEmpty)) {
        final initialCatId = _selectedCategoryId ?? _categories.first.id;
        setState(() {
          _loading = false;
          _selectedCategoryId = initialCatId;
          if (_visibleNodes.isEmpty) {
            _visibleCategoryIds = [initialCatId];
            _visibleNodes = _buildNodesForCategory(initialCatId);
          }
        });
        _log('reassemble recovery applied: loading=$_loading, visibleNodes=${_visibleNodes.length}');
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    CartService.cartCountNotifier.removeListener(_recomputeCart);
    super.dispose();
  }

  Future<void> _initMinOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('delivery_mode');
    if (mode != 'delivery') {
      setState(() {
        _minOrderAmount = null;
        _discountedCartTotal = 0.0;
      });
      return;
    }
    final postal = prefs.getString('user_postal_code');
    if (postal == null || postal.isEmpty) return;
    final mo = await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    setState(() => _minOrderAmount = mo);
    await _computeDiscountedCartTotal();
  }

  void _recomputeCart() {
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
      final supabase = Supabase.instance.client;
      final itemIds = items.map((e) => e.itemId).toSet().toList();
      final sizeIds = items.map((e) => e.sizeId).where((e) => e != null).cast<int>().toSet().toList();
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
        for (final e in first.extras.entries) {
          final price = extraPriceMap['${first.sizeId}|${e.key}'] ?? 0.0;
          unit += price * e.value;
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

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      _log('search cleared');
      return;
    }
    // Собираем все позиции из всех категорий и фильтруем по имени/описанию, затем сортируем по релевантности
    final all = _itemsByCat.values.expand((e) => e).toList();
    final filtered = all.where((m) {
      final name = m.name.toLowerCase();
      final desc = (m.description ?? '').toLowerCase();
      return name.contains(q) || desc.contains(q);
    }).toList();
    filtered.sort((a, b) => _relevanceScore(b, q).compareTo(_relevanceScore(a, q)));
    setState(() => _searchResults = filtered);
    _log('search query="$q" results=${filtered.length}');
  }

  int _relevanceScore(MenuItem item, String q) {
    if (q.isEmpty) return 0;
    final name = item.name.toLowerCase();
    final desc = (item.description ?? '').toLowerCase();
    int score = 0;
    if (name.startsWith(q)) score += 1000;
    final idx = name.indexOf(q);
    if (idx > 0) {
      final prev = name[idx - 1];
      final isBoundary = !RegExp(r'[a-z0-9]').hasMatch(prev);
      if (isBoundary) score += 500;
    }
    if (idx >= 0) score += 300;
    if (desc.contains(q)) score += 50;
    // легкий бонус коротким названиям
    score += (200 - name.length.clamp(0, 200));
    return score;
  }

  Future<void> _loadMenu({bool showFullScreenLoader = true}) async {
    final swTotal = Stopwatch()..start();
    setState(() {
      if (showFullScreenLoader) {
        _loading = true;
      }
      _error = null;
    });
    try {
      _log('loadMenu: start');
      // 1) Загрузить категории (одним запросом) — v2
      final swCats = Stopwatch()..start();
      final catData = await _supabase
          .from('menu_v2_category')
      .select('id,name,description')
      .eq('is_active', true)
      .order('sort_order', ascending: true)
      .order('id', ascending: true);
      swCats.stop();

      _categories = (catData as List)
          .map((m) => Category(
                id: ((m['id'] as int?) ?? 0),
                name: (m['name'] as String?) ?? '',
                description: (m['description'] as String?)?.trim(),
              ))
          .toList();
      _log('categories loaded: ${_categories.length} in ${swCats.elapsedMilliseconds}ms');

      if (_categories.isNotEmpty && _selectedCategoryId == null) {
        _selectedCategoryId = _categories.first.id;
      }

      // 2) Загрузить ВСЕ позиции меню одним запросом (вместо цикла по категориям) — v2
      final swItems = Stopwatch()..start();
    final itemsData = await _supabase
          .from('menu_v2_item')
          .select('''
            id,
            category_id,
            name,
            description,
            image_url,
            sku,
            has_sizes
          ''')
          .order('category_id', ascending: true)
          .order('id', ascending: true);
      swItems.stop();

      final rawItems = (itemsData as List).cast<Map<String, dynamic>>();
      _log('items loaded: ${rawItems.length} in ${swItems.elapsedMilliseconds}ms');
      // Собираем список ID для многоразмерных позиций
      final itemIds = <int>[];
      final hasMulti = <int, bool>{};       // id -> has_sizes
      final byCategory = <int, List<Map<String, dynamic>>>{};

      for (final e in rawItems) {
        final id = (e['id'] as int?) ?? 0;
        final catId = (e['category_id'] as int?) ?? 0;
        final hm = e['has_sizes'] as bool? ?? false;
        hasMulti[id] = hm;
        itemIds.add(id);
        byCategory.putIfAbsent(catId, () => []).add(e);
      }

      // 3) Получаем минимальные цены для всех id из единого view menu_v2_item_prices
  final minPriceMap = <int, double>{};
  final Map<int, List<Map<String, dynamic>>> priceRowsByItem = {};
      if (itemIds.isNotEmpty) {
        final swPrices = Stopwatch()..start();
        final inList = '(${itemIds.join(',')})';
        final pricesRaw = await _supabase
            .from('menu_v2_item_prices')
    .select('item_id, size_id, price')
            .filter('item_id', 'in', inList);
        final castRows = (pricesRaw as List).cast<Map<String, dynamic>>();
        for (final row in castRows) {
          final mid = (row['item_id'] as int?) ?? 0;
          if (mid == 0) continue;
          final p = (row['price'] as num?)?.toDouble() ?? 0.0;
          priceRowsByItem.putIfAbsent(mid, () => []).add(row);
          final cur = minPriceMap[mid];
          if (cur == null || p < cur) minPriceMap[mid] = p;
        }
        swPrices.stop();
        _log('v2 prices loaded for items=${itemIds.length}, rows=${minPriceMap.length} in ${swPrices.elapsedMilliseconds}ms');
      }

      // 4) Собираем итоговые объекты MenuItem по категориям
  final Map<int, List<MenuItem>> itemsByCat = {};
  final Map<int, int> itemToCategory = {};
      _itemToCatId.clear();
      for (final cat in _categories) {
        final rows = byCategory[cat.id] ?? const [];
        final list = <MenuItem>[];
        for (final e in rows) {
          final id = (e['id'] as int?) ?? 0;
          _itemToCatId[id] = cat.id;
          itemToCategory[id] = cat.id;
          final hm = hasMulti[id] ?? false;
          final minPrice = minPriceMap[id] ?? 0.0;
          list.add(MenuItem(
            id: id,
            name: e['name'] as String? ?? '',
            description: e['description'] as String?,
            imageUrl: e['image_url'] as String?,
            article: e['sku'] as String?,
            minPrice: minPrice,
            hasMultipleSizes: hm,
            singleSizePrice: hm ? null : minPrice,
          ));
        }
        itemsByCat[cat.id] = list;
      }

      // 4.1) Рассчитываем минимальную промо-цену для каждой позиции
      final promotions = await getCachedPromotions(now: DateTime.now());
      final Map<int, PromotionPrice> itemPromoSummary = {};
      for (final entry in priceRowsByItem.entries) {
        final itemId = entry.key;
        final catId = itemToCategory[itemId];
        if (catId == null) continue;
        final rows = entry.value;
        PromotionPrice? best;
        for (final row in rows) {
          final price = (row['price'] as num?)?.toDouble();
          if (price == null) continue;
          final rawSizeId = row['size_id'];
          int? sizeId;
          if (rawSizeId is int && rawSizeId != 0) {
            sizeId = rawSizeId;
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
              ((info.finalPrice - best.finalPrice).abs() <= 0.0005 && info.discountAmount > best.discountAmount)) {
            best = info;
          }
        }
        if (best != null) {
          itemPromoSummary[itemId] = best;
        } else {
          final fallback = minPriceMap[itemId];
          if (fallback != null) {
            itemPromoSummary[itemId] = PromotionPrice(
              basePrice: fallback,
              finalPrice: fallback,
              discountAmount: 0,
              promotion: null,
              target: null,
            );
          }
        }
      }

      // Подготовим результаты поиска, если поле поиска уже заполнено во время загрузки
      List<MenuItem> updatedSearch = _searchResults;
      final query = _searchController.text.trim().toLowerCase();
      if (_showSearch && query.isNotEmpty) {
        final all = itemsByCat.values.expand((e) => e).toList();
        updatedSearch = all.where((m) {
          final name = m.name.toLowerCase();
          final desc = (m.description ?? '').toLowerCase();
          return name.contains(query) || desc.contains(query);
        }).toList();
        updatedSearch.sort((a, b) => _relevanceScore(b, query).compareTo(_relevanceScore(a, query)));
      }

      if (!mounted) return;
      setState(() {
        _itemsByCat = itemsByCat;
        _searchResults = updatedSearch;
        _loading = false;
        _itemPromoSummary
          ..clear()
          ..addAll(itemPromoSummary);
        // Гарантированная инициализация видимых узлов
        if (_selectedCategoryId != null && _itemsByCat[_selectedCategoryId!] != null) {
          _visibleCategoryIds = [_selectedCategoryId!];
          _visibleNodes = _buildNodesForCategory(_selectedCategoryId!);
        } else if (_categories.isNotEmpty) {
          final firstCatId = _categories.first.id;
          _selectedCategoryId = firstCatId;
          _visibleCategoryIds = [firstCatId];
          _visibleNodes = _buildNodesForCategory(firstCatId);
        }
      });
      final totalItems = itemsByCat.values.fold<int>(0, (p, e) => p + e.length);
      swTotal.stop();
      _log('loadMenu: ready categories=${_categories.length}, totalItems=$totalItems in ${swTotal.elapsedMilliseconds}ms');
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
      _log('loadMenu: error: $err');
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    final bool searchActive = _showSearch && _searchController.text.trim().isNotEmpty;
    final hasCategories = _categories.isNotEmpty;
    _buildCount++;
    if (_buildCount <= 3) {
  _log('build #$_buildCount loading=$_loading searchActive=$searchActive cats=${_categories.length} visibleNodes=${_visibleNodes.length}');
    }

    // (убрано) Ранее здесь была build-time "страховка" с setState в post-frame.
    // Оставляем инициализацию строго в _loadMenu и (для hot reload) в reassemble().

    // отступ снизу под нижний NavigationBar
    final bottomPadding = MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight;

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search, color: appTheme.iconColor),
          onPressed: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
                _searchResults = [];
              }
            });
          },
        ),
        title: Text('Menü', style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: CartService.cartCountNotifier,
            builder: (context, cartCount, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.shopping_cart, color: appTheme.iconColor),
                    tooltip: 'Warenkorb',
                    onPressed: () => Navigator.of(context).pushNamed('/cart'),
                  ),
                  if (cartCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$cartCount', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
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
                    border: Border(top: BorderSide(color: Colors.redAccent.withOpacity(0.35), width: 0.8)),
                  ),
                  alignment: Alignment.center,
                  child: _computingCartTotal
                      ? Text('Prüfe Mindestbestellwert…', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11))
                      : Text(
                          'Noch €${(_minOrderAmount! - _discountedCartTotal).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                          style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                ),
              )
            : null,
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: appTheme.primaryColor))
          : _error != null
              ? NoInternetWidget(
                  onRetry: () => _loadMenu(showFullScreenLoader: true),
                  errorText: _error?.contains('SocketException') == true || _error == 'Нет подключения к интернету'
                      ? 'Keine Internetverbindung'
                      : _error,
                )
              : CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  slivers: [
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (_showSearch)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              onChanged: (_) => _onSearchChanged(),
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
                        ),
                      ),
                    if (_showSearch) const SliverToBoxAdapter(child: SizedBox(height: 12)),
                    if (searchActive)
                      ..._buildSearchResults(appTheme, _searchResults, bottomPadding)
                    else ...[
                      if (hasCategories)
                        SliverAppBar(
                          pinned: true,
                          automaticallyImplyLeading: false,
                          elevation: 0,
                          backgroundColor: appTheme.backgroundColor,
                          toolbarHeight: 64,
                          title: _buildCategoryTabsRow(
                            appTheme: appTheme,
                            categories: _categories,
                            selectedCategoryId: _selectedCategoryId,
                            onSelectCategory: (id) => _startFromCategory(id),
                            onOpenPicker: _openCategoryPicker,
                          ),
                        ),
                      if (hasCategories) const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      if (!hasCategories)
                        SliverPadding(
                          padding: EdgeInsets.only(left: 20, right: 20, bottom: bottomPadding + 40),
                          sliver: SliverToBoxAdapter(
                            child: _buildEmptyState(
                              appTheme: appTheme,
                              title: 'Keine Kategorien',
                              subtitle: 'Wir arbeiten daran, das Menü zu aktualisieren. Bitte versuchen Sie es später erneut.',
                            ),
                          ),
                        )
                      else ..._buildVisibleContent(context, appTheme, bottomPadding),
                    ],
                  ],
                ),
    );
  }

  // Шапка категорий как обычный виджет (используется в SliverAppBar.title)
  Widget _buildCategoryTabsRow({
    required AppTheme appTheme,
    required List<Category> categories,
    required int? selectedCategoryId,
    required ValueChanged<int> onSelectCategory,
    required VoidCallback onOpenPicker,
  }) {
    return Container(
      key: _tabsRowKey,
      child: Row(
      children: [
        Expanded(
          child: ShaderMask(
            shaderCallback: (Rect rect) {
              // Маска: большая часть строки непрозрачна, правый край плавно в ноль
              return const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                // Сделал fade шире и мягче (последние ~22%)
                stops: [0.0, 0.78, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              controller: _catScrollController,
              child: Row(
                children: categories.map((cat) {
                  final bool isSelected = cat.id == selectedCategoryId;
                  final key = _catKeys.putIfAbsent(cat.id, () => GlobalKey());
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: key,
                        borderRadius: BorderRadius.circular(26),
                        onTap: () => onSelectCategory(cat.id),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            gradient: isSelected
                                ? LinearGradient(
                                    colors: [appTheme.primaryColor, const Color(0xFFFF8A65)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: isSelected ? null : appTheme.cardColor.withValues(alpha: 0.9),
                            border: Border.all(
                              color: isSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                cat.name,
                                style: GoogleFonts.poppins(
                                  color: isSelected ? Colors.white : appTheme.textColor,
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onOpenPicker,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.list, color: appTheme.iconColor, size: 22),
            ),
          ),
        ),
      ],
    ));
  }

  // (iOS fallback helper удалён, используем один pinned header на всех платформах)

  // Контент: единый непрерывный список из _visibleNodes (заголовки + элементы)
  List<Widget> _buildVisibleContent(BuildContext context, AppTheme appTheme, double bottomPadding) {
    final nodes = _visibleNodes;
    _log('build visible content: nodes=${nodes.length}');
    if (nodes.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 32, bottom: bottomPadding + 60),
          sliver: SliverToBoxAdapter(
            child: _buildEmptyState(
              appTheme: appTheme,
              title: 'Keine Artikel',
              subtitle: 'In dieser Kategorie sind derzeit keine Gerichte verfügbar.',
            ),
          ),
        ),
      ];
    }

    // Для заголовков категорий оставляем список (без грида)
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPadding + 28),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final node = nodes[index];
              if (node.type == _NodeType.header) {
                final cat = _categories.firstWhere((c) => c.id == node.categoryId);
                final key = _categoryHeaderKeys.putIfAbsent(cat.id, () => GlobalKey());
                return Padding(
                  key: key,
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: _buildCategoryHeader(appTheme, cat),
                );
              }
              final item = node.item!;
              if (index == 0) _log('first list node built: item id=${item.id}');
              return Padding(
                padding: EdgeInsets.only(bottom: index == nodes.length - 1 ? 0 : 16),
                child: MenuItemTile(
                  item: item,
                  layout: MenuItemTileLayout.list,
                  priceInfo: _itemPromoSummary[item.id],
                  showImage: false,
                  onTap: () => _openMenuItem(item),
                ),
              );
            },
            childCount: nodes.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildCategoryHeader(AppTheme appTheme, Category cat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cat.name,
          style: GoogleFonts.poppins(
            color: appTheme.textColor,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        if ((cat.description ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              cat.description!,
              style: GoogleFonts.poppins(
                color: appTheme.textColorSecondary,
                fontSize: 13,
              ),
            ),
          ),
      ],
    );
  }

  void _onScroll() {
    if (_loading) return;
    if (_showSearch && _searchController.text.trim().isNotEmpty) return;
    if (!_scrollController.hasClients) return;

    final now = DateTime.now();
    if (_lastScrollCheck != null && now.difference(_lastScrollCheck!).inMilliseconds < 120) {
      return; // троттлинг
    }
    _lastScrollCheck = now;

    final pos = _scrollController.position;
    final nearBottom = pos.pixels >= (pos.maxScrollExtent - 300);
    if (nearBottom) {
      _appendNextCategory();
    }
    _updateActiveCategoryByHeaders();
  }

  void _updateActiveCategoryByHeaders() {
    if (_visibleCategoryIds.isEmpty) return;
    try {
      final tabsCtx = _tabsRowKey.currentContext;
      if (tabsCtx == null) return;
      final tabsBox = tabsCtx.findRenderObject() as RenderBox?;
      if (tabsBox == null) return;
      final tabsBottomGlobal = tabsBox.localToGlobal(Offset(0, tabsBox.size.height)).dy;

      int? activeId;
      for (final catId in _visibleCategoryIds) {
        final key = _categoryHeaderKeys[catId];
        final ctx = key?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final topDy = box.localToGlobal(Offset.zero).dy;
        if (topDy <= tabsBottomGlobal + 6) {
          activeId = catId;
        } else {
          break;
        }
      }

      if (activeId != null && activeId != _selectedCategoryId) {
        setState(() {
          _selectedCategoryId = activeId;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollCategoryTabIntoView(activeId!));
      }
    } catch (_) {
      // ignore
    }
  }

  void _appendNextCategory() {
    if (_isAppending) return;
    if (_categories.isEmpty || _itemsByCat.isEmpty) return;
    if (_visibleCategoryIds.isEmpty) return;
    final lastId = _visibleCategoryIds.last;
    final idx = _categories.indexWhere((c) => c.id == lastId);
    if (idx < 0) return;
    int nextIdx = idx + 1;
    while (nextIdx < _categories.length) {
      final nextCat = _categories[nextIdx];
      final nextItems = _itemsByCat[nextCat.id] ?? const <MenuItem>[];
      if (nextItems.isNotEmpty) {
        _isAppending = true;
        setState(() {
          _visibleNodes.add(_VisibleNode.header(nextCat.id));
          for (final it in nextItems) {
            _visibleNodes.add(_VisibleNode.item(nextCat.id, it));
          }
          _visibleCategoryIds.add(nextCat.id);
          _selectedCategoryId = nextCat.id; // обновим активную вкладку
        });
        _isAppending = false;
        _log('append category ${nextCat.id} -> visibleNodes=${_visibleNodes.length}');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollCategoryTabIntoView(nextCat.id);
        });
        break;
      }
      nextIdx++;
    }
  }

  void _startFromCategory(int categoryId) {
    if (_selectedCategoryId == categoryId && _visibleCategoryIds.isNotEmpty && _visibleCategoryIds.first == categoryId) {
      // уже в нужном состоянии
      return;
    }
    setState(() {
      _selectedCategoryId = categoryId;
      _visibleCategoryIds = [categoryId];
      _visibleNodes = _buildNodesForCategory(categoryId);
    });
    // Прокручиваем вкладки так, чтобы активная "прилипла" к левому краю
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollCategoryTabIntoView(categoryId);
    });
    // прокрутка к началу
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
    _log('startFromCategory $categoryId nodes=${_visibleNodes.length}');
  }

  void _scrollCategoryTabIntoView(int categoryId) {
    final key = _catKeys[categoryId];
    if (key == null) return;
    final context = key.currentContext;
    if (context == null) return;

    try {
      final box = context.findRenderObject() as RenderBox?;
      final scrollBox = _catScrollController.position.context.storageContext.findRenderObject() as RenderBox?;
      if (box == null || scrollBox == null) return;

      final itemGlobal = box.localToGlobal(Offset.zero);
      final scrollGlobal = scrollBox.localToGlobal(Offset.zero);
      final dx = itemGlobal.dx - scrollGlobal.dx; // расстояние от левого края вьюпорта
      final targetOffset = (_catScrollController.offset + dx - 12).clamp(0.0, _catScrollController.position.maxScrollExtent);
      _catScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // В крайнем случае — просто ensureVisible
      Scrollable.ensureVisible(context, alignment: 0.0, duration: const Duration(milliseconds: 250));
    }
  }

  // scrollToCategory больше не нужен, используем старт отображения с выбранной категории

  // Собрать узлы (заголовок + элементы) для одной категории
  List<_VisibleNode> _buildNodesForCategory(int categoryId) {
    final nodes = <_VisibleNode>[];
    nodes.add(_VisibleNode.header(categoryId));
    final items = _itemsByCat[categoryId] ?? const <MenuItem>[];
    for (final it in items) {
      nodes.add(_VisibleNode.item(categoryId, it));
    }
    return nodes;
  }

  void _openCategoryPicker() async {
    final appTheme = ThemeProvider.of(context);
    _log('openCategoryPicker');
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: appTheme.cardColor.withValues(alpha: 0.98),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.list, color: appTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'Kategorien',
                      style: GoogleFonts.poppins(
                        color: appTheme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    final selected = c.id == _selectedCategoryId;
                    return ListTile(
                      leading: Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: selected ? appTheme.primaryColor : appTheme.textColorSecondary,
                      ),
                      title: Text(
                        c.name,
                        style: GoogleFonts.poppins(
                          color: appTheme.textColor,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      onTap: () => Navigator.of(ctx).pop(c.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (picked != null) {
      _log('picker -> $picked');
      _startFromCategory(picked);
    }
  }

  

  

  List<Widget> _buildSearchResults(AppTheme appTheme, List<MenuItem> items, double bottomPadding) {
    if (items.isEmpty) {
      return [
        SliverPadding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: bottomPadding + 60),
          sliver: SliverToBoxAdapter(
            child: _buildEmptyState(
              appTheme: appTheme,
              title: 'Keine Treffer',
              subtitle: 'Keine Artikel entsprechen Ihrer Suche.',
            ),
          ),
        ),
      ];
    }
    // В выдаче поиска показываем компактные карточки без изображений — лучше читается
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(12, 4, 12, bottomPadding + 28),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return Padding(
                padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 16),
                child: SearchResultTile(
                  item: item,
                  query: _searchController.text.trim(),
                  categoryName: () {
                    final catId = _itemToCatId[item.id];
                    if (catId == null) return null;
                    final cat = _categories.firstWhere(
                      (c) => c.id == catId,
                      orElse: () => Category(id: -1, name: '', description: null),
                    );
                    return cat.id == -1 || cat.name.isEmpty ? null : cat.name;
                  }(),
                  priceInfo: _itemPromoSummary[item.id],
                  onTap: () => _openMenuItem(item),
                ),
              );
            },
            childCount: items.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildEmptyState({
    required AppTheme appTheme,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: appTheme.cardColor.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [appTheme.primaryColor, const Color(0xFFFF8A65)],
              ),
            ),
            child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              color: appTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: appTheme.textColorSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  

  Future<void> _openMenuItem(MenuItem summary) async {
    if (!mounted) return;
    // Пытаемся сопоставить с бандлом по SKU (article) или по точному имени
    int? bundleId;
    try {
      final sku = summary.article?.trim();
      Map<String, dynamic>? row;
      if (sku != null && sku.isNotEmpty) {
        row = await _supabase
            .from('menu_v2_bundle')
            .select('id')
            .eq('sku', sku)
            .maybeSingle();
      }
      row ??= await _supabase
          .from('menu_v2_bundle')
          .select('id')
          .eq('name', summary.name)
          .maybeSingle();
      bundleId = row != null ? (row['id'] as int?) : null;
    } catch (_) {
      bundleId = null;
    }

    if (bundleId != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BundleDetailScreen(bundleId: bundleId!),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MenuItemDetailScreen(item: summary),
        ),
      );
    }
    if (!mounted) return;
    setState(() {});
  }
}
void _log(String msg) {
  if (!_MenuScreenState._kLog) return;
  final ts = DateTime.now().toIso8601String();
  debugPrint('[Menu][$ts] $msg');
}
  enum MenuItemTileLayout { list, grid }

  class MenuItemTile extends StatelessWidget {
    final MenuItem item;
    final MenuItemTileLayout layout;
    final PromotionPrice? priceInfo;
    final VoidCallback onTap;
    // When false, completely hide the media section (image/placeholder)
    // to make room for longer titles and compact cards.
    final bool showImage;

    const MenuItemTile({
      super.key,
      required this.item,
      required this.layout,
      this.priceInfo,
      required this.onTap,
      this.showImage = true,
    });

    @override
    Widget build(BuildContext context) {
      final appTheme = ThemeProvider.of(context);
      final bool isGrid = layout == MenuItemTileLayout.grid;
      final bool hasImage = item.imageUrl?.isNotEmpty == true;
      // Show the media section if showImage=true (even if there is no actual
      // image, we'll render a graceful placeholder). If showImage=false, we
      // skip the media entirely for a denser layout.
      final bool showMediaSection = showImage;
      final BorderRadius borderRadius = BorderRadius.circular(isGrid ? 22 : 20);

      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
            onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: appTheme.cardColor.withValues(alpha: isGrid ? 0.96 : 0.92),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 20,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(isGrid ? 16 : 18),
              child: isGrid
                  ? _buildGridLayout(appTheme, showMediaSection, hasImage, borderRadius)
                  : _buildListLayout(appTheme, showMediaSection, hasImage, borderRadius),
            ),
          ),
        ),
      );
    }

    Widget _buildListLayout(
      AppTheme appTheme,
      bool showMediaSection,
      bool hasImage,
      BorderRadius borderRadius,
    ) {
      final priceContent = _buildPriceContent(appTheme);
      if (showMediaSection) {
        // Original layout with media on the left
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMedia(
              appTheme,
              hasImage,
              borderRadius,
              width: 118,
              height: 112,
              isGrid: false,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: SizedBox(
                height: 112,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.article != null && item.article!.isNotEmpty)
                      Text(
                        'Art.Nr. ${item.article}',
                        style: GoogleFonts.poppins(
                          color: appTheme.primaryColor.withValues(alpha: 0.9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Text(
                      item.name,
                      style: GoogleFonts.poppins(
                        color: appTheme.textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description != null && item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item.description!,
                          style: GoogleFonts.poppins(
                            color: appTheme.textColorSecondary,
                            fontSize: 13,
                          ),
                          // Увеличиваем макс. строки и позволяем переносы \n
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          softWrap: true,
                        ),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        if (priceContent != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: appTheme.primaryColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: priceContent,
                          ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            size: 14,
                            color: appTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // Compact layout without media, allowing longer titles to wrap
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.article != null && item.article!.isNotEmpty)
            Text(
              'Art.Nr. ${item.article}',
              style: GoogleFonts.poppins(
                color: appTheme.primaryColor.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          Text(
            item.name,
            style: GoogleFonts.poppins(
              color: appTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          if (item.description != null && item.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.description!,
                style: GoogleFonts.poppins(
                  color: appTheme.textColorSecondary,
                  fontSize: 13,
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (priceContent != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: appTheme.primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: priceContent,
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: appTheme.primaryColor,
                ),
              ),
            ],
          ),
        ],
      );
    }

    Widget _buildGridLayout(
      AppTheme appTheme,
      bool showMediaSection,
      bool hasImage,
      BorderRadius borderRadius,
    ) {
        final priceContent = _buildPriceContent(appTheme, fontSize: 14);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMediaSection) ...[
            _buildMedia(
              appTheme,
              hasImage,
              borderRadius,
              width: double.infinity,
              height: 150,
              isGrid: true,
            ),
            const SizedBox(height: 14),
          ],
          if (item.article != null && item.article!.isNotEmpty)
            Text(
              'Art.Nr. ${item.article}',
              style: GoogleFonts.poppins(
                color: appTheme.primaryColor.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          Text(
            item.name,
            style: GoogleFonts.poppins(
              color: appTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
            maxLines: showMediaSection ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
          ),
          const SizedBox(height: 6),
          if (item.description != null && item.description!.isNotEmpty)
            Text(
              item.description!,
              style: GoogleFonts.poppins(
                color: appTheme.textColorSecondary,
                fontSize: 13,
              ),
              maxLines: showMediaSection ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          const SizedBox(height: 14),
          if (priceContent != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    appTheme.primaryColor.withValues(alpha: 0.45),
                    const Color(0xFFFF8A65).withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: priceContent,
            ),
        ],
      );
    }

    Widget _buildMedia(
      AppTheme appTheme,
      bool hasImage,
      BorderRadius borderRadius, {
      required double width,
      required double height,
      required bool isGrid,
    }) {
      if (hasImage) {
        final image = ClipRRect(
          borderRadius: borderRadius,
          child: Image.network(
            item.imageUrl!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                width: width,
                height: height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  color: appTheme.backgroundColor.withValues(alpha: 0.2),
                ),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(appTheme.primaryColor),
                  ),
                ),
              );
            },
            errorBuilder: (_, __, ___) => _buildFallbackMedia(
              appTheme,
              borderRadius,
              width: width,
              height: height,
              isGrid: isGrid,
            ),
          ),
        );

        return SizedBox(
          width: width,
          height: height,
          child: Hero(
            tag: 'menuItemImage_${item.id}',
            child: image,
          ),
        );
      }

      return _buildFallbackMedia(
        appTheme,
        borderRadius,
        width: width,
        height: height,
        isGrid: isGrid,
      );
    }

    Widget _buildFallbackMedia(
      AppTheme appTheme,
      BorderRadius borderRadius, {
      required double width,
      required double height,
      required bool isGrid,
    }) {
      final gradientColors = isGrid
          ? const [Color(0xFF2D325A), Color(0xFF1C213A)]
          : const [Color(0xFF2B314C), Color(0xFF1A1F33)];

      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -8,
              right: -12,
              child: Icon(
                Icons.blur_on,
                color: Colors.white.withValues(alpha: 0.06),
                size: isGrid ? 118 : 96,
              ),
            ),
            Align(
              alignment: Alignment.center,
              child: Icon(
                Icons.local_pizza,
                color: Colors.white.withValues(alpha: 0.88),
                size: isGrid ? 44 : 38,
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.94),
                  fontSize: isGrid ? 16 : 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    PromotionPrice? get _resolvedPriceInfo {
      if (priceInfo != null) return priceInfo;
      double? fallback;
      if (item.hasMultipleSizes) {
        fallback = item.minPrice > 0 ? item.minPrice : null;
      } else {
        fallback = item.singleSizePrice ?? (item.minPrice > 0 ? item.minPrice : null);
      }
      if (fallback == null) return null;
      return PromotionPrice(
        basePrice: fallback,
        finalPrice: fallback,
        discountAmount: 0,
        promotion: null,
        target: null,
      );
    }

    Widget? _buildPriceContent(AppTheme appTheme, {double fontSize = 13}) {
      final info = _resolvedPriceInfo;
      if (info == null) return null;
      final formatter = (double value) => '${value.toStringAsFixed(2)} €';
      final finalStyle = GoogleFonts.poppins(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
      );
      final baseStyle = finalStyle.copyWith(
        decoration: TextDecoration.lineThrough,
        color: Colors.white.withValues(alpha: 0.7),
      );

      Widget content = PriceWithPromotion(
        basePrice: info.basePrice,
        finalPrice: info.finalPrice,
        finalStyle: finalStyle,
        baseStyle: baseStyle,
        formatter: formatter,
      );

      if (item.hasMultipleSizes && info.basePrice > 0) {
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ab ', style: finalStyle),
            content,
          ],
        );
      }
      return content;
    }
  }



// Делегат для фиксированного (pinned) заголовка с горизонтальными вкладками категорий
// Старый делегат для pinned header удалён (используем SliverAppBar)



