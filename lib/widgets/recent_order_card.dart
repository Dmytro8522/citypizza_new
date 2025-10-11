// lib/widgets/recent_order_card.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/cart_service.dart';
import '../theme/theme_provider.dart';

class RecentOrderCard extends StatelessWidget {
  final CartItem item;
  final VoidCallback? onTap;

  const RecentOrderCard({
    Key? key,
    required this.item,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: appTheme.backgroundColor == Colors.white
            ? Colors.white
            : appTheme.cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Image and details
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _buildImage(context),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: appTheme.textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.article != null ? '[${item.article}]' : '',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: appTheme.textColorSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${item.size} • ${item.basePrice.toStringAsFixed(2)} €',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: appTheme.textColor,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: appTheme.iconColor),
                          onPressed: () async {
                            await CartService.removeItem(item);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('${item.name} entfernt'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Исправлено: безопасно получаем картинку блюда по itemId через menu_item
  Widget _buildImage(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _fetchMenuItem(item.itemId),
      builder: (context, snapshot) {
        final imageUrl = snapshot.data?['image_url'] as String?;
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return Image.network(
            imageUrl,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
          );
        }
        return Container(
          width: 64,
          height: 64,
          color: Colors.grey[300],
          child: Icon(Icons.fastfood, size: 32, color: Colors.grey),
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchMenuItem(int itemId) async {
    final supabase = Supabase.instance.client;
    final res = await supabase
        .from('menu_item')
        .select('image_url')
        .eq('id', itemId)
        .maybeSingle();
    return res as Map<String, dynamic>?;
  }
}