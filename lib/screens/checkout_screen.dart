// lib/screens/checkout_screen.dart

import 'dart:convert';
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
import '../widgets/no_internet_widget.dart';
import '../theme/theme_provider.dart';
import 'cart_screen.dart';
import 'menu_item_detail_screen.dart';
import 'menu_screen.dart'; // Для возврата после успешного заказа
import 'home_screen.dart';   
import 'email_signup_screen.dart';

class _ExtraInfo {
  final String name;
  final double price;
  final int quantity;
  _ExtraInfo({required this.name, required this.price, required this.quantity});
}

class CheckoutScreen extends StatefulWidget {
  final double totalSum;
  final Map<String, String> itemComments;
  final double? totalDiscount;
  final List<Map<String, dynamic>>? appliedDiscounts;

  const CheckoutScreen({
    Key? key,
    required this.totalSum,
    required this.itemComments,
    this.totalDiscount,
    this.appliedDiscounts,
  }) : super(key: key);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _upsellShown = false;

  String _name = '';
  String _phone = '';
  bool _isDelivery = true;
  String _paymentMethod = 'cash';
  double? _minOrder;

  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _houseNumberController = TextEditingController();
  final TextEditingController _postalController = TextEditingController();
  final TextEditingController _floorController = TextEditingController();

  final TextEditingController _orderCommentController = TextEditingController();
  final TextEditingController _courierCommentController = TextEditingController();

  bool _isCustomTime = false;
  TimeOfDay? _selectedTime;

  static const Map<String, double> _zoneMin = {
    '04420': 14.0,
    '04205': 19.0,
    '04209': 19.0,
    '04179': 23.0,
    '04178': 24.0,
    '04523': 24.0,
    '06254': 24.0,
    '06686': 24.0,
    '06231': 27.0,
    '04229': 29.0,
    '04249': 29.0,
    '04442': 29.0,
    '04435': 32.0,
  };

