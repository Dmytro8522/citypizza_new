// lib/screens/recent_orders_carousel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_service.dart';
import '../widgets/animated_gradient_section.dart';
import '../widgets/no_internet_widget.dart';

class RecentOrdersCarousel extends StatefulWidget {
  const RecentOrdersCarousel({super.key});

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

      final rawOrders = await supabase
          .from('orders')
          .select('id, created_at, total_sum')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(5);
      final ordersList = (rawOrders as List).cast<Map<String, dynamic>>();
      final orderIds = ordersList
          .map((o) => (o['id'] as int?) ?? 0)
          .where((id) => id != 0)
          .toList();

      final List<dynamic> rawItems = orderIds.isNotEmpty
          ? await supabase
              .from('order_items')
              .select('*')
              .filter('order_id', 'in', '(${orderIds.join(',')})')
          : <dynamic>[];
      final itemsList = rawItems.cast<Map<String, dynamic>>();

      final menuIds = itemsList
          .map((it) => ((it['menu_v2_item_id'] as int?) ??
              (it['menu_item_id'] as int?) ??
              0))
          .where((id) => id != 0)
          .toSet()
          .toList();
      final hasSizes = <int, bool>{};
      if (menuIds.isNotEmpty) {
        final rawMenu = await supabase
            .from('menu_v2_item')
            .select('id, has_sizes')
            .filter('id', 'in', '(${menuIds.join(',')})');
        for (final m in (rawMenu as List).cast<Map<String, dynamic>>()) {
          final mid = (m['id'] as int?) ?? 0;
          if (mid != 0) hasSizes[mid] = (m['has_sizes'] as bool?) ?? false;
        }
      }

      final sizeIds = itemsList
          .map((it) => it['size_id'] as int?)
          .where((id) => id != null && id != 0)
          .cast<int>()
          .toSet()
          .toList();
      final sizeNames = <int, String>{};
      if (sizeIds.isNotEmpty) {
        final rawSizes = await supabase
            .from('menu_size')
            .select('id, name')
            .filter('id', 'in', '(${sizeIds.join(',')})');
        for (final s in (rawSizes as List).cast<Map<String, dynamic>>()) {
          final sid = (s['id'] as int?) ?? 0;
          if (sid != 0) sizeNames[sid] = (s['name'] as String?) ?? '';
        }
      }

      final itemIds = itemsList
          .map((it) => (it['id'] as int?) ?? 0)
          .where((id) => id != 0)
          .toList();

      final extrasBy = <int, List<Map<String, dynamic>>>{};
      if (itemIds.isNotEmpty) {
        final rawExtras = await supabase
            .from('order_item_extras')
            .select('*')
            .filter('order_item_id', 'in', '(${itemIds.join(',')})');
        final extraIds = (rawExtras as List)
            .map((e) => ((e['menu_v2_extra_id'] as int?) ??
                (e['extra_id'] as int?) ??
                0))
            .where((id) => id != 0)
            .toSet()
            .toList();

        final extraNames = <int, String>{};
        if (extraIds.isNotEmpty) {
          final rawExtraNames = await supabase
              .from('menu_v2_extra')
              .select('id, name')
              .filter('id', 'in', '(${extraIds.join(',')})');
          for (final e
              in (rawExtraNames as List).cast<Map<String, dynamic>>()) {
            final eid = (e['id'] as int?) ?? 0;
            if (eid != 0) extraNames[eid] = (e['name'] as String?) ?? '';
          }
        }

        for (final e in (rawExtras as List).cast<Map<String, dynamic>>()) {
          final pid = (e['order_item_id'] as int?) ?? 0;
          if (pid == 0) continue;
          final resolvedExtraId =
              (e['menu_v2_extra_id'] as int?) ?? (e['extra_id'] as int?) ?? 0;
          extrasBy.putIfAbsent(pid, () => []).add({
            ...e,
            'extra_name': extraNames[resolvedExtraId] ?? '',
            'resolved_extra_id': resolvedExtraId,
          });
        }
      }

