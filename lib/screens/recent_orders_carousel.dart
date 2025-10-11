// lib/widgets/recent_orders_carousel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_service.dart';
import 'home_screen.dart'; // для AnimatedGradientSection
import '../widgets/no_internet_widget.dart';

class RecentOrdersCarousel extends StatefulWidget {
  const RecentOrdersCarousel({Key? key}) : super(key: key);

  @override
  State<RecentOrdersCarousel> createState() => _RecentOrdersCarouselState();
}

class _RecentOrdersCarouselState extends State<RecentOrdersCarousel> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      // 1) последние 5 заказов
      final rawOrders = await supabase
          .from('orders')
          .select('id, created_at, total_sum')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);
      final ordersList = (rawOrders as List).cast<Map<String, dynamic>>();
      final orderIds = ordersList.map((o) => o['id'] as int).toList();

      // 2) все позиции по этим заказам
      final rawItems = await supabase
          .from('order_items')
          .select(
            'id, order_id, menu_item_id, item_name, size_id, quantity, price, item_comment, article',
          )
          .filter('order_id', 'in', orderIds);
      final itemsList = (rawItems as List).cast<Map<String, dynamic>>();

      // 3) подтягиваем картинки из menu_item
      final menuIds = itemsList.map((it) => it['menu_item_id'] as int).toSet().toList();
      final imageUrls = <int, String?>{};
      if (menuIds.isNotEmpty) {
        final rawMenu = await supabase
            .from('menu_item')
            .select('id, image_url')
            .filter('id', 'in', menuIds);
        for (final m in (rawMenu as List)) {
          imageUrls[m['id'] as int] = m['image_url'] as String?;
        }
      }

      // 4) названия размеров
      final sizeIds = itemsList
          .map((it) => it['size_id'] as int?)
          .where((i) => i != null)
          .cast<int>()
          .toSet()
          .toList();
      final sizeNames = <int, String>{};
      if (sizeIds.isNotEmpty) {
        final rawSizes = await supabase
            .from('menu_size')
            .select('id, name')
            .filter('id', 'in', sizeIds);
        for (final s in (rawSizes as List)) {
          sizeNames[s['id'] as int] = s['name'] as String;
        }
      }

      // 5) добавки
      final itemIds = itemsList.map((it) => it['id'] as int).toList();
      final extrasBy = <int, List<Map<String, dynamic>>>{};
      if (itemIds.isNotEmpty) {
        final rawExtras = await supabase
            .from('order_item_extras')
            .select('order_item_id, extra_id, quantity, price')
            .filter('order_item_id', 'in', itemIds);
        final extraIds = (rawExtras as List)
            .map((e) => e['extra_id'] as int)
            .toSet()
            .toList();

        final extraNames = <int, String>{};
        if (extraIds.isNotEmpty) {
          final rawExtraNames = await supabase
              .from('menu_extra')
              .select('id, name')
              .filter('id', 'in', extraIds);
          for (final e in (rawExtraNames as List)) {
            extraNames[e['id'] as int] = e['name'] as String;
          }
        }

        for (final e in (rawExtras as List)) {
          final pid = e['order_item_id'] as int;
          extrasBy.putIfAbsent(pid, () => []).add({
            ...e,
            'extra_name': extraNames[e['extra_id'] as int] ?? '',
          });
        }
      }

      // 6) группируем по заказам
      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final it in itemsList) {
        grouped.putIfAbsent(it['order_id'] as int, () => []).add(it);
      }

      // 7) собираем итоговый список
      final result = ordersList.map((o) {
        final rawIts = grouped[o['id']] ?? [];
        final enriched = rawIts.map((it) {
          final sid = it['size_id'] as int?;
          return {
            ...it,
            'size_label': sid != null && sizeNames.containsKey(sid) ? ' (${sizeNames[sid]})' : '',
            'extras': extrasBy[it['id'] as int] ?? [],
            'image_url': imageUrls[it['menu_item_id'] as int],
          };
        }).toList();
        return {
          'id': o['id'],
          'created_at': o['created_at'],
          'total_sum': o['total_sum'],
          'items': enriched,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _orders = result;
        _loading = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _error = 'Keine Internetverbindung';
        _loading = false;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
      return;
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['items'] as List<Map<String, dynamic>>;
    final dt = DateTime.parse(order['created_at'] as String);
    final dateStr = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  'Bestellung vom $dateStr',
                  style: GoogleFonts.poppins(
                    color: Colors.orange,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final it in items) ...[
                  Text(
                    '${it['quantity']}× ${(it['article'] != null ? '[${it['article']}] ' : '')}'
                    '${it['item_name']}${it['size_label']} – '
                    '${(it['price'] as num).toStringAsFixed(2)} €',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                  ),
                  if ((it['extras'] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final ex in it['extras'] as List)
                            Text(
                              '+ ${ex['extra_name']}'
                              '${(ex['quantity'] as int) > 1 ? ' x${ex['quantity']}' : ''}'
                              '${(ex['price'] != null) ? ', ${(ex['price'] as num).toStringAsFixed(2)} €' : ''}',
                              style: GoogleFonts.poppins(
                                color: Colors.orange,
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    ),
                  if ((it['item_comment'] as String?)?.isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '„${it['item_comment']}“',
                        style:
                            GoogleFonts.poppins(color: Colors.white54, fontSize: 14),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onPressed: () {
                      for (final it in items) {
                        final extras = <int, int>{};
                        for (final ex in it['extras'] as List) {
                          final id = ex['extra_id'] as int?;
                          final qty = ex['quantity'] as int? ?? 1;
                          if (id != null) extras[id] = qty;
                        }
                        CartService.addItem(
                          CartItem(
                            itemId: it['menu_item_id'] as int,
                            name: it['item_name'] as String,
                            size: it['size_label'] ?? '',
                            basePrice: (it['price'] as num).toDouble(),
                            extras: extras,
                            article: it['article'] as String?,
                          ),
                        );
                      }
                      Navigator.pushNamed(context, '/cart');
                    },
                    child: Text(
                      'Erneut bestellen',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: NoInternetWidget(
          onRetry: _loadRecent,
          errorText: _error,
        ),
      );
    }
    if (_orders.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (ctx, i) {
        final o = _orders[i];
        final dt = DateTime.parse(o['created_at'] as String);
        final dateStr =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
        final items = o['items'] as List<Map<String, dynamic>>;
        final previewCount = 2;
        final preview = items.take(previewCount).toList();
        final moreCount = items.length - preview.length;
        final imageUrl = items.isNotEmpty ? items.first['image_url'] as String? : null;

        return Container(
          width: 240,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6)],
          ),
          child: Column(
            children: [
              // шапка
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      dateStr,
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 28),
                    onPressed: () => _showOrderDetails(o),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // строка: картинка + текст
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // картинка
                  if (imageUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.local_pizza, size: 32, color: Colors.white38),
                    ),

                  const SizedBox(width: 16),

                  // текстовый блок с фоном и fade
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (final it in preview) ...[
                                  Text(
                                    '${it['quantity']}× '
                                    '${(it['article'] != null ? '[${it['article']}] ' : '')}'
                                    '${it['item_name']}${it['size_label']} – '
                                    '${(it['price'] as num).toStringAsFixed(2)} €',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                ],
                              ],
                            ),
                            if (moreCount > 0) ...[
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 2,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: Text(
                                  '+$moreCount mehr',
                                  style: GoogleFonts.poppins(
                                    color: Colors.orangeAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // кнопка сразу под картинкой/текстом
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  onPressed: () {
                    for (final it in items) {
                      final extras = <int, int>{};
                      for (final ex in it['extras'] as List) {
                        final id = ex['extra_id'] as int?;
                        final qty = ex['quantity'] as int? ?? 1;
                        if (id != null) extras[id] = qty;
                      }
                      CartService.addItem(
                        CartItem(
                          itemId: it['menu_item_id'] as int,
                          name: it['item_name'] as String,
                          size: it['size_label'] ?? '',
                          basePrice: (it['price'] as num).toDouble(),
                          extras: extras,
                          article: it['article'] as String?,
                        ),
                      );
                    }
                    Navigator.pushNamed(context, '/cart');
                  },
                  child: Text(
                    'One-Tap Reorder',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Обёртка-секция с градиентом
class RecentOrdersSection extends StatelessWidget {
  const RecentOrdersSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const SizedBox.shrink();
    return AnimatedGradientSection(
      title: Row(
        children: [
          const Icon(Icons.history, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            'Kürzlich bestellt',
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
        height: 220, // скорректировали под новую верстку
        child: const RecentOrdersCarousel(),
      ),
    );
  }
}
