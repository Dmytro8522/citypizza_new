// lib/widgets/screen_padding.dart

import 'package:flutter/material.dart';

class ScreenPadding extends StatelessWidget {
  final Widget child;
  final double bottomPadding;

  const ScreenPadding({
    super.key,
    required this.child,
    this.bottomPadding = 68, // Это высота твоего меню! Можно скорректировать.
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: child,
    );
  }
}