      final optionsBy = <int, List<Map<String, dynamic>>>{};
      if (itemIds.isNotEmpty) {
        final rawOpts = await supabase
            .from('order_item_options')
            .select('*')
            .filter('order_item_id', 'in', '(${itemIds.join(',')})');
        final optionIds = (rawOpts as List)
            .map((o) => ((o['modifier_option_id'] as int?) ??
                (o['option_id'] as int?) ??
                0))
            .where((id) => id != 0)
            .toSet()
            .toList();

        final optionNames = <int, Map<String, dynamic>>{};
        if (optionIds.isNotEmpty) {
          final rawOptionNames = await supabase
              .from('menu_v2_modifier_option')
              .select('id, name')
              .filter('id', 'in', '(${optionIds.join(',')})');
          for (final r
              in (rawOptionNames as List).cast<Map<String, dynamic>>()) {
            final id = (r['id'] as int?) ?? 0;
            if (id != 0) {
              optionNames[id] = {
                'name': (r['name'] as String?) ?? '',
                'price_delta': 0.0,
              };
            }
          }
        }

        for (final o in (rawOpts as List).cast<Map<String, dynamic>>()) {
          final pid = (o['order_item_id'] as int?) ?? 0;
          if (pid == 0) continue;
          final oid = (o['modifier_option_id'] as int?) ??
              (o['option_id'] as int?) ??
              0;
          final meta = optionNames[oid] ?? const {};
          final resolvedName = (meta['name'] as String?) ?? '';
          final resolvedDelta = (o['price_delta'] as num?)?.toDouble() ??
              (meta['price_delta'] as num?)?.toDouble() ??
              0.0;
          optionsBy.putIfAbsent(pid, () => []).add({
            ...o,
            'option_name': resolvedName,
            'resolved_price_delta': resolvedDelta,
            'resolved_option_id': oid,
          });
        }
      }

      final grouped = <int, List<Map<String, dynamic>>>{};
      for (final it in itemsList) {
        final oid = (it['order_id'] as int?) ?? 0;
        if (oid == 0) continue;
        grouped.putIfAbsent(oid, () => []).add(it);
      }

