import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class DiscountResult {
  final double total;
  final double totalDiscount;
  final List<Map<String, dynamic>> appliedDiscounts;

  DiscountResult({
    required this.total,
    required this.totalDiscount,
    required this.appliedDiscounts,
  });
}

// ===== New Promotion Schema Models (menu_v2_promotion / menu_v2_promotion_target) =====

class Promotion {
  final int id;
  final String name;
  final String? description;
  final String discountType; // percentage | fixed_amount | fixed_price
  final double discountValue;
  final DateTime startsAt;
  final DateTime? endsAt;
  final List<int> weekdays; // empty -> any day
  final TimeOfDay? timeFrom;
  final TimeOfDay? timeTo;
  final bool isActive;
  final int priority;
  final List<PromotionTarget> targets;

  Promotion({
    required this.id,
    required this.name,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.startsAt,
    required this.endsAt,
    required this.weekdays,
    required this.timeFrom,
    required this.timeTo,
    required this.isActive,
    required this.priority,
    required this.targets,
  });
}

class PromotionTarget {
  final int id;
  final int promotionId;
  final String targetType; // category | category_size | item | item_size
  final int? categoryId;
  final int? itemId;
  final int? sizeId;

  PromotionTarget({
    required this.id,
    required this.promotionId,
    required this.targetType,
    required this.categoryId,
    required this.itemId,
    required this.sizeId,
  });
}

class PromotionPrice {
  final double basePrice;
  final double finalPrice;
  final double discountAmount;
  final Promotion? promotion;
  final PromotionTarget? target;

  const PromotionPrice({
    required this.basePrice,
    required this.finalPrice,
    required this.discountAmount,
    required this.promotion,
    required this.target,
  });

  bool get hasDiscount => discountAmount > 0.0001;
}

class _PromotionCache {
  static List<Promotion>? _promotions;
  static DateTime? _cachedAt;

  static Future<List<Promotion>> get({
    DateTime? now,
    bool forceRefresh = false,
    Duration ttl = const Duration(seconds: 45),
  }) async {
    final effectiveNow = now ?? DateTime.now();
    if (!forceRefresh && _promotions != null && _cachedAt != null) {
      final delta = effectiveNow.difference(_cachedAt!).abs();
      if (delta <= ttl) {
        return _promotions!;
      }
    }
    final fetched = await fetchActivePromotions(at: effectiveNow);
    _promotions = fetched;
    _cachedAt = effectiveNow;
    return fetched;
  }

  // ignore: unused_element
  static void clear() {
    _promotions = null;
    _cachedAt = null;
  }
}

class _PromotionSelection {
  final Promotion promotion;
  final PromotionTarget target;
  final int specificity;

  const _PromotionSelection({
    required this.promotion,
    required this.target,
    required this.specificity,
  });
}

int _targetSpecificity(PromotionTarget t) {
  switch (t.targetType) {
    case 'item_size':
      return 4;
    case 'item':
      return 3;
    case 'category_size':
      return 2;
    case 'category':
      return 1;
    default:
      return 0;
  }
}

PromotionTarget? _bestTargetForPromotion(
  Promotion promotion, {
  required int itemId,
  int? categoryId,
  int? sizeId,
}) {
  PromotionTarget? best;
  for (final target in promotion.targets) {
    bool matches = false;
    switch (target.targetType) {
      case 'item_size':
        matches = target.itemId == itemId && target.sizeId == sizeId && itemId != 0 && sizeId != null;
        break;
      case 'item':
        matches = target.itemId == itemId && itemId != 0;
        break;
      case 'category_size':
        matches = target.categoryId == categoryId && target.sizeId == sizeId && categoryId != null && sizeId != null;
        break;
      case 'category':
        matches = target.categoryId == categoryId && categoryId != null;
        break;
      default:
        matches = false;
    }
    if (!matches) continue;
    if (best == null || _targetSpecificity(target) > _targetSpecificity(best)) {
      best = target;
    }
  }
  return best;
}

