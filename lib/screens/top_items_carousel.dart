// lib/screens/top_items_carousel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cart_service.dart'; // CartService & CartItem
import '../models/menu_item.dart'; // MenuItem model
import '../widgets/animated_gradient_section.dart';
import '../widgets/no_internet_widget.dart';
import '../theme/theme_provider.dart';
// removed unused imports

/// Маленькая анимированная иконка огонька
class AnimatedFireIcon extends StatefulWidget {
  final double size;
  final Color color;
  const AnimatedFireIcon({
    super.key,
    this.size = 22,
    this.color = Colors.orange,
  });

  @override
  _AnimatedFireIconState createState() => _AnimatedFireIconState();
}

class _AnimatedFireIconState extends State<AnimatedFireIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _anim,
      child: Icon(
        Icons.local_fire_department,
        color: widget.color,
        size: widget.size,
      ),
    );
  }
}

/// Секция "Beliebte Gerichte" с градиентным фоном
class TopItemsSection extends StatefulWidget {
  final void Function(MenuItem item) onTap;
  const TopItemsSection({super.key, required this.onTap});

  @override
  State<TopItemsSection> createState() => _TopItemsSectionState();
}

class _TopItemsSectionState extends State<TopItemsSection> {
  final _supabase = Supabase.instance.client;
  bool _checked = false;
  bool _hasItems = false;

  @override
  void initState() {
    super.initState();
    _quickCheck();
  }