      final result = ordersList.map((o) {
        final rawIts =
            grouped[(o['id'] as int?) ?? 0] ?? <Map<String, dynamic>>[];
        final enriched = rawIts.map((it) {
          final sid = it['size_id'] as int?;
          final resolvedMid = (it['menu_v2_item_id'] as int?) ??
              (it['menu_item_id'] as int?) ??
              0;
          final showSize = (sid != null) && (hasSizes[resolvedMid] == true);
          return {
            ...it,
            'size_name': showSize && sizeNames.containsKey(sid)
                ? (sizeNames[sid] ?? '')
                : '',
            'size_label': showSize && sizeNames.containsKey(sid)
                ? ' (${sizeNames[sid]})'
                : '',
            'extras':
                extrasBy[(it['id'] as int?) ?? 0] ?? <Map<String, dynamic>>[],
            'options':
                optionsBy[(it['id'] as int?) ?? 0] ?? <Map<String, dynamic>>[],
            'resolved_menu_item_id': resolvedMid,
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showOrderDetails(Map<String, dynamic> order) {
    final items = order['items'] as List<Map<String, dynamic>>;
    final dt = DateTime.parse((order['created_at'] as String?) ?? '');
    final dateStr = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.${dt.year}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                    style:
                        GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                  ),
                  if ((it['extras'] as List).isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 8, top: 4, bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final ex in it['extras'] as List)
                            Text(
                              '+ ${ex['extra_name']}'
                              '${(((ex['quantity'] as int?) ?? 0) > 1) ? ' x${ex['quantity']}' : ''}'
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
                  if ((it['options'] as List).isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(left: 8, top: 0, bottom: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final op in it['options'] as List)
                            Text(
                              '+ ${op['option_name']}'
                              '${(((op['quantity'] as int?) ?? 0) > 1) ? ' x${op['quantity']}' : ''}'
                              '${(op['resolved_price_delta'] != null && (op['resolved_price_delta'] as num) != 0) ? ', ${(op['resolved_price_delta'] as num).toStringAsFixed(2)} €' : ''}',
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
                        style: GoogleFonts.poppins(
                            color: Colors.white54, fontSize: 14),
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
                          final id = (ex['resolved_extra_id'] as int?) ??
                              (ex['menu_v2_extra_id'] as int?) ??
                              (ex['extra_id'] as int?);
                          final qty = ex['quantity'] as int? ?? 1;
                          if (id != null) extras[id] = qty;
                        }
                        final options = <int, int>{};
                        for (final op in it['options'] as List) {
                          final id = (op['resolved_option_id'] as int?) ??
                              (op['modifier_option_id'] as int?) ??
                              (op['option_id'] as int?);
                          final qty = op['quantity'] as int? ?? 1;
                          if (id != null) options[id] = qty;
                        }
                        CartService.addItem(
                          CartItem(
                            itemId: (it['resolved_menu_item_id'] as int?) ??
                                (it['menu_v2_item_id'] as int?) ??
                                (it['menu_item_id'] as int?) ??
                                0,
                            name: (it['item_name'] as String?) ?? '',
                            size: (it['size_name'] as String?) ?? '',
                            basePrice: (it['price'] as num).toDouble(),
                            extras: extras,
                            options: options,
                            article: it['article'] as String?,
                            sizeId: it['size_id'] as int?,
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

    final cards = <Widget>[];
    for (var i = 0; i < _orders.length; i++) {
      cards.add(_buildOrderCard(_orders[i]));
      if (i != _orders.length - 1) {
        cards.add(const SizedBox(width: 12));
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: cards,
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final dt = DateTime.parse((order['created_at'] as String?) ?? '');
    final dateStr =
        '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    final items = order['items'] as List<Map<String, dynamic>>;
    const previewCount = 2;
    final preview = items.take(previewCount).toList();
    final moreCount = items.length - preview.length;

    final previewLines = <Widget>[];
    for (var j = 0; j < preview.length; j++) {
      final it = preview[j];
      previewLines.add(
        Text(
          '${it['quantity']}× '
          '${(it['article'] != null ? '[${it['article']}] ' : '')}'
          '${it['item_name']}${it['size_label']} – '
          '${(it['price'] as num).toStringAsFixed(2)} €',
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
      if (j != preview.length - 1) {
        previewLines.add(const SizedBox(height: 6));
      }
    }

    return Container(
      width: 240,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  style:
                      GoogleFonts.poppins(color: Colors.white70, fontSize: 10),
                ),
              ),
              const Spacer(),
              IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.info_outline,
                    color: Colors.orangeAccent, size: 28),
                onPressed: () => _showOrderDetails(order),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...previewLines,
                if (moreCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: Colors.orangeAccent.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+$moreCount mehr',
                          style: GoogleFonts.poppins(
                            color: Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
                    final id = (ex['resolved_extra_id'] as int?) ??
                        (ex['menu_v2_extra_id'] as int?) ??
                        (ex['extra_id'] as int?);
                    final qty = ex['quantity'] as int? ?? 1;
                    if (id != null) extras[id] = qty;
                  }
                  final options = <int, int>{};
                  for (final op in it['options'] as List) {
                    final id = (op['resolved_option_id'] as int?) ??
                        (op['modifier_option_id'] as int?) ??
                        (op['option_id'] as int?);
                    final qty = op['quantity'] as int? ?? 1;
                    if (id != null) options[id] = qty;
                  }
                  CartService.addItem(
                    CartItem(
                      itemId: (it['resolved_menu_item_id'] as int?) ??
                          (it['menu_v2_item_id'] as int?) ??
                          (it['menu_item_id'] as int?) ??
                          0,
                      name: (it['item_name'] as String?) ?? '',
                      size: (it['size_name'] as String?) ?? '',
                      basePrice: (it['price'] as num).toDouble(),
                      extras: extras,
                      options: options,
                      article: it['article'] as String?,
                      sizeId: it['size_id'] as int?,
                    ),
                  );
                }
                Navigator.pushNamed(context, '/cart');
              },
              child: Text(
                'One-Tap Reorder',
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Обёртка-секция с градиентом
class RecentOrdersSection extends StatefulWidget {
  const RecentOrdersSection({super.key});

  @override
  State<RecentOrdersSection> createState() => _RecentOrdersSectionState();
}

class _RecentOrdersSectionState extends State<RecentOrdersSection> {
  final _supabase = Supabase.instance.client;
  bool _hasOrders = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _quickCheck();
  }

  Future<void> _quickCheck() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _checked = true;
        _hasOrders = false;
      });
      return;
    }
    try {
      final rows = await _supabase
          .from('orders')
          .select('id')
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(1);
      final list = (rows as List);
      if (!mounted) return;
      setState(() {
        _hasOrders = list.isNotEmpty;
        _checked = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOrders = false;
        _checked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (!_hasOrders) return const SizedBox.shrink();
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
      gradients: const [
        [Color(0x552C3E7B), Color(0x443F51B5)],
        [Color(0x553F51B5), Color(0x552C3E7B)],
        [Color(0x552C3E7B), Color(0x553F51B5)],
      ],
      child: const RecentOrdersCarousel(),
    );
  }
}
