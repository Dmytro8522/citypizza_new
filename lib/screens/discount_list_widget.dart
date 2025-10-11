import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/fire_background_section.dart';
import '../widgets/fire_particles.dart';

const double _cardWidth = 260;
const double _cardHeight = 180;
const Duration _autoScrollInterval = Duration(seconds: 4);
const Duration _pageAnimationDuration = Duration(milliseconds: 800);

/// Обёртка для секции со скидками
class DiscountSection extends StatelessWidget {
  const DiscountSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FireBackgroundSection(
      title: const SizedBox.shrink(),
      child: const DiscountListWidget(),
    );
  }
}

class DiscountListWidget extends StatefulWidget {
  const DiscountListWidget({Key? key}) : super(key: key);

  @override
  State<DiscountListWidget> createState() => _DiscountListWidgetState();
}

class _DiscountListWidgetState extends State<DiscountListWidget>
    with TickerProviderStateMixin {  // <-- 변경 здесь
  final PageController _pageCtrl = PageController(viewportFraction: 0.9);
  Timer? _autoScrollTimer;
  List<Map<String, dynamic>> _discounts = [];
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

    _fetchDiscounts();
  }

  Future<void> _fetchDiscounts() async {
    setState(() => _loading = true);
    final now = DateTime.now().toIso8601String();
    final res = await Supabase.instance.client
        .from('discounts')
        .select()
        .eq('active', true)
        .lte('start_at', now)
        .order('start_at', ascending: false);

    final filt = (res as List)
        .cast<Map<String, dynamic>>()
        .where((d) =>
            d['end_at'] == null ||
            DateTime.parse(d['end_at']).isAfter(DateTime.now()))
        .toList();

    if (!mounted) return;
    setState(() {
      _discounts = filt;
      _loading = false;
    });
  }

  void _nextPage() {
    if (_discounts.isEmpty || !_pageCtrl.hasClients) return;
    final current = (_pageCtrl.page ?? 0).round();
    final next = current + 1 >= _discounts.length ? 0 : current + 1;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return SizedBox(
        height: _cardHeight,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    if (_discounts.isEmpty) {
      return SizedBox(
        height: _cardHeight,
        child: const Center(
          child: Text(
            'Zurzeit keine Angebote',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return SizedBox(
      height: _cardHeight,
      child: PageView.builder(
        controller: _pageCtrl,
        itemCount: _discounts.length,
        padEnds: false,
        itemBuilder: (context, idx) {
          final d = _discounts[idx];
          final isPercent = d['discount_type'] == 'percent';
          // Исправлено: отображаем только целые числа
          final value = d['value'];
          final valueStr = isPercent
              ? '${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}%'
              : '€${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}';
          final title = d['name'] ?? 'Angebot';
          final desc = (d['description'] ?? '').toString().trim();
          final period = (d['start_at'] != null ? _formatDate(d['start_at']) : '') +
              (d['end_at'] != null ? ' – ${_formatDate(d['end_at'])}' : '');
          final glow = 0.6 + 0.4 * _pulseCtrl.value;

          return GestureDetector(
            onTap: () => _showDetail(context, d),
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
                      Positioned(
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
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: GoogleFonts.fredokaOne(
                                      color: Colors.white,
                                      fontSize: 18,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.info_outline,
                                    size: 20,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () => _showDetail(context, d),
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
                                '-$valueStr',
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

  void _showDetail(BuildContext ctx, Map<String, dynamic> d) {
    final isPercent = d['discount_type'] == 'percent';
    // Исправлено: отображаем только целые числа
    final value = d['value'];
    final valueStr = isPercent
        ? '${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}%'
        : '€${(value is num ? value.toInt() : int.tryParse(value.toString()) ?? value)}';
    final title = d['name'] ?? 'Angebot';
    final desc = (d['description'] ?? '').toString().trim();
    final period = (d['start_at'] != null ? _formatDate(d['start_at']) : '') +
        (d['end_at'] != null ? ' – ${_formatDate(d['end_at'])}' : '');

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
                valueStr,
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