  Future<void> _quickCheck() async {
    try {
      dynamic raw;
      try {
        raw = await _supabase
            .from('order_items')
            .select('menu_v2_item_id, menu_item_id')
            .limit(1);
      } catch (_) {
        raw =
            await _supabase.from('order_items').select('menu_item_id').limit(1);
      }
      final list = (raw as List).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _checked = true;
          _hasItems = false;
        });
        return;
      }
      // Вторичная проверка: исключаем напитки (берём до 1 популярного блюда)
      final cats = await _supabase.from('menu_v2_category').select('id,name');
      final drinkCatIds = <int>{};
      for (final c in (cats as List).cast<Map<String, dynamic>>()) {
        final id = (c['id'] as int?) ?? 0;
        final nameRaw = (c['name'] as String?) ?? '';
        final name = nameRaw.toLowerCase();
        final normalized = name
            .replaceAll('ä', 'ae')
            .replaceAll('ö', 'oe')
            .replaceAll('ü', 'ue')
            .replaceAll('ß', 'ss');
        final lowerTrim = name.trim();
        final equalsDrink = lowerTrim == 'alkoholfreie getränke' ||
            lowerTrim == 'alkoholische getränke' ||
            normalized.trim() == 'alkoholfreie getraenke' ||
            normalized.trim() == 'alkoholische getraenke';
        final matchesDrink = equalsDrink ||
            name.contains('getränk') ||
            normalized.contains('getraenk') ||
            name.contains('drinks') ||
            name.contains('drink') ||
            name.contains('alkohol') ||
            name.contains('bier') ||
            name.contains('wein') ||
            name.contains('cola') ||
            name.contains('saft') ||
            name.contains('wasser') ||
            name.contains('limo');
        if (matchesDrink) drinkCatIds.add(id);
      }
      // Проверяем есть ли хотя бы одно блюдо не напиток среди order_items
      final firstRow = list.first;
      final firstId = (firstRow['menu_v2_item_id'] as int?) ??
          (firstRow['menu_item_id'] as int?) ??
          0;
      bool show = false;
      if (firstId != 0) {
        final item = await _supabase
            .from('menu_v2_item')
            .select('id, category_id, name, description, sku')
            .eq('id', firstId)
            .maybeSingle();
        if (item != null) {
          final cid = (item['category_id'] as int?) ?? -1;
          final name = (item['name'] as String?)?.toLowerCase() ?? '';
          final desc = (item['description'] as String?)?.toLowerCase() ?? '';
          final sku = (item['sku'] as String?)?.toLowerCase() ?? '';
          bool looksDrink(String s) =>
              s.contains('cola') ||
              s.contains('bier') ||
              s.contains('wein') ||
              s.contains('saft') ||
              s.contains('wasser') ||
              s.contains('drink') ||
              s.contains('getränk') ||
              s.contains('getraenk') ||
              s.contains('limo');
          if (!drinkCatIds.contains(cid) &&
              !looksDrink(name) &&
              !looksDrink(desc) &&
              !looksDrink(sku)) {
            show = true;
          }
        }
      }
      setState(() {
        _checked = true;
        _hasItems = show;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checked = true;
        _hasItems = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (!_hasItems) return const SizedBox.shrink();
    return AnimatedGradientSection(
      title: Row(
        children: [
          const Icon(Icons.local_fire_department,
              color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            'Beliebte Gerichte',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      gradients: const [
        [Color(0x552C3E7B), Color(0x443F51B5)],
        [Color(0x553F51B5), Color(0x552C3E7B)],
        [Color(0x552C3E7B), Color(0x553F51B5)],
      ],
      child: SizedBox(
        height: 120,
        child: TopItemsCarousel(onTap: widget.onTap),
      ),
    );
  }
}

/// Горизонтальная карусель топ-блюд
class TopItemsCarousel extends StatefulWidget {
  final void Function(MenuItem item) onTap;
  const TopItemsCarousel({super.key, required this.onTap});

  @override
  State<TopItemsCarousel> createState() => _TopItemsCarouselState();
}

class _TopItemsCarouselState extends State<TopItemsCarousel> {
  final supabase = Supabase.instance.client;
  List<MenuItem> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTopItems();
  }

  Future<void> _loadTopItems() async {
    try {
      // 1) собираем частоту заказов
      dynamic raw;
      try {
        raw = await supabase
            .from('order_items')
            .select('menu_v2_item_id, menu_item_id');
      } catch (_) {
        raw = await supabase.from('order_items').select('menu_item_id');
      }
      final all = (raw as List).cast<Map<String, dynamic>>();
      final freq = <int, int>{};
      for (final r in all) {
        final id =
            (r['menu_v2_item_id'] as int?) ?? (r['menu_item_id'] as int?) ?? 0;
        if (id == 0) continue;
        freq[id] = (freq[id] ?? 0) + 1;
      }
      if (freq.isEmpty) return;

      // 2) топ-10 ID
      final ids = freq.keys.toList()
        ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
      final topIds = ids.take(10).toList();

      // 3) минимальные цены через unified view
      final pp = await supabase
          .from('menu_v2_item_prices')
          .select('item_id, price')
          .filter('item_id', 'in', '(${topIds.join(",")})');
      final priceList = (pp as List).cast<Map<String, dynamic>>();
      final multiMin = <int, double>{};
      for (final row in priceList) {
        final mid = (row['item_id'] as int?) ?? 0;
        final p = (row['price'] as num).toDouble();
        if (!multiMin.containsKey(mid) || p < multiMin[mid]!) multiMin[mid] = p;
      }

      // 3b) Подтянем категории (v2) и определим ID категорий напитков
      final cats = await supabase.from('menu_v2_category').select('id,name');
      final drinkCatIds = <int>{};
      for (final c in (cats as List).cast<Map<String, dynamic>>()) {
        final id = (c['id'] as int?) ?? 0;
        final nameRaw = (c['name'] as String?) ?? '';
        final name = nameRaw.toLowerCase();
        // простая эвристика по названию категории
        final normalized = name
            .replaceAll('ä', 'ae')
            .replaceAll('ö', 'oe')
            .replaceAll('ü', 'ue')
            .replaceAll('ß', 'ss');
        // точное совпадение для указанных категорий
        final lowerTrim = name.trim();
        final equalsDrink = lowerTrim == 'alkoholfreie getränke' ||
            lowerTrim == 'alkoholische getränke' ||
            normalized.trim() == 'alkoholfreie getraenke' ||
            normalized.trim() == 'alkoholische getraenke';

        final matchesDrink = equalsDrink ||
            name.contains('getränk') ||
            normalized.contains('getraenk') ||
            name.contains('drinks') ||
            name.contains('drink') ||
            name.contains('napit') /* translit */ ||
            name.contains('напит') ||
            name.contains('alkohol') ||
            name.contains('bier') ||
            name.contains('wein') ||
            name.contains('cola') ||
            name.contains('saft') ||
            name.contains('wasser') ||
            name.contains('limo') ||
            name.contains('softdrink') ||
            name.contains('beverage') ||
            name.contains('soda');
        if (matchesDrink) {
          drinkCatIds.add(id);
        }
      }

      // 4) читаем menu_v2_item вместе с category_id, на сервере исключим напиточные категории если известны
      final menuSel = supabase.from('menu_v2_item').select('''
            id,
            category_id,
            name,
            description,
            image_url,
            sku,
            has_sizes,
            is_active,
            is_available
          ''').filter('id', 'in', '(${topIds.join(",")})');
      if (drinkCatIds.isNotEmpty) {
        menuSel.not('category_id', 'in', '(${drinkCatIds.join(",")})');
      }
      final itemsRaw = await menuSel;
      final rawList = (itemsRaw as List).cast<Map<String, dynamic>>();
      // Исключаем напитки (двойная защита: по category_id и по текстовым признакам в названии)
      bool looksLikeDrink(String s) {
        final n = s.toLowerCase();
        return n.contains('cola') ||
            n.contains('fanta') ||
            n.contains('sprite') ||
            n.contains('wasser') ||
            n.contains('saft') ||
            n.contains('juice') ||
            n.contains('bier') ||
            n.contains('wein') ||
            n.contains('alkohol') ||
            n.contains('getränk') ||
            n.contains('getraenk') ||
            n.contains('drink') ||
            n.contains('drinks') ||
            n.contains('soda') ||
            n.contains('limo');
      }

      final filteredRaw = rawList.where((m) {
        final cid = (m['category_id'] as int?) ?? -1;
        if (drinkCatIds.contains(cid)) return false;
        final name = (m['name'] as String?) ?? '';
        final desc = (m['description'] as String?) ?? '';
        final sku = (m['sku'] as String?) ?? '';
        if (looksLikeDrink(name) || looksLikeDrink(desc) || looksLikeDrink(sku))
          return false;
        return true;
      }).toList();

      // 5) собираем результат в локальную переменную
      final newItems = filteredRaw.map((m) {
        final id = (m['id'] as int?) ?? 0;
        final hasMulti = m['has_sizes'] as bool? ?? true;
        // В v2 даже одноразмерные позиции имеют запись в size_price, берём минимальную цену для всех
        final price = (multiMin[id] ?? 0.0);

        return MenuItem(
          id: id,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          imageUrl: m['image_url'] as String?,
          article: m['sku'] as String?,
          klein: null,
          normal: null,
          gross: null,
          familie: null,
          party: null,
          minPrice: price,
          hasMultipleSizes: hasMulti,
          singleSizePrice: null,
        );
      }).toList();

      // перед setState проверяем, что State ещё смонтирован
      if (!mounted) return;
      setState(() {
        _items = newItems;
      });
    } on SocketException {
      setState(() {
        _error = 'Keine Internetverbindung';
      });
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SizedBox(
        height: 120,
        child: NoInternetWidget(
          onRetry: _loadTopItems,
          errorText: _error,
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();
    final appTheme = ThemeProvider.of(context);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 4, right: 8),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final ml = i == 0 ? 4.0 : 8.0;
        return GestureDetector(
          onTap: () => widget.onTap(item),
          child: Container(
            width: 150,
            margin: EdgeInsets.only(left: ml, right: 4),
            child: Stack(
              children: [
                // Фон карточки (компактный)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: appTheme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: appTheme.borderColor.withOpacity(0.2)),
                    ),
                  ),
                ),
                // Огонёк популярности
                Positioned(
                  top: 8,
                  right: 8,
                  child:
                      AnimatedFireIcon(size: 18, color: appTheme.primaryColor),
                ),
                // Контент: название, цена, кнопка
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${item.article != null ? '[${item.article}] ' : ''}${item.name}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: appTheme.textColor,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((item.description?.trim().isNotEmpty ?? false)) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.description!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: appTheme.textColorSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: appTheme.primaryColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item.hasMultipleSizes
                                    ? 'ab ${item.minPrice.toStringAsFixed(2)} €'
                                    : '${item.minPrice.toStringAsFixed(2)} €',
                                style: GoogleFonts.poppins(
                                  color: appTheme.primaryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () async {
                                await CartService.addItemById(item.id);
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: appTheme.primaryColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.add_shopping_cart,
                                    color: Colors.black, size: 16),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
