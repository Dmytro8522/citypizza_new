import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../widgets/no_internet_widget.dart';

class DiscountsScreen extends StatefulWidget {
  const DiscountsScreen({Key? key}) : super(key: key);

  @override
  State<DiscountsScreen> createState() => _DiscountsScreenState();
}

class _DiscountsScreenState extends State<DiscountsScreen> {
  late Future<List<Map<String, dynamic>>> _discountsFuture;

  @override
  void initState() {
    super.initState();
    _discountsFuture = fetchDiscounts();
  }

  Future<List<Map<String, dynamic>>> fetchDiscounts() async {
    final now = DateTime.now().toIso8601String();

    // Берём все активные скидки, чья дата старта <= сейчас, и дата окончания либо null, либо >= сейчас
    final discounts = await Supabase.instance.client
        .from('discounts')
        .select()
        .eq('active', true)
        .lte('start_at', now);

    // Берём все targets для найденных скидок
    final ids = discounts.map((d) => d['id']).toList();
    Map<int, List<Map<String, dynamic>>> targetsMap = {};
    if (ids.isNotEmpty) {
      final targets = await Supabase.instance.client
          .from('discount_targets')
          .select()
          .filter('discount_id', 'in', ids);
      for (final t in targets) {
        final dId = t['discount_id'] as int;
        targetsMap.putIfAbsent(dId, () => []).add(t);
      }
    }

    // Объединяем скидки с их target-ами
    return discounts.map<Map<String, dynamic>>((d) {
      final dId = d['id'] as int;
      return {
        ...d,
        'targets': targetsMap[dId] ?? [],
      };
    }).toList();
  }

  String _formatTarget(Map<String, dynamic> target) {
    final type = target['target_type'];
    final value = target['target_value'];
    switch (type) {
      case 'all':
        return 'Für alle Bestellungen';
      case 'category':
        return 'Nur für Kategorie: $value';
      case 'item':
        return 'Nur für Artikel: $value';
      case 'user':
        return 'Persönliche Aktion';
      case 'user_group':
        return 'Für Gruppe: $value';
      case 'promo_code':
        return 'Mit Code: $value';
      case 'birthday':
        return 'Zum Geburtstag';
      case 'holiday':
        return 'Zum Feiertag';
      case 'first_order':
        return 'Für die erste Bestellung';
      case 'delivery_type':
        return 'Nur für: $value';
      case 'payment_type':
        return 'Nur bei Zahlung: $value';
      default:
        return type != null ? type.toString() : 'Sonderaktion';
    }
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _discountsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.orange));
          } else if (snapshot.hasError) {
            return NoInternetWidget(
              onRetry: () {
                setState(() {
                  _discountsFuture = fetchDiscounts();
                });
              },
              errorText: snapshot.error.toString().contains('SocketException')
                  ? 'Keine Internetverbindung'
                  : 'Fehler beim Laden der Angebote.',
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(
                'Zurzeit gibt es keine aktiven Angebote.',
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final discounts = snapshot.data!;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: discounts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemBuilder: (context, idx) {
              final d = discounts[idx];
              final isPercent = d['discount_type'] == 'percent';
              // Исправлено: отображаем только целые числа
              final value = d['value'];
              final valueStr = isPercent
                  ? "${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}%"
                  : "€${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}";
              final dateFormat = DateFormat('dd.MM.yyyy');
              final start = d['start_at'] != null ? dateFormat.format(DateTime.parse(d['start_at'])) : '';
              final end = d['end_at'] != null ? dateFormat.format(DateTime.parse(d['end_at'])) : '';
              final minOrder = d['min_order'] ?? 0;
              final targets = (d['targets'] ?? []) as List;

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
                      d['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if ((d['description'] ?? '').isNotEmpty)
                      Text(
                        d['description'],
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
                              "Rabatt: $valueStr",
                              style: const TextStyle(
                                color: Colors.orange,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (minOrder > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "Mindestbestellwert: €$minOrder",
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 14,
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
                          _formatTarget(t),
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
}
