import 'dart:math';
import 'package:flutter/material.dart';

const int _particleCount = 120;

/// Анимация огня — такой же, как была
class FireParticles extends StatefulWidget {
  final double width;
  final double height;
  const FireParticles({Key? key, required this.width, required this.height})
      : super(key: key);

  @override
  State<FireParticles> createState() => _FireParticlesState();
}

class _FireParticlesState extends State<FireParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rnd = Random();

  @override
  void initState() {
    super.initState();
    _particles = List.generate(
      _particleCount,
      (_) => _Particle(_rnd, widget.width, widget.height),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )
      ..addListener(() {
        for (final p in _particles) p.update();
        setState(() {});
      })
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _FirePainter(_particles),
    );
  }
}

class _Particle {
  late Offset pos;
  late double speed;
  late Color color;
  final Random rnd;
  final double width, height;

  _Particle(this.rnd, this.width, this.height) {
    reset();
  }

  void reset() {
    pos = Offset(rnd.nextDouble() * width, rnd.nextDouble() * height);
    speed = rnd.nextDouble() * 2 + 1;
    color = Colors.orange.withOpacity(rnd.nextDouble());
  }

  void update() {
    pos = Offset(pos.dx + (rnd.nextDouble() - 0.5) * 2, pos.dy - speed);
    if (pos.dy < 0) {
      reset();
      pos = Offset(rnd.nextDouble() * width, height);
    }
  }
}

class _FirePainter extends CustomPainter {
  final List<_Particle> particles;
  _FirePainter(this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final rnd = Random();
    for (final p in particles) {
      paint.color = p.color;
      canvas.drawCircle(p.pos, rnd.nextDouble() * 3 + 2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
