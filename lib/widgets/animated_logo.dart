import 'package:flutter/material.dart';

/// Анимационный виджет лого: вход, пульс, выход
class AnimatedLogo extends StatelessWidget {
  final Animation<Offset> entryOffset;
  final Animation<Offset> exitOffset;
  final Animation<double> pulseScale;

  const AnimatedLogo({
    super.key,
    required this.entryOffset,
    required this.exitOffset,
    required this.pulseScale,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final logoSize = w * 289 / 390;
    return SlideTransition(
      position: exitOffset,
      child: SlideTransition(
        position: entryOffset,
        child: ScaleTransition(
          scale: pulseScale,
          child: Center(
            child: Image.asset(
              'assets/logo.png',
              width: logoSize,
              height: logoSize,
            ),
          ),
        ),
      ),
    );
  }
}
