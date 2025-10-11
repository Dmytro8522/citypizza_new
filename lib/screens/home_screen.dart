// lib/screens/home_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../theme/theme_provider.dart';
import '../widgets/common_app_bar.dart';
import '../widgets/creative_cta_section.dart';
import '../widgets/no_internet_widget.dart';
import 'cart_screen.dart';
import 'discount_list_widget.dart';
import 'menu_item_detail_screen.dart';
import 'menu_screen.dart';
import 'profile_screen.dart';
import 'profile_screen_auth.dart';
import 'recent_orders_carousel.dart';
import 'top_items_carousel.dart';

/// Модель пункта меню.
/// Если вы уже импортируете её из другого файла, 
/// просто уберите дублирование и используйте свой импорт.
class MenuItem {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? article;
  final double? klein, normal, gross, familie, party;
  final double minPrice;
  final bool hasMultipleSizes;
  final double? singleSizePrice;

  MenuItem({
    required this.id,
    required this.name,
    this.description,
    this.imageUrl,
    this.article,
    this.klein,
    this.normal,
    this.gross,
    this.familie,
    this.party,
    required this.minPrice,
    this.hasMultipleSizes = true,
    this.singleSizePrice,
  });

  factory MenuItem.fromMap(Map<String, dynamic> m) => MenuItem(
        id: m['id'] as int,
        name: m['name'] as String,
        description: m['description'] as String?,
        imageUrl: (m['image_url'] as String?) ?? (m['image'] as String?),
        article: m['article'] as String?,
        klein: (m['klein'] as num?)?.toDouble(),
        normal: (m['normal'] as num?)?.toDouble(),
        gross: (m['gross'] as num?)?.toDouble(),
        familie: (m['familie'] as num?)?.toDouble(),
        party: (m['party'] as num?)?.toDouble(),
        minPrice: m['minPrice'] is num ? (m['minPrice'] as num).toDouble() : 0.0,
        hasMultipleSizes: m['has_multiple_sizes'] as bool? ?? true,
        singleSizePrice:
            m['single_size_price'] != null ? (m['single_size_price'] as num).toDouble() : null,
      );
}

/// Виджет с анимированным градиентным фоном для обёртки секций.
class AnimatedGradientSection extends StatefulWidget {
  final Widget title;
  final Widget child;
  final List<List<Color>> gradients;
  final Duration duration;

  const AnimatedGradientSection({
    Key? key,
    required this.title,
    required this.child,
    required this.gradients,
    this.duration = const Duration(seconds: 3),
  }) : super(key: key);

  @override
  State<AnimatedGradientSection> createState() => _AnimatedGradientSectionState();
}

