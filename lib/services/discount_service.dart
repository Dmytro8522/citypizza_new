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

/// cartItems: [{'id', 'category_id', 'price', 'quantity'}, ...]

Future<DiscountResult> calculateDiscountedTotal({
  required List<Map<String, dynamic>> cartItems,
  required double subtotal,
  String? userId,
  String? userGroup,
  DateTime? userBirthdate,
  bool isFirstOrder = false,
  String? appliedPromoCode,
  String? deliveryType,
  String? paymentType,
  DateTime? now,
}) async {
  now ??= DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // 1. Получаем все скидки вместе с их таргетами
  final discountsRaw = await Supabase.instance.client
      .from('discounts')
      .select('*, discount_targets(*)')
      .eq('active', true)
      .lte('start_at', now.toIso8601String())
      .order('priority', ascending: false)
      .order('start_at', ascending: false);

  // 2. Фильтруем только валидные по дате и мин.сумме
  final List<Map<String, dynamic>> validDiscounts =
      List<Map<String, dynamic>>.from(discountsRaw).where((d) {
    final endAt = d['end_at'];
    final minOrder = d['min_order'] ?? 0;
    final validEnd = endAt == null || DateTime.parse(endAt).isAfter(now!);
    return validEnd && subtotal >= minOrder;
  }).toList();

  double sumWithoutDiscounts = 0;
  for (final item in cartItems) {
    sumWithoutDiscounts += (item['price'] as double) * (item['quantity'] as int);
  }

  // 3. Для каждого товара будем хранить список скидок
  final Map<String, List<Map<String, dynamic>>> discountsPerItem = {};
  final Map<String, double> discountAmountsPerItem = {};

  // Генерируем уникальный ключ для каждой позиции
  String itemKeyFn(Map item, int idx) => '${item['id']}_${item['category_id']}_$idx';

  // Универсальная функция для времени
  bool isInTimeRange(DateTime dt, String? from, String? to) {
    if (from == null || to == null) return true;
    final timeFrom = TimeOfDay(
      hour: int.parse(from.split(':')[0]),
      minute: int.parse(from.split(':')[1]),
    );
    final timeTo = TimeOfDay(
      hour: int.parse(to.split(':')[0]),
      minute: int.parse(to.split(':')[1]),
    );
    final nowTime = TimeOfDay(hour: dt.hour, minute: dt.minute);

    bool isAfterFrom = nowTime.hour > timeFrom.hour ||
        (nowTime.hour == timeFrom.hour && nowTime.minute >= timeFrom.minute);
    bool isBeforeTo = nowTime.hour < timeTo.hour ||
        (nowTime.hour == timeTo.hour && nowTime.minute <= timeTo.minute);

    return isAfterFrom && isBeforeTo;
  }

  // 4. Для каждого товара ищем подходящие скидки
  for (int idx = 0; idx < cartItems.length; idx++) {
    final item = cartItems[idx];
    final itemKey = itemKeyFn(item, idx);
    List<Map<String, dynamic>> foundDiscounts = [];

    for (final discount in validDiscounts) {
      final applyType = discount['apply_type'] ?? 'first'; // 'first', 'best', 'stack', 'priority'
      final stackable = discount['stackable'] ?? false;
      final priority = discount['priority'] ?? 0;
      final discountType = discount['discount_type'];
      final value = double.tryParse(discount['value'].toString()) ?? 0;

      // Проверка лимитов
      if (discount['usage_limit'] != null &&
          discount['usage_count'] != null &&
          (discount['usage_count'] as int) >= (discount['usage_limit'] as int)) {
        continue;
      }

      // Получаем таргеты для этой скидки
      final List targets = discount['discount_targets'] ?? [];
      final bool hasNoTargets = targets.isEmpty;
      bool applicable = false;

      // Проверяем, подходит ли эта скидка к item
      if (hasNoTargets) {
        applicable = true;
      } else {
        for (final t in targets) {
          String? targetType = t['target_type'];
          dynamic targetValue = t['target_value'];
          switch (targetType) {
            case 'category':
              if (item['category_id'] == int.tryParse(targetValue.toString())) applicable = true;
              break;
            case 'item':
              if (item['id'] == int.tryParse(targetValue.toString())) applicable = true;
              break;
            case 'user':
              if (userId != null && userId == targetValue) applicable = true;
              break;
            case 'user_group':
              if (userGroup != null && userGroup == targetValue) applicable = true;
              break;
            case 'promo_code':
              if (appliedPromoCode != null && appliedPromoCode == targetValue) applicable = true;
              break;
            case 'first_order':
              if (isFirstOrder == true) applicable = true;
              break;
            case 'birthday':
              if (userBirthdate != null && t['birthday_days'] != null) {
                final birthThisYear = DateTime(today.year, userBirthdate.month, userBirthdate.day);
                final diff = today.difference(birthThisYear).inDays;
                if (diff.abs() <= (t['birthday_days'] ?? 0)) applicable = true;
              }
              break;
            case 'holiday':
              if (t['holiday_date'] != null) {
                final holiday = DateTime.parse(t['holiday_date']);
                if (holiday.year == today.year &&
                    holiday.month == today.month &&
                    holiday.day == today.day) {
                  applicable = true;
                }
              }
              break;
            case 'delivery_type':
              if (deliveryType != null && deliveryType == targetValue) applicable = true;
              break;
            case 'payment_type':
              if (paymentType != null && paymentType == targetValue) applicable = true;
              break;
            case 'time_range':
              if (t['time_from'] != null && t['time_to'] != null) {
                if (isInTimeRange(now!, t['time_from']?.toString(), t['time_to']?.toString())) applicable = true;
              }
              break;
            default:
              break;
          }
        }
      }
      if (!applicable) continue;

      // Рассчитаем сумму скидки для этого товара
      final itemSum = (item['price'] as double) * (item['quantity'] as int);
      double discountValue = 0;
      if (discountType == 'percent') {
        discountValue = itemSum * value / 100;
      } else if (discountType == 'fixed') {
        discountValue = value * (item['quantity'] as int);
      }

      if (discountValue > 0) {
        foundDiscounts.add({
          ...discount,
          'discount_amount': discountValue,
          'priority': priority,
          'apply_type': applyType,
          'stackable': stackable,
        });
      }
    }

    discountsPerItem[itemKey] = foundDiscounts;
  }

  // 5. Применяем скидки по всем сценариям: stack, best, priority, first
  final Set<String> alreadyDiscountedItems = {};
  final List<Map<String, dynamic>> appliedDiscounts = [];
  double totalDiscount = 0;

  for (int idx = 0; idx < cartItems.length; idx++) {
    final item = cartItems[idx];
    final itemKey = itemKeyFn(item, idx);
    final itemSum = (item['price'] as double) * (item['quantity'] as int);
    final discountsForThisItem = discountsPerItem[itemKey] ?? [];

    if (discountsForThisItem.isEmpty) continue;

    // 5.1. stackable — применяем все скидки с stackable == true
    final List<Map<String, dynamic>> stackables =
        discountsForThisItem.where((d) => d['stackable'] == true).toList();

    // 5.2. best/priority/first — выбираем одну максимальную
    final List<Map<String, dynamic>> nonStackables =
        discountsForThisItem.where((d) => d['stackable'] != true).toList();

    // Среди nonStackables определяем приоритет:
    Map<String, dynamic>? bestDiscount;
    if (nonStackables.isNotEmpty) {
      // Если среди nonStackables есть apply_type == 'priority', берём с максимальным priority
      final priorityDiscounts = nonStackables
          .where((d) => d['apply_type'] == 'priority')
          .toList();
      if (priorityDiscounts.isNotEmpty) {
        bestDiscount = priorityDiscounts.reduce((a, b) =>
            (a['priority'] as int) > (b['priority'] as int) ? a : b);
      } else {
        // Если есть apply_type == 'best' — берём с наибольшим discount_amount
        final bestDiscounts = nonStackables
            .where((d) => d['apply_type'] == 'best')
            .toList();
        if (bestDiscounts.isNotEmpty) {
          bestDiscount = bestDiscounts.reduce((a, b) =>
              (a['discount_amount'] as double) > (b['discount_amount'] as double)
                  ? a
                  : b);
        } else {
          // Если есть apply_type == 'first' — берём первую из nonStackables
          final firstDiscounts = nonStackables
              .where((d) => d['apply_type'] == 'first' || d['apply_type'] == null)
              .toList();
          if (firstDiscounts.isNotEmpty) {
            bestDiscount = firstDiscounts.first;
          }
        }
      }
    }

    double discountForItem = 0;
    // Применяем все stackable скидки
    for (final d in stackables) {
      discountForItem += d['discount_amount'] as double;
      appliedDiscounts.add({...d, 'applied_to': itemKey});
    }
    // Применяем best/priority/first скидку, если таковая есть (и если её нет среди stackable)
    if (bestDiscount != null &&
        (stackables.isEmpty || !stackables.any((d) => d['id'] == bestDiscount!['id']))) {
      discountForItem += bestDiscount['discount_amount'] as double;
      appliedDiscounts.add({...bestDiscount, 'applied_to': itemKey});
    }
    // Итоговая скидка на этот товар
    if (discountForItem > 0) {
      alreadyDiscountedItems.add(itemKey);
      discountAmountsPerItem[itemKey] = discountForItem;
      totalDiscount += discountForItem;
    }
  }

  final total = (sumWithoutDiscounts - totalDiscount).clamp(0, sumWithoutDiscounts).toDouble();

  return DiscountResult(
    total: total,
    totalDiscount: totalDiscount,
    appliedDiscounts: appliedDiscounts,
  );
}