_PromotionSelection? _selectBestPromotion(
  List<Promotion> promotions, {
  required int itemId,
  required double unitPrice,
  int? categoryId,
  int? sizeId,
}) {
  _PromotionSelection? best;
  for (final promotion in promotions) {
    if (promotion.targets.isEmpty) continue;
    final target = _bestTargetForPromotion(
      promotion,
      itemId: itemId,
      categoryId: categoryId,
      sizeId: sizeId,
    );
    if (target == null) continue;
    final candidate = _PromotionSelection(
      promotion: promotion,
      target: target,
      specificity: _targetSpecificity(target),
    );
    if (best == null) {
      best = candidate;
      continue;
    }
    final prioCmp = candidate.promotion.priority.compareTo(best.promotion.priority);
    if (prioCmp > 0) {
      best = candidate;
      continue;
    }
    if (prioCmp < 0) {
      continue;
    }
    final bestFinal = _finalUnitPriceForPromotion(
      promotion: best.promotion,
      unitPrice: unitPrice,
    );
    final candidateFinal = _finalUnitPriceForPromotion(
      promotion: candidate.promotion,
      unitPrice: unitPrice,
    );
    final finalCmp = candidateFinal.compareTo(bestFinal);
    if (finalCmp < 0) {
      best = candidate;
      continue;
    }
    if (finalCmp > 0) {
      continue;
    }
    final specCmp = candidate.specificity.compareTo(best.specificity);
    if (specCmp > 0) {
      best = candidate;
      continue;
    }
    if (specCmp < 0) {
      continue;
    }
    if (candidate.promotion.id < best.promotion.id) {
      best = candidate;
    }
  }
  return best;
}

double _finalUnitPriceForPromotion({
  required Promotion promotion,
  required double unitPrice,
}) {
  if (unitPrice <= 0) return 0;
  double finalPrice;
  switch (promotion.discountType) {
    case 'percentage':
      final reduction = promotion.discountValue / 100.0;
      finalPrice = unitPrice * (1 - reduction);
      break;
    case 'fixed_amount':
      finalPrice = unitPrice - promotion.discountValue;
      break;
    case 'fixed_price':
      finalPrice = promotion.discountValue;
      break;
    default:
      finalPrice = unitPrice;
  }
  if (finalPrice.isNaN || finalPrice.isInfinite) {
    finalPrice = unitPrice;
  }
  if (finalPrice < 0) {
    finalPrice = 0;
  }
  if (finalPrice > unitPrice) {
    finalPrice = unitPrice;
  }
  return finalPrice;
}

double _calculateLineDiscount({
  required Promotion promotion,
  required double unitPrice,
  required int quantity,
}) {
  if (quantity <= 0 || unitPrice <= 0) return 0;
  final linePrice = unitPrice * quantity;
  final finalUnitPrice = _finalUnitPriceForPromotion(
    promotion: promotion,
    unitPrice: unitPrice,
  );
  final finalLinePrice = finalUnitPrice * quantity;
  if (finalLinePrice >= linePrice) return 0;
  final discount = linePrice - finalLinePrice;
  return math.min(discount, linePrice);
}

