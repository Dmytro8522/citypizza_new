// lib/screens/order_status_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/theme_provider.dart';
import '../services/app_config_service.dart' as cfg;

class OrderStatusScreen extends StatefulWidget {
  final int orderId;
  const OrderStatusScreen({super.key, required this.orderId});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen>
    with SingleTickerProviderStateMixin {
  final _db = Supabase.instance.client;
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;
  int _visibleMinutes = 60; // default
  int _etaMinutes = 45; // default ETA hint
  final Map<int, String> _optionNameCache = {};
  RealtimeChannel? _channel;
  late final AnimationController _blinkCtrl;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _blinkCtrl.repeat(reverse: true);
    _init();
  }

  Future<void> _init() async {
    try {
      // Load config first
      _visibleMinutes = await cfg.AppConfigService.get<int>(
          'current_order_widget_minutes',
          defaultValue: 60);
      _etaMinutes = await cfg.AppConfigService.get<int>('default_eta_minutes',
          defaultValue: 45);

      // Load order with nested items/extras/options for detailed view
      Map<String, dynamic>? row = await _db
          .from('orders')
          .select(
              '*, order_items(*, order_item_extras(*), order_item_options(*))')
          .eq('id', widget.orderId)
          .maybeSingle();
      // Fallback для гостя/без доступа: читаем локальный снапшот
      if (row == null) {
        // Если заказа нет в базе — очищаем локальные ключи, чтобы виджет больше не показывался.
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedId = prefs.getInt('last_order_id');
          if (savedId == widget.orderId) {
            await prefs.remove('last_order_id');
          }
          final snapStr = prefs.getString('last_order_snapshot');
          if (snapStr != null) {
            try {
              final snap = jsonDecode(snapStr) as Map<String, dynamic>;
              final sid = (snap['id'] as int?) ?? 0;
              if (sid == widget.orderId) {
                await prefs.remove('last_order_snapshot');
              }
            } catch (_) {
              await prefs.remove('last_order_snapshot');
            }
          }
        } catch (_) {}
        try {
          final prefs = await SharedPreferences.getInstance();
          final snapStr = prefs.getString('last_order_snapshot');
          if (snapStr != null) {
            final snap = jsonDecode(snapStr) as Map<String, dynamic>;
            final sid = (snap['id'] as int?) ?? 0;
            if (sid == widget.orderId) {
              final createdLocal = (snap['created_at_local'] as String?);
              final isDelivery = (snap['is_delivery'] as bool?) ?? true;
              final discount =
                  (snap['discount_amount'] as num?)?.toDouble() ?? 0.0;
              final totalAfter =
                  (snap['total_after'] as num?)?.toDouble() ?? 0.0;
              final total = totalAfter + discount;
              final items =
                  (snap['items'] as List?)?.cast<Map<String, dynamic>>() ??
                      const [];
              final builtItems = items.map((it) {
                final extras =
                    (it['extras'] as List?)?.cast<Map<String, dynamic>>() ??
                        const [];
                final opts =
                    (it['options'] as List?)?.cast<Map<String, dynamic>>() ??
                        const [];
                return {
                  'item_name': [
                    it['name'],
                    if ((it['size'] as String?)?.isNotEmpty == true)
                      '(${it['size']})'
                  ].whereType<String>().join(' '),
                  'base_price': (it['base_price'] as num?)?.toDouble() ?? 0.0,
                  'order_item_extras': extras
                      .map((e) => {
                            'extra_id': e['id'],
                            'name': e['name'],
                            'quantity': e['quantity'] ?? 1,
                            'price': (e['price'] as num?)?.toDouble() ?? 0.0,
                          })
                      .toList(),
                  'order_item_options': opts
                      .map((o) => {
                            'option_id': o['id'],
                            'option_name': o['name'],
                            'quantity': o['quantity'] ?? 1,
                            'price_delta':
                                (o['price_delta'] as num?)?.toDouble() ?? 0.0,
                          })
                      .toList(),
                };
              }).toList();
              row = {
                'id': widget.orderId,
                if (createdLocal != null) 'created_at': createdLocal,
                'is_delivery': isDelivery,
                'status': 'eingegangen',
                'discount_amount': discount,
                'total_sum': total,
                'order_items': builtItems,
              };
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _order = row;
        _loading = false;
      });
      _bindRealtime();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _bindRealtime() {
    _channel?.unsubscribe();
    _channel = _db
        .channel('order-status-${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.orderId.toString()),
          callback: (payload) async {
            final row = await _db
                .from('orders')
                .select(
                    '*, order_items(*, order_item_extras(*), order_item_options(*))')
                .eq('id', widget.orderId)
                .maybeSingle();
            if (!mounted) return;
            setState(() {
              _order = row;
            });
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: appTheme.backgroundColor,
        title: Text('Bestellstatus',
            style: GoogleFonts.fredokaOne(color: appTheme.primaryColor)),
        centerTitle: true,
      ),
      body: _buildBody(appTheme),
    );
  }

  Widget _buildBody(appTheme) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: appTheme.primaryColor));
    }
    if (_error != null) {
      return Center(
        child: Text('Fehler: $_error',
            style: GoogleFonts.poppins(color: appTheme.textColor)),
      );
    }
    if (_order == null) {
      return Center(
        child: Text('Bestellung nicht gefunden',
            style: GoogleFonts.poppins(color: appTheme.textColor)),
      );
    }

