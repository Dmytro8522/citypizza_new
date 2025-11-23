// lib/screens/cart_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../services/discount_service.dart';
import '../widgets/no_internet_widget.dart';
import 'checkout_screen.dart';
// removed unused imports: menu_item_detail_screen.dart, home_screen.dart
import '../theme/theme_provider.dart';
import '../widgets/price_with_promotion.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/delivery_zone_service.dart';

class _ExtraInfo {
  final int id;
  final String name;
  final double price;
  final int quantity;
  _ExtraInfo({required this.id, required this.name, required this.price, required this.quantity});
}

class _OptionInfo {
  final int id;
  final String name;
  final double priceDelta;
  final int quantity;
  _OptionInfo({required this.id, required this.name, required this.priceDelta, required this.quantity});
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  bool _loadingDetails = true;
  double _totalSum = 0;
  double _totalDiscount = 0;
  List<Map<String, dynamic>> _appliedDiscounts = [];
  Map<String, PromotionPrice> _linePromotionPrices = {};

  final Map<int, int> _itemCategoryCache = {};
  final Map<String, TextEditingController> _commentControllers = {};
  // Кэш признака наличия нескольких размеров у товара (menu_v2_item.has_sizes)
  final Map<int, bool> _hasSizes = {};
  // removed unused _commentVisible

  String? _userId;
  String? _error;

  // Mindestbestellwert für Liefermodus
  double? _minOrderAmount;
  bool _computingMinOrder = false;
  bool _isDeliveryMode = false;

  bool get _showMinOrderBar => _isDeliveryMode && _minOrderAmount != null && _totalSum + 0.0001 < _minOrderAmount!;

  @override
  void initState() {
    super.initState();
    CartService.init().then((_) async {
  await _loadUserData(); // currently only loads userId; birthdate no longer needed for promotions
      await _recalculateTotal();
      await _initMinOrderContext();
    });
    // Подписка на изменения корзины: при добавлении из UpSell на другом экране пересчитаем сумму
    CartService.cartCountNotifier.addListener(_onCartChanged);
  }

  void _onCartChanged() {
    // Пересчитать сумму и обновить UI при каждом изменении количества элементов в корзине
    _recalculateTotal();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CartService.cartCountNotifier.removeListener(_onCartChanged);
    super.dispose();
  }