  String? _error;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Показ upsell-диалога после первого рендера
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_upsellShown) {
        _upsellShown = true;
        _showUpsellDialog();
      }
      // Важно: загружаем профиль после первого кадра, чтобы избежать конфликтов с контроллерами
      _loadUserProfileIfAuth();
    });
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
      _cityController.text = userData['city']?.toString() ?? '';
      _streetController.text = userData['street']?.toString() ?? '';
      _houseNumberController.text = userData['house_number']?.toString() ?? '';
      _postalController.text = userData['postal_code']?.toString() ?? '';
      setState(() {}); // Обновляем форму, чтобы контроллеры отобразили значения
    }
  }

  void _showUpsellDialog() {
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
                    subtotal: widget.totalSum,
                    onItemAdded: () {
                      setState(() {});
                    },
                    onItemTap: (itemId) async {
                      Navigator.of(context, rootNavigator: true).pop(); // исправлено
                      // Подгружаем полные данные о товаре
                      final supabase = Supabase.instance.client;
                      final m = await supabase
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
                          .eq('id', itemId)
                          .maybeSingle() as Map<String, dynamic>?;
                      if (m == null) return;
                      // Определяем минимальную цену
                      final hasMulti = m['has_multiple_sizes'] as bool? ?? false;
                      final singlePrice = (m['single_size_price'] as num?)?.toDouble() ?? 0.0;
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
                    onTap: () => Navigator.of(context, rootNavigator: true).pop(), // исправлено
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bitte aktiviere die Standortdienste.')));
      return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Standortberechtigung verweigert.')));
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
        localeIdentifier: 'de_DE', // Явно указываем немецкий язык
      );
      final pl = placemarks.first;
      setState(() {
        _cityController.text = pl.locality ?? '';
        _streetController.text = pl.thoroughfare ?? '';
        _houseNumberController.text = pl.subThoroughfare ?? '';
        _postalController.text = pl.postalCode ?? '';
        _onPostalChanged(_postalController.text);
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Standort ermitteln fehlgeschlagen: $e')));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t != null) {
      final now = DateTime.now();
      if (!WorkingHours.isWithin(t, now)) {
        final intervals = WorkingHours.intervals(now)
            .map((i) => '${i['start']!.format(context)}–${i['end']!.format(context)}')
            .join(', ');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bitte wählen Sie eine andere Zeit: $intervals')));
        return;
      }
      setState(() {
        _selectedTime = t;
        _isCustomTime = true;
      });
    }
  }

  void _onPostalChanged(String code) {
    setState(() {
      _minOrder = _zoneMin[code];
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isCustomTime && _selectedTime == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bitte gewünschte Uhrzeit wählen')));
      return;
    }
    _formKey.currentState!.save();

    try {
      await OrderService.createOrder(
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

      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Bestellung erfolgreich gespeichert!')));

      if (user == null) {
        await showDialog(
          context: context,
          builder: (context) {
            final appTheme = ThemeProvider.of(context);
            return AlertDialog(
              backgroundColor: appTheme.cardColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    _buildBenefitRow(Icons.star, 'Exklusive Angebote', appTheme),
                    _buildBenefitRow(Icons.history, 'Bestellverlauf', appTheme),
                    _buildBenefitRow(Icons.flash_on, 'Schneller Checkout', appTheme),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('Nein, danke', style: TextStyle(color: appTheme.textColorSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: appTheme.primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Ja, registrieren', style: TextStyle(color: appTheme.textColor)),
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
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MenuScreen()),
              (route) => false,
            );
          }
        });
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MenuScreen()),
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
          style: GoogleFonts.poppins(color: appTheme.textColor, fontWeight: FontWeight.bold),
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
            child: Text('Abbrechen', style: TextStyle(color: appTheme.textColorSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: appTheme.primaryColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text('Speichern', style: TextStyle(color: appTheme.textColor)),
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
      final key =
          '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}';
      grouped.putIfAbsent(key, () => []).add(cartItem);
    }
    final orderLines = grouped.entries
        .map((entry) => {'key': entry.key, 'item': entry.value.first, 'count': entry.value.length})
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                              onPressed: () => _showOrderCommentDialog(context, Theme.of(context)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...orderLines.map((line) {
                          final key = line['key'] as String;
                          final it = line['item'] as CartItem;
                          final cnt = line['count'] as int;
                          final sumLine = it.basePrice * cnt;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              '$cnt × ${it.article != null ? '[${it.article!}] ' : ''}${it.name} (${it.size}) – €${sumLine.toStringAsFixed(2)}',
                              style: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),
                        Divider(color: appTheme.borderColor.withOpacity(0.2)),
                        // Итоговая сумма заказа
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Gesamtsumme:',
                                style: GoogleFonts.poppins(
                                  color: appTheme.textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '€${widget.totalSum.toStringAsFixed(2)}',
                                style: GoogleFonts.poppins(
                                  color: appTheme.textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if ((widget.totalDiscount ?? 0) > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Rabatt:',
                                  style: GoogleFonts.poppins(
                                    color: appTheme.primaryColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  )),
                              Text('-€${widget.totalDiscount!.toStringAsFixed(2)}',
                                  style: GoogleFonts.poppins(
                                    color: appTheme.primaryColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: appTheme.buttonColor,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(color: appTheme.textColor),
                        decoration: _inputDecoration('Name'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Name ist erforderlich' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        style: TextStyle(color: appTheme.textColor),
                        decoration: _inputDecoration('Telefon'),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Telefon ist erforderlich';
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Abholung oder Lieferung',
                            style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 16)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: FittedBox(fit: BoxFit.scaleDown, child: Text('Lieferung', style: TextStyle(color: appTheme.textColor))),
                              value: true,
                              groupValue: _isDelivery,
                              onChanged: (v) => setState(() => _isDelivery = true),
                              activeColor: appTheme.primaryColor,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: FittedBox(fit: BoxFit.scaleDown, child: Text('Abholung', style: TextStyle(color: appTheme.textColor))),
                              value: false,
                              groupValue: _isDelivery,
                              onChanged: (v) => setState(() => _isDelivery = false),
                              activeColor: appTheme.primaryColor,
                            ),
                          ),
                        ]),
                        if (_isDelivery) ...[
                          Divider(color: appTheme.borderColor.withOpacity(0.2)),
                          ElevatedButton.icon(
                            icon: Icon(Icons.my_location, color: appTheme.textColor),
                            label: Text('Aktuellen Standort verwenden', style: TextStyle(color: appTheme.textColor)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appTheme.cardColor,
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
                            ),
                            onPressed: _useCurrentLocation,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _cityController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Stadt'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Stadt ist erforderlich' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _streetController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Straße'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Straße ist erforderlich' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _houseNumberController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Hausnummer'),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Hausnummer ist erforderlich' : null,
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: _postalController,
                            style: TextStyle(color: appTheme.textColor),
                            decoration: _inputDecoration('Postleitzahl'),
                            keyboardType: TextInputType.number,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'PLZ ist erforderlich' : null,
                            onChanged: _onPostalChanged,
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
                            decoration: _inputDecoration('Kommentar für den Kurier (optional)'),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  margin: const EdgeInsets.only(bottom: 18),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Gewünschte Zeit',
                            style: GoogleFonts.poppins(color: appTheme.textColor, fontSize: 16)),
                        Divider(color: appTheme.borderColor.withOpacity(0.2)),
                        ListTile(
                          leading: Icon(Icons.flash_on, color: IconTheme.of(context).color),
                          title: Text('So schnell wie möglich', style: GoogleFonts.poppins(color: appTheme.textColor)),
                          trailing: !_isCustomTime ? Icon(Icons.check, color: appTheme.primaryColor) : null,
                          onTap: () {
                            setState(() {
                              _isCustomTime = false;
                              _selectedTime = null;
                            });
                          },
                        ),
                        ListTile(
                          leading: Icon(Icons.access_time, color: IconTheme.of(context).color),
                          title: Text('Wunschzeit einstellen', style: GoogleFonts.poppins(color: appTheme.textColor)),
                          subtitle: Text(
                            _selectedTime == null ? 'Tippen, um Zeit auszuwählen' : 'Gewählte Zeit: ${_selectedTime!.format(context)}',
                            style: TextStyle(color: appTheme.textColor.withOpacity(0.7)),
                          ),
                          trailing: _selectedTime != null ? Icon(Icons.check, color: appTheme.primaryColor) : null,
                          onTap: _pickTime,
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 1,
                  ),
                  onPressed: _submit,
                  child: Text(
                    'Bestellung abschicken',
                    style: GoogleFonts.poppins(fontSize: 18, color: appTheme.textColor),
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
}
