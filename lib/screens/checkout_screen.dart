// lib/screens/checkout_screen.dart

// import 'dart:convert'; // unused
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../services/order_service.dart';
import '../utils/working_hours.dart';
import '../widgets/upsell_widget.dart';
import '../services/upsell_service.dart';
import '../services/discount_service.dart';
import '../widgets/no_internet_widget.dart';
import '../theme/theme_provider.dart';
import 'cart_screen.dart';
import 'menu_item_detail_screen.dart';
// import 'menu_screen.dart'; // Больше не используем прямой переход сюда после заказа
import '../models/menu_item.dart';
import 'email_signup_screen.dart';
import 'order_status_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/price_with_promotion.dart';
import '../services/delivery_zone_service.dart';
import '../utils/address_localization.dart';

// Removed unused _ExtraInfo helper

class CheckoutScreen extends StatefulWidget {
  final double totalSum;
  final Map<String, String> itemComments;
  final double? totalDiscount;
  final List<Map<String, dynamic>>? appliedDiscounts;

  const CheckoutScreen({
    super.key,
    required this.totalSum,
    required this.itemComments,
    this.totalDiscount,
    this.appliedDiscounts,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _upsellShown = false;

  // Removed unused _name and _phone (we use controllers instead)
  bool _isDelivery = true;
  String _paymentMethod = 'cash';
  // Removed unused _minOrder

  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _houseNumberController = TextEditingController();
  final TextEditingController _postalController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();

  final TextEditingController _orderCommentController = TextEditingController();
  final TextEditingController _courierCommentController =
      TextEditingController();

  bool _isCustomTime = false;
  TimeOfDay? _selectedTime;

  // Removed unused delivery zone minimums (was _zoneMin)

  String? _error;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // Текущая сумма без скидки (для правил UpSell) и с учётом скидки (для отображения)
  // _currentTotalSum уже объявлена выше в файле — используем её как сумму без скидки
  double _currentTotalSumDiscounted = 0.0; // сумма с учётом скидки
  double _currentDiscountAmount = 0.0; // величина скидки

  // Текущая сумма корзины (пересчитываемая после добавлений из UpSell)
  double _currentTotalSum = 0.0;
  Map<String, PromotionPrice> _linePromotionPrices = {};
  double? _minOrderAmount; // минимальная сумма заказа для текущего postal code
  bool _loadingMinOrder = false;

  // Helpers to show extras and options in summary
  Future<List<Map<String, dynamic>>> _loadExtrasInfo(
      int itemId, Map<int, int> extrasMap,
      {int? sizeId, String? sizeName}) async {
    if (extrasMap.isEmpty) return [];
    int? resolvedSizeId = sizeId;
    if (resolvedSizeId == null && (sizeName != null && sizeName.isNotEmpty)) {
      final szRow = await Supabase.instance.client
          .from('menu_size')
          .select('id')
          .eq('name', sizeName)
          .maybeSingle();
      resolvedSizeId = szRow != null ? (szRow['id'] as int?) ?? 0 : null;
    }

    final priceMap = <int, double>{};
    if (resolvedSizeId != null && resolvedSizeId != 0) {
      final extraPriceRows = await Supabase.instance.client
          .from('menu_v2_extra_price_by_size')
          .select('extra_id, price')
          .eq('size_id', resolvedSizeId)
          .filter('extra_id', 'in', extrasMap.keys.toList());
      for (var row in extraPriceRows as List) {
        final eid = (row['extra_id'] as int?) ?? 0;
        final p = (row['price'] as num).toDouble();
        priceMap[eid] = p;
      }
    }

    final extraRows = await Supabase.instance.client
        .from('menu_v2_extra')
        .select('id, name')
        .filter('id', 'in', extrasMap.keys.toList());
    final nameMap = <int, String>{
      for (var row in extraRows as List)
        ((row['id'] as int?) ?? 0): ((row['name'] as String?) ?? ''),
    };

    return extrasMap.entries
        .map((e) => {
              'name': nameMap[e.key] ?? '—',
              'price': priceMap[e.key] ?? 0,
              'quantity': e.value,
            })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadOptionsInfo(
      Map<int, int> optionsMap) async {
    if (optionsMap.isEmpty) return [];
    final optRows = await Supabase.instance.client
        .from('menu_v2_modifier_option')
        .select('id, name')
        .filter('id', 'in', optionsMap.keys.toList());
    final list = (optRows as List).cast<Map<String, dynamic>>();
    return list.map((row) {
      final id = (row['id'] as int?) ?? 0;
      final name = (row['name'] as String?) ?? '';
      return {
        'name': name,
        'priceDelta': 0.0,
        'quantity': optionsMap[id] ?? 0,
      };
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    // Инициализируем текущую сумму перед первым показом
    _currentTotalSum = widget.totalSum;
    // Показ upsell-диалога после первого рендера
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_upsellShown) {
        _upsellShown = true;
        _showUpsellDialog();
      }
      // Важно: загружаем профиль после первого кадра, чтобы избежать конфликтов с контроллерами
      _loadUserProfileIfAuth();
      // Пересчитываем сумму корзины на всякий случай из актуального состояния CartService
      _refreshCartTotal();
      _prefillFromPrefs();
    });
  }

  Future<void> _prefillFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Только если поле пустое (не перетирать профиль пользователя)
    if (_postalController.text.trim().isEmpty) {
      final pc = prefs.getString('user_postal_code');
      if (pc != null && pc.isNotEmpty) {
        _postalController.text = pc;
        _onPostalChanged(pc);
      }
    }
    if (_cityController.text.trim().isEmpty) {
      final city = prefs.getString('user_city');
      if (city != null && city.isNotEmpty) {
        _cityController.text = normalizeAddressComponent(city);
      }
    }
    if (_streetController.text.trim().isEmpty) {
      final street = prefs.getString('user_street');
      if (street != null && street.isNotEmpty) {
        _streetController.text = normalizeAddressComponent(street);
      }
    }
    if (_houseNumberController.text.trim().isEmpty) {
      final house = prefs.getString('user_house_number');
      if (house != null && house.isNotEmpty) {
        _houseNumberController.text = normalizeAddressComponent(house);
      }
    }
    setState(() {});
  }

  // Пересчет суммы корзины, включая экстра и опции, на основе CartService.items
  Future<void> _refreshCartTotal() async {
    final items = CartService.items;
    if (items.isEmpty) {
      if (mounted) {
        setState(() {
          _currentTotalSum = 0.0;
          _currentTotalSumDiscounted = 0.0;
          _currentDiscountAmount = 0.0;
          _linePromotionPrices = {};
        });
      }
      return;
    }

    final promotions = await getCachedPromotions(now: DateTime.now());

    // Собираем уникальные идентификаторы для батч-запросов
    final itemIds = items.map((e) => e.itemId).toSet().toList();
    final sizeIds = items
        .map((e) => e.sizeId)
        .where((e) => e != null)
        .cast<int>()
        .toSet()
        .toList();
    final optionIds = <int>{};
    final extraIds = <int>{};
    for (final it in items) {
      optionIds.addAll(it.options.keys);
      extraIds.addAll(it.extras.keys);
    }

    // Карта цен на опции: option_id -> price_delta
    final optionPriceMap = <int, double>{};
    if (optionIds.isNotEmpty) {
      // В v2 опции не имеют наценок — оставляем пустую карту, все дельты 0
    }

    // Карта цен на экстра: (menu_item_id, size_id?, extra_id) -> price
    final extraPriceMap = <String, double>{};
    if (extraIds.isNotEmpty && sizeIds.isNotEmpty) {
      final rows = await Supabase.instance.client
          .from('menu_v2_extra_price_by_size')
          .select('size_id, extra_id, price')
          .filter('extra_id', 'in', extraIds.toList())
          .filter('size_id', 'in', sizeIds);
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final sid = (r['size_id'] as int?) ?? 0;
        final eid = (r['extra_id'] as int?) ?? 0;
        final p = (r['price'] as num).toDouble();
        extraPriceMap['$sid|$eid'] = p;
      }
    }

    double sum = 0.0;
    // Подготовим для скидок: группировка одинаковых конфигураций
    final grouped = <String, List<CartItem>>{};
    for (final it in items) {
      final sigOpts =
          it.options.entries.map((e) => '${e.key}:${e.value}').join(',');
      final sigExtras =
          it.extras.entries.map((e) => '${e.key}:${e.value}').join(',');
      final metaSig = _metaSignature(it);
      final key = '${it.itemId}|${it.size}|$sigExtras|$sigOpts|$metaSig';
      grouped.putIfAbsent(key, () => []).add(it);
    }
    // Получим категории для всех itemId
    final Map<int, int> itemIdToCategory = {};
    if (itemIds.isNotEmpty) {
      final catRows = await Supabase.instance.client
          .from('menu_v2_item')
          .select('id, category_id')
          .filter('id', 'in', itemIds);
      for (final r in (catRows as List).cast<Map<String, dynamic>>()) {
        final mid = (r['id'] as int?) ?? 0;
        final cid = (r['category_id'] as int?) ?? 0;
        if (mid != 0) itemIdToCategory[mid] = cid;
      }
    }
    final cartList = <Map<String, dynamic>>[];
    for (final it in items) {
      double line = it.basePrice;
      // Экстра
      if (it.extras.isNotEmpty) {
        for (final entry in it.extras.entries) {
          final eid = entry.key;
          final qty = entry.value;
          final key = '${it.sizeId}|$eid';
          final price = extraPriceMap[key] ?? 0.0;
          line += price * qty;
        }
      }
      // Опции
      if (it.options.isNotEmpty) {
        for (final entry in it.options.entries) {
          final oid = entry.key;
          final qty = entry.value;
          final delta = optionPriceMap[oid] ?? 0.0;
          line += delta * qty;
        }
      }
      sum += line;
    }

    // Собираем cartList с агрегацией
    final linePromotions = <String, PromotionPrice>{};
    for (final entry in grouped.entries) {
      final first = entry.value.first;
      final count = entry.value.length;
      // вычисляем цену за 1 с учётом экстра/опций
      double unit = first.basePrice;
      if (first.extras.isNotEmpty) {
        for (final e in first.extras.entries) {
          final key = '${first.sizeId}|${e.key}';
          final price = extraPriceMap[key] ?? 0.0;
          unit += price * e.value;
        }
      }
      if (first.options.isNotEmpty) {
        for (final o in first.options.entries) {
          final delta = optionPriceMap[o.key] ?? 0.0;
          unit += delta * o.value;
        }
      }
      final categoryId = itemIdToCategory[first.itemId];
      cartList.add({
        'id': first.itemId,
        'category_id': categoryId,
        'size_id': first.sizeId,
        'price': unit,
        'quantity': count,
      });
      linePromotions[entry.key] = evaluatePromotionForUnitPrice(
        promotions: promotions,
        unitPrice: unit,
        itemId: first.itemId,
        categoryId: categoryId,
        sizeId: first.sizeId,
      );
    }

    // Скидки
    DiscountResult? dres;
    try {
      dres = await calculateDiscountedTotal(cartItems: cartList, subtotal: sum);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _currentTotalSum = sum; // без скидки (для правил UpSell)
        _currentTotalSumDiscounted = dres?.total ?? sum;
        _currentDiscountAmount = dres?.totalDiscount ?? 0.0;
        _linePromotionPrices = linePromotions;
      });
    }
  }

  Future<void> _loadUserProfileIfAuth() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final userData = await supabase
        .from('user_data')
        .select('first_name, phone, city, street, house_number, postal_code')
        .eq('id', user.id)
        .maybeSingle();

    // Используем контроллеры только если виджет еще смонтирован
    if (!mounted) return;
    if (userData != null) {
      _nameController.text = userData['first_name']?.toString() ?? '';
      _phoneController.text = userData['phone']?.toString() ?? '';
      // Применяем нормализацию для адресных компонентов (во избежание русских или неформатированных значений)
      _cityController.text =
          normalizeAddressComponent(userData['city']?.toString() ?? '');
      _streetController.text =
          normalizeAddressComponent(userData['street']?.toString() ?? '');
      _houseNumberController.text =
          normalizeAddressComponent(userData['house_number']?.toString() ?? '');
      _postalController.text = userData['postal_code']?.toString() ?? '';
      setState(() {});
    }
  }

  Future<void> _showUpsellDialog() async {
    // Предзагрузка офферов: если пусто, диалог не показываем, чтобы избежать «чёрного квадрата»
    final offers = await UpSellService.fetchUpsell(
      channel: 'checkout',
      subtotal: _currentTotalSum,
      userId: Supabase.instance.client.auth.currentUser?.id,
    );
    if (!mounted || offers.isEmpty) return;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Upsell',
      pageBuilder: (_, __, ___) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height * 0.45,
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: UpSellWidget(
                    channel: 'checkout',
                    subtotal: _currentTotalSum,
                    autoCloseOnAdd: true,
                    initialItems: offers,
                    onItemAdded: () async {
                      await _refreshCartTotal();
                      if (mounted) setState(() {});
                    },
                    onItemTap: (itemId) async {
                      Navigator.of(context, rootNavigator: true)
                          .pop(); // исправлено
                      // Подгружаем полные данные о товаре
                      final supabase = Supabase.instance.client;
                      final m = await supabase.from('menu_v2_item').select('''
                            id,
                            name,
                            description,
                            image_url,
                            sku,
                            has_sizes
                          ''').eq('id', itemId).maybeSingle();
                      if (m == null) return;
                      // Определяем минимальную цену
                      final hasMulti = (m['has_sizes'] as bool?) ?? false;
                      double minPrice = 0.0;
                      final List<Map<String, dynamic>> pr = await supabase
                          .from('menu_v2_item_size_price')
                          .select('price')
                          .eq('item_id', itemId)
                          .eq('is_available', true)
                          .order('price', ascending: true)
                          .limit(1);
                      if (pr.isNotEmpty) {
                        minPrice = (pr.first['price'] as num).toDouble();
                      }
                      final menuItem = MenuItem(
                        id: (m['id'] as int?) ?? 0,
                        name: m['name'] as String? ?? '',
                        description: m['description'] as String?,
                        imageUrl: m['image_url'] as String?,
                        article: m['sku'] as String?,
                        klein: null,
                        normal: null,
                        gross: null,
                        familie: null,
                        party: null,
                        minPrice: minPrice,
                        hasMultipleSizes: hasMulti,
                        singleSizePrice: hasMulti ? null : minPrice,
                      );
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MenuItemDetailScreen(item: menuItem),
                      ));
                    },
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context, rootNavigator: true)
                        .pop(), // исправлено
                    child:
                        const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: anim, child: child),
        );
      },
    );
  }

  Future<void> _useCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Bitte aktiviere die Standortdienste.')));
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Standortberechtigung verweigert.')));
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
        localeIdentifier: 'de_DE', // Явно указываем немецкий язык
      );
      final pl = placemarks.first;
      setState(() {
        // Нормализуем каждый компонент перед установкой
        _cityController.text = normalizeAddressComponent(pl.locality ?? '');
        _streetController.text =
            normalizeAddressComponent(pl.thoroughfare ?? '');
        _houseNumberController.text =
            normalizeAddressComponent(pl.subThoroughfare ?? '');
        _postalController.text = pl.postalCode ?? '';
        _onPostalChanged(_postalController.text);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Standort ermitteln fehlgeschlagen: $e')));
    }
  }

  Future<void> _pickTime() async {
    final t =
        await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) {
      final now = DateTime.now();
      if (!WorkingHours.isWithin(t, now)) {
        final intervals = WorkingHours.intervals(now)
            .map((i) =>
                '${i['start']!.format(context)}–${i['end']!.format(context)}')
            .join(', ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Bitte wählen Sie eine andere Zeit: $intervals')));
        return;
      }
      setState(() {
        _selectedTime = t;
        _isCustomTime = true;
      });
    }
  }

  void _onPostalChanged(String code) {
    final trimmed = code.trim();
    if (trimmed.length < 3) {
      if (mounted) {
        setState(() {
          _minOrderAmount = null;
        });
      }
      return;
    }
    _fetchMinOrder(trimmed);
  }

  Future<void> _fetchMinOrder(String postal) async {
    setState(() {
      _loadingMinOrder = true;
    });
    final minOrder =
        await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    if (!mounted) return;
    setState(() {
      _minOrderAmount = minOrder;
      _loadingMinOrder = false;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Проверка минимальной суммы для доставки
    if (_isDelivery && _minOrderAmount != null) {
      final effectiveTotal = _currentTotalSumDiscounted; // уже после скидок
      if (effectiveTotal + 0.0001 < _minOrderAmount!) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Mindestbestellwert: €${_minOrderAmount!.toStringAsFixed(2)} (aktuell: €${effectiveTotal.toStringAsFixed(2)})',
            ),
          ),
        );
        return;
      }
    }
    if (_isCustomTime && _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bitte gewünschte Uhrzeit wählen')));
      return;
    }
    _formKey.currentState!.save();

    try {
      // Сохраним снапшот корзины до очистки сервиса
      final cartSnapshot = List<CartItem>.from(CartService.items);

      final int orderId = await OrderService.createOrder(
        name: _nameController.text,
        phone: _phoneController.text,
        isDelivery: _isDelivery,
        paymentMethod: _paymentMethod,
        city: _cityController.text,
        street: _streetController.text,
        houseNumber: _houseNumberController.text,
        postalCode: _postalController.text,
        floor: _floorController.text,
        comment: _orderCommentController.text,
        courierComment: _courierCommentController.text,
        itemComments: widget.itemComments,
        totalSum: widget.totalSum,
        isCustomTime: _isCustomTime,
        scheduledTime: _isCustomTime && _selectedTime != null
            ? DateTime(
                DateTime.now().year,
                DateTime.now().month,
                DateTime.now().day,
                _selectedTime!.hour,
                _selectedTime!.minute,
              )
            : null,
        totalDiscount: widget.totalDiscount,
        appliedDiscounts: widget.appliedDiscounts,
      );
      if (!mounted) return;

      // Сохраним локально last_order_id, чтобы баннер показывался и для гостя
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_order_id', orderId);
        await _saveLastOrderSnapshotLocal(prefs, orderId, cartSnapshot);
      } catch (_) {}

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bestellung erfolgreich gespeichert!')));

      if (user == null) {
        await showDialog(
          context: context,
          builder: (context) {
            final appTheme = ThemeProvider.of(context);
            return AlertDialog(
              backgroundColor: appTheme.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Konto erstellen?',
                style: GoogleFonts.poppins(
                  color: appTheme.textColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ihre Bestellung wurde erfolgreich aufgegeben!',
                      style: GoogleFonts.poppins(color: appTheme.textColor),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Möchten Sie ein Konto erstellen и von exklusiven Vorteilen profitieren?',
                      style: GoogleFonts.poppins(color: appTheme.textColor),
                    ),
                    const SizedBox(height: 12),
                    // Исправлено: передаем AppTheme вместо ThemeProvider
                    _buildBenefitRow(Icons.cake, 'Geburtstagsrabatt', appTheme),
                    _buildBenefitRow(
                        Icons.star, 'Exklusive Angebote', appTheme),
                    _buildBenefitRow(Icons.history, 'Bestellverlauf', appTheme),
                    _buildBenefitRow(
                        Icons.flash_on, 'Schneller Checkout', appTheme),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Nein, danke',
                      style: TextStyle(color: appTheme.textColorSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appTheme.primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Ja, registrieren',
                      style: TextStyle(color: appTheme.textColor)),
                ),
              ],
            );
          },
        ).then((wantRegister) {
          if (wantRegister == true) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EmailSignupScreen(
                  // Передаем известные поля для автозаполнения
                  initialName: _nameController.text,
                  initialPhone: _phoneController.text,
                  initialCity: _cityController.text,
                  initialStreet: _streetController.text,
                  initialHouseNumber: _houseNumberController.text,
                  initialPostal: _postalController.text,
                ),
              ),
            );
          } else {
            // После заказа показываем экран статуса
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (_) => OrderStatusScreen(orderId: orderId)),
              (route) => false,
            );
          }
        });
      } else {
        // Авторизован: сразу показываем статус заказа
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => OrderStatusScreen(orderId: orderId)),
          (route) => false,
        );
      }
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

  Future<void> _saveLastOrderSnapshotLocal(
      SharedPreferences prefs, int orderId, List<CartItem> items) async {
    try {
      // Подготовим карты цен, чтобы зафиксировать цены в момент заказа
      final sizeIds = items
          .map((e) => e.sizeId)
          .where((e) => e != null)
          .cast<int>()
          .toSet()
          .toList();
      final optionIds = <int>{};
      final extraIds = <int>{};
      for (final it in items) {
        optionIds.addAll(it.options.keys);
        extraIds.addAll(it.extras.keys);
      }

      // Опции: id -> {name, delta}
      final optionInfo = <int, Map<String, dynamic>>{};
      if (optionIds.isNotEmpty) {
        final optRows = await Supabase.instance.client
            .from('menu_v2_modifier_option')
            .select('id, name')
            .filter('id', 'in', '(${optionIds.join(',')})');
        for (final r in (optRows as List).cast<Map<String, dynamic>>()) {
          final id = (r['id'] as int?) ?? 0;
          final name = (r['name'] as String?) ?? '';
          optionInfo[id] = {
            'name': name,
            'delta': 0.0,
          };
        }
      }

      // Допы: цены по размеру и карта имён extra_id -> name
      final extraPriceMap = <String, double>{};
      final extraNameMap = <int, String>{};
      int? fallbackSizeId;
      if (extraIds.isNotEmpty) {
        final sizeSet = sizeIds.toSet();
        if (sizeSet.isEmpty) {
          final normalRow = await Supabase.instance.client
              .from('menu_size')
              .select('id')
              .eq('name', 'Normal')
              .maybeSingle();
          fallbackSizeId = (normalRow?['id'] as int?);
          if (fallbackSizeId != null) {
            sizeSet.add(fallbackSizeId);
          }
        }

        if (sizeSet.isNotEmpty) {
          final rows = await Supabase.instance.client
              .from('menu_v2_extra_price_by_size')
              .select('size_id, extra_id, price')
              .filter('size_id', 'in', '(${sizeSet.join(',')})')
              .filter('extra_id', 'in', '(${extraIds.join(',')})');
          for (final r in (rows as List).cast<Map<String, dynamic>>()) {
            final sid = (r['size_id'] as int?) ?? 0;
            final eid = (r['extra_id'] as int?) ?? 0;
            final price = (r['price'] as num).toDouble();
            extraPriceMap['$sid|$eid'] = price;
          }
        }

        final names = await Supabase.instance.client
            .from('menu_v2_extra')
            .select('id, name')
            .filter('id', 'in', '(${extraIds.join(',')})');
        for (final r in (names as List).cast<Map<String, dynamic>>()) {
          extraNameMap[(r['id'] as int?) ?? 0] = (r['name'] as String?) ?? '';
        }
      }

      // Сформируем снапшот
      final List<Map<String, dynamic>> itemSnaps = [];
      for (final it in items) {
        final exList = <Map<String, dynamic>>[];
        it.extras.forEach((eid, qty) {
          final resolvedSizeId = it.sizeId ?? fallbackSizeId;
          final priceKey =
              resolvedSizeId != null ? '${resolvedSizeId}|$eid' : null;
          final price =
              priceKey != null ? (extraPriceMap[priceKey] ?? 0.0) : 0.0;
          exList.add({
            'id': eid,
            'name': extraNameMap[eid] ?? 'Extra #$eid',
            'price': price,
            'quantity': qty
          });
        });
        final optList = <Map<String, dynamic>>[];
        it.options.forEach((oid, qty) {
          final oi = optionInfo[oid];
          final name = oi != null && (oi['name'] as String).isNotEmpty
              ? oi['name'] as String
              : 'Option #$oid';
          final delta = (oi != null ? (oi['delta'] as double) : 0.0);
          optList.add(
              {'id': oid, 'name': name, 'price_delta': delta, 'quantity': qty});
        });
        itemSnaps.add({
          'name': it.name,
          'size': it.size,
          'base_price': it.basePrice,
          'extras': exList,
          'options': optList,
        });
      }

      final nowIso = DateTime.now().toIso8601String();
      final scheduled = _isCustomTime && _selectedTime != null
          ? DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              _selectedTime!.hour,
              _selectedTime!.minute,
            ).toIso8601String()
          : null;
      final snapshot = {
        'id': orderId,
        'created_at_local': nowIso,
        'is_delivery': _isDelivery,
        if (scheduled != null) 'scheduled_time': scheduled,
        'discount_amount': _currentDiscountAmount,
        'total_after': _currentTotalSumDiscounted,
        'items': itemSnaps,
      };
      await prefs.setString('last_order_snapshot', jsonEncode(snapshot));
    } catch (_) {
      // игнорируем — баннер просто не покажет локальные детали
    }
  }

  // Вспомогательный метод для строки преимущества
  Widget _buildBenefitRow(IconData icon, String title, appTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: appTheme.primaryColor, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: appTheme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    final theme = Theme.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        color: theme.colorScheme.onSurface.withOpacity(0.7),
        fontWeight: FontWeight.w500,
      ),
      filled: true,
      fillColor: theme.cardColor,
      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: theme.colorScheme.primary, width: 2),
      ),
    );
  }

  void _showOrderCommentDialog(BuildContext context, ThemeData theme) {
    final appTheme = ThemeProvider.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: appTheme.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Kommentar zur Bestellung',
          style: GoogleFonts.poppins(
              color: appTheme.textColor, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _orderCommentController,
          style: TextStyle(color: appTheme.textColor),
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Kommentar...',
            hintStyle: TextStyle(color: appTheme.textColorSecondary),
            filled: true,
            fillColor: appTheme.backgroundColor.withOpacity(0.15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: appTheme.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: appTheme.borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: appTheme.primaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Abbrechen',
                style: TextStyle(color: appTheme.textColorSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: appTheme.primaryColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context),
            child:
                Text('Speichern', style: TextStyle(color: appTheme.textColor)),
          ),
        ],
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
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Bestellung',
            style: GoogleFonts.fredokaOne(color: appTheme.primaryColor),
          ),
          centerTitle: true,
        ),
        body: NoInternetWidget(
          onRetry: () {
            setState(() {
              _error = null;
            });
          },
          errorText: _error,
        ),
      );
    }

    final items = CartService.items;
    final grouped = <String, List<CartItem>>{};
    for (var cartItem in items) {
      final optionsSig =
          cartItem.options.entries.map((e) => '${e.key}:${e.value}').join(',');
      final extrasSig =
          cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',');
      // Включаем сигнатуру метаданных (например, bundle), чтобы разные композиции не схлопывались
      final metaSig = _metaSignature(cartItem);
      final key =
          '${cartItem.itemId}|${cartItem.size}|$extrasSig|$optionsSig|$metaSig';
      grouped.putIfAbsent(key, () => []).add(cartItem);
    }
    final orderLines = grouped.entries
        .map((entry) => {
              'key': entry.key,
              'item': entry.value.first,
              'count': entry.value.length
            })
        .toList();

    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: appTheme.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Bestellung',
          style: GoogleFonts.fredokaOne(color: appTheme.primaryColor),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  color: appTheme.cardColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Bestellübersicht',
                                style: GoogleFonts.poppins(
                                  color: appTheme.textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.comment_outlined,
                                color: _orderCommentController.text.isEmpty
                                    ? appTheme.iconColor
                                    : appTheme.primaryColor,
                              ),
                              tooltip: 'Комментарий к заказу',
                              onPressed: () => _showOrderCommentDialog(
                                  context, Theme.of(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_isDelivery &&
                            _minOrderAmount != null &&
                            _currentTotalSumDiscounted + 0.0001 <
                                _minOrderAmount!)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.4),
                                  width: 0.8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.redAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Mindestbestellwert €${_minOrderAmount!.toStringAsFixed(2)} – aktuell €${_currentTotalSumDiscounted.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: Colors.redAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...orderLines.map((line) {
                          final it = line['item'] as CartItem;
                          final cnt = line['count'] as int;
                          final lineKey = line['key'] as String;
                          final priceInfo = _linePromotionPrices[lineKey];
                          return FutureBuilder<List<Map<String, dynamic>>>(
                            future: _loadExtrasInfo(it.itemId, it.extras,
                                sizeId: it.sizeId, sizeName: it.size),
                            builder: (context, esnap) {
                              final extras = esnap.data ?? [];
                              return FutureBuilder<List<Map<String, dynamic>>>(
                                future: _loadOptionsInfo(it.options),
                                builder: (context, osnap) {
                                  final opts = osnap.data ?? [];
                                  // Печатаем покомпонентно: базовая позиция, затем extras и options.
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '$cnt × ${it.article != null ? '[${it.article!}] ' : ''}${it.name} (${it.size})',
                                                style: GoogleFonts.poppins(
                                                  color: appTheme
                                                      .textColorSecondary,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            priceInfo != null
                                                ? PriceWithPromotion(
                                                    basePrice:
                                                        priceInfo.basePrice,
                                                    finalPrice:
                                                        priceInfo.finalPrice,
                                                    formatter: (value) =>
                                                        '€${value.toStringAsFixed(2)}',
                                                    finalStyle:
                                                        GoogleFonts.poppins(
                                                      color: appTheme
                                                          .textColorSecondary,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    baseStyle:
                                                        GoogleFonts.poppins(
                                                      color: appTheme
                                                          .textColorSecondary
                                                          .withValues(
                                                              alpha: 0.65),
                                                      fontSize: 13,
                                                    ),
                                                    alignment:
                                                        MainAxisAlignment.end,
                                                  )
                                                : Text(
                                                    '€${it.basePrice.toStringAsFixed(2)}',
                                                    style: GoogleFonts.poppins(
                                                      color: appTheme
                                                          .textColorSecondary,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                          ],
                                        ),
                                        if (extras.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 10, top: 2),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: extras
                                                  .map((e) => Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              '+ ${e['name']} ×${e['quantity']}',
                                                              style: GoogleFonts
                                                                  .poppins(
                                                                color: appTheme
                                                                    .textColorSecondary,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          Text(
                                                            '+€${(e['price'] as double).toStringAsFixed(2)}',
                                                            style: GoogleFonts
                                                                .poppins(
                                                              color: appTheme
                                                                  .textColorSecondary,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ],
                                                      ))
                                                  .toList(),
                                            ),
                                          ),
                                        if (opts.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 10, top: 2),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: opts
                                                  .map((o) => Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .spaceBetween,
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              '+ ${o['name']} ×${o['quantity']}',
                                                              style: GoogleFonts
                                                                  .poppins(
                                                                color: appTheme
                                                                    .textColorSecondary,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              width: 8),
                                                          if ((o['priceDelta']
                                                                  as double) !=
                                                              0)
                                                            Text(
                                                              '+€${(o['priceDelta'] as double).toStringAsFixed(2)}',
                                                              style: GoogleFonts
                                                                  .poppins(
                                                                color: appTheme
                                                                    .textColorSecondary,
                                                                fontSize: 12,
                                                              ),
                                                            ),
                                                        ],
                                                      ))
                                                  .toList(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        }),
                        const SizedBox(height: 6),
                        Divider(color: appTheme.borderColor.withOpacity(0.2)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Gesamt:',
                                      style: GoogleFonts.poppins(
                                        color: appTheme.textColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '€${_currentTotalSumDiscounted.toStringAsFixed(2)}',
                                    style: GoogleFonts.poppins(
                                      color: appTheme.textColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    'Zahlungsart:',
                                    style: GoogleFonts.poppins(
                                      color: appTheme.textColorSecondary,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: appTheme.primaryColor
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: appTheme.primaryColor
                                              .withOpacity(0.3),
                                          width: 0.7),
                                    ),
                                    child: Text(
                                      _paymentMethod == 'cash'
                                          ? 'Bar'
                                          : 'Karte (mobiles Terminal)',
                                      style: GoogleFonts.poppins(
                                        color: appTheme.primaryColor,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_currentDiscountAmount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'inkl. Rabatt',
                                    style: GoogleFonts.poppins(
                                      color: appTheme.textColorSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (_currentDiscountAmount > 0) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Rabatt:',
                                  style: GoogleFonts.poppins(
                                    color: appTheme.primaryColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '-€${_currentDiscountAmount.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  color: appTheme.primaryColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appTheme.buttonColor,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const CartScreen())),
                          child: Text(
                            'Bestellung bearbeiten',
                            style: GoogleFonts.poppins(
                              color: appTheme.textColor,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // — Имя и телефон —
                Card(
                  color: appTheme.cardColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: appTheme.textColor),
                        decoration: _inputDecoration('Name'),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Name ist erforderlich'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        style: TextStyle(color: appTheme.textColor),
                        decoration: _inputDecoration('Telefon'),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Telefon ist erforderlich';
                          final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                          if (digits.length < 5) return 'Ungültige Nummer';
                          return null;
                        },
                      ),
                    ]),
                  ),
                ),

                // — Abholung или Lieferung —
                Card(
                  color: appTheme.cardColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Abholung oder Lieferung',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColor, fontSize: 16)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Lieferung',
                                      style: TextStyle(
                                          color: appTheme.textColor))),
                              value: true,
                              groupValue: _isDelivery,
                              onChanged: (v) =>
                                  setState(() => _isDelivery = true),
                              activeColor: appTheme.primaryColor,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text('Abholung',
                                      style: TextStyle(
                                          color: appTheme.textColor))),
                              value: false,
                              groupValue: _isDelivery,
                              onChanged: (v) =>
                                  setState(() => _isDelivery = false),
                              activeColor: appTheme.primaryColor,
                            ),
                          ),
                        ]),
                        if (_isDelivery) ...[
                          Divider(color: appTheme.borderColor.withOpacity(0.2)),
                          ElevatedButton.icon(
                            icon: Icon(Icons.my_location,
                                color: appTheme.textColor),
                            label: Text('Aktuellen Standort verwenden',
                                style: TextStyle(color: appTheme.textColor)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appTheme.cardColor,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12, horizontal: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _useCurrentLocation,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cityController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Stadt'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Stadt ist erforderlich'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _streetController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Straße'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Straße ist erforderlich'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _houseNumberController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Hausnummer'),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Hausnummer ist erforderlich'
                                : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _postalController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Postleitzahl'),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'PLZ ist erforderlich'
                                : null,
                            onChanged: _onPostalChanged,
                          ),
                          if (_isDelivery)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _loadingMinOrder
                                        ? Text(
                                            'Mindestbestellwert wird geladen…',
                                            style: GoogleFonts.poppins(
                                              color:
                                                  appTheme.textColorSecondary,
                                              fontSize: 12,
                                            ),
                                          )
                                        : Text(
                                            _minOrderAmount != null
                                                ? 'Mindestbestellwert: €${_minOrderAmount!.toStringAsFixed(2)}'
                                                : 'Kein Mindestbestellwert gefunden',
                                            style: GoogleFonts.poppins(
                                              color:
                                                  appTheme.textColorSecondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                  ),
                                  if (_minOrderAmount != null &&
                                      _currentTotalSumDiscounted + 0.0001 <
                                          (_minOrderAmount ?? 0))
                                    Text(
                                      'Zu wenig',
                                      style: GoogleFonts.poppins(
                                        color: Colors.redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _floorController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Etage (optional)'),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _courierCommentController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration(
                                'Kommentar für den Kurier (optional)'),
                            maxLines: 3,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // — Gewünschte Zeit —
                Card(
                  color: appTheme.cardColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Gewünschte Zeit',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColor, fontSize: 16)),
                        Divider(color: appTheme.borderColor.withOpacity(0.2)),
                        ListTile(
                          leading: Icon(Icons.flash_on,
                              color: IconTheme.of(context).color),
                          title: Text('So schnell wie möglich',
                              style: GoogleFonts.poppins(
                                  color: appTheme.textColor)),
                          trailing: !_isCustomTime
                              ? Icon(Icons.check, color: appTheme.primaryColor)
                              : null,
                          onTap: () {
                            setState(() {
                              _isCustomTime = false;
                              _selectedTime = null;
                            });
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.access_time,
                              color: IconTheme.of(context).color),
                          title: Text('Wunschzeit einstellen',
                              style: GoogleFonts.poppins(
                                  color: appTheme.textColor)),
                          subtitle: Text(
                            _selectedTime == null
                                ? 'Tippen, um Zeit auszuwählen'
                                : 'Gewählte Zeit: ${_selectedTime!.format(context)}',
                            style: TextStyle(
                                color: appTheme.textColor.withOpacity(0.7)),
                          ),
                          trailing: _selectedTime != null
                              ? Icon(Icons.check, color: appTheme.primaryColor)
                              : null,
                          onTap: _pickTime,
                        ),
                      ],
                    ),
                  ),
                ),

                // — Zahlungsart —
                Card(
                  color: appTheme.cardColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zahlungsart',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColor, fontSize: 16)),
                        const SizedBox(height: 8),
                        RadioListTile<String>(
                          value: 'cash',
                          groupValue: _paymentMethod,
                          activeColor: appTheme.primaryColor,
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'cash'),
                          title: Text('Barzahlung',
                              style: TextStyle(color: appTheme.textColor)),
                        ),
                        RadioListTile<String>(
                          value: 'card',
                          groupValue: _paymentMethod,
                          activeColor: appTheme.primaryColor,
                          onChanged: (v) =>
                              setState(() => _paymentMethod = v ?? 'card'),
                          title: Text('Kartenzahlung',
                              style: TextStyle(color: appTheme.textColor)),
                        ),
                        if (_paymentMethod == 'card')
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 6, left: 4, right: 4),
                            child: Text(
                              'Der Kurier bringt ein mobiles Kartenterminal (EC-/Kreditkarte).',
                              style: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // — Abschicken —
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appTheme.buttonColor,
                    foregroundColor: appTheme.textColor,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 1,
                  ),
                  onPressed: _submit,
                  child: Text(
                    'Bestellung abschicken',
                    style: GoogleFonts.poppins(
                        fontSize: 18, color: appTheme.textColor),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _metaSignature(CartItem it) {
    final m = it.meta;
    if (m == null) return '';
    final type = m['type'];
    if (type == 'bundle') {
      final bid = m['bundleId'];
      final slots =
          (m['slots'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      final parts = <String>[];
      for (final s in slots) {
        final sid = s['slotId'];
        final items =
            (s['items'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final ids = items.map((e) => e['itemId']).toList()
          ..sort((a, b) => (a as int).compareTo(b as int));
        parts.add('$sid:${ids.join("_")}');
      }
      parts.sort();
      return 'bundle:$bid:${parts.join("|")}';
    }
    return '';
  }
}
