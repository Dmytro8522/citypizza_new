// lib/screens/order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/order_service.dart';
import '../utils/globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/no_internet_widget.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _futureOrders;

  // Кешируем имена блюд, размеров, добавок, чтобы не делать повторных запросов
  final Map<int, String> _menuItemNames = {};
  final Map<int, String> _sizeNames = {};
  final Map<int, String> _extraNames = {};
  final Map<int, Map<String, dynamic>> _optionMeta = {}; // id -> {name, price}
  final Map<int, bool> _hasSizes = {}; // menu item id -> has_sizes

  @override
  void initState() {
    super.initState();
    _futureOrders = OrderService.getOrderHistory();
  }

  Future<String> _getMenuItemName(int id) async {
    if (_menuItemNames.containsKey(id)) return _menuItemNames[id]!;
    final row = await Supabase.instance.client
        .from('menu_v2_item')
        .select('name, has_sizes')
        .eq('id', id)
        .maybeSingle();
    final name = row?['name'] as String? ?? '№$id';
    final hs = row?['has_sizes'] as bool? ?? false;
    _menuItemNames[id] = name;
    _hasSizes[id] = hs;
    return name;
  }

  Future<String> _getSizeName(int? id) async {
    if (id == null) return '';
    if (_sizeNames.containsKey(id)) return _sizeNames[id]!;
    final row = await Supabase.instance.client
        .from('menu_size')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    final name = row?['name'] as String? ?? '';
    _sizeNames[id] = name;
    return name;
  }

  Future<String> _getExtraName(int id) async {
    if (_extraNames.containsKey(id)) return _extraNames[id]!;
    final row = await Supabase.instance.client
        .from('menu_v2_extra')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    final name = row?['name'] as String? ?? '№$id';
    _extraNames[id] = name;
    return name;
  }

  Future<Map<String, dynamic>> _getOptionMeta(int id) async {
    if (id == 0) return {'name': 'Option', 'price': 0.0};
    if (_optionMeta.containsKey(id)) return _optionMeta[id]!;
    final row = await Supabase.instance.client
        .from('menu_v2_modifier_option')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    String name = '';
    double price = 0.0;
    if (row != null) {
      name = row['name'] as String? ?? '';
      price = 0.0;
    }
    final meta = {'name': name, 'price': price};
    _optionMeta[id] = meta;
    return meta;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => navigatorKey.currentState?.pop(),
        ),
        title: Text('Bestellhistorie',
            style: GoogleFonts.fredokaOne(color: Colors.orange)),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureOrders,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.orange));
          }
          if (snap.hasError) {
            return NoInternetWidget(
              onRetry: () {
                setState(() {
                  _futureOrders = OrderService.getOrderHistory();
                });
              },
              errorText: snap.error.toString().contains('SocketException')
                  ? 'Keine Internetverbindung'
                  : 'Fehler: ${snap.error}',
            );
          }
          final orders = snap.data!;
          if (orders.isEmpty) {
            return Center(
              child: Text('Keine Bestellungen gefunden',
                  style: GoogleFonts.poppins(color: Colors.white70)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, i) {
              final order = orders[i];
              final items =
                  (order['order_items'] as List).cast<Map<String, dynamic>>();
              return Card(
                color: Colors.white12,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bestellt am ${DateTime.parse(order['created_at']).toLocal().toString().substring(0, 16)}',
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ...items.map((it) {
                          final extras = (it['order_item_extras'] as List)
                              .cast<Map<String, dynamic>>();
                          final resolvedItemId =
                              (it['menu_v2_item_id'] as int?) ??
                                  (it['menu_item_id'] as int?) ??
                                  0;
                          return FutureBuilder(
                            future: Future.wait([
                              _getMenuItemName(resolvedItemId),
                              _getSizeName(it['size_id'] as int?),
                            ]),
                            builder: (context,
                                AsyncSnapshot<List<String>> menuSnap) {
                              final itemName =
                                  menuSnap.hasData ? menuSnap.data![0] : '...';
                              final sizeName =
                                  menuSnap.hasData ? menuSnap.data![1] : '';
                              final article =
                                  it['article'] as String?; // получаем артикул
                              final mid = resolvedItemId;
                              final showSize = (_hasSizes[mid] == true) &&
                                  sizeName.isNotEmpty;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${it['quantity']}× '
                                        '${article != null ? '[$article] ' : ''}'
                                        '$itemName'
                                        '${showSize ? ' ($sizeName)' : ''}'
                                        ' – €${(it['price'] as num).toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(
                                            color: Colors.white, fontSize: 14),
                                      ),
                                      if (extras.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: extras.map((e) {
                                              final extraId =
                                                  (e['menu_v2_extra_id']
                                                          as int?) ??
                                                      (e['extra_id'] as int?) ??
                                                      0;
                                              return FutureBuilder(
                                                future: _getExtraName(extraId),
                                                builder: (context,
                                                    AsyncSnapshot<String>
                                                        extraSnap) {
                                                  final extraName =
                                                      extraSnap.hasData
                                                          ? extraSnap.data!
                                                          : '...';
                                                  return Text(
                                                    '+ $extraName ×${e['quantity']}'
                                                    '${(e['price'] != null) ? ' (€${(e['price'] as num).toStringAsFixed(2)})' : ''}',
                                                    style: GoogleFonts.poppins(
                                                        color: Colors.white54,
                                                        fontSize: 12),
                                                  );
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      // Опции
                                        if ((it['order_item_options'] as List?)
                                            ?.isNotEmpty ==
                                          true)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 12, top: 4),
                                          child: Column(
                                          crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                          children: (it['order_item_options']
                                              as List)
                                            .cast<Map<String, dynamic>>()
                                            .map((op) {
                                            final optId =
                                              (op['modifier_option_id']
                                                  as int?) ??
                                                (op['option_id']
                                                  as int?) ??
                                                0;
                                            final qty =
                                              (op['quantity'] as int?) ?? 1;
                                            final snapDelta =
                                              (op['price_delta'] as num?)
                                                  ?.toDouble() ??
                                                0.0;
                                            final storedName =
                                              (op['option_name'] as String?)
                                                ?.trim();

                                            Text buildText(String displayName) {
                                            final showDelta =
                                              snapDelta.abs() > 0.0001;
                                            final deltaStr =
                                              snapDelta.toStringAsFixed(2);
                                            return Text(
                                              '+ $displayName ×$qty${showDelta ? ' (€$deltaStr)' : ''}',
                                              style: GoogleFonts.poppins(
                                                color: Colors.white54,
                                                fontSize: 12),
                                            );
                                            }

                                            if (storedName != null &&
                                              storedName.isNotEmpty) {
                                            return buildText(storedName);
                                            }
                                            if (optId == 0) {
                                            return buildText('Option');
                                            }
                                            return FutureBuilder(
                                            future: _getOptionMeta(optId),
                                            builder: (context,
                                              AsyncSnapshot<
                                                  Map<String,
                                                    dynamic>>
                                                osnap) {
                                              if (osnap.connectionState !=
                                                ConnectionState.done) {
                                              return buildText('…');
                                              }
                                              final meta = osnap.data ??
                                                const {
                                                'name': '',
                                                'price': 0.0
                                                };
                                              final name =
                                                (meta['name'] as String?) ??
                                                  'Option #$optId';
                                              final metaPrice =
                                                (meta['price'] as num?)
                                                    ?.toDouble() ??
                                                  0.0;
                                              final effectiveDelta =
                                                snapDelta == 0.0
                                                  ? metaPrice
                                                  : snapDelta;
                                              final showDelta =
                                                effectiveDelta.abs() >
                                                  0.0001;
                                              final deltaStr =
                                                effectiveDelta
                                                  .toStringAsFixed(2);
                                              return Text(
                                              '+ $name ×$qty${showDelta ? ' (€$deltaStr)' : ''}',
                                              style: GoogleFonts.poppins(
                                                color: Colors.white54,
                                                fontSize: 12),
                                              );
                                            },
                                            );
                                          }).toList(),
                                          ),
                                        ),
                                    ]),
                              );
                            },
                          );
                        }),
                        const Divider(color: Colors.white24),
                        Text(
                          'Gesamt: €${(order['total_sum'] as num).toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold),
                        ),
                      ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
