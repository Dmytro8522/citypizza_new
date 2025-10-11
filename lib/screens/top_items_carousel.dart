// lib/screens/top_items_carousel.dart

import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/cart_service.dart';   // CartService & CartItem
import 'home_screen.dart';               // MenuItem, AnimatedGradientSection
import '../widgets/no_internet_widget.dart';

/// Маленькая анимированная иконка огонька
class AnimatedFireIcon extends StatefulWidget {
  final double size;
  final Color color;
  const AnimatedFireIcon({
    Key? key,
    this.size = 22,
    this.color = Colors.orange,
  }) : super(key: key);

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
class TopItemsSection extends StatelessWidget {
  final void Function(MenuItem item) onTap;
  const TopItemsSection({Key? key, required this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
      gradients: [
        [const Color(0x552C3E7B), const Color(0x443F51B5)],
        [const Color(0x553F51B5), const Color(0x552C3E7B)],
        [const Color(0x552C3E7B), const Color(0x553F51B5)],
      ],
      child: SizedBox(
        height: 180,
        child: TopItemsCarousel(onTap: onTap),
      ),
    );
  }
}

/// Горизонтальная карусель топ-блюд
class TopItemsCarousel extends StatefulWidget {
  final void Function(MenuItem item) onTap;
  const TopItemsCarousel({Key? key, required this.onTap}) : super(key: key);

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
      final raw = await supabase.from('order_items').select('menu_item_id');
      final all = (raw as List).cast<Map<String, dynamic>>();
      final freq = <int, int>{};
      for (final r in all) {
        final id = r['menu_item_id'] as int;
        freq[id] = (freq[id] ?? 0) + 1;
      }
      if (freq.isEmpty) return;

      // 2) топ-10 ID
      final ids = freq.keys.toList()
        ..sort((a, b) => freq[b]!.compareTo(freq[a]!));
      final topIds = ids.take(10).toList();

      // 3) минимальные цены для многоразмерных
      final pp = await supabase
          .from('menu_item_price')
          .select('menu_item_id, price')
          .filter('menu_item_id', 'in', '(${topIds.join(",")})')
          .order('price', ascending: true);
      final priceList = (pp as List).cast<Map<String, dynamic>>();
      final multiMin = <int, double>{};
      for (final row in priceList) {
        final mid = row['menu_item_id'] as int;
        final p = (row['price'] as num).toDouble();
        if (!multiMin.containsKey(mid) || p < multiMin[mid]!) {
          multiMin[mid] = p;
        }
      }

      // 4) читаем menu_item вместе с новыми полями
      final itemsRaw = await supabase
          .from('menu_item')
          .select('''
            id,
            name,
            description,
            image_url,
            article,
            has_multiple_sizes,
            single_size_price
          ''')
          .filter('id', 'in', '(${topIds.join(",")})');
      final rawList = (itemsRaw as List).cast<Map<String, dynamic>>();

      // 5) собираем результат в локальную переменную
      final newItems = rawList.map((m) {
        final id = m['id'] as int;
        final hasMulti = m['has_multiple_sizes'] as bool? ?? true;
        final singlePrice = m['single_size_price'] != null
            ? (m['single_size_price'] as num).toDouble()
            : null;
        final price = hasMulti
            ? (multiMin[id] ?? 0.0)
            : (singlePrice ?? 0.0);

        return MenuItem(
          id: id,
          name: m['name'] as String? ?? '',
          description: m['description'] as String?,
          imageUrl: m['image_url'] as String?,
          article: m['article'] as String?,
          klein: null,
          normal: null,
          gross: null,
          familie: null,
          party: null,
          minPrice: price,
          hasMultipleSizes: hasMulti,
          singleSizePrice: singlePrice,
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
        height: 180,
        child: NoInternetWidget(
          onRetry: _loadTopItems,
          errorText: _error,
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();
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
            width: 140,
            margin: EdgeInsets.only(left: ml, right: 4),
            child: Stack(
              children: [
                // картинка
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: item.imageUrl != null
                      ? Image.network(item.imageUrl!,
                          fit: BoxFit.cover, width: 140, height: 140)
                      : Container(
                          width: 140, height: 140, color: Colors.white10),
                ),
                // огонёк
                const Positioned(
                  top: 8,
                  right: 8,
                  child:
                      AnimatedFireIcon(size: 20, color: Colors.orangeAccent),
                ),
                // градиент снизу
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: 60,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                  ),
                ),
                // подпись + цена + кнопка
                Positioned(
                  bottom: 8,
                  left: 12,
                  right: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.article != null ? '[${item.article}] ' : ''}${item.name}',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.hasMultipleSizes
                                  ? 'ab ${item.minPrice.toStringAsFixed(2)} €'
                                  : '${item.minPrice.toStringAsFixed(2)} €',
                              style: GoogleFonts.poppins(
                                  color: Colors.orangeAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          CartService.addItem(CartItem(
                            itemId: item.id,
                            name: item.name,
                            size: item.hasMultipleSizes ? 'Standard' : 'Normal',
                            basePrice: item.minPrice,
                            extras: {},
                            article: item.article,
                            sizeId: item.hasMultipleSizes ? null : 2,
                          ));
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: Colors.deepOrange,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.add_shopping_cart,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ],
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
