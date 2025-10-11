// lib/screens/menu_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/theme_provider.dart';
import '../widgets/common_app_bar.dart';
import '../widgets/no_internet_widget.dart'; // добавлено
import 'home_screen.dart'; // здесь модель MenuItem
import 'menu_item_detail_screen.dart';

class Category {
  final int id;
  final String name;
  Category({required this.id, required this.name});
}

class MenuScreen extends StatefulWidget {
  const MenuScreen({Key? key}) : super(key: key);

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Category> _categories = [];
  Map<int, List<MenuItem>> _itemsByCat = {};

  @override
  void initState() {
    super.initState();
    _loadMenu();
  }

  Future<void> _loadMenu() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 1) Загрузить категории
      final catData = await _supabase
          .from('menu_category')
          .select('id,name')
          .order('sort_order', ascending: true);

      _categories = (catData as List)
          .map((m) => Category(id: m['id'] as int, name: m['name'] as String))
          .toList();

      final Map<int, List<MenuItem>> itemsByCat = {};

      // 2) Для каждой категории — загрузить позиции
      for (final cat in _categories) {
        final itemsData = await _supabase
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
            .eq('category_id', cat.id)
            .eq('is_deleted', false)
            .order('sort_order', ascending: true);

        final List<MenuItem> items = [];

        for (final e in (itemsData as List)) {
          final itemId = e['id'] as int;
          final bool hasMultiple = e['has_multiple_sizes'] as bool? ?? true;
          final double? singlePrice = e['single_size_price'] != null
              ? (e['single_size_price'] as num).toDouble()
              : null;

          double minPrice = 0.0;
          if (!hasMultiple) {
            minPrice = singlePrice ?? 0.0;
          } else {
            final pricesRaw = await _supabase
                .from('menu_item_price')
                .select('price')
                .eq('menu_item_id', itemId);

            if (pricesRaw is List && pricesRaw.isNotEmpty) {
              final sorted = pricesRaw
                  .map((p) => (p['price'] as num?)?.toDouble() ?? 0.0)
                  .toList()
                ..sort();
              minPrice = sorted.first;
            }
          }

          items.add(MenuItem(
            id: itemId,
            name: e['name'] as String? ?? '',
            description: e['description'] as String?,
            imageUrl: e['image_url'] as String?,
            article: e['article'] as String?,
            minPrice: minPrice,
            hasMultipleSizes: hasMultiple,
            singleSizePrice: singlePrice,
          ));
        }

        itemsByCat[cat.id] = items;
      }
    if (!mounted) return;
      setState(() {
        _itemsByCat = itemsByCat;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);

    // отступ снизу под нижний NavigationBar
    final bottomPadding =
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight;

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        title: Text(
          'Menü',
          style: GoogleFonts.fredokaOne(color: appTheme.primaryColor),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false, // стрелка назад убрана
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart, color: Colors.white),
            tooltip: 'Warenkorb',
            onPressed: () {
              Navigator.of(context).pushNamed('/cart');
            },
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: appTheme.primaryColor),
            )
          : _error != null
              ? NoInternetWidget(
                  onRetry: _loadMenu,
                  errorText: _error?.contains('SocketException') == true || _error == 'Нет подключения к интернету'
                      ? 'Keine Internetverbindung'
                      : _error,
                )
              : ListView.builder(
                  padding: EdgeInsets.only(bottom: bottomPadding),
                  itemCount: _categories.length,
                  itemBuilder: (_, idx) {
                    final cat = _categories[idx];
                    final items = _itemsByCat[cat.id] ?? [];
                    if (items.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 16),
                          child: Text(
                            cat.name,
                            style: GoogleFonts.poppins(
                              color: appTheme.textColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        ...items.map(
                          (item) => _MenuListItem(
                            item: item,
                            onTap: () async {
                              // при тапе — подгружаем полные данные и показываем детальный экран
                              final data = await _supabase
                                  .from('menu_item')
                                  .select()
                                  .eq('id', item.id)
                                  .single();
                              final menuItem = MenuItem.fromMap(
                                  data as Map<String, dynamic>);
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MenuItemDetailScreen(item: menuItem),
                                ),
                              );
                              setState(() {}); // чтобы обновить состояние после возврата
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _MenuListItem extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;

  const _MenuListItem({
    Key? key,
    required this.item,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    return Card(
      color: appTheme.cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 120,
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Фото
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: appTheme.backgroundColor.withOpacity(0.7),
                ),
                clipBehavior: Clip.antiAlias,
                child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                    ? Hero(
                        tag: 'menuItemImage_${item.id}',
                        child: Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.image_not_supported,
                            color: appTheme.textColorSecondary,
                            size: 44,
                          ),
                        ),
                      )
                    : Icon(Icons.fastfood,
                        color: appTheme.textColorSecondary, size: 44),
              ),
              const SizedBox(width: 16),
              // Инфо
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.article != null && item.article!.isNotEmpty)
                      Text(
                        'Art.Nr. ${item.article}',
                        style: GoogleFonts.poppins(
                          color: appTheme.primaryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    Text(
                      item.name,
                      style: GoogleFonts.poppins(
                        color: appTheme.textColor,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.description != null &&
                        item.description!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3.0),
                        child: Text(
                          item.description!,
                          style: GoogleFonts.poppins(
                            color: appTheme.textColorSecondary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const Spacer(),
                    // Цена
                    Text(
                      item.hasMultipleSizes
                          ? (item.minPrice > 0
                              ? 'ab ${item.minPrice.toStringAsFixed(2)} €'
                              : '')
                          : (item.singleSizePrice != null
                              ? '${item.singleSizePrice!.toStringAsFixed(2)} €'
                              : ''),
                      style: GoogleFonts.poppins(
                        color: appTheme.primaryColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onTap,
                child: Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: appTheme.buttonColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_shopping_cart,
                    color: appTheme.textColor,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
