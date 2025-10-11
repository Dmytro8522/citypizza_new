import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fire_particles.dart';

/// Раздел «Акции» с живым фоном огня и яркими пицца-тонами
class FireBackgroundSection extends StatelessWidget {
  final Widget title;
  final Widget child;

  const FireBackgroundSection({
    Key? key,
    required this.title,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      height: 300,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Огненная анимация на весь раздел
          FireParticles(width: double.infinity, height: 300),

          // Яркий градиент для пицца-настроения
          Container(
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

          // Чуть затемняем для контраста текста
          Container(color: Colors.black.withOpacity(0.3)),

          // Содержимое
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Заголовок раздела
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
                          Shadow(
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
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
