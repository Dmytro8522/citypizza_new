import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fire_particles.dart';

/// Раздел «Акции» с живым фоном огня и яркими пицца-тонами
class FireBackgroundSection extends StatelessWidget {
  final Widget title;
  final Widget child;
  final double? maxHeight;
  const FireBackgroundSection({
    super.key,
    required this.title,
    required this.child,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Базовая высота контента = высота дочернего виджета (если он ограничен) + отступы и заголовок.
    // Чтобы не растягивать секцию, используем IntrinsicHeight окружение и фиксированную высоту огня.
    const double particlesHeight = 260; // чуть больше карточек чтобы огонь выглядел естественно
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24)),
      child: Stack(
        children: [
          // Огненная анимация фон — используем Positioned.fill с ограничением по высоте через SizedBox
          SizedBox(
            height: maxHeight ?? particlesHeight,
            width: double.infinity,
            child: const FireParticles(width: double.infinity, height: particlesHeight),
          ),
          SizedBox(
            height: maxHeight ?? particlesHeight,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.redAccent.withOpacity(0.6),
                    Colors.orangeAccent.withOpacity(0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          SizedBox(
            height: maxHeight ?? particlesHeight,
            width: double.infinity,
            child: Container(color: Colors.black.withOpacity(0.3)),
          ),
          // Контент по фактической высоте, без Expanded
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                // Ограничиваем, чтобы контент не «растягивал» фон сверх maxHeight
                maxHeight: maxHeight ?? particlesHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_pizza, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      Text(
                        'Aktuelle Angebote',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            const Shadow(
                              blurRadius: 8,
                              color: Colors.orangeAccent,
                              offset: Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Контент сам задаёт свою высоту (например, список акций)
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
