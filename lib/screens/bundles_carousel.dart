// lib/screens/bundles_carousel.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/theme_provider.dart';
import '../widgets/no_internet_widget.dart';
import 'bundle_detail_screen.dart';

class BundleSummary {
  final int id;
  final String name;
  final String? description;
  final String? imageUrl;
  final double minPrice; // теперь это bundle.price
  final int? sizeId; // не используется при фиксированной цене
  BundleSummary({
    required this.id,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.minPrice,
    this.sizeId,
  });
}

class BundlesSection extends StatefulWidget {
  const BundlesSection({super.key});

  @override
  State<BundlesSection> createState() => _BundlesSectionState();
}

class _BundlesSectionState extends State<BundlesSection> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  List<BundleSummary> _bundles = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _supabase
          .from('menu_v2_bundle')
          .select('id, name, description, image_url, is_active, price')
          .eq('is_active', true)
          .order('id', ascending: true);
      final list = (rows as List).cast<Map<String, dynamic>>();
      final bundles = <BundleSummary>[];
      for (final m in list) {
        final id = (m['id'] as int?) ?? 0;
        if (id == 0) continue;
        final price = (m['price'] as num?)?.toDouble() ?? 0.0;
        bundles.add(BundleSummary(
          id: id,
          name: (m['name'] as String?) ?? '',
          description: (m['description'] as String?)?.trim(),
          imageUrl: (m['image_url'] as String?),
          minPrice: price,
        ));
      }
      if (!mounted) return;
      setState(() {
        _bundles = bundles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    if (_error != null) return const SizedBox.shrink();
    if (_bundles.isEmpty) return const SizedBox.shrink();
    final appTheme = ThemeProvider.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Angebote & Bundles',
          style: GoogleFonts.poppins(
            color: appTheme.textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              for (int i = 0; i < _bundles.length; i++) ...[
                if (i == 0) const SizedBox(width: 4),
                _BundleCard(bundle: _bundles[i]),
                const SizedBox(width: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// Удалён внутренний _BundlesCarousel: логика перенесена в BundlesSection для скрытия пустой секции

class _BundleCard extends StatelessWidget {
  final BundleSummary bundle;
  const _BundleCard({required this.bundle});

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    final borderRadius = BorderRadius.circular(14);
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => BundleDetailScreen(bundleId: bundle.id),
            ),
          );
        },
        child: Container(
          width: 270,
          decoration: BoxDecoration(
            color: appTheme.cardColor.withValues(alpha: 0.96),
            borderRadius: borderRadius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.local_offer, color: Colors.orange.shade300),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bundle.name,
                          style: GoogleFonts.poppins(
                            color: appTheme.textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${bundle.minPrice.toStringAsFixed(2)} €',
                          style: GoogleFonts.poppins(
                            color: appTheme.primaryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: appTheme.iconColor),
                ],
              ),
              if ((bundle.description ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: Scrollbar(
                    thumbVisibility: false,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        (bundle.description ?? '').trim(),
                        style: GoogleFonts.poppins(
                          color: appTheme.textColorSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
