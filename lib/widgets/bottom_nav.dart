// lib/widgets/bottom_nav.dart

import 'package:flutter/material.dart';

typedef OnTab = void Function(int index);

/// Общий виджет нижнего меню приложения с тремя вкладками:
/// Home, Menü, Profil
class BottomNav extends StatelessWidget {
  final int currentIndex;
  final OnTab onTap;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;

  const BottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      backgroundColor: backgroundColor ?? Colors.black,
      selectedItemColor: selectedColor ?? Colors.orange,
      unselectedItemColor: unselectedColor ?? Colors.white54,
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.local_pizza),
          label: 'Menü',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profil',
        ),
      ],
    );
  }
}