class _AnimatedGradientSectionState extends State<AnimatedGradientSection> {
  int _gradientIndex = 0;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    // Запускаем таймер для циклической смены градиента
    _timer = Timer.periodic(widget.duration, (_) {
      setState(() {
        _gradientIndex = (_gradientIndex + 1) % widget.gradients.length;
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradients[_gradientIndex];
    return Stack(
      children: [
        AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.only(top: 16, left: 16, bottom: 16, right: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.title,
              const SizedBox(height: 12),
              widget.child,
            ],
          ),
        ),
        // Наложение полупрозрачного градиента справа
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              width: 54,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.07),
                    Colors.black.withOpacity(0.12),
                    Colors.black.withOpacity(0.24),
                    Colors.black.withOpacity(0.45),
                  ],
                  stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Главный экран с табами: «Главная», «Меню», «Профиль»
class HomeScreen extends StatefulWidget {
  final int initialIndex;

  const HomeScreen({Key? key, this.initialIndex = 0}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  List<MenuItem> _allItems = [];
  List<MenuItem> _filteredItems = [];
  bool _loading = true;
  String? _error;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialIndex;
    _loadMenu(); // Загружаем меню при инициализации (с учётом кэша)
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Фильтрация списка при вводе в строке поиска
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = query.isEmpty
          ? List.from(_allItems)
          : _allItems.where((item) => item.name.toLowerCase().contains(query)).toList();
    });
  }

  /// Загрузка меню из Supabase с кэшированием в SharedPreferences и обработкой ошибок сети.
  Future<void> _loadMenu({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final prefs = await SharedPreferences.getInstance();

    // ШАГ 1: Если не refresh и в кэше есть данные — показываем их сразу
    if (!refresh && prefs.containsKey('cached_menu')) {
      try {
        final cachedString = prefs.getString('cached_menu')!;
        final List decoded = json.decode(cachedString) as List;
        final cachedItems = decoded
            .map((e) => MenuItem.fromMap(e as Map<String, dynamic>))
            .toList();
        _allItems = cachedItems;
        _filteredItems = List.from(_allItems);
        setState(() => _loading = false);
      } catch (_) {
        // Если не удалось распарсить кэш — просто игнорируем
      }
    }

    // ШАГ 2: Пробуем получить актуальные данные с Supabase
    try {
      final data = await supabase
          .from('menu_item')
          .select()
          .order('id', ascending: true);
      final itemsFromServer = (data as List)
          .map((e) => MenuItem.fromMap(e as Map<String, dynamic>))
          .toList();

      _allItems = itemsFromServer;
      _filteredItems = List.from(_allItems);

      // ШАГ 3: Обновляем кэш в SharedPreferences
      await prefs.setString('cached_menu', json.encode(data));
    } on SocketException {
      // Если нет интернета
      _error = 'Нет подключения к интернету';
    } catch (e) {
      // Любая другая ошибка
      _error = e.toString();
    } finally {
      // Проверяем mounted, чтобы не вызывать setState после dispose
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// При выходе из профиля: переключаемся на вкладку «Профиль»
  void _handleLogout() {
    setState(() => _tabIndex = 2);
  }

  /// Переход в экран корзины. После возврата обновляем состояние, чтобы бейджик пересчитал товары.
  void _goToCart() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CartScreen()),
    ).then((_) {
      if (!mounted) return;
      setState(() {
        // Обновляем, чтобы значок корзины отобразил актуальное количество
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);

    // Название AppBar по текущему табу
    final title = _tabIndex == 0
        ? 'City Pizza Service'
        : _tabIndex == 1
            ? 'Menü'
            : 'Profil';

    // Определяем, какой контент показывать внутри body
    Widget bodyContent;
    if (_loading) {
      // Пока идёт загрузка — показываем индикатор
      bodyContent = const Center(child: CircularProgressIndicator(color: Colors.orange));
    } else if (_error != null) {
      // Используем универсальный виджет для отсутствия интернета
      bodyContent = NoInternetWidget(
        onRetry: () => _loadMenu(refresh: true),
        errorText: _error == 'Нет подключения к интернету' ? 'Keine Internetverbindung' : _error,
      );
    } else {
      // Нет загрузки и нет ошибок — смотрим, какая вкладка выбрана
      if (_tabIndex == 0) {
        // === Вкладка «Главная» ===
        bodyContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showSearch) ...[
              SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Suche Pizza…',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: Colors.white10,
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: RefreshIndicator(
                color: Colors.orange,
                onRefresh: () => _loadMenu(refresh: true),
                child: _showSearch && _searchController.text.trim().isNotEmpty
                    // Если поиск открыт и пользователь что-то ввёл — показываем поиск
                    ? GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        itemCount: _filteredItems.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.75,
                        ),
                        itemBuilder: (ctx, i) {
                          final item = _filteredItems[i];
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => MenuItemDetailScreen(item: item)),
                              ).then((_) {
                                if (!mounted) return;
                                setState(() {});
                              });
                            },
                            child: _MenuCard(item: item),
                          );
                        },
                      )
                    // Иначе — стандартный главный экран с секциями
                    : _buildHomeTab(),
              ),
            ),
          ],
        );
      } else if (_tabIndex == 1) {
        // === Вкладка «Меню» ===
        bodyContent = const MenuScreen();
      } else {
        // === Вкладка «Профиль» ===
        final user = supabase.auth.currentUser;
        bodyContent = user != null
            ? ProfileScreenAuth(onLogout: _handleLogout)
            : const ProfileScreen();
      }
    }

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: _tabIndex == 0
          // Если мы на главной вкладке — рисуем кастомный AppBar с возможностью поиска и корзиной
          ? AppBar(
              backgroundColor: appTheme.backgroundColor,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: Icon(
                  _showSearch ? Icons.close : Icons.search,
                  color: appTheme.iconColor,
                ),
                onPressed: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) {
                      _searchController.clear();
                    }
                  });
                },
              ),
              title: Text(title),
              titleTextStyle: GoogleFonts.fredokaOne(
                color: appTheme.primaryColor,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              actions: [
                // Заменено: теперь используем ValueListenableBuilder для обновления бейджика корзины
                ValueListenableBuilder<int>(
                  valueListenable: CartService.cartCountNotifier,
                  builder: (context, cartCount, child) {
                    return Stack(
                      children: [
                        IconButton(
                          icon: Icon(Icons.shopping_cart, color: appTheme.iconColor),
                          onPressed: _goToCart,
                        ),
                        if (cartCount > 0)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                '$cartCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            )
          // В остальных случаях (Меню/Профиль) используем общий AppBar
          : buildCommonAppBar(title: title, context: context),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: bodyContent,
      ),
      extendBody: true,
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: appTheme.backgroundColor,
        currentIndex: _tabIndex,
        selectedItemColor: appTheme.primaryColor,
        unselectedItemColor: appTheme.textColorSecondary,
        onTap: (index) {
          setState(() {
            _tabIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Главная',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu_book),
            label: 'Меню',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }

  /// Вспомогательный метод: строит содержимое вкладки «Главная» 
  /// с основными секциями: CTA, недавние заказы, скидки, топ-позиции
  Widget _buildHomeTab() {
    return ListView(
      clipBehavior: Clip.none,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      children: [
        CreativeCtaSection(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MenuScreen()),
            ).then((_) {
              if (!mounted) return;
              setState(() {});
            });
          },
        ),
        const SizedBox(height: 24),
        const RecentOrdersSection(),
        const SizedBox(height: 12),
        const DiscountListWidget(),
        const SizedBox(height: 12),
        TopItemsSection(
          onTap: (item) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MenuItemDetailScreen(item: item)),
            ).then((_) {
              if (!mounted) return;
              setState(() {});
            });
          },
        ),
      ],
    );
  }
}