    // Visibility window control (created_at + _visibleMinutes)
    final createdAtStr = _order!['created_at']?.toString();
    DateTime? createdAt;
    if (createdAtStr != null) {
      try {
        createdAt = DateTime.parse(createdAtStr);
      } catch (_) {}
    }
    final now = DateTime.now().toUtc();
    bool withinWindow = true;
    if (createdAt != null) {
      final expiry = createdAt.add(Duration(minutes: _visibleMinutes));
      withinWindow = now.isBefore(expiry.toUtc());
    }

    // ETA hint: use scheduled_time if present else created_at + _etaMinutes
    DateTime? eta;
    final scheduledStr = _order!['scheduled_time']?.toString();
    if (scheduledStr != null) {
      try {
        eta = DateTime.parse(scheduledStr);
      } catch (_) {}
    }
    eta ??= (createdAt ?? DateTime.now()).add(Duration(minutes: _etaMinutes));

    final status = (_order!['status'] as String?) ?? 'eingegangen';
    final isDelivery = (_order!['is_delivery'] as bool?) ?? true;
    final totalSumRaw = (_order!['total_sum'] as num?)?.toDouble();
    final discount = (_order!['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final totalAfterRaw = (_order!['total_after'] as num?)?.toDouble();
    // Правило отображения:
    // - если есть total_after → показываем его
    // - иначе считаем, что total_sum уже «после скидки» (наш кейс) и показываем total_sum без повторного вычитания
    final displayTotal =
        (totalAfterRaw ?? totalSumRaw ?? 0.0).clamp(0, double.infinity);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!withinWindow)
            _infoCard(
              appTheme,
              icon: Icons.info_outline,
              title: 'Status nicht mehr verfügbar',
              subtitle: 'Diese Bestellung ist älter als $_visibleMinutes Min.',
            ),
          if (withinWindow)
            _statusCard(appTheme,
                status: status, eta: eta, isDelivery: isDelivery),
          const SizedBox(height: 12),
          _summaryCard(appTheme,
              totalAfter: displayTotal.toDouble(),
              discount: discount.toDouble()),
          const SizedBox(height: 12),
          _detailsCard(appTheme, order: _order!),
          const SizedBox(height: 12),
          _itemsCard(appTheme, order: _order!),
          const SizedBox(height: 12),
          _callRestaurantButton(appTheme),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _blinkCtrl.dispose();
    super.dispose();
  }

