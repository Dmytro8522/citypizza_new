import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MenuItemPlaceholder extends StatelessWidget {
  final double width;
  final double height;
  final String? title;
  final String? price;
  final double borderRadius;

  const MenuItemPlaceholder({
    Key? key,
    this.width = double.infinity,
    this.height = 120,
    this.title,
    this.price,
    this.borderRadius = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFFFF9800);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          colors: [Color(0xFF1b1b1b), Color(0xFF262626)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // subtle pattern / vignette
          Positioned.fill(
            child: Opacity(
              opacity: 0.06,
              child: Image.asset(
                'assets/pizza_slice.png',
                fit: BoxFit.cover,
                color: Colors.white,
                colorBlendMode: BlendMode.srcATop,
              ),
            ),
          ),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary,
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: const Icon(Icons.fastfood, color: Colors.white, size: 28),
            ),
          ),
          // title + price overlay at bottom
          if ((title ?? '').isNotEmpty || (price ?? '').isNotEmpty)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if ((price ?? '').isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          price ?? '',
                          style: GoogleFonts.poppins(
                            color: Colors.black,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
