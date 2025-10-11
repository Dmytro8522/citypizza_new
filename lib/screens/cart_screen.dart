// lib/screens/cart_screen.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../services/discount_service.dart';
import '../widgets/no_internet_widget.dart';
import 'checkout_screen.dart';
import 'menu_item_detail_screen.dart';
import 'home_screen.dart'; // для MenuItem
import '../theme/theme_provider.dart';

class _ExtraInfo {
  final String name;
  final double price;
  final int quantity;
  _ExtraInfo({required this.name, required this.price, required this.quantity});
}

class CartScreen extends StatefulWidget {
  const CartScreen({Key? key}) : super(key: key);

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen>
    with SingleTickerProviderStateMixin {
  bool _loadingDetails = true;
  double _totalSum = 0;
  double _totalDiscount = 0;
  List<Map<String, dynamic>> _appliedDiscounts = [];

  final Map<int, int> _itemCategoryCache = {};
  final Map<String, TextEditingController> _commentControllers = {};
  final Set<String> _commentVisible = {};

  DateTime? _userBirthdate;
  String? _userId;
  String? _error;

  @override
  void initState() {
    super.initState();
    CartService.init().then((_) async {
      await _loadUserData();
      await _recalculateTotal();
    });
  }

  Future<void> _loadUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    _userId = user?.id;
    if (_userId == null) return;
    final profile = await Supabase.instance.client
        .from('user_profiles')
        .select('birthdate')
        .eq('id', _userId!)
        .maybeSingle();
    final birthdateStr = profile?['birthdate'];
    _userBirthdate =
        birthdateStr != null ? DateTime.parse(birthdateStr) : null;
  }

  Future<int?> _getCategoryId(int itemId) async {
    if (_itemCategoryCache.containsKey(itemId)) {
      return _itemCategoryCache[itemId];
    }
    final res = await Supabase.instance.client
        .from('menu_item')
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
      int itemId, Map<int, int> extrasMap, String sizeName) async {
    if (extrasMap.isEmpty) return [];
    final szRow = await Supabase.instance.client
        .from('menu_size')
        .select('id')
        .eq('name', sizeName)
        .maybeSingle();
    if (szRow == null) return [];
    final sizeId = szRow['id'] as int;

    final extraPriceRows = await Supabase.instance.client
        .from('menu_item_extra_price')
        .select('extra_id, price')
        .eq('menu_item_id', itemId)
        .eq('size_id', sizeId);
    final priceMap = <int, double>{
      for (var row in extraPriceRows as List)
        row['extra_id'] as int: (row['price'] as num).toDouble(),
    };

    final extraRows = await Supabase.instance.client
        .from('menu_extra')
        .select('id, name')
        .filter('id', 'in', extrasMap.keys.toList());
    final nameMap = <int, String>{
      for (var row in extraRows as List) row['id'] as int: row['name'] as String,
    };

    return extrasMap.entries
        .map((e) => _ExtraInfo(
              name: nameMap[e.key] ?? 'Неизвестно',
              price: priceMap[e.key] ?? 0,
              quantity: e.value,
            ))
        .toList();
  }

