// lib/screens/order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/order_service.dart';
import '../utils/globals.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/no_internet_widget.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({Key? key}) : super(key: key);

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _futureOrders;

  // Кешируем имена блюд, размеров, добавок, чтобы не делать повторных запросов
  final Map<int, String> _menuItemNames = {};
  final Map<int, String> _sizeNames = {};
  final Map<int, String> _extraNames = {};

  @override
  void initState() {
    super.initState();
    _futureOrders = OrderService.getOrderHistory();
  }

  Future<String> _getMenuItemName(int id) async {
    if (_menuItemNames.containsKey(id)) return _menuItemNames[id]!;
    final row = await Supabase.instance.client
        .from('menu_item')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    final name = row?['name'] as String? ?? '№$id';
    _menuItemNames[id] = name;
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
        .from('menu_extra')
        .select('name')
        .eq('id', id)
        .maybeSingle();
    final name = row?['name'] as String? ?? '№$id';
    _extraNames[id] = name;
    return name;
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
        title: Text('Bestellhistorie', style: GoogleFonts.fredokaOne(color: Colors.orange)),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _futureOrders,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
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
              child: Text('Keine Bestellungen gefunden', style: GoogleFonts.poppins(color: Colors.white70)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, i) {
              final order = orders[i];
              final items = (order['order_items'] as List).cast<Map<String, dynamic>>();
              return Card(
                color: Colors.white12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      'Bestellt am ${DateTime.parse(order['created_at']).toLocal().toString().substring(0, 16)}',
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    ...items.map((it) {
                      final extras = (it['order_item_extras'] as List).cast<Map<String, dynamic>>();
                      return FutureBuilder(
                        future: Future.wait([
                          _getMenuItemName(it['menu_item_id'] as int),
                          _getSizeName(it['size_id'] as int?),
                        ]),
                        builder: (context, AsyncSnapshot<List<String>> menuSnap) {
                          final itemName = menuSnap.hasData ? menuSnap.data![0] : '...';
                          final sizeName = menuSnap.hasData ? menuSnap.data![1] : '';
                          final article = it['article'] as String?;  // получаем артикул
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                '${it['quantity']}× '
                                '${article != null ? '[$article] ' : ''}'
                                 '$itemName'
                                 '${sizeName.isNotEmpty ? ' ($sizeName)' : ''}'
                                 ' – €${(it['price'] as num).toStringAsFixed(2)}',
                                 style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                              ),   
                              if (extras.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: extras.map((e) {
                                      return FutureBuilder(
                                        future: _getExtraName(e['extra_id'] as int),
                                        builder: (context, AsyncSnapshot<String> extraSnap) {
                                          final extraName = extraSnap.hasData ? extraSnap.data! : '...';
                                          return Text(
                                            '+ $extraName ×${e['quantity']}'
                                            '${(e['price'] != null) ? ' (€${(e['price'] as num).toStringAsFixed(2)})' : ''}',
                                            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
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
                    }).toList(),
                    const Divider(color: Colors.white24),
                    Text(
                      'Gesamt: €${(order['total_sum'] as num).toStringAsFixed(2)}',
                      style: GoogleFonts.poppins(color: Colors.orange, fontWeight: FontWeight.bold),
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
