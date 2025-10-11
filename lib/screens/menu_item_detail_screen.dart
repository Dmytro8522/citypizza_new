// lib/screens/menu_item_detail_screen.dart

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'home_screen.dart';               // MenuItem model
import '../services/cart_service.dart';  // CartItem & CartService
import 'cart_screen.dart';               // CartScreen for navigation
import '../widgets/no_internet_widget.dart';
import '../theme/theme_provider.dart';
import '../widgets/menu_item_placeholder.dart';

class ExtraOption {
  final int id;
  final String name;
  final double price;
  int quantity;
  Key key;
  ExtraOption({
    required this.id,
    required this.name,
    required this.price,
    this.quantity = 0,
  }) : key = UniqueKey();
}

class SizeOption {
  final int? id;
  final String name;
  final double price;
  SizeOption({
    required this.id,
    required this.name,
    required this.price,
  });
}

class MenuItemDetailScreen extends StatefulWidget {
  final MenuItem item;
  const MenuItemDetailScreen({Key? key, required this.item}) : super(key: key);

  @override
  State<MenuItemDetailScreen> createState() => _MenuItemDetailScreenState();
}

class _MenuItemDetailScreenState extends State<MenuItemDetailScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Размеры и допы
  List<SizeOption> _sizeOptions = [];
  SizeOption? _selectedSize;
  List<ExtraOption> _extras = [];
  bool _loadingSizes = true;
  bool _loadingExtras = false;

  // Информационные добавки (additives)
  List<String> _additiveLabels = [];
  bool _loadingAdditives = true;

  late final ScrollController _scrollController;

  String? _error;

  // Добавлено: для отложенной загрузки "тяжёлого" контента
  bool _showHeavyContent = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initAll();

    // Сначала показываем только базовый контент, heavyContent появится после анимации
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 180));
      if (_scrollController.hasClients) {
        try {
          await _scrollController.animateTo(
            36,
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
          );
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutBack,
          );
        } catch (_) {}
      }
      // Показываем heavyContent после анимации
      if (mounted) {
        setState(() {
          _showHeavyContent = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initAll() async {
    try {
      await _initSizesAndExtras();
      await _loadAdditives();
    } on SocketException {
      setState(() {
        _error = 'Keine Internetverbindung';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _initSizesAndExtras() async {
    setState(() {
      _loadingSizes = true;
      _loadingExtras = true;
    });

    if (widget.item.hasMultipleSizes) {
      final prices = await _supabase
          .from('menu_item_price')
          .select('size_id, price')
          .eq('menu_item_id', widget.item.id);
      final rawList = (prices as List).cast<Map<String, dynamic>>();
      if (rawList.isNotEmpty) {
        final sizeIds = rawList.map((p) => p['size_id'] as int).toList();
        final sizes = await _supabase
            .from('menu_size')
            .select('id, name')
            .filter('id', 'in', '(${sizeIds.join(",")})');
        final nameMap = {
          for (var s in (sizes as List)) s['id'] as int: s['name'] as String
        };
        _sizeOptions = rawList.map((p) {
          final sid = p['size_id'] as int;
          final rawPrice = p['price'];
          final price = rawPrice is num
              ? rawPrice.toDouble()
              : double.parse(rawPrice.toString());
          return SizeOption(
            id: sid,
            name: nameMap[sid] ?? '',
            price: price,
          );
        }).toList();
        _sizeOptions.sort((a, b) => a.price.compareTo(b.price));
        _selectedSize = _sizeOptions.first;
      } else {
        _sizeOptions = [];
        _selectedSize = null;
      }
    } else {
      _sizeOptions = [
        SizeOption(
          id: 2,
          name: 'Normal',
          price: widget.item.singleSizePrice ?? 0.0,
        )
      ];
      _selectedSize = _sizeOptions.first;
    }

    setState(() => _loadingSizes = false);
    await _loadExtras();
  }

  Future<void> _loadExtras() async {
    setState(() {
      _loadingExtras = true;
      _extras = [];
    });

    if (_selectedSize == null) {
      setState(() => _loadingExtras = false);
      return;
    }

    // Запрос всех допов для данного блюда и выбранного размера
    var builder = _supabase
        .from('menu_item_extra_price')
        .select('extra_id, price')
        .eq('menu_item_id', widget.item.id);

    if (widget.item.hasMultipleSizes) {
      builder = builder.eq('size_id', _selectedSize!.id!);
    } else {
      builder = builder.filter('size_id', 'is', null);
    }

    final rows = (await builder as List).cast<Map<String, dynamic>>();

    // Собираем последнюю цену для каждого extra_id
    final priceByExtra = <int, double>{};
    for (var r in rows) {
      final eid = r['extra_id'] as int;
      final rawPrice = r['price'];
      final price = rawPrice is num
          ? rawPrice.toDouble()
          : double.parse(rawPrice.toString());
      priceByExtra[eid] = price;
    }

    if (priceByExtra.isEmpty) {
      setState(() => _loadingExtras = false);
      return;
    }

    // Подтягиваем названия допов
    final extraRows = await _supabase
        .from('menu_extra')
        .select('id, name')
        .filter('id', 'in', '(${priceByExtra.keys.join(",")})');
    final nameMap = {
      for (var x in (extraRows as List)) x['id'] as int: x['name'] as String
    };

    // Создаем список ExtraOption и обновляем ключи
    _extras = priceByExtra.entries.map((e) {
      final opt = ExtraOption(
        id: e.key,
        name: nameMap[e.key]!,
        price: e.value,
      );
      opt.key = UniqueKey();
      return opt;
    }).toList();

    setState(() => _loadingExtras = false);
  }

  Future<void> _loadAdditives() async {
    setState(() => _loadingAdditives = true);

    final rows = await _supabase
        .from('menu_item_additive')
        .select('additive_id')
        .eq('menu_item_id', widget.item.id);
    final ids =
        (rows as List).map((r) => r['additive_id'] as int).toSet().toList();
    if (ids.isEmpty) {
      setState(() => _loadingAdditives = false);
      return;
    }

    final adds = await _supabase
        .from('additives')
        .select('code, title')
        .filter('id', 'in', '(${ids.join(",")})');
    _additiveLabels = (adds as List).map((a) {
      return '${a['code']}: ${a['title']}';
    }).toList();

    setState(() => _loadingAdditives = false);
  }

  void _onSizeChanged(SizeOption? s) async {
    if (s == null) return;
    setState(() {
      _selectedSize = s;
      _loadingExtras = true;
      _extras = [];
    });
    await _loadExtras();
  }

  void _close() => Navigator.pop(context);

  Future<void> _addToCart() async {
    final extrasMap = <int, int>{
      for (var e in _extras) if (e.quantity > 0) e.id: e.quantity
    };
    await CartService.addItem(CartItem(
      itemId: widget.item.id,
      name: widget.item.name,
      size: _selectedSize!.name,
      basePrice: _selectedSize!.price,
      extras: extrasMap,
      article: widget.item.article,
      sizeId: _selectedSize!.id, // Добавлено: передаем sizeId
    ));
    final total = extrasMap.values.fold<int>(0, (a, b) => a + b);
    // Показываем кастомный SnackBar с двумя кнопками
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        backgroundColor: Colors.grey[900],
        duration: const Duration(seconds: 5),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.item.name} (${_selectedSize!.name}) hinzugefügt${total > 0 ? ' mit $total Extras' : ''}',
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      scaffold.hideCurrentSnackBar();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: Text(
                      'Weiter bestellen',
                      style: GoogleFonts.poppins(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    onPressed: () {
                      scaffold.hideCurrentSnackBar();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      Navigator.of(context).pushNamed('/cart');
                    },
                    child: Text(
                      'Zum Warenkorb',
                      style: GoogleFonts.poppins(
                        color: Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    if (_error != null) {
      return Scaffold(
        backgroundColor: appTheme.backgroundColor,
        appBar: AppBar(
          backgroundColor: appTheme.backgroundColor,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: appTheme.textColor),
            onPressed: _close,
          ),
          title: Text(widget.item.name,
              style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
          centerTitle: true,
          elevation: 0,
        ),
        body: NoInternetWidget(
          onRetry: _initAll,
          errorText: _error,
        ),
      );
    }
    final item = widget.item;
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appTheme.textColor),
          onPressed: _close,
        ),
        title: Text(item.name,
            style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.close, color: appTheme.textColor),
            onPressed: _close,
          ),
        ],
      ),
      body: RawScrollbar(
        controller: _scrollController,
        thumbColor: appTheme.primaryColor,
        thickness: 6,
        radius: const Radius.circular(3),
        thumbVisibility: true,
        child: ListView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (item.imageUrl != null && item.imageUrl!.isNotEmpty) ...[
              Hero(
                tag: 'menuItemImage_${item.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    item.imageUrl!,
                    height: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox(
                      height: 240,
                      child: MenuItemPlaceholder(
                        title: item.name,
                        price: item.singleSizePrice != null ? '${item.singleSizePrice!.toStringAsFixed(2)} €' : null,
                        borderRadius: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              // no image: show placeholder
              MenuItemPlaceholder(
                height: 240,
                title: item.name,
                price: item.singleSizePrice != null ? '${item.singleSizePrice!.toStringAsFixed(2)} €' : null,
                borderRadius: 16,
              ),
              const SizedBox(height: 16),
            ],
            Text(item.name,
                style: GoogleFonts.fredokaOne(
                    fontSize: 28, color: appTheme.textColor)),
            if (item.description != null) ...[
              const SizedBox(height: 8),
              Text(item.description!,
                  style: GoogleFonts.poppins(
                      color: appTheme.textColorSecondary, fontSize: 16)),
            ],
            if (!_loadingAdditives && _additiveLabels.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Kennzeichnung der Inhaltsstoffe: '
                '${_additiveLabels.join(", ")}',
                style: GoogleFonts.poppins(
                    color: appTheme.textColorSecondary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            Text('Preis:',
                style:
                    GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18)),
            const SizedBox(height: 8),
            if (_loadingSizes)
              Center(
                  child:
                      CircularProgressIndicator(color: appTheme.primaryColor))
            else if (item.hasMultipleSizes)
              ..._sizeOptions.map((opt) => RadioListTile<SizeOption>(
                    activeColor: appTheme.primaryColor,
                    value: opt,
                    groupValue: _selectedSize,
                    title: Text(
                      '${opt.name} — ${opt.price.toStringAsFixed(2)} €',
                      style:
                          GoogleFonts.poppins(color: appTheme.textColor),
                    ),
                    onChanged: _onSizeChanged,
                  ))
            else
              Text(
                '${_selectedSize!.price.toStringAsFixed(2)} €',
                style: GoogleFonts.poppins(
                    color: appTheme.textColor, fontSize: 20),
              ),
            const SizedBox(height: 24),

            // heavyContent: Extras и всё, что ниже
            if (_showHeavyContent)
              ...[
                if (_loadingExtras)
                  Center(
                      child:
                          CircularProgressIndicator(color: appTheme.primaryColor))
                else if (_extras.isNotEmpty) ...[
                  Text('Extras:',
                      style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 18)),
                  const SizedBox(height: 8),
                  Container(
                    height: _extras.length * 48.0,
                    child: ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _extras.length,
                      itemBuilder: (_, idx) {
                        final opt = _extras[idx];
                        return Padding(
                          key: opt.key,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${opt.name} (+${opt.price.toStringAsFixed(2)} €)',
                                  style: TextStyle(color: appTheme.textColor),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.remove_circle_outline,
                                    color: appTheme.iconColor),
                                onPressed: () => setState(() {
                                  if (opt.quantity > 0) opt.quantity--;
                                }),
                              ),
                              Text('${opt.quantity}',
                                  style: TextStyle(color: appTheme.textColor)),
                              IconButton(
                                icon: Icon(Icons.add_circle_outline,
                                    color: appTheme.iconColor),
                                onPressed: () => setState(() => opt.quantity++),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                const SizedBox(height: 80),
              ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: appTheme.buttonColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            onPressed: _selectedSize == null ? null : _addToCart,
            child: Text('In den Warenkorb',
                style: GoogleFonts.poppins(
                    color: appTheme.textColor, fontSize: 18)),
          ),
        ),
      ),
    );
  }
}
