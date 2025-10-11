// lib/widgets/screen_padding.dart

import 'package:flutter/material.dart';

class ScreenPadding extends StatelessWidget {
  final Widget child;
  final double bottomPadding;

  const ScreenPadding({
    Key? key,
    required this.child,
    this.bottomPadding = 68, // Это высота твоего меню! Можно скорректировать.
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: child,
    );
  }
}