  Future<void> _initMinOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('delivery_mode');
    _isDeliveryMode = mode == 'delivery';
    if (!_isDeliveryMode) {
      setState(() {
        _minOrderAmount = null;
      });
      return;
    }
    final postal = prefs.getString('user_postal_code');
    if (postal == null || postal.isEmpty) return;
    setState(() => _computingMinOrder = true);
    final mo = await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    if (!mounted) return;
    setState(() {
      _minOrderAmount = mo;
      _computingMinOrder = false;
    });
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    _userId = user?.id;
    if (_userId == null) return;
  // Birthdate previously used for legacy birthday discounts; removed in promotion system.
  // If birthday-based promotions are reintroduced, fetch here.
  }

  Future<int?> _getCategoryId(int itemId) async {
    if (_itemCategoryCache.containsKey(itemId)) {
      return _itemCategoryCache[itemId];
    }
  final res = await Supabase.instance.client
    .from('menu_v2_item')
    .select('category_id')
    .eq('id', itemId)
    .maybeSingle();
    final categoryId = res?['category_id'] as int?;
    if (categoryId != null) {
      _itemCategoryCache[itemId] = categoryId;
    }
    return categoryId;
  }

  Future<List<_ExtraInfo>> _loadExtrasInfo(
      int itemId, Map<int, int> extrasMap, {int? sizeId, String? sizeName}) async {
    if (extrasMap.isEmpty) return [];
    int? resolvedSizeId = sizeId;
    if (resolvedSizeId == null && (sizeName != null && sizeName.isNotEmpty)) {
      final szRow = await Supabase.instance.client
          .from('menu_size')
          .select('id')
          .eq('name', sizeName)
          .maybeSingle();
      if (szRow == null) return [];
      resolvedSizeId = (szRow['id'] as int?) ?? 0;
    }

    // В v2 цены допов зависят только от размера
    final priceMap = <int, double>{};
    if (resolvedSizeId != null && resolvedSizeId != 0) {
      final extraPriceRows = await Supabase.instance.client
          .from('menu_v2_extra_price_by_size')
          .select('extra_id, price')
          .eq('size_id', resolvedSizeId)
          .filter('extra_id', 'in', extrasMap.keys.toList());
      for (var row in extraPriceRows as List) {
        final eid = (row['extra_id'] as int?) ?? 0;
        final p = (row['price'] as num).toDouble();
        priceMap[eid] = p;
      }
    }

    final extraRows = await Supabase.instance.client
        .from('menu_v2_extra')
        .select('id, name')
        .filter('id', 'in', extrasMap.keys.toList());
    final nameMap = <int, String>{
      for (var row in extraRows as List) ((row['id'] as int?) ?? 0): ((row['name'] as String?) ?? ''),
    };

  return extrasMap.entries
    .map((e) => _ExtraInfo(
        id: e.key,
        name: nameMap[e.key] ?? 'Неизвестно',
        price: priceMap[e.key] ?? 0,
        quantity: e.value,
      ))
    .toList();
  }

  Future<List<_OptionInfo>> _loadOptionsInfo(Map<int, int> optionsMap) async {
    if (optionsMap.isEmpty) return [];
    final optRows = await Supabase.instance.client
        .from('menu_v2_modifier_option')
        .select('id, name')
        .filter('id', 'in', optionsMap.keys.toList());
    final list = (optRows as List).cast<Map<String, dynamic>>();
    return list.map((row) {
      final id = (row['id'] as int?) ?? 0;
      final name = (row['name'] as String?) ?? '';
      return _OptionInfo(id: id, name: name, priceDelta: 0.0, quantity: optionsMap[id] ?? 0);
    }).toList();
  }

  // Редактирование количества опций (модификаторов) в корзине запрещено по ТЗ

  // Изменение количества экстра для одной позиции
  Future<void> _changeExtraQty(CartItem base, int extraId, int newQty) async {
    final newExtras = Map<int, int>.from(base.extras);
    if (newQty <= 0) {
      newExtras.remove(extraId);
    } else {
      newExtras[extraId] = newQty;
    }
    final newItem = CartItem(
      itemId: base.itemId,
      name: base.name,
      size: base.size,
      basePrice: base.basePrice,
      extras: newExtras,
      options: base.options,
      article: base.article,
      sizeId: base.sizeId,
    );
    await CartService.replaceFirst(base, newItem);
    await _recalculateTotal();
    if (mounted) setState(() {});
  }

  Widget _qtyStepper({required int qty, required VoidCallback onDec, required VoidCallback onInc}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          iconSize: 20,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: onDec,
        ),
        Text('$qty', style: GoogleFonts.poppins(fontSize: 13)),
        IconButton(
          iconSize: 20,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: onInc,
        ),
      ],
    );
  }

  Future<void> _recalculateTotal() async {
    try {
      final items = CartService.items;
      final promotions = await getCachedPromotions(now: DateTime.now());
      // Соберём уникальные itemId для батч-запроса has_sizes
      final uniqueItemIds = <int>{}..addAll(items.map((e) => e.itemId));
      final grouped = <String, List<CartItem>>{};
      for (final cartItem in items) {
        final optionsSig = cartItem.options.entries.map((e) => '${e.key}:${e.value}').join(',');
        String bundleSig = '';
        if (cartItem.meta?['type'] == 'bundle') {
          final slots = (cartItem.meta?['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
          final slotParts = <String>[];
            for (final s in slots) {
              final sid = (s['slotId'] as int?) ?? 0;
              final itemsList = (s['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
              final itemParts = <String>[];
              for (final it in itemsList) {
                final iid = (it['itemId'] as int?) ?? 0;
                final sz = (it['sizeId'] as int?) ?? -1;
                final oids = ((it['optionIds'] as List?) ?? const <dynamic>[])..sort();
                final eids = ((it['extraIds'] as List?) ?? const <dynamic>[])..sort();
                itemParts.add('i:$iid|s:$sz|o:${oids.join(";")}|e:${eids.join(";")}');
              }
              itemParts.sort();
              slotParts.add('slot:$sid=>${itemParts.join("#")}');
            }
          slotParts.sort();
          bundleSig = slotParts.join('||');
        }
        final key = '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}|$optionsSig|$bundleSig';
        grouped.putIfAbsent(key, () => []).add(cartItem);
        _commentControllers.putIfAbsent(key, () => TextEditingController());
      }

      double subtotal = 0;
      final cartList = <Map<String, dynamic>>[];
      final linePromotions = <String, PromotionPrice>{};

      for (final entry in grouped.entries) {
        final first = entry.value.first;
        final count = entry.value.length;
        final extras = await _loadExtrasInfo(first.itemId, first.extras, sizeId: first.sizeId, sizeName: first.size);
        final extrasCost = extras.fold<double>(0, (p, e) => p + e.price * e.quantity);
        final opts = await _loadOptionsInfo(first.options);
        final optsCost = opts.fold<double>(0, (p, o) => p + o.priceDelta * o.quantity);
        final unitPrice = first.basePrice + extrasCost + optsCost;
        final lineTotal = unitPrice * count;
        subtotal += lineTotal;

        final categoryId = await _getCategoryId(first.itemId);
        linePromotions[entry.key] = evaluatePromotionForUnitPrice(
          promotions: promotions,
          unitPrice: unitPrice,
          itemId: first.itemId,
          categoryId: categoryId,
          sizeId: first.sizeId,
        );
        cartList.add({
          'id': first.itemId,
          'category_id': categoryId,
          'size_id': first.sizeId,
          'price': unitPrice,
          'quantity': count,
        });
      }

      final discountResult = await calculateDiscountedTotal(
        cartItems: cartList,
        subtotal: subtotal,
      );

      // Подтягиваем has_sizes для всех уникальных itemId одной пачкой
      if (uniqueItemIds.isNotEmpty) {
        try {
          final inIds = uniqueItemIds.toList();
          final rows = await Supabase.instance.client
              .from('menu_v2_item')
              .select('id, has_sizes')
              .filter('id', 'in', inIds);
          final map = <int, bool>{};
          for (final r in (rows as List)) {
            final id = (r['id'] as int?) ?? 0;
            final hs = (r['has_sizes'] as bool?) ?? false;
            if (id > 0) map[id] = hs;
          }
          if (mounted) {
            setState(() {
              _hasSizes
                ..clear()
                ..addAll(map);
            });
          }
        } catch (_) {
          // игнорируем: по умолчанию будем отображать размер, если неизвестно
        }
      }

      if (!mounted) return;
      setState(() {
        _totalSum = discountResult.total;
        _totalDiscount = discountResult.totalDiscount;
        _appliedDiscounts = discountResult.appliedDiscounts;
        _loadingDetails = false;
        _linePromotionPrices = linePromotions;
      });
    } on SocketException {
      setState(() {
        _error = 'Keine Internetverbindung';
        _loadingDetails = false;
        _linePromotionPrices = {};
      });
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingDetails = false;
        _linePromotionPrices = {};
      });
      return;
    }
  }

  // removed unused _navigateToDetail

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);

    if (_loadingDetails) {
      return Scaffold(
        backgroundColor: appTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: appTheme.backgroundColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: appTheme.textColor),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Warenkorb',
              style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: appTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: appTheme.backgroundColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: appTheme.textColor),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Warenkorb',
              style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
          centerTitle: true,
        ),
        body: NoInternetWidget(
          onRetry: _recalculateTotal,
          errorText: _error,
        ),
      );
    }

    final items = CartService.items;
    final grouped = <String, List<CartItem>>{};
    for (final cartItem in items) {
      final optionsSig = cartItem.options.entries.map((e) => '${e.key}:${e.value}').join(',');
      String bundleSig = '';
      if (cartItem.meta?['type'] == 'bundle') {
        final slots = (cartItem.meta?['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
        final slotParts = <String>[];
        for (final s in slots) {
          final sid = (s['slotId'] as int?) ?? 0;
          final itemsList = (s['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
          final itemParts = <String>[];
          for (final it in itemsList) {
            final iid = (it['itemId'] as int?) ?? 0;
            final sz = (it['sizeId'] as int?) ?? -1;
            final oids = ((it['optionIds'] as List?) ?? const <dynamic>[])..sort();
            final eids = ((it['extraIds'] as List?) ?? const <dynamic>[])..sort();
            itemParts.add('i:$iid|s:$sz|o:${oids.join(";")}|e:${eids.join(";")}');
          }
          itemParts.sort();
          slotParts.add('slot:$sid=>${itemParts.join("#")}');
        }
        slotParts.sort();
        bundleSig = slotParts.join('||');
      }
      final key = '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}|$optionsSig|$bundleSig';
      grouped.putIfAbsent(key, () => []).add(cartItem);
    }
    final lines = grouped.entries.map((entry) {
      final first = entry.value.first;
      final count = entry.value.length;
      final baseTotal = first.basePrice * count;
      return {
        'key': entry.key,
        'item': first,
        'count': count,
        'baseTotal': baseTotal,
      };
    }).toList();

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Warenkorb',
            style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
        centerTitle: true,
        bottom: _showMinOrderBar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    border: Border(top: BorderSide(color: Colors.redAccent.withOpacity(0.35), width: 0.8)),
                  ),
                  alignment: Alignment.center,
                  child: _computingMinOrder
                      ? Text('Prüfe Mindestbestellwert…', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11))
                      : Text(
                          'Noch €${(_minOrderAmount! - _totalSum).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                          style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: lines.isEmpty
                ? Center(
                    child: Text('Ihr Warenkorb ist leer',
                        style: GoogleFonts.poppins(color: appTheme.textColorSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    itemCount: lines.length,
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      final cartItem = line['item'] as CartItem;
                      final count = line['count'] as int;
                      final lineKey = line['key'] as String;
                      final priceInfo = _linePromotionPrices[lineKey];
                      // baseTotal не используется в отображении — общий итог внизу
                      return FutureBuilder<List<_ExtraInfo>>(
                        future: _loadExtrasInfo(
                            cartItem.itemId, cartItem.extras, sizeId: cartItem.sizeId, sizeName: cartItem.size),
                        builder: (context, snap) {
                          final extras = snap.data ?? [];
                              // extrasCost не используется в отображении — выводим построчно
                          return FutureBuilder<List<_OptionInfo>>(
                            future: _loadOptionsInfo(cartItem.options),
                            builder: (context, osnap) {
                              final opts = osnap.data ?? [];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: appTheme.cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Основная строка: слева позиция, справа цена позиции (за 1 шт.)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  () {
                                                    // Специальная обработка Bundle: скрываем содержимое скобок и префиксы
                                                    String rawName = cartItem.name;
                                                    if (cartItem.meta != null && cartItem.meta!['type'] == 'bundle') {
                                                      // Удаляем любые (...) и [...] вместе с содержимым
                                                      rawName = rawName.replaceAll(RegExp(r'\([^)]*\)'), '')
                                                                       .replaceAll(RegExp(r'\[[^]]*\]'), '')
                                                                       .replaceAll(RegExp(r'\s{2,}'), ' ')
                                                                       .trim();
                                                    }
                                                    final articlePrefix = (cartItem.article != null && cartItem.meta?['type'] != 'bundle')
                                                        ? '[${cartItem.article!}] '
                                                        : '';
                                                    final hasMulti = _hasSizes[cartItem.itemId] ?? true;
                                                    final sizeSuffix = (hasMulti && cartItem.size.trim().isNotEmpty && cartItem.meta?['type'] != 'bundle')
                                                        ? ' (${cartItem.size})'
                                                        : '';
                                                    return '$count × $articlePrefix$rawName$sizeSuffix';
                                                  }(),
                                                  style: GoogleFonts.poppins(
                                                    color: appTheme.textColor,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                // Детализация состава Bundle
                                                if (cartItem.meta != null && cartItem.meta!['type'] == 'bundle') ...[
                                                  const SizedBox(height: 6),
                                                  ..._buildBundleComposition(cartItem.meta!),
                                                ],
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              if (priceInfo != null)
                                                PriceWithPromotion(
                                                  basePrice: priceInfo.basePrice,
                                                  finalPrice: priceInfo.finalPrice,
                                                  formatter: (value) => '€${value.toStringAsFixed(2)}',
                                                  finalStyle: GoogleFonts.poppins(
                                                    color: appTheme.textColor,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  baseStyle: GoogleFonts.poppins(
                                                    color: appTheme.textColor.withValues(alpha: 0.65),
                                                    fontSize: 13,
                                                  ),
                                                  alignment: MainAxisAlignment.end,
                                                )
                                              else
                                                Text(
                                                  '€${cartItem.basePrice.toStringAsFixed(2)}',
                                                  style: GoogleFonts.poppins(
                                                    color: appTheme.textColor,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              const SizedBox(height: 4),
                                              _qtyStepper(
                                                qty: count,
                                                onDec: () async {
                                                  await CartService.removeItem(cartItem);
                                                  await _recalculateTotal();
                                                  if (mounted) setState(() {});
                                                },
                                                onInc: () async {
                                                  await CartService.addItem(cartItem);
                                                  await _recalculateTotal();
                                                  if (mounted) setState(() {});
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      // --- ДОПОЛНЕНИЯ ---
                                      if (extras.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        ...extras.map((e) => Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${e.quantity} × ${e.name}',
                                                    style: GoogleFonts.poppins(
                                                      color: appTheme.textColorSecondary,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    Text(
                                                      '+€${e.price.toStringAsFixed(2)}',
                                                      style: GoogleFonts.poppins(
                                                        color: appTheme.textColorSecondary,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    _qtyStepper(
                                                      qty: e.quantity,
                                                      onDec: () => _changeExtraQty(cartItem, e.id, (e.quantity - 1).clamp(0, 9999)),
                                                      onInc: () => _changeExtraQty(cartItem, e.id, e.quantity + 1),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            )),
                                      ],
                                      // --- ОПЦИИ ---
                                      if (opts.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        ...opts.map((o) => Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '${o.quantity} × ${o.name}',
                                                    style: GoogleFonts.poppins(
                                                      color: appTheme.textColorSecondary,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Модификаторы (опции) теперь нередактируемы в корзине: без степпера.
                                                if (o.priceDelta != 0)
                                                  Text(
                                                    '+€${o.priceDelta.toStringAsFixed(2)}',
                                                    style: GoogleFonts.poppins(
                                                      color: appTheme.textColorSecondary,
                                                      fontSize: 13,
                                                    ),
                                                  )
                                                else
                                                  const SizedBox.shrink(),
                                              ],
                                            )),
                                      ],
                                      const SizedBox(height: 8),
                                    ],
                                  ),
                                ),
                                const SizedBox.shrink(),
                              ],
                            ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),

          SafeArea(
            top: false,
            child: Container(
              color: appTheme.backgroundColor,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_totalDiscount > 0) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Rabatt:',
                            style: GoogleFonts.poppins(
                                color: appTheme.primaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        Text('-€${_totalDiscount.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                                color: appTheme.primaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _totalDiscount > 0 ? 'Gesamt (inkl. Rabatt):' : 'Gesamt:',
                        style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18),
                      ),
                      Text(
                        '€${_totalSum.toStringAsFixed(2)}',
                        style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: appTheme.buttonColor,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    onPressed: lines.isEmpty
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Ihr Warenkorb ist leer. Bitte fügen Sie Artikel hinzu.',
                                  style: TextStyle(color: appTheme.textColor),
                                ),
                                backgroundColor: appTheme.primaryColor,
                              ),
                            );
                          }
                        : () {
                            final comments = _commentControllers
                                .map((k, v) => MapEntry(k, v.text.trim()));
                            final roundedTotal =
                                double.parse(_totalSum.toStringAsFixed(2));
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CheckoutScreen(
                                  totalSum: roundedTotal,
                                  itemComments: comments,
                                  totalDiscount: _totalDiscount,
                                  appliedDiscounts: _appliedDiscounts,
                                ),
                              ),
                            );
                          },
                    child: Text('Zur Kasse',
                        style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on _CartScreenState {
  // Построить строки состава бандла по meta
  List<Widget> _buildBundleComposition(Map<String, dynamic> meta) {
    final appTheme = ThemeProvider.of(context);
    final slots = (meta['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
    final widgets = <Widget>[];
    for (final slot in slots) {
      final slotName = (slot['name'] as String?) ?? '';
      final items = (slot['items'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
      if (items.isEmpty) continue;
      // строка с названием слота
      widgets.add(Text(
        slotName,
        style: GoogleFonts.poppins(
          color: appTheme.textColorSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ));
      // элементы внутри слота
      for (final it in items) {
        final name = (it['itemName'] as String?) ?? '';
        final sizeName = (it['sizeName'] as String?) ?? '';
        final extraNames = (it['extraNames'] as List?)?.cast<String>() ?? const <String>[];
        final optionNames = (it['optionNames'] as List?)?.cast<String>() ?? const <String>[];
        final sizePart = sizeName.isNotEmpty ? ' ($sizeName)' : '';
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, top: 2),
          child: Text(
            '• $name$sizePart',
            style: GoogleFonts.poppins(
              color: appTheme.textColorSecondary,
              fontSize: 13,
            ),
          ),
        ));
        // Детали выбора: платные Extras/модификаторы построчно
        final detailEntries = (it['detailEntries'] as List?)?.cast<Map<String, dynamic>>() ?? const <Map<String, dynamic>>[];
        if (detailEntries.isNotEmpty) {
          for (final d in detailEntries) {
            final name = (d['name'] as String?) ?? '';
            final charged = (d['charged'] as bool?) ?? false;
            final price = (d['price'] as num?)?.toDouble() ?? 0.0;
            widgets.add(Padding(
              padding: const EdgeInsets.only(left: 16, top: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '· $name',
                      style: GoogleFonts.poppins(
                        color: appTheme.textColorSecondary.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (charged && price > 0)
                    Text(
                      '+€${price.toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(
                        color: appTheme.textColorSecondary,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ));
          }
        } else if (extraNames.isNotEmpty || optionNames.isNotEmpty) {
          // Fallback: если вдруг детализация отсутствует — прежний краткий вид
          final details = [
            if (optionNames.isNotEmpty) 'Optionen: ${optionNames.join(', ')}',
            if (extraNames.isNotEmpty) 'Extras: ${extraNames.join(', ')}',
          ].join('  •  ');
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 16, top: 1),
            child: Text(
              details,
              style: GoogleFonts.poppins(
                color: appTheme.textColorSecondary.withOpacity(0.85),
                fontSize: 12,
              ),
            ),
          ));
        }
      }
      widgets.add(const SizedBox(height: 4));
    }
    return widgets;
  }
}
