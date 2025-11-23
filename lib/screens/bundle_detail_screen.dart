import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/theme_provider.dart';
import '../widgets/no_internet_widget.dart';
import '../widgets/upsell_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/delivery_zone_service.dart';
import '../services/discount_service.dart';
import '../services/cart_service.dart';
import '../utils/globals.dart';

class BundleDetailScreen extends StatefulWidget {
  final int bundleId;
  const BundleDetailScreen({super.key, required this.bundleId});

  @override
  State<BundleDetailScreen> createState() => _BundleDetailScreenState();
}

class _BundleDetailScreenState extends State<BundleDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;

  // Bundle core
  String _bundleName = '';
  String? _bundleDesc;
  double _bundlePrice = 0.0; // прямая цена из menu_v2_bundle.price

  // Slots
  List<_Slot> _slots = [];
  // User selections per slot: slotId -> list of itemIds (length <= max_qty)
  final Map<int, List<_ChosenItem>> _chosenBySlot = {};
  // Loading state per slot for staged UI while allowed items fetched in bulk
  final Set<int> _loadingSlots = <int>{};
  // Cache for extra prices by (sizeId, extraId)
  final Map<String, double> _extraPriceCache = {};
  // Cache extras list per itemId to avoid repeated fetch
  final Map<int, List<_ExtraOption>> _extrasCache = {};
  // Size name lookup (size_id -> name)
  final Map<int, String> _sizeNameById = {};
  final Set<int> _sizeFetchInProgress = {};

  // Mindestbestellwert Hinweis
  double? _minOrderAmount;
  double _discountedCartTotal = 0.0;
  bool _computingCartTotal = false;
  bool get _showMinOrderBar =>
      _minOrderAmount != null &&
      _discountedCartTotal + 0.0001 < _minOrderAmount!;

  Future<void> _ensureSizeName(int sizeId) async {
    if (_sizeNameById.containsKey(sizeId) ||
        _sizeFetchInProgress.contains(sizeId)) return;
    _sizeFetchInProgress.add(sizeId);
    try {
      final row = await _supabase
          .from('menu_size')
          .select('id, name')
          .eq('id', sizeId)
          .maybeSingle();
      if (row != null) {
        setState(() {
          _sizeNameById[sizeId] = (row['name'] as String?) ?? '';
        });
      }
    } catch (_) {
      // ignore
    } finally {
      _sizeFetchInProgress.remove(sizeId);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
    _initMinOrderContext();
    CartService.cartCountNotifier.addListener(_recomputeCartTotal);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch bundle and slots concurrently
      final results = await Future.wait([
        _supabase
            .from('menu_v2_bundle')
            .select('id, name, description, price')
            .eq('id', widget.bundleId)
            .maybeSingle(),
        _supabase
            .from('menu_v2_bundle_slot')
            .select(
                'id, name, min_qty, max_qty, allow_paid_upgrade, sort_order')
            .eq('bundle_id', widget.bundleId)
            .order('sort_order', ascending: true),
      ]);

      final bRow = results[0] as Map<String, dynamic>?;
      if (bRow == null) throw Exception('Bundle nicht gefunden');
      _bundleName = (bRow['name'] as String?) ?? '';
      _bundleDesc = (bRow['description'] as String?)?.trim();
      _bundlePrice = (bRow['price'] as num?)?.toDouble() ?? 0.0;

      final sRows = (results[1] as List).cast<Map<String, dynamic>>();
      final slots = sRows
          .map((m) => _Slot(
                id: (m['id'] as int?) ?? 0,
                name: (m['name'] as String?) ?? '',
                minQty: (m['min_qty'] as int?) ?? 1,
                maxQty: (m['max_qty'] as int?) ?? 1,
                allowPaidUpgrade: (m['allow_paid_upgrade'] as bool?) ?? false,
              ))
          .toList();

      _loadingSlots
        ..clear()
        ..addAll(slots.map((e) => e.id));
      setState(() {
        _slots = slots;
        _loading = false;
      });

      if (slots.isNotEmpty) {
        await _loadAllowedForSlots(slots);
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _initMinOrderContext() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('delivery_mode');
    if (mode != 'delivery') {
      setState(() {
        _minOrderAmount = null;
        _discountedCartTotal = 0.0;
      });
      return;
    }
    final postal = prefs.getString('user_postal_code');
    if (postal == null || postal.isEmpty) return;
    final mo =
        await DeliveryZoneService.getMinOrderForPostal(postalCode: postal);
    setState(() => _minOrderAmount = mo);
    await _computeDiscountedCartTotal();
  }

  void _recomputeCartTotal() {
    _computeDiscountedCartTotal();
  }

  Future<void> _computeDiscountedCartTotal() async {
    final items = CartService.items;
    if (!mounted) return;
    if (items.isEmpty) {
      setState(() => _discountedCartTotal = 0.0);
      return;
    }
    setState(() => _computingCartTotal = true);
    try {
      final supabase = Supabase.instance.client;
      final itemIds = items.map((e) => e.itemId).toSet().toList();
      final sizeIds = items
          .map((e) => e.sizeId)
          .where((e) => e != null)
          .cast<int>()
          .toSet()
          .toList();
      final extraIds = <int>{};
      for (final it in items) extraIds.addAll(it.extras.keys);
      final extraPriceMap = <String, double>{};
      if (extraIds.isNotEmpty && sizeIds.isNotEmpty) {
        final rows = await supabase
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
      final Map<int, int> itemIdToCategory = {};
      if (itemIds.isNotEmpty) {
        final catRows = await supabase
            .from('menu_v2_item')
            .select('id, category_id')
            .filter('id', 'in', itemIds);
        for (final r in (catRows as List).cast<Map<String, dynamic>>()) {
          final mid = (r['id'] as int?) ?? 0;
          final cid = (r['category_id'] as int?) ?? 0;
          if (mid != 0) itemIdToCategory[mid] = cid;
        }
      }
      final grouped = <String, List<CartItem>>{};
      for (final it in items) {
        final sigExtras =
            it.extras.entries.map((e) => '${e.key}:${e.value}').join(',');
        final sigOpts =
            it.options.entries.map((e) => '${e.key}:${e.value}').join(',');
        final key = '${it.itemId}|${it.size}|$sigExtras|$sigOpts';
        grouped.putIfAbsent(key, () => []).add(it);
      }
      double rawSum = 0.0;
      final cartList = <Map<String, dynamic>>[];
      for (final entry in grouped.entries) {
        final first = entry.value.first;
        double unit = first.basePrice;
        for (final e in first.extras.entries) {
          unit += (extraPriceMap['${first.sizeId}|${e.key}'] ?? 0.0) * e.value;
        }
        final count = entry.value.length;
        rawSum += unit * count;
        cartList.add({
          'id': first.itemId,
          'category_id': itemIdToCategory[first.itemId],
          'size_id': first.sizeId,
          'price': unit,
          'quantity': count,
        });
      }
      DiscountResult? dres;
      try {
        dres = await calculateDiscountedTotal(
            cartItems: cartList, subtotal: rawSum);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _discountedCartTotal = dres?.total ?? rawSum;
        _computingCartTotal = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _computingCartTotal = false);
    }
  }

  Future<void> _loadAllowedForSlots(List<_Slot> slots) async {
    try {
      final slotIds = slots.map((s) => s.id).toList();
      final aRows = await _supabase
          .from('menu_v2_bundle_slot_allowed')
          .select('slot_id, include_type, category_id, item_id, size_id')
          .filter('slot_id', 'in', '(${slotIds.join(',')})');
      final allowedList = (aRows as List).cast<Map<String, dynamic>>();

      final Set<int> directItemIds = {};
      final Set<int> categoryIds = {};
      for (final a in allowedList) {
        final type = (a['include_type'] as String?) ?? 'item';
        if (type == 'item') {
          final id = a['item_id'] as int?;
          if (id != null) directItemIds.add(id);
        } else if (type == 'category') {
          final cid = a['category_id'] as int?;
          if (cid != null) categoryIds.add(cid);
        }
      }

      Future<List<Map<String, dynamic>>> fetchItemsByIds() async {
        if (directItemIds.isEmpty) return [];
        final res = await _supabase
            .from('menu_v2_item')
            .select('id, name, category_id')
            .filter('id', 'in', '(${directItemIds.join(',')})');
        return (res as List).cast<Map<String, dynamic>>();
      }

      Future<List<Map<String, dynamic>>> fetchItemsByCategories() async {
        if (categoryIds.isEmpty) return [];
        final res = await _supabase
            .from('menu_v2_item')
            .select('id, name, category_id')
            .filter('category_id', 'in', '(${categoryIds.join(',')})')
            .eq('is_active', true)
            .order('name');
        return (res as List).cast<Map<String, dynamic>>();
      }

      final results = await Future.wait([
        fetchItemsByIds(),
        fetchItemsByCategories(),
      ]);
      final itemsByIdList = results[0];
      final itemsByCatList = results[1];

      final Map<int, Map<String, dynamic>> byId = {
        for (final m in itemsByIdList) (m['id'] as int): m,
      };
      final Map<int, List<Map<String, dynamic>>> byCategory = {};
      for (final m in itemsByCatList) {
        final cid = m['category_id'] as int?;
        if (cid == null) continue;
        (byCategory[cid] ??= []).add(m);
      }

      final Map<int, List<Map<String, dynamic>>> allowedBySlot = {};
      for (final a in allowedList) {
        final sid = a['slot_id'] as int?;
        if (sid == null) continue;
        (allowedBySlot[sid] ??= []).add(a);
      }

      // Collect size ids for later name lookup
      final Set<int> sizeIdsToFetch = {};

      // Fetch extra policy per slot
      final policyRows = await _supabase
          .from('menu_v2_bundle_slot_extra_policy')
          .select('slot_id, included_extras_count, allow_paid_extras')
          .filter('slot_id', 'in', '(${slotIds.join(',')})');
      final Map<int, Map<String, dynamic>> policyBySlot = {
        for (final m in (policyRows as List).cast<Map<String, dynamic>>())
          (m['slot_id'] as int): m,
      };

      // Fetch modifier groups mapping for slots
      final smgRows = await _supabase
          .from('menu_v2_bundle_slot_modifier_group')
          .select('slot_id, group_id, sort_order')
          .filter('slot_id', 'in', '(${slotIds.join(',')})')
          .order('sort_order');
      final smgList = (smgRows as List).cast<Map<String, dynamic>>();
      final groupIds = {
        for (final m in smgList)
          if (m['group_id'] != null) (m['group_id'] as int)
      }.toList();

      // Fetch groups and options
      List<Map<String, dynamic>> groupsList = [];
      List<Map<String, dynamic>> optionsList = [];
      if (groupIds.isNotEmpty) {
        final gRows = await _supabase
            .from('menu_v2_modifier_group')
            .select('id, name, min_select, max_select, sort_order')
            .filter('id', 'in', '(${groupIds.join(',')})');
        groupsList = (gRows as List).cast<Map<String, dynamic>>();
        final oRows = await _supabase
            .from('menu_v2_modifier_option')
            .select('id, group_id, name, sort_order')
            .filter('group_id', 'in', '(${groupIds.join(',')})')
            .order('sort_order');
        optionsList = (oRows as List).cast<Map<String, dynamic>>();
      }
      final Map<int, Map<String, dynamic>> groupById = {
        for (final g in groupsList) (g['id'] as int): g,
      };
      final Map<int, List<Map<String, dynamic>>> optionsByGroup = {};
      for (final o in optionsList) {
        final gid = o['group_id'] as int?;
        if (gid == null) continue;
        (optionsByGroup[gid] ??= []).add(o);
      }

      for (final slot in slots) {
        final list = allowedBySlot[slot.id] ?? const <Map<String, dynamic>>[];
        final Map<int, _AllowedItem> acc = {};
        for (final a in list) {
          final type = (a['include_type'] as String?) ?? 'item';
          final fixedSizeId = a['size_id'] as int?;
          if (type == 'item') {
            final id = a['item_id'] as int?;
            if (id == null) continue;
            final it = byId[id];
            if (it == null) continue;
            acc[id] = _AllowedItem(
              itemId: id,
              itemName: (it['name'] as String?) ?? '',
              fixedSizeId: fixedSizeId,
              categoryId: it['category_id'] as int?,
            );
          } else if (type == 'category') {
            final cid = a['category_id'] as int?;
            if (cid == null) continue;
            for (final it
                in (byCategory[cid] ?? const <Map<String, dynamic>>[])) {
              final id = (it['id'] as int?) ?? 0;
              if (id == 0) continue;
              acc[id] = _AllowedItem(
                itemId: id,
                itemName: (it['name'] as String?) ?? '',
                fixedSizeId: fixedSizeId,
                categoryId: it['category_id'] as int?,
              );
            }
          }
        }
        final items = acc.values.toList()
          ..sort((a, b) =>
              a.itemName.toLowerCase().compareTo(b.itemName.toLowerCase()));
        if (!mounted) return;
        setState(() {
          final idx = _slots.indexWhere((s) => s.id == slot.id);
          if (idx != -1) {
            _slots[idx].allowedItems = items;
            // attach policy
            final pol = policyBySlot[slot.id];
            if (pol != null) {
              _slots[idx].includedExtrasCount =
                  (pol['included_extras_count'] as int?) ?? 0;
              _slots[idx].allowPaidExtras =
                  (pol['allow_paid_extras'] as bool?) ?? false;
            }
            // attach modifier groups
            final slotGroups = smgList
                .where((m) => (m['slot_id'] as int?) == slot.id)
                .toList();
            final groups = <_ModifierGroup>[];
            for (final sg in slotGroups) {
              final gid = sg['group_id'] as int?;
              if (gid == null) continue;
              final g = groupById[gid];
              if (g == null) continue;
              final options = <_ModifierOption>[];
              for (final o
                  in (optionsByGroup[gid] ?? const <Map<String, dynamic>>[])) {
                options.add(_ModifierOption(
                  id: (o['id'] as int?) ?? 0,
                  name: (o['name'] as String?) ?? '',
                  extraId: o['extra_id'] as int?,
                  sortOrder: (o['sort_order'] as int?) ?? 0,
                ));
              }
              options.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
              groups.add(_ModifierGroup(
                id: (g['id'] as int?) ?? 0,
                name: (g['name'] as String?) ?? '',
                minSelect: (g['min_select'] as int?) ?? 0,
                maxSelect: (g['max_select'] as int?) ?? 0,
                sortOrder: (g['sort_order'] as int?) ?? 0,
                options: options,
              ));
            }
            groups.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
            _slots[idx].modifierGroups = groups;
            _loadingSlots.remove(slot.id);
          }
        });
      }
      // Fetch size names if any (after building items list)
      if (sizeIdsToFetch.isNotEmpty) {
        final szRows = await _supabase
            .from('menu_size')
            .select('id, name')
            .filter('id', 'in', '(${sizeIdsToFetch.join(',')})');
        final map = <int, String>{};
        for (final r in (szRows as List).cast<Map<String, dynamic>>()) {
          final id = r['id'] as int?;
          if (id == null) continue;
          map[id] = (r['name'] as String?) ?? '';
        }
        if (mounted) {
          setState(() {
            _sizeNameById.addAll(map);
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error ??= 'Fehler beim Laden des Inhalts: ${e.toString()}';
        _loadingSlots.clear();
      });
    }
  }

  double get _currentPrice {
    double total = _bundlePrice;
    // add paid extras across all slots/items
    for (final s in _slots) {
      final chosen = _chosenBySlot[s.id] ?? const <_ChosenItem>[];
      for (final c in chosen) {
        total += _paidExtrasPriceFor(s, c);
      }
    }
    return total;
  }

  int _selectedExtrasCount(_Slot slot, _ChosenItem chosen) {
    // Count extras from modifier options (if schema supports) + explicit extras selection
    int count = chosen.selectedExtraIds.length;
    for (final g in slot.modifierGroups) {
      for (final o in g.options) {
        if (o.extraId != null && chosen.selectedOptionIds.contains(o.id))
          count++;
      }
    }
    return count;
  }

  double _paidExtrasPriceFor(_Slot slot, _ChosenItem chosen) {
    final totalSelected = _selectedExtrasCount(slot, chosen);
    final free = slot.includedExtrasCount;
    if (totalSelected <= free) return 0.0;
    if (!slot.allowPaidExtras) return 0.0;
    final toCharge = totalSelected - free;
    // take first N paid extras prices (order by option sort)
    final prices = <double>[];
    // Prices from modifier options (if any map to extras)
    for (final g in slot.modifierGroups) {
      for (final o in g.options) {
        if (o.extraId == null) continue;
        if (!chosen.selectedOptionIds.contains(o.id)) continue;
        final p = _extraPriceForSize(o.extraId!, chosen.sizeId);
        if (p != null) prices.add(p);
      }
    }

    // Prices from explicit extras selection
    for (final extraId in chosen.selectedExtraIds) {
      final p = _extraPriceForSize(extraId, chosen.sizeId);
      if (p != null) prices.add(p);
    }
    prices.sort(); // choose cheapest for fairness if more selected than free
    double sum = 0.0;
    for (int i = 0; i < prices.length && i < toCharge; i++) {
      sum += prices[i];
    }
    return sum;
  }

  double? _extraPriceForSize(int extraId, int? sizeId) {
    if (sizeId == null) return null;
    final key = '$sizeId|$extraId';
    if (_extraPriceCache.containsKey(key)) return _extraPriceCache[key];
    // Not loaded yet; fetch synchronously is not ideal — defer to async prefetch in editor
    return null;
  }

  bool get _isValid {
    for (final s in _slots) {
      final chosen = _chosenBySlot[s.id] ?? const [];
      if (chosen.length < s.minQty) return false;
      if (chosen.length > s.maxQty) return false;
    }
    return true;
  }

  String? get _disabledReason {
    for (final s in _slots) {
      final chosen = _chosenBySlot[s.id] ?? const [];
      if (chosen.length < s.minQty) {
        return 'Wählen Sie ${s.minQty} Stk. in „${s.name}“';
      }
      if (chosen.length > s.maxQty) {
        return '„${s.name}“: max. ${s.maxQty} Stk.';
      }
    }
    return null;
  }

  Future<void> _pickItemForSlot(_Slot slot) async {
    final items = slot.allowedItems;
    if (items.isEmpty) return;
    final result = await showModalBottomSheet<_AllowedItem>(
      context: context,
      isScrollControlled: false,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.6;
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Auswahl: ${slot.name}',
                            style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final it = items[i];
                      String? sub;
                      if (it.fixedSizeId != null) {
                        final id = it.fixedSizeId!;
                        sub = _sizeNameById[id];
                        if (sub == null) {
                          // fire and forget fetch
                          _ensureSizeName(id);
                        }
                      }
                      return ListTile(
                        title: Text(it.itemName),
                        subtitle: sub != null ? Text(sub) : null,
                        trailing: (it.fixedSizeId != null && sub != null)
                            ? Chip(label: Text(sub))
                            : null,
                        onTap: () => Navigator.pop(ctx, it),
                      );
                    },
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
    if (result != null) {
      setState(() {
        final cur = _chosenBySlot[slot.id] ?? <_ChosenItem>[];
        if (cur.length >= slot.maxQty) {
          // replace last
          cur[cur.length - 1] = _ChosenItem(
              itemId: result.itemId,
              itemName: result.itemName,
              sizeId: result.fixedSizeId);
        } else {
          cur.add(_ChosenItem(
              itemId: result.itemId,
              itemName: result.itemName,
              sizeId: result.fixedSizeId));
        }
        _chosenBySlot[slot.id] = cur;
      });
      // Auto-open configurator so Extras/Modifikatoren are visible immediately
      final indexToEdit = (_chosenBySlot[slot.id]?.length ?? 1) - 1;
      if (indexToEdit >= 0) {
        // Decide if need to open configurator: only if extras or modifiers exist
        Future.microtask(() async {
          final chosen = _chosenBySlot[slot.id]![indexToEdit];
          final allowedItem = slot.allowedItems.firstWhere(
            (ai) => ai.itemId == chosen.itemId,
            orElse: () =>
                _AllowedItem(itemId: chosen.itemId, itemName: chosen.itemName),
          );
          final extras = await _loadAllowedExtrasForChosen(allowedItem);
          // Cache even if empty so badge logic works
          _extrasCache[chosen.itemId] = extras;
          if (extras.isEmpty && slot.modifierGroups.isEmpty) {
            return; // nothing to configure
          }
          _configureChosen(slot, indexToEdit);
        });
      }
    }
  }

  int _virtualItemIdForSlot(int slotId) => -1000000 - slotId;

  int _ensureVirtualSelection(_Slot slot) {
    final virtualId = _virtualItemIdForSlot(slot.id);
    final existing = _chosenBySlot[slot.id];
    if (existing != null) {
      final idx = existing.indexWhere((c) => c.itemId == virtualId);
      if (idx != -1) return idx;
    }
    final updated = [...(existing ?? const <_ChosenItem>[])];
    updated.add(_ChosenItem(itemId: virtualId, itemName: slot.name));
    _chosenBySlot[slot.id] = updated;
    return updated.length - 1;
  }

  Future<void> _configureSlotModifiersOnly(_Slot slot) async {
    if (slot.modifierGroups.isEmpty) return;
    final index = _ensureVirtualSelection(slot);
    await _configureChosen(slot, index);
  }

  Future<void> _addToCart() async {
    if (!_isValid) return;
    // Compose meta
    final metaSlots = <Map<String, dynamic>>[];
    for (final s in _slots) {
      final chosenList = _chosenBySlot[s.id] ?? const <_ChosenItem>[];
      final metaItems = <Map<String, dynamic>>[];
      for (final c in chosenList) {
        // Ищем extras для этого itemId из кеша (загружались при выборе/конфигурировании)
        final List<_ExtraOption> cachedExtras =
            _extrasCache[c.itemId] ?? const <_ExtraOption>[];
        final extraNames = <String>[];
        for (final exId in c.selectedExtraIds) {
          final found = cachedExtras.firstWhere(
            (e) => e.id == exId,
            orElse: () => _ExtraOption(id: exId, name: 'Extra $exId'),
          );
          extraNames.add(found.name);
        }
        // Ищем названия модификатор-опций и сопоставляем extraId (если есть)
        final optionNames = <String>[];
        final optionExtraIds = <int>[];
        final optionPriceEntries = <_PriceEntry>[];
        for (final g in s.modifierGroups) {
          for (final o in g.options) {
            if (c.selectedOptionIds.contains(o.id)) {
              optionNames.add(o.name);
              if (o.extraId != null) {
                optionExtraIds.add(o.extraId!);
                final price = _extraPriceForSize(o.extraId!, c.sizeId) ?? 0.0;
                optionPriceEntries.add(_PriceEntry(name: o.name, price: price));
              }
            }
          }
        }
        // Цены для явных Extras
        final extraPriceEntries = <_PriceEntry>[];
        for (final exId in c.selectedExtraIds) {
          final found = cachedExtras.firstWhere(
            (e) => e.id == exId,
            orElse: () => _ExtraOption(id: exId, name: 'Extra $exId'),
          );
          final price = _extraPriceForSize(exId, c.sizeId) ?? 0.0;
          extraPriceEntries.add(_PriceEntry(name: found.name, price: price));
        }
        // Рассчитываем какие из выбранных extras оплачиваемые по политике
        final totalSelected =
            extraPriceEntries.length + optionPriceEntries.length;
        final free = s.includedExtrasCount;
        final allowPaid = s.allowPaidExtras;
        final detailEntries = <Map<String, dynamic>>[];
        if (totalSelected > 0) {
          // объединяем все с ценами
          final all = [...optionPriceEntries, ...extraPriceEntries];
          // выберем платные: минимальные цены — именно их суммирует _paidExtrasPriceFor
          int toCharge = 0;
          if (allowPaid && totalSelected > free) {
            toCharge = totalSelected - free;
          }
          final sorted = [...all]..sort((a, b) => a.price.compareTo(b.price));
          final chargedSet = <_PriceEntry>{...sorted.take(toCharge)};
          for (final e in all) {
            final charged = chargedSet.contains(e) && e.price > 0.0;
            detailEntries
                .add({'name': e.name, 'price': e.price, 'charged': charged});
          }
        }
        metaItems.add({
          'itemId': c.itemId,
          'itemName': c.itemName,
          'sizeId': c.sizeId,
          'sizeName': c.sizeId != null ? (_sizeNameById[c.sizeId] ?? '') : null,
          'extraIds': c.selectedExtraIds.toList(),
          'extraNames': extraNames,
          'optionIds': c.selectedOptionIds.toList(),
          'optionNames': optionNames,
          'optionExtraIds': optionExtraIds,
          'detailEntries': detailEntries,
        });
      }
      metaSlots.add({
        'slotId': s.id,
        'name': s.name,
        'items': metaItems,
      });
    }
    final meta = <String, dynamic>{
      'type': 'bundle',
      'bundleId': widget.bundleId,
      'price': _bundlePrice,
      'slots': metaSlots,
    };

    final item = CartItem(
      itemId:
          -widget.bundleId, // отрицательный, чтобы не пересекаться с menu_item
      name: _bundleName,
      size: 'Bundle',
      basePrice: _currentPrice,
      extras: const {},
      options: const {},
      article: 'bundle',
      sizeId: null,
      meta: meta,
    );
    await CartService.addItem(item);
    if (!mounted) return;
    // Покажем SnackBar как на экране деталей позиции меню: продолжить или перейти в корзину
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
              '"$_bundleName" hinzugefügt',
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
                      navigatorKey.currentState?.pushReplacementNamed('tab_1');
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
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Bundle'),
          bottom: _showMinOrderBar
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      border: Border(
                          top: BorderSide(
                              color: Colors.redAccent.withOpacity(0.35),
                              width: 0.8)),
                    ),
                    alignment: Alignment.center,
                    child: _computingCartTotal
                        ? Text('Prüfe Mindestbestellwert…',
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent, fontSize: 11))
                        : Text(
                            'Noch €${(_minOrderAmount! - _discountedCartTotal).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                )
              : null,
        ),
        body: const Center(
            child: CircularProgressIndicator(color: Colors.orange)),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Bundle'),
          bottom: _showMinOrderBar
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(24),
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.12),
                      border: Border(
                          top: BorderSide(
                              color: Colors.redAccent.withOpacity(0.35),
                              width: 0.8)),
                    ),
                    alignment: Alignment.center,
                    child: _computingCartTotal
                        ? Text('Prüfe Mindestbestellwert…',
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent, fontSize: 11))
                        : Text(
                            'Noch €${(_minOrderAmount! - _discountedCartTotal).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                  ),
                )
              : null,
        ),
        body: NoInternetWidget(onRetry: _load, errorText: _error),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_bundleName),
        bottom: _showMinOrderBar
            ? PreferredSize(
                preferredSize: const Size.fromHeight(24),
                child: Container(
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    border: Border(
                        top: BorderSide(
                            color: Colors.redAccent.withOpacity(0.35),
                            width: 0.8)),
                  ),
                  alignment: Alignment.center,
                  child: _computingCartTotal
                      ? Text('Prüfe Mindestbestellwert…',
                          style: GoogleFonts.poppins(
                              color: Colors.redAccent, fontSize: 11))
                      : Text(
                          'Noch €${(_minOrderAmount! - _discountedCartTotal).clamp(0, _minOrderAmount!).toStringAsFixed(2)} bis Mindestbestellwert (€${_minOrderAmount!.toStringAsFixed(2)})',
                          style: GoogleFonts.poppins(
                              color: Colors.redAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              )
            : null,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isValid && _disabledReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    _disabledReason!,
                    style: GoogleFonts.poppins(
                        color: Colors.orangeAccent, fontSize: 12),
                  ),
                ),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isValid ? _addToCart : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: appTheme.primaryColor),
                  child: Text(
                    'In den Warenkorb — ${_currentPrice.toStringAsFixed(2)} €',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_bundleDesc != null && _bundleDesc!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _bundleDesc!,
                style: GoogleFonts.poppins(color: appTheme.textColorSecondary),
              ),
            ),
          Text('Inhalt des Bundles',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ..._slots.map((s) => _slotCard(context, s)),
          const SizedBox(height: 12),
          // Upsell recommendations on bundle detail
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: UpSellWidget(
              channel: 'detail',
              subtotal: CartService.items
                  .fold<double>(0.0, (p, e) => p + e.basePrice),
              onItemAdded: () => setState(() {}),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  // Удалены размеры — фиксированная цена

  Widget _slotCard(BuildContext context, _Slot s) {
    final appTheme = ThemeProvider.of(context);
    final chosen = _chosenBySlot[s.id] ?? const <_ChosenItem>[];
    return Card(
      color: appTheme.cardColor.withValues(alpha: 0.96),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('${chosen.length}/${s.maxQty}',
                    style: GoogleFonts.poppins(
                        color: appTheme.textColorSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            if (chosen.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < chosen.length; i++)
                    _chosenChip(context, s, i, chosen[i])
                ],
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (s.allowedItems.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _loadingSlots.contains(s.id)
                        ? null
                        : () => _pickItemForSlot(s),
                    icon: const Icon(Icons.add),
                    label: Text(_loadingSlots.contains(s.id)
                        ? 'Laden…'
                        : (chosen.length < s.maxQty
                            ? 'Hinzufügen'
                            : 'Ersetzen')),
                  )
                else if (s.modifierGroups.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _loadingSlots.contains(s.id)
                        ? null
                        : () => _configureSlotModifiersOnly(s),
                    icon: const Icon(Icons.tune),
                    label: Text(
                        _loadingSlots.contains(s.id) ? 'Laden…' : 'Anpassen'),
                  ),
                if (s.allowedItems.isNotEmpty || s.modifierGroups.isNotEmpty)
                  const SizedBox(width: 8),
                Text('Minimum: ${s.minQty}',
                    style: GoogleFonts.poppins(
                        color: appTheme.textColorSecondary, fontSize: 12)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _chosenChip(
      BuildContext context, _Slot slot, int index, _ChosenItem chosen) {
    final extrasCnt = _selectedExtrasCount(slot, chosen);
    final free = slot.includedExtrasCount;
    final paid = (extrasCnt - free).clamp(0, 999);
    String sizeLabel = '';
    if (chosen.sizeId != null) {
      final id = chosen.sizeId!;
      final name = _sizeNameById[id];
      if (name != null) {
        sizeLabel = ' ($name)';
      } else {
        // trigger fetch and leave empty until setState
        _ensureSizeName(id);
      }
    }
    final nothingToConfigure = slot.modifierGroups.isEmpty &&
        (_extrasCache[chosen.itemId]?.isEmpty ?? true);
    return InputChip(
      avatar: nothingToConfigure
          ? const Icon(Icons.check_circle, size: 16, color: Colors.green)
          : const Icon(Icons.tune, size: 16),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
              child: Text('${chosen.itemName}$sizeLabel',
                  overflow: TextOverflow.ellipsis)),
          if (extrasCnt > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Chip(
                  label: Text('$extrasCnt Extra'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            ),
          if (paid > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Chip(
                  label: Text('+$paid'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
            )
        ],
      ),
      onPressed: _loadingSlots.contains(slot.id)
          ? null
          : () async {
              final allowedItem = slot.allowedItems.firstWhere(
                (ai) => ai.itemId == chosen.itemId,
                orElse: () => _AllowedItem(
                    itemId: chosen.itemId, itemName: chosen.itemName),
              );
              List<_ExtraOption> extras = _extrasCache[chosen.itemId] ??
                  await _loadAllowedExtrasForChosen(allowedItem);
              if (extras.isEmpty && slot.modifierGroups.isEmpty)
                return; // nothing to configure
              _extrasCache[chosen.itemId] = extras;
              _configureChosen(slot, index);
            },
      onDeleted: () {
        setState(() {
          final cur = _chosenBySlot[slot.id] ?? <_ChosenItem>[];
          if (index >= 0 && index < cur.length) cur.removeAt(index);
          _chosenBySlot[slot.id] = cur;
        });
      },
    );
  }

  Future<void> _configureChosen(_Slot slot, int index) async {
    final chosen = (_chosenBySlot[slot.id] ?? const <_ChosenItem>[])[index];
    // Find allowed item details
    final allowedItem = _slots
        .firstWhere((s) => s.id == slot.id)
        .allowedItems
        .firstWhere((ai) => ai.itemId == chosen.itemId,
            orElse: () => _AllowedItem(
                itemId: chosen.itemId,
                itemName: chosen.itemName,
                fixedSizeId: chosen.sizeId));
    // Load allowed extras for this item (or its category)
    final List<_ExtraOption> extras = _extrasCache[chosen.itemId] ??
        await _loadAllowedExtrasForChosen(allowedItem);
    if (extras.isEmpty && slot.modifierGroups.isEmpty) {
      return; // nothing to configure
    }
    // Prefetch prices for this chosen's size for all extras (modifier-linked and explicit extras)
    final allExtraIds = <int>{...extras.map((e) => e.id)};
    for (final g in slot.modifierGroups) {
      for (final o in g.options) {
        if (o.extraId != null) allExtraIds.add(o.extraId!);
      }
    }
    await _prefetchExtraPricesForIds(allExtraIds, chosen.sizeId);
    final result = await showModalBottomSheet<_ChosenItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _ConfigSheet(
          slot: slot,
          initial: chosen,
          priceLookup: (extraId) => _extraPriceForSize(extraId, chosen.sizeId),
          extras: extras,
        );
      },
    );
    if (result != null) {
      setState(() {
        final cur = _chosenBySlot[slot.id] ?? <_ChosenItem>[];
        if (index >= 0 && index < cur.length) cur[index] = result;
        _chosenBySlot[slot.id] = cur;
      });
    }
  }

  Future<void> _prefetchExtraPricesForIds(
      Set<int> extraIds, int? sizeId) async {
    if (sizeId == null || extraIds.isEmpty) return;
    final missing = extraIds
        .where((eid) => !_extraPriceCache.containsKey('$sizeId|$eid'))
        .toList();
    if (missing.isEmpty) return;
    final rows = await _supabase
        .from('menu_v2_extra_price_by_size')
        .select('extra_id, size_id, price')
        .eq('size_id', sizeId)
        .filter('extra_id', 'in', '(${missing.join(',')})');
    for (final m in (rows as List).cast<Map<String, dynamic>>()) {
      final key = '${m['size_id']}|${m['extra_id']}';
      _extraPriceCache[key] = (m['price'] as num?)?.toDouble() ?? 0.0;
    }
  }

  Future<List<_ExtraOption>> _loadAllowedExtrasForChosen(
      _AllowedItem item) async {
    // Try item-allowed extras first
    final eItemRows = await _supabase
        .from('menu_v2_item_allowed_extras')
        .select('extra_id')
        .eq('item_id', item.itemId);
    List<int> extraIds =
        (eItemRows as List?)?.map((m) => m['extra_id'] as int).toList() ?? [];
    if (extraIds.isEmpty && item.categoryId != null) {
      final eCatRows = await _supabase
          .from('menu_v2_category_allowed_extras')
          .select('extra_id')
          .eq('category_id', item.categoryId!);
      extraIds =
          (eCatRows as List?)?.map((m) => m['extra_id'] as int).toList() ?? [];
    }
    if (extraIds.isEmpty) return const [];
    final rows = await _supabase
        .from('menu_v2_extra')
        .select('id, name, is_active')
        .filter('id', 'in', '(${extraIds.join(',')})')
        .eq('is_active', true)
        .order('name');
    final list = <_ExtraOption>[];
    for (final m in (rows as List).cast<Map<String, dynamic>>()) {
      list.add(_ExtraOption(
          id: (m['id'] as int?) ?? 0, name: (m['name'] as String?) ?? ''));
    }
    return list;
  }
}

class _Slot {
  final int id;
  final String name;
  final int minQty;
  final int maxQty;
  final bool allowPaidUpgrade;
  List<_AllowedItem> allowedItems;
  // Extras policy
  int includedExtrasCount;
  bool allowPaidExtras;
  // Modifier groups for this slot
  List<_ModifierGroup> modifierGroups;
  _Slot({
    required this.id,
    required this.name,
    required this.minQty,
    required this.maxQty,
    required this.allowPaidUpgrade,
  })  : allowedItems = const [],
        includedExtrasCount = 0,
        allowPaidExtras = false,
        modifierGroups = const [];
}

class _AllowedItem {
  final int itemId;
  final String itemName;
  final int? fixedSizeId;
  final int? categoryId;
  _AllowedItem(
      {required this.itemId,
      required this.itemName,
      this.fixedSizeId,
      this.categoryId});
}

class _ChosenItem {
  final int itemId;
  final String itemName;
  final int? sizeId; // если фиксированный в слоте
  // selected modifier option ids
  final Set<int> selectedOptionIds;
  // selected extras (by extra_id)
  final Set<int> selectedExtraIds;
  _ChosenItem({
    required this.itemId,
    required this.itemName,
    this.sizeId,
    Set<int>? selectedOptionIds,
    Set<int>? selectedExtraIds,
  })  : selectedOptionIds = selectedOptionIds ?? <int>{},
        selectedExtraIds = selectedExtraIds ?? <int>{};
}

class _ModifierGroup {
  final int id;
  final String name;
  final int minSelect;
  final int maxSelect; // 0 or 1+; 1 means radio
  final int sortOrder;
  final List<_ModifierOption> options;
  _ModifierGroup({
    required this.id,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    required this.sortOrder,
    required this.options,
  });
}

class _ModifierOption {
  final int id;
  final String name;
  final int sortOrder;
  final int? extraId; // when not null, maps to an extra
  _ModifierOption(
      {required this.id,
      required this.name,
      required this.sortOrder,
      this.extraId});
}

class _ExtraOption {
  final int id; // extra_id
  final String name;
  _ExtraOption({required this.id, required this.name});
}

class _PriceEntry {
  final String name;
  final double price;
  const _PriceEntry({required this.name, required this.price});
  @override
  bool operator ==(Object other) =>
      other is _PriceEntry && other.name == name && other.price == price;
  @override
  int get hashCode => Object.hash(name, price);
}

class _ConfigSheet extends StatefulWidget {
  final _Slot slot;
  final _ChosenItem initial;
  final double? Function(int extraId) priceLookup;
  final List<_ExtraOption> extras;
  const _ConfigSheet(
      {required this.slot,
      required this.initial,
      required this.priceLookup,
      required this.extras});

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  late Set<int> _selected;
  late Set<int> _selectedExtras;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial.selectedOptionIds};
    _selectedExtras = {...widget.initial.selectedExtraIds};
  }

  int get _extrasCount {
    int c = 0;
    for (final g in widget.slot.modifierGroups) {
      for (final o in g.options) {
        if (o.extraId != null && _selected.contains(o.id)) c++;
      }
    }
    return c;
  }

  double get _paidExtrasPrice {
    final free = widget.slot.includedExtrasCount;
    final allowPaid = widget.slot.allowPaidExtras;
    if (!allowPaid) return 0;
    // collect prices in option order
    final prices = <double>[];
    for (final g in widget.slot.modifierGroups) {
      for (final o in g.options) {
        if (o.extraId == null) continue;
        if (!_selected.contains(o.id)) continue;
        final p = widget.priceLookup(o.extraId!);
        if (p != null) prices.add(p);
      }
    }
    // plus explicit extras
    for (final e in widget.extras) {
      if (!_selectedExtras.contains(e.id)) continue;
      final p = widget.priceLookup(e.id);
      if (p != null) prices.add(p);
    }
    final totalSel = _extrasCount;
    final toCharge = (totalSel - free).clamp(0, 999);
    if (toCharge == 0) return 0;
    prices.sort();
    double sum = 0;
    for (int i = 0; i < prices.length && i < toCharge; i++) {
      sum += prices[i];
    }
    return sum;
  }

  void _toggleOption(_ModifierGroup g, _ModifierOption o, bool selected) {
    setState(() {
      if (g.maxSelect == 1) {
        // radio-like
        for (final opt in g.options) {
          _selected.remove(opt.id);
        }
        if (selected) _selected.add(o.id);
      } else {
        final countInGroup =
            g.options.where((opt) => _selected.contains(opt.id)).length;
        if (selected) {
          if (g.maxSelect == 0 || countInGroup < g.maxSelect) {
            _selected.add(o.id);
          }
        } else {
          _selected.remove(o.id);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    return SafeArea(
      top: false,
      child: DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) {
          return Material(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Anpassen: ${widget.slot.name}',
                            style: GoogleFonts.poppins(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close))
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                            'Inklusive Extras: ${widget.slot.includedExtrasCount}\nZusätzliche Extras sind kostenpflichtig.',
                            style: GoogleFonts.poppins(
                                color: appTheme.textColorSecondary,
                                fontSize: 12)),
                      ),
                      Text(
                          _paidExtrasPrice > 0
                              ? '+${_paidExtrasPrice.toStringAsFixed(2)} €'
                              : '',
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.w600))
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      if (widget.extras.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text('Extras',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...widget.extras.map((e) {
                          final selected = _selectedExtras.contains(e.id);
                          final price = widget.priceLookup(e.id);
                          final subtitle =
                              (price != null && widget.slot.allowPaidExtras)
                                  ? '+${price.toStringAsFixed(2)} €'
                                  : null;
                          return CheckboxListTile(
                            value: selected,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedExtras.add(e.id);
                                } else {
                                  _selectedExtras.remove(e.id);
                                }
                              });
                            },
                            title: Text(e.name),
                            subtitle: subtitle != null ? Text(subtitle) : null,
                          );
                        })
                      ],
                      for (final g in widget.slot.modifierGroups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(g.name,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600)),
                        ),
                        ...g.options.map((o) {
                          final isSelected = _selected.contains(o.id);
                          final isRadio = g.maxSelect == 1;
                          final price = o.extraId != null
                              ? widget.priceLookup(o.extraId!)
                              : null;
                          final subtitle = (o.extraId != null &&
                                  price != null &&
                                  widget.slot.allowPaidExtras)
                              ? '+${price.toStringAsFixed(2)} €'
                              : null;
                          return isRadio
                              ? RadioListTile<int>(
                                  value: o.id,
                                  groupValue: isSelected ? o.id : null,
                                  onChanged: (v) => _toggleOption(g, o, true),
                                  title: Text(o.name),
                                  subtitle:
                                      subtitle != null ? Text(subtitle) : null,
                                )
                              : CheckboxListTile(
                                  value: isSelected,
                                  onChanged: (v) =>
                                      _toggleOption(g, o, v ?? false),
                                  title: Text(o.name),
                                  subtitle:
                                      subtitle != null ? Text(subtitle) : null,
                                );
                        })
                      ]
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () {
                          // Validate minSelect per group and extras policy if paid not allowed
                          for (final g in widget.slot.modifierGroups) {
                            final selCount = g.options
                                .where((o) => _selected.contains(o.id))
                                .length;
                            if (selCount < g.minSelect) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(
                                      'Bitte wählen Sie mindestens ${g.minSelect} in „${g.name}“')));
                              return;
                            }
                          }
                          if (!widget.slot.allowPaidExtras &&
                              _extrasCount > widget.slot.includedExtrasCount) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Zusatz-Extras nicht erlaubt. Entfernen Sie einige Extras.')));
                            return;
                          }
                          Navigator.pop(
                              context,
                              _ChosenItem(
                                itemId: widget.initial.itemId,
                                itemName: widget.initial.itemName,
                                sizeId: widget.initial.sizeId,
                                selectedOptionIds: _selected,
                                selectedExtraIds: _selectedExtras,
                              ));
                        },
                        child: Text(_paidExtrasPrice > 0
                            ? 'Übernehmen (+${_paidExtrasPrice.toStringAsFixed(2)} €)'
                            : 'Übernehmen'),
                      ),
                    ),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}
