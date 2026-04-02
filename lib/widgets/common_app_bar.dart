// lib/widgets/common_app_bar.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/cart_service.dart';
import '../utils/globals.dart';  
import '../theme/theme_provider.dart';
import '../services/app_config_service.dart';
import '../utils/app_text.dart';

/// единый AppBar с корзинкой и бейджем
PreferredSizeWidget buildCommonAppBar({
  required String title,
  String? titleKey,
  required BuildContext context,
}) {
  final appTheme = ThemeProvider.of(context);
  final appBarBackground = AppConfigService.color(
    'theme.appBarBackground',
    fallback: appTheme.backgroundColor,
  );
  final appBarTitleColor = AppConfigService.color(
    'theme.appBarTitleColor',
    fallback: appTheme.primaryColor,
  );
  final appBarIconColor = AppConfigService.color(
    'theme.appBarIconColor',
    fallback: appTheme.iconColor,
  );
  final resolvedTitle = titleKey != null
      ? AppText.t(titleKey, fallback: title)
      : title;
  return AppBar(
    backgroundColor: appBarBackground,
    title: Text(
      resolvedTitle,
      style: GoogleFonts.fredokaOne(fontSize: 20, color: appBarTitleColor),
    ),
    centerTitle: true,
    elevation: 0,
    leading: null, // <-- стрелка назад (leading) явно отключена
    actions: [
      Stack(
        children: [
          IconButton(
            icon: Icon(Icons.shopping_cart, color: appBarIconColor),
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
                decoration: const BoxDecoration(
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
