// lib/widgets/upsell_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/upsell_service.dart';
import '../services/cart_service.dart';

class UpSellWidget extends StatefulWidget {
  final String channel;
  final double subtotal;
  final VoidCallback? onItemAdded;
  final void Function(int itemId)? onItemTap;

  const UpSellWidget({
    Key? key,
    required this.channel,
    required this.subtotal,
    this.onItemAdded,
    this.onItemTap,
  }) : super(key: key);

  @override
  _UpSellWidgetState createState() => _UpSellWidgetState();
}

class _UpSellWidgetState extends State<UpSellWidget> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadUpsell();
  }

  Future<void> _loadUpsell() async {
    final data = await UpSellService.fetchUpsell(
      channel: widget.channel,
      subtotal: widget.subtotal,
      userId: null,
    );
    if (!mounted) return;
    setState(() {
      _items = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    return Container(
      color: Colors.grey[850],
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок
          Text(
            'Das könnte Ihnen gefallen',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // Горизонтальный ряд, динамическая высота через IntrinsicHeight
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _items.map((it) {
                return Expanded(
                  child: _buildTile(it),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(Map<String, dynamic> it) {
    return GestureDetector(
      onTap: () => widget.onItemTap?.call(it['id'] as int),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            // 1) Изображение
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              child: it['image_url'] != null
                  ? Image.network(
                      it['image_url'] as String,
                      height: 80,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      height: 80,
                      color: Colors.white10,
                    ),
            ),
            const SizedBox(height: 6),
            // 2) Название
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${it['article'] != null ? '[${it['article']}] ' : ''}${it['name']}',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            // 3) Цена
            Text(
              '${(it['price'] as double).toStringAsFixed(2)} €',
              style: GoogleFonts.poppins(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(), // подтягивает кнопку вниз
            // 4) Кнопка
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                height: 32,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () async {
                    // Вместо ручного создания CartItem, используем addItemById,
                    // чтобы CartService сам выбрал минимальный размер/цену.
                    await CartService.addItemById(it['id'] as int);
                    widget.onItemAdded?.call();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Hinzugefügt: ${it['name']}')),
                    );
                  },
                  child: Text(
                    'Hinzufügen',
                    style: GoogleFonts.poppins(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
