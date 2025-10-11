// lib/widgets/common_app_bar.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/cart_service.dart';
import '../screens/cart_screen.dart';
import '../utils/globals.dart';  
import '../theme/theme_provider.dart';

/// единый AppBar с корзинкой и бейджем
PreferredSizeWidget buildCommonAppBar({
  required String title,
  required BuildContext context,
}) {
  final appTheme = ThemeProvider.of(context);
  return AppBar(
    backgroundColor: appTheme.backgroundColor,
    title: Text(title,
        style: GoogleFonts.fredokaOne(fontSize: 20, color: appTheme.primaryColor)),
    centerTitle: true,
    elevation: 0,
    leading: null, // <-- стрелка назад (leading) явно отключена
    actions: [
      Stack(
        children: [
          IconButton(
            icon: Icon(Icons.shopping_cart, color: appTheme.iconColor),
            onPressed: () {
              // Переходим внутри MainScaffold
              navigatorKey.currentState!.pushNamed('/cart');
            },
          ),
          if (CartService.items.isNotEmpty)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${CartService.items.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}