PromotionPrice evaluatePromotionForUnitPrice({
  required List<Promotion> promotions,
  required double unitPrice,
  required int itemId,
  int? categoryId,
  int? sizeId,
}) {
  if (unitPrice <= 0 || itemId == 0) {
    return PromotionPrice(
      basePrice: unitPrice,
      finalPrice: unitPrice,
      discountAmount: 0,
      promotion: null,
      target: null,
    );
  }
  final selection = _selectBestPromotion(
    promotions,
    itemId: itemId,
    unitPrice: unitPrice,
    categoryId: categoryId,
    sizeId: sizeId,
  );
  if (selection == null) {
    return PromotionPrice(
      basePrice: unitPrice,
      finalPrice: unitPrice,
      discountAmount: 0,
      promotion: null,
      target: null,
    );
  }
  final unitDiscount = _calculateLineDiscount(
    promotion: selection.promotion,
    unitPrice: unitPrice,
    quantity: 1,
  );
  final cappedDiscount = math.min(unitDiscount, unitPrice);
  final finalPrice = (unitPrice - cappedDiscount).clamp(0, unitPrice).toDouble();
  return PromotionPrice(
    basePrice: unitPrice,
    finalPrice: finalPrice,
    discountAmount: cappedDiscount,
    promotion: selection.promotion,
    target: selection.target,
  );
}

Future<PromotionPrice> getPromotionPrice({
  required double unitPrice,
  required int itemId,
  int? categoryId,
  int? sizeId,
  DateTime? now,
  bool forceRefresh = false,
}) async {
  final promotions = await _PromotionCache.get(now: now, forceRefresh: forceRefresh);
  return evaluatePromotionForUnitPrice(
    promotions: promotions,
    unitPrice: unitPrice,
    itemId: itemId,
    categoryId: categoryId,
    sizeId: sizeId,
  );
}

Future<List<Promotion>> getCachedPromotions({
  DateTime? now,
  bool forceRefresh = false,
}) {
  return _PromotionCache.get(now: now, forceRefresh: forceRefresh);
}

TimeOfDay? _parseTime(String? v) {
  if (v == null) return null;
  final parts = v.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return TimeOfDay(hour: h, minute: m);
}

/// Fetch active promotions at a given timestamp using new schema (simplified; one query + client filtering for time window).
Future<List<Promotion>> fetchActivePromotions({DateTime? at}) async {
  at ??= DateTime.now();
  final supa = Supabase.instance.client;

  // Query promotions + targets via two queries (avoid huge JOIN result duplication).
  final pRows = await supa
      .from('menu_v2_promotion')
      .select('id, name, description, discount_type, discount_value, starts_at, ends_at, weekdays, time_from, time_to, is_active, priority')
      .lte('starts_at', at.toIso8601String())
      .or('ends_at.is.null,ends_at.gte.${at.toIso8601String()}')
      .eq('is_active', true)
      .order('priority', ascending: false)
      .order('starts_at');

  final ids = (pRows as List).map((e) => e['id'] as int).toList();
  Map<int, List<PromotionTarget>> targetsByPromotion = {};
  if (ids.isNotEmpty) {
    final tRows = await supa
        .from('menu_v2_promotion_target')
        .select('id, promotion_id, target_type, category_id, item_id, size_id')
        .filter('promotion_id', 'in', '(${ids.join(',')})');
    for (final r in (tRows as List)) {
      final pid = r['promotion_id'] as int?; if (pid == null) continue;
      (targetsByPromotion[pid] ??= []).add(PromotionTarget(
        id: (r['id'] as int?) ?? 0,
        promotionId: pid,
        targetType: (r['target_type'] as String?) ?? 'item',
        categoryId: r['category_id'] as int?,
        itemId: r['item_id'] as int?,
        sizeId: r['size_id'] as int?,
      ));
    }
  }

  final weekday = at.weekday % 7; // Dart: Mon=1..Sun=7 => want Sun=0..Sat=6
  final normalizedWeekday = (weekday == 7) ? 0 : weekday; // Sunday adjust
  final minutesInDay = at.hour * 60 + at.minute;

  final promotions = <Promotion>[];
  for (final r in pRows as List) {
    final startsAt = DateTime.parse(r['starts_at']);
    final endsAtStr = r['ends_at'];
    final endsAt = endsAtStr != null ? DateTime.tryParse(endsAtStr) : null;
    if (startsAt.isAfter(at)) continue;
    if (endsAt != null && endsAt.isBefore(at)) continue;
    final weekdaysRaw = (r['weekdays'] as List?)?.map((e) => e as int).toList() ?? const <int>[];
    if (weekdaysRaw.isNotEmpty && !weekdaysRaw.contains(normalizedWeekday)) continue;
    final tf = _parseTime(r['time_from']);
    final tt = _parseTime(r['time_to']);
    bool timeOk = true;
    if (tf != null && tt == null) {
      final fromMin = tf.hour * 60 + tf.minute;
      timeOk = minutesInDay >= fromMin;
    } else if (tf != null && tt != null) {
      final fromMin = tf.hour * 60 + tf.minute;
      final toMin = tt.hour * 60 + tt.minute;
      timeOk = minutesInDay >= fromMin && minutesInDay <= toMin;
    }
    if (!timeOk) continue;
    promotions.add(Promotion(
      id: (r['id'] as int?) ?? 0,
      name: (r['name'] as String?) ?? '',
      description: r['description'] as String?,
      discountType: (r['discount_type'] as String?) ?? 'percentage',
      discountValue: (r['discount_value'] as num?)?.toDouble() ?? 0.0,
      startsAt: startsAt,
      endsAt: endsAt,
      weekdays: weekdaysRaw,
      timeFrom: tf,
      timeTo: tt,
      isActive: (r['is_active'] as bool?) ?? true,
      priority: (r['priority'] as int?) ?? 0,
      targets: targetsByPromotion[(r['id'] as int? ?? 0)] ?? const <PromotionTarget>[],
    ));
  }
  return promotions;
}