  Future<void> _recalculateTotal() async {
    try {
      final items = CartService.items;
      final grouped = <String, List<CartItem>>{};
      for (final cartItem in items) {
        final key =
            '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}';
        grouped.putIfAbsent(key, () => []).add(cartItem);
        _commentControllers.putIfAbsent(key, () => TextEditingController());
      }

      double subtotal = 0;
      final cartList = <Map<String, dynamic>>[];

      for (final entry in grouped.entries) {
        final first = entry.value.first;
        final count = entry.value.length;
        final extras =
            await _loadExtrasInfo(first.itemId, first.extras, first.size);
        final extrasCost =
            extras.fold<double>(0, (p, e) => p + e.price * e.quantity);
        final lineTotal = (first.basePrice + extrasCost) * count;
        subtotal += lineTotal;

        final categoryId = await _getCategoryId(first.itemId);
        cartList.add({
          'id': first.itemId,
          'category_id': categoryId,
          'price': (first.basePrice + extrasCost),
          'quantity': count,
        });
      }

      final discountResult = await calculateDiscountedTotal(
        cartItems: cartList,
        subtotal: subtotal,
        userId: _userId,
        userBirthdate: _userBirthdate,
      );

      if (!mounted) return;
      setState(() {
        _totalSum = discountResult.total;
        _totalDiscount = discountResult.totalDiscount;
        _appliedDiscounts = discountResult.appliedDiscounts;
        _loadingDetails = false;
      });
    } on SocketException {
      setState(() {
        _error = 'Keine Internetverbindung';
        _loadingDetails = false;
      });
      return;
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loadingDetails = false;
      });
      return;
    }
  }

  void _navigateToDetail(int itemId) async {
    final supabase = Supabase.instance.client;
    final m = await supabase
        .from('menu_item')
        .select('''
          id,name,description,image_url,article,
          has_multiple_sizes,single_size_price
        ''')
        .eq('id', itemId)
        .maybeSingle() as Map<String, dynamic>?;
    if (m == null) return;
    final hasMulti = m['has_multiple_sizes'] as bool? ?? false;
    final singlePrice = m['single_size_price'] != null
        ? (m['single_size_price'] as num).toDouble()
        : 0.0;
    double minPrice = singlePrice;
    if (hasMulti) {
      final pr = await supabase
          .from('menu_item_price')
          .select('price')
          .eq('menu_item_id', itemId)
          .order('price', ascending: true)
          .limit(1);
      if (pr is List && pr.isNotEmpty) {
        minPrice = (pr.first['price'] as num).toDouble();
      }
    }
    final menuItem = MenuItem(
      id: m['id'] as int,
      name: m['name'] as String? ?? '',
      description: m['description'] as String?,
      imageUrl: m['image_url'] as String?,
      article: m['article'] as String?,
      klein: null,
      normal: null,
      gross: null,
      familie: null,
      party: null,
      minPrice: minPrice,
      hasMultipleSizes: hasMulti,
      singleSizePrice: hasMulti ? null : singlePrice,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => MenuItemDetailScreen(item: menuItem)),
    );
  }

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
      final key =
          '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}';
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
                      final baseTotal = line['baseTotal'] as double;
                      return FutureBuilder<List<_ExtraInfo>>(
                        future: _loadExtrasInfo(
                            cartItem.itemId, cartItem.extras, cartItem.size),
                        builder: (context, snap) {
                          final extras = snap.data ?? [];
                          final extrasCost = extras.fold<double>(
                              0, (p, e) => p + e.price * e.quantity);
                          final lineTotal = baseTotal + extrasCost * count;
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
                                      Text(
                                        '${cartItem.article != null ? '[${cartItem.article!}] ' : ''}${cartItem.name}',
                                        style: GoogleFonts.poppins(
                                          color: appTheme.textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${cartItem.size}, Menge: $count',
                                        style: GoogleFonts.poppins(
                                          color: appTheme.textColorSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      // --- ДОПОЛНЕНИЯ ---
                                      if (extras.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        ...extras.map((e) => Text(
                                              '${e.quantity} × ${e.name} (+${e.price.toStringAsFixed(2)} €)',
                                              style: GoogleFonts.poppins(
                                                color: appTheme.textColorSecondary,
                                                fontSize: 13,
                                              ),
                                            )),
                                      ],
                                      const SizedBox(height: 8),
                                      Text(
                                        '€${lineTotal.toStringAsFixed(2)}',
                                        style: GoogleFonts.poppins(
                                          color: appTheme.textColor,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                          Icons.remove_circle_outline,
                                          color: appTheme.iconColor),
                                      onPressed: () async {
                                        await CartService.removeItem(cartItem);
                                        await _recalculateTotal();
                                        setState(() {});
                                      },
                                    ),
                                    Text(
                                      '$count',
                                      style: GoogleFonts.poppins(
                                        color: appTheme.textColor,
                                        fontSize: 14,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                          Icons.add_circle_outline,
                                          color: appTheme.iconColor),
                                      onPressed: () async {
                                        await CartService.addItem(cartItem);
                                        await _recalculateTotal();
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
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
                      Text('Gesamt:',
                          style:
                              GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18)),
                      Text('€${_totalSum.toStringAsFixed(2)}',
                          style:
                              GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18)),
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
