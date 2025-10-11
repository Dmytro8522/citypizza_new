// lib/widgets/working_hours_banner.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/working_hours.dart';
// импортируем navigatorKey
import '../utils/globals.dart';

class WorkingHoursBanner extends StatefulWidget {
  final double bottomInset;
  const WorkingHoursBanner({Key? key, this.bottomInset = 0}) : super(key: key);

  @override
  State<WorkingHoursBanner> createState() => _WorkingHoursBannerState();
}

class _WorkingHoursBannerState extends State<WorkingHoursBanner>
    with TickerProviderStateMixin {
  late final AnimationController _blinkController;
  late final Animation<double> _opacityAnim;

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnim;

  Timer? _timer;
  bool _isOpen = WorkingHours.isOpen(DateTime.now());
  bool _manuallyClosed = false;

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _opacityAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );

    if (!_isOpen) {
      _slideController.forward();
    }

    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkIfOpened(),
    );
  }

  void _checkIfOpened() {
    final now = DateTime.now();
    final openNow = WorkingHours.isOpen(now);
    if (openNow && !_isOpen) {
      _slideController.reverse();
      _isOpen = true;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _slideController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _showHoursDialog() {
    final ctx = navigatorKey.currentContext!;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Öffnungszeiten'),
        content: const Text(
          'Montag: 11:00–14:30, 17:00–23:00\n'
          'Dienstag: geschlossen\n'
          'Mittwoch–Sonntag: 11:00–14:30, 17:00–23:00',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Schließen'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isOpen || _manuallyClosed) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottomInset,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _opacityAnim,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Wir sind gerade geschlossen. '
                    'Sie können trotzdem jetzt bestellen – Lieferung, sobald wir öffnen.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                TextButton(
                  onPressed: _showHoursDialog,
                  child: const Text(
                    'Öffnungszeiten',
                    style: TextStyle(
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => setState(() => _manuallyClosed = true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
