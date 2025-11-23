import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/no_internet_widget.dart';
import '../services/discount_service.dart';

class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({super.key});

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  late Future<List<Promotion>> _promosFuture;

  @override
  void initState() {
    super.initState();
    _promosFuture = fetchPromotions();
  }

  Future<List<Promotion>> fetchPromotions() async {
    return fetchActivePromotions(at: DateTime.now());
  }

  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Gutscheine und Angebote',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.orange),
        elevation: 0,
      ),
      body: FutureBuilder<List<Promotion>>(
        future: _promosFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          } else if (snapshot.hasError) {
            return NoInternetWidget(
              onRetry: () { setState(() { _promosFuture = fetchPromotions(); }); },
              errorText: snapshot.error.toString().contains('SocketException')
                  ? 'Keine Internetverbindung'
                  : 'Fehler beim Laden der Angebote.',
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'Zurzeit gibt es keine aktiven Angebote.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final promotions = snapshot.data!;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: promotions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, idx) {
        final d = promotions[idx];
    final type = d.discountType
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('-', '_');
  final isDiscountReduction = !type.startsWith('fixed_price');
  final rawValue = d.discountValue.abs();
    final decimals = rawValue.truncateToDouble() == rawValue ? 0 : 2;
    final formatted = rawValue.toStringAsFixed(decimals);
  final baseValue = type.contains('percent') ? "$formatted%" : "€$formatted";
    final badgeText = isDiscountReduction
      ? "Rabatt: -$baseValue"
      : "Aktionspreis: $baseValue";
              final dateFormat = DateFormat('dd.MM.yyyy');
              final start = dateFormat.format(d.startsAt);
              final end = d.endsAt != null ? dateFormat.format(d.endsAt!) : '';
              final targets = d.targets;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.orange, width: 1.2),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if ((d.description ?? '').isNotEmpty)
                      Text(
                        d.description!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              badgeText,
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (start.isNotEmpty || end.isNotEmpty)
                      Text(
                        start.isNotEmpty && end.isNotEmpty
                          ? "Gültig: $start – $end"
                          : start.isNotEmpty
                            ? "Ab: $start"
                            : "Bis: $end",
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    if (targets.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ...targets.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _formatTargetNew(t),
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 14,
                          ),
                        ),
                      )),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _formatTargetNew(PromotionTarget t) {
    switch (t.targetType) {
      case 'category':
        return 'Kategorie-ID: ${t.categoryId}';
      case 'item':
        return 'Artikel-ID: ${t.itemId}';
      case 'category_size':
        return 'Kategorie ${t.categoryId}, Größe ${t.sizeId}';
      case 'item_size':
        return 'Artikel ${t.itemId}, Größe ${t.sizeId}';
      default:
        return t.targetType;
    }
  }
}
