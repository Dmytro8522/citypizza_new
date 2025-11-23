import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/fire_background_section.dart';
import '../widgets/fire_particles.dart';
import '../services/discount_service.dart';

const double _cardWidth = 260;
const double _cardHeight = 180;
const Duration _autoScrollInterval = Duration(seconds: 4);
const Duration _pageAnimationDuration = Duration(milliseconds: 800);

/// Обёртка для секции со скидками
class DiscountSection extends StatelessWidget {
  const DiscountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const FireBackgroundSection(
      title: SizedBox.shrink(),
      child: DiscountListWidget(),
    );
  }
}

class DiscountListWidget extends StatefulWidget {
  const DiscountListWidget({super.key});

  @override
  State<DiscountListWidget> createState() => _DiscountListWidgetState();
}

class _DiscountListWidgetState extends State<DiscountListWidget>
    with TickerProviderStateMixin {  // <-- 변경 здесь
  final PageController _pageCtrl = PageController(viewportFraction: 0.9);
  Timer? _autoScrollTimer;
  List<Promotion> _promotions = [];
  bool _loading = true;

  // пульс-эффект для рамки
  late final AnimationController _pulseCtrl;
  // анимация для градиентного текста
  late final AnimationController _gradCtrl;
  late final Animation<double> _gradAnim;

  @override
  void initState() {
    super.initState();

    // Пульс-эффект рамки
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )
      ..addListener(() => setState(() {}))
      ..repeat(reverse: true);

    // Градиентная анимация для текста скидки
    _gradCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _gradAnim = CurvedAnimation(parent: _gradCtrl, curve: Curves.easeInOut);
    _gradCtrl.repeat(reverse: true);

    // Автопрокрутка страниц
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoScrollTimer =
          Timer.periodic(_autoScrollInterval, (_) => _nextPage());
    });

    _fetchPromotions();
  }

  Future<void> _fetchPromotions() async {
    setState(() => _loading = true);
    try {
      final promos = await fetchActivePromotions(at: DateTime.now());

      if (!mounted) return;
      setState(() {
        _promotions = promos;
        _loading = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _promotions = [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promotions = [];
        _loading = false;
      });
    }
  }

  void _nextPage() {
    if (_promotions.isEmpty || !_pageCtrl.hasClients) return;
    final current = (_pageCtrl.page ?? 0).round();
    final next = current + 1 >= _promotions.length ? 0 : current + 1;
    _pageCtrl.animateToPage(
      next,
      duration: _pageAnimationDuration,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageCtrl.dispose();
    _pulseCtrl.dispose();
    _gradCtrl.dispose();
    super.dispose();
  }

  String _formatDate(String ds) {
    final dt = DateTime.tryParse(ds);
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')}.'
        '${dt.year}';
  }

  String _normalizedType(Promotion promo) => promo.discountType
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll('-', '_');

  bool _isFixedPrice(Promotion promo) {
    final type = _normalizedType(promo);
    return type.startsWith('fixed_price');
  }

  bool _isDiscountReduction(Promotion promo) {
    return !_isFixedPrice(promo);
  }

  String _formattedValue(Promotion promo) {
    final magnitude = promo.discountValue.abs();
    final decimals = magnitude.truncateToDouble() == magnitude ? 0 : 2;
    final formatted = magnitude.toStringAsFixed(decimals);
    final type = _normalizedType(promo);
    if (type.contains('percent')) {
      return '$formatted%';
    }
    return '€$formatted';
  }

  String _headlineValue(Promotion promo) {
    final base = _formattedValue(promo);
    return _isDiscountReduction(promo) ? '-$base' : base;
  }

  String _badgeLabel(Promotion promo) {
    final base = _formattedValue(promo);
    return _isDiscountReduction(promo) ? 'Rabatt: -$base' : 'Aktionspreis: $base';
  }

  String _detailValue(Promotion promo) {
    final base = _formattedValue(promo);
    return _isDiscountReduction(promo) ? '-$base' : base;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: _cardHeight,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_promotions.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: _cardHeight,
      child: PageView.builder(
        controller: _pageCtrl,
    itemCount: _promotions.length,
        padEnds: false,
        itemBuilder: (context, idx) {
          final promo = _promotions[idx];
          final headlineValue = _headlineValue(promo);
          final title = promo.name.isNotEmpty ? promo.name : 'Angebot';
          final desc = (promo.description ?? '').toString().trim();
          final period = _formatDate(promo.startsAt.toIso8601String()) +
              (promo.endsAt != null
                  ? ' – ${_formatDate(promo.endsAt!.toIso8601String())}'
                  : '');
          final glow = 0.6 + 0.4 * _pulseCtrl.value;

          return GestureDetector(
            onTap: () => _showDetail(context, promo),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Transform.scale(
                scale: 1.0 + 0.02 * (_pulseCtrl.value - 0.5),
                child: Container(
                  width: _cardWidth,
                  height: _cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: glow),
                      width: 2,
                    ),
                    color: Colors.black.withValues(alpha: 0.3),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      const Positioned(
                        top: -20,
                        left: -20,
                        child: SizedBox(
                          width: _cardWidth + 40,
                          height: _cardHeight + 40,
                          child: FireParticles(
                            width: _cardWidth + 40,
                            height: _cardHeight + 40,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.fredokaOne(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => _showDetail(context, promo),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // ——— динамический градиент для цифры скидки ———
                            AnimatedBuilder(
                              animation: _gradAnim,
                              builder: (context, child) {
                                final t = _gradAnim.value;
                                final begin = Alignment(-1.0 + 2 * t, 0);
                                final end   = Alignment(1.0 - 2 * t, 0);
                                return ShaderMask(
                                  blendMode: BlendMode.srcIn,
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      begin: begin,
                                      end: end,
                                      colors: const [
                                        Colors.yellowAccent,
                                        Colors.orangeAccent,
                                        Colors.redAccent,
                                      ],
                                    ).createShader(bounds);
                                  },
                                  child: child,
                                );
                              },
                              child: Text(
                                headlineValue,
                                style: GoogleFonts.fredokaOne(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (desc.isNotEmpty)
                              Text(
                                desc,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 6),
                            Text(
                              period,
                              style: GoogleFonts.poppins(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDetail(BuildContext ctx, Promotion promo) {
    final title = promo.name.isNotEmpty ? promo.name : 'Angebot';
    final desc = (promo.description ?? '').trim();
    final start = _formatDate(promo.startsAt.toIso8601String());
    final end = promo.endsAt != null
        ? _formatDate(promo.endsAt!.toIso8601String())
        : '';
    String period = '';
    if (start.isNotEmpty && end.isNotEmpty) {
      period = '$start – $end';
    } else if (start.isNotEmpty) {
      period = 'Ab: $start';
    } else if (end.isNotEmpty) {
      period = 'Bis: $end';
    }
    final detailValue = _detailValue(promo);

    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                title,
                style: GoogleFonts.fredokaOne(
                  color: Colors.orangeAccent,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _badgeLabel(promo),
                style: GoogleFonts.poppins(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                detailValue,
                style: GoogleFonts.poppins(
                  color: Colors.yellowAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                ),
              ),
              if (desc.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 2),
                  child: Text(
                    desc,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 15),  
                  ),
                ),
              if (period.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    period,
                    style: GoogleFonts.poppins(color: Colors.white60, fontSize: 14),
                  ),
                ),
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