/// Простой карточный виджет для элементов меню (используется в GridView при поиске)
class _MenuCard extends StatelessWidget {
  final MenuItem item;

  const _MenuCard({Key? key, required this.item}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: item.imageUrl != null
                  ? Image.network(item.imageUrl!, fit: BoxFit.cover)
                  : const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description!,
                    style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'ab ${item.minPrice.toStringAsFixed(2)} €',
                  style: GoogleFonts.poppins(
                    color: Colors.orangeAccent,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildRecentOrders(BuildContext context) {
  final appTheme = ThemeProvider.of(context);

  return Container(
    decoration: BoxDecoration(
      color: appTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      // Убираем прозрачность/затемнение для белой темы
    ),
    child: Stack(
      children: [
        // ...existing code...
        // Удаляем/не добавляем затемнение справа для белой темы
        // if (appTheme.backgroundColor != Colors.white)
        //   Positioned(
        //     right: 0,
        //     top: 0,
        //     bottom: 0,
        //     child: Container(
        //       width: 48,
        //       decoration: BoxDecoration(
        //         gradient: LinearGradient(
        //           begin: Alignment.centerLeft,
        //           end: Alignment.centerRight,
        //           colors: [
        //             Colors.transparent,
        //             Colors.black.withOpacity(0.18),
        //           ],
        //         ),
        //       ),
        //     ),
        //   ),
        // ...existing code...
      ],
    ),
  );
}

Widget _buildPopularDishes(BuildContext context) {
  final appTheme = ThemeProvider.of(context);

  return Container(
    decoration: BoxDecoration(
      color: appTheme.cardColor,
      borderRadius: BorderRadius.circular(16),
      // Убираем прозрачность/затемнение для белой темы
    ),
    child: Stack(
      children: [
        // ...existing code...
        // if (appTheme.backgroundColor != Colors.white)
        //   Positioned(
        //     right: 0,
        //     top: 0,
        //     bottom: 0,
        //     child: Container(
        //       width: 48,
        //       decoration: BoxDecoration(
        //         gradient: LinearGradient(
        //           begin: Alignment.centerLeft,
        //           end: Alignment.centerRight,
        //           colors: [
        //             Colors.transparent,
        //             Colors.black.withOpacity(0.18),
        //           ],
        //         ),
        //       ),
        //     ),
        //   ),
        // ...existing code...
      ],
    ),
  );
}