/// cartItems: [{'id', 'category_id', 'price', 'quantity'}, ...]

Future<DiscountResult> calculateDiscountedTotal({
  required List<Map<String, dynamic>> cartItems,
  required double subtotal,
  DateTime? now,
}) async {
  now ??= DateTime.now();
  final promotions = await _PromotionCache.get(now: now);

  double sumWithoutDiscounts = 0;
  double totalDiscount = 0;
  final appliedDiscounts = <Map<String, dynamic>>[];

  for (int idx = 0; idx < cartItems.length; idx++) {
    final line = cartItems[idx];
    final unitPrice = (line['price'] as num?)?.toDouble() ?? 0.0;
    final qtyNum = line['quantity'];
    final qty = qtyNum is num ? qtyNum.toInt() : 0;
    final itemId = (line['id'] as num?)?.toInt();
    final categoryId = (line['category_id'] as num?)?.toInt();
    final sizeId = (line['size_id'] as num?)?.toInt();

    final lineSubtotal = unitPrice * qty;
    sumWithoutDiscounts += lineSubtotal;

    if (itemId == null || itemId == 0 || qty <= 0 || unitPrice <= 0) {
      continue;
    }

    final selection = _selectBestPromotion(
      promotions,
      itemId: itemId,
      unitPrice: unitPrice,
      categoryId: categoryId,
      sizeId: sizeId,
    );
    if (selection == null) continue;

    final discountValue = _calculateLineDiscount(
      promotion: selection.promotion,
      unitPrice: unitPrice,
      quantity: qty,
    );
    if (discountValue <= 0) continue;

    totalDiscount += discountValue;
    appliedDiscounts.add({
      'promotion_id': selection.promotion.id,
      'name': selection.promotion.name,
      'discount_type': selection.promotion.discountType,
      'discount_value': selection.promotion.discountValue,
      'applied_to_index': idx,
      'discount_amount': discountValue,
      'target_type': selection.target.targetType,
      'target_category_id': selection.target.categoryId,
      'target_item_id': selection.target.itemId,
      'target_size_id': selection.target.sizeId,
    });
  }

  final total = (sumWithoutDiscounts - totalDiscount).clamp(0, sumWithoutDiscounts).toDouble();
  return DiscountResult(total: total, totalDiscount: totalDiscount, appliedDiscounts: appliedDiscounts);
}