  Widget _infoCard(appTheme,
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: appTheme.primaryColor),
        title: Text(title,
            style: GoogleFonts.poppins(
                color: appTheme.textColor, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: GoogleFonts.poppins(color: appTheme.textColorSecondary)),
      ),
    );
  }

  Widget _statusCard(appTheme,
      {required String status,
      required DateTime? eta,
      required bool isDelivery}) {
    String statusLabel;
    switch (status.toLowerCase()) {
      case 'preparing':
        statusLabel = 'In Vorbereitung';
        break;
      case 'on_the_way':
        statusLabel = isDelivery ? 'Unterwegs' : 'Bereit zur Abholung';
        break;
      case 'delivered':
        statusLabel = isDelivery ? 'Zugestellt' : 'Abgeholt';
        break;
      default:
        statusLabel = 'Eingegangen';
    }
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текущий статус с мигающей точкой (реалтайм)
            Row(
              children: [
                FadeTransition(
                  opacity: Tween<double>(begin: 0.35, end: 1.0).animate(
                      CurvedAnimation(
                          parent: _blinkCtrl, curve: Curves.easeInOut)),
                  child: Icon(Icons.circle,
                      size: 10, color: appTheme.primaryColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: appTheme.textColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (eta != null)
              Row(
                children: [
                  Icon(Icons.schedule, color: appTheme.iconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Voraussichtlich bis ${_formatTime(eta)}',
                      style: GoogleFonts.poppins(
                          color: appTheme.textColorSecondary),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // Убрали многошаговый прогресс — показываем только текущий статус с мигающей точкой

  Widget _summaryCard(appTheme,
      {required double totalAfter, required double discount}) {
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _kvRow(appTheme, 'Gesamt:', '€${totalAfter.toStringAsFixed(2)}'),
            if (discount > 0)
              _kvRow(appTheme, 'Rabatt:', '-€${discount.toStringAsFixed(2)}',
                  color: appTheme.primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _detailsCard(appTheme, {required Map<String, dynamic> order}) {
    final createdAtStr = order['created_at']?.toString();
    String createdDisp = createdAtStr ?? '';
    try {
      if (createdAtStr != null) {
        final dt = DateTime.parse(createdAtStr);
        createdDisp =
            '${_pad(dt.day)}.${_pad(dt.month)}.${dt.year} ${_pad(dt.hour)}:${_pad(dt.minute)}';
      }
    } catch (_) {}
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bestell-Details',
                style: GoogleFonts.poppins(
                    color: appTheme.textColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _kvRow(appTheme, 'Bestellnummer:', '#${order['id']}'),
            _kvRow(appTheme, 'Bestellt am:', createdDisp),
            _kvRow(appTheme, 'Art:',
                (order['is_delivery'] == true) ? 'Lieferung' : 'Abholung'),
          ],
        ),
      ),
    );
  }

  Widget _itemsCard(appTheme, {required Map<String, dynamic> order}) {
    final items =
        (order['order_items'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      color: appTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bestellpositionen',
                style: GoogleFonts.poppins(
                    color: appTheme.textColor, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...items.map((it) => _itemBlock(appTheme, it)),
          ],
        ),
      ),
    );
  }

  Widget _itemBlock(appTheme, Map<String, dynamic> it) {
    final base = (it['base_price'] as num?)?.toDouble() ?? 0.0;
    final extras =
        (it['order_item_extras'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
    final opts =
        (it['order_item_options'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];

    // Попробуем формировать отображаемое имя как: [Art] Name (+ размер для has_sizes)
    final mid =
        (it['menu_v2_item_id'] as int?) ?? (it['menu_item_id'] as int?) ?? 0;
    final sid = (it['size_id'] as int?);
    final article = (it['article'] as String?);

    return FutureBuilder<Map<String, dynamic>?>(
      future: (() async => await _db
          .from('menu_v2_item')
          .select('name, has_sizes')
          .eq('id', mid)
          .maybeSingle())(),
      builder: (context, snap) {
        final name = (snap.data?['name'] as String?) ??
            ((it['item_name'] as String?) ?? '—');
        final hs = (snap.data?['has_sizes'] as bool?) ?? false;
        return FutureBuilder<Map<String, dynamic>?>(
          future: (sid != null && hs)
              ? (() async => await _db
                  .from('menu_size')
                  .select('name')
                  .eq('id', sid)
                  .maybeSingle())()
              : Future.value(null),
          builder: (context, ss) {
            final sizeName = (ss.data?['name'] as String?) ?? '';
            final display = '${article != null ? '[$article] ' : ''}$name'
                '${(hs && sizeName.isNotEmpty) ? ' ($sizeName)' : ''}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Text(display,
                              style: GoogleFonts.poppins(
                                  color: appTheme.textColor))),
                      const SizedBox(width: 8),
                      Text('€${base.toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              color: appTheme.textColorSecondary)),
                    ],
                  ),
                  if (extras.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: extras.map((e) {
                          final qty = (e['quantity'] as int?) ?? 0;
                          final price = (e['price'] as num?)?.toDouble() ?? 0.0;
                          final resolvedExtraId =
                              (e['menu_v2_extra_id'] as int?) ??
                                  (e['extra_id'] as int?) ??
                                  (e['id'] as int?) ??
                                  0;
                          final ename = (e['name'] as String?) ??
                              'Extra #$resolvedExtraId';
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                  child: Text('+ $ename ×$qty',
                                      style: GoogleFonts.poppins(
                                          color: appTheme.textColorSecondary,
                                          fontSize: 12))),
                              const SizedBox(width: 8),
                              Text('+€${price.toStringAsFixed(2)}',
                                  style: GoogleFonts.poppins(
                                      color: appTheme.textColorSecondary,
                                      fontSize: 12)),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  if (opts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 10, top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            opts.map((o) => _optionLine(appTheme, o)).toList(),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String> _resolveOptionName(int id) async {
    if (id == 0) return 'Option';
    if (_optionNameCache.containsKey(id)) return _optionNameCache[id]!;
    try {
      final row = await _db
          .from('menu_v2_modifier_option')
          .select('name')
          .eq('id', id)
          .maybeSingle();
      final raw = (row?['name'] as String?)?.trim();
      final resolved = (raw != null && raw.isNotEmpty) ? raw : 'Option #$id';
      _optionNameCache[id] = resolved;
      return resolved;
    } catch (_) {
      return 'Option #$id';
    }
  }

  Widget _optionLine(appTheme, Map<String, dynamic> optionRow) {
    final qty = (optionRow['quantity'] as int?) ?? 0;
    final delta = (optionRow['price_delta'] as num?)?.toDouble() ?? 0.0;
    final optId = (optionRow['modifier_option_id'] as int?) ??
        (optionRow['option_id'] as int?) ??
        (optionRow['id'] as int?) ??
        0;
    final storedName =
        (optionRow['option_name'] as String?)?.trim() ?? '';

    Widget buildRow(String name, double effectiveDelta) {
      final showDelta = effectiveDelta.abs() > 0.0001;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text('+ $name ×$qty',
                  style: GoogleFonts.poppins(
                      color: appTheme.textColorSecondary, fontSize: 12))),
          const SizedBox(width: 8),
          if (showDelta)
            Text('+€${effectiveDelta.toStringAsFixed(2)}',
                style: GoogleFonts.poppins(
                    color: appTheme.textColorSecondary, fontSize: 12)),
        ],
      );
    }

    if (storedName.isNotEmpty) {
      return buildRow(storedName, delta);
    }

    return FutureBuilder<String>(
      future: _resolveOptionName(optId),
      builder: (context, snapshot) {
        final resolvedName = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            resolvedName == null) {
          return buildRow('Option', delta);
        }
        return buildRow(resolvedName, delta);
      },
    );
  }

  Widget _callRestaurantButton(appTheme) {
    const phone = '034205 83916';
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: appTheme.primaryColor,
        foregroundColor: appTheme.textColor,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.call),
      label: Text('In der Pizzeria anrufen',
          style: GoogleFonts.poppins(
              color: Colors.black, fontWeight: FontWeight.w600)),
      onPressed: () async {
        final uri = Uri(scheme: 'tel', path: phone.replaceAll(' ', ''));
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      },
    );
  }

  Widget _kvRow(appTheme, String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
              child: Text(k,
                  style:
                      GoogleFonts.poppins(color: appTheme.textColorSecondary))),
          const SizedBox(width: 8),
          Text(v,
              style: GoogleFonts.poppins(
                  color: color ?? appTheme.textColor,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) => '${_pad(t.hour)}:${_pad(t.minute)}';
  String _pad(int v) => v < 10 ? '0$v' : '$v';
}
