import 'package:flutter/material.dart';

class CreativeCtaSection extends StatefulWidget {
  final VoidCallback onTap;
  const CreativeCtaSection({Key? key, required this.onTap}) : super(key: key);

  @override
  _CreativeCtaSectionState createState() => _CreativeCtaSectionState();
}

class _CreativeCtaSectionState extends State<CreativeCtaSection>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _angleAnim;
  late Animation<double> _yOffsetAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _angleAnim = Tween(begin: -0.035, end: 0.035).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _yOffsetAnim = Tween(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Карточка
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hungrig?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF212121),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Wir haben was für dich!',
                  style:
                      Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 16,
                            color: const Color(0xFF424242),
                          ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: widget.onTap,
                  icon: const Icon(Icons.arrow_forward, color: Colors.white),
                  label: const Text('Zum Menü'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5722),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Акцентная граница снизу
          Positioned(
            left: 0,
            right: 0,
            bottom: -2,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5722),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(18),
                ),
              ),
            ),
          ),

          // Выходящая иллюстрация
          Positioned(
            right: -40,
            bottom: -10,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) {
                return Transform.translate(
                  offset: Offset(0, _yOffsetAnim.value),
                  child: Transform.rotate(
                    angle: _angleAnim.value,
                    child: child,
                  ),
                );
              },
              child: Image.asset(
                'assets/pizza_slice.png',
                width: 160,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
