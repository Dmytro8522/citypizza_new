import 'package:supabase_flutter/supabase_flutter.dart';
import 'cart_service.dart';

class OrderService {
  static final SupabaseClient _db = Supabase.instance.client;

  /// Создаёт новый заказ:
  /// 1) вставляет запись в orders,
  /// 2) CartItem → order_items (+ item_comment),
  /// 3) extras → order_item_extras,
  /// 4) очищает корзину.
  static Future<void> createOrder({
    required String name,
    required String phone,
    required bool isDelivery,
    required String paymentMethod,
    required String city,
    required String street,
    required String houseNumber,
    required String postalCode,
    required String floor,
    required String comment,
    required String courierComment,
    required Map<String, String> itemComments,
    required double totalSum,
    required bool isCustomTime,
    DateTime? scheduledTime,
    double? totalDiscount,
    List<Map<String, dynamic>>? appliedDiscounts,
  }) async {
    // 1) Insert в orders и возврат ID
    final orderInsert = await _db.from('orders').insert({
      'user_id': _db.auth.currentUser?.id,
      'name': name,
      'phone': phone,
      'is_delivery': isDelivery,
      'payment_method': paymentMethod,
      'city': city,
      'street': street,
      'house_number': houseNumber,
      'postal_code': postalCode,
      'floor': floor,
      'order_comment': comment,
      'courier_comment': courierComment,
      'total_sum': totalSum,
      'discount_amount': totalDiscount ?? 0,
      if (appliedDiscounts != null) 'applied_discounts': appliedDiscounts,
      if (isCustomTime && scheduledTime != null)
        'scheduled_time': scheduledTime.toIso8601String(),
    }).select('id').single();

    final int orderId = orderInsert['id'] as int;

    // 2) Вставка позиций
    final items = CartService.items;
    for (final cartItem in items) {
      // генерируем ключ для комментариев
      final commentKey =
          '${cartItem.itemId}|${cartItem.size}|${cartItem.extras.entries.map((e) => '${e.key}:${e.value}').join(',')}';
      final itemComment = itemComments[commentKey] ?? '';

      // Определяем size_id
      int? sizeId = cartItem.sizeId;
      if (sizeId == null) {
        final szRow = await _db
            .from('menu_size')
            .select('id')
            .eq('name', cartItem.size)
            .maybeSingle();
        if (szRow == null || szRow['id'] == null) {
          throw Exception(
              'Не удалось определить size_id для размера "${cartItem.size}"');
        }
        sizeId = szRow['id'] as int;
      }

      // Вставляем order_item (каждая CartItem — количество 1)
      final createdItem = await _db.from('order_items').insert({
        'order_id': orderId,
        'menu_item_id': cartItem.itemId,
        'size_id': sizeId,
        'quantity': 1,
        'base_price': cartItem.basePrice,
        'price': cartItem.basePrice,
        'line_total': cartItem.basePrice,
        'item_name': cartItem.name,
        if (itemComment.isNotEmpty) 'item_comment': itemComment,
        if (cartItem.article != null) 'article': cartItem.article,
      }).select('id').single();

      final int orderItemId = createdItem['id'] as int;

      // 3) Вставка extras для позиции
      for (final extraEntry in cartItem.extras.entries) {
        final extraId = extraEntry.key;
        final quantity = extraEntry.value;
        // Получаем цену допов
        final priceRow = await _db
            .from('menu_item_extra_price')
            .select('price')
            .eq('menu_item_id', cartItem.itemId)
            .eq('size_id', sizeId)
            .eq('extra_id', extraId)
            .maybeSingle();
        final extraPrice = priceRow != null
            ? (priceRow['price'] as num).toDouble()
            : 0.0;

        await _db.from('order_item_extras').insert({
          'order_item_id': orderItemId,
          'extra_id': extraId,
          'size_id': sizeId,
          'quantity': quantity,
          'price': extraPrice,
        });
      }
    }

    // 4) Очистка корзины
    await CartService.clear();
  }

  /// Возвращает историю заказов текущего пользователя вместе с вложением
  static Future<List<Map<String, dynamic>>> getOrderHistory() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return [];
    final data = await _db
        .from('orders')
        .select('*, order_items(*, order_item_extras(*))')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List).cast();
  }
}
