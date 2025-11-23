// lib/widgets/animated_gradient_section.dart

import 'dart:async';
import 'package:flutter/material.dart';

class AnimatedGradientSection extends StatefulWidget {
  final Widget title;
  final Widget child;
  final List<List<Color>> gradients;
  final Duration duration;

  const AnimatedGradientSection({
    super.key,
    required this.title,
    required this.child,
    required this.gradients,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AnimatedGradientSection> createState() => _AnimatedGradientSectionState();
}

class _AnimatedGradientSectionState extends State<AnimatedGradientSection> {
  int _gradientIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.duration, (_) {
      if (!mounted) return;
      setState(() {
        _gradientIndex = (_gradientIndex + 1) % widget.gradients.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.gradients[_gradientIndex];
    return Stack(
      children: [
        AnimatedContainer(
          duration: widget.duration,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.only(top: 16, left: 16, bottom: 16, right: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.title,
              const SizedBox(height: 12),
              widget.child,
            ],
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              width: 54,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.07),
                    Colors.black.withOpacity(0.12),
                    Colors.black.withOpacity(0.24),
                    Colors.black.withOpacity(0.45),
                  ],
                  stops: const [0.0, 0.3, 0.6, 0.85, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
