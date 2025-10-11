// lib/widgets/main_scaffold.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/globals.dart';

import '../screens/discounts_screen.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/working_hours_banner.dart';
import '../screens/home_screen.dart';
import '../screens/menu_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/profile_screen_auth.dart';
import '../screens/menu_item_detail_screen.dart';
import '../screens/checkout_screen.dart';
import '../screens/order_history_screen.dart';
import '../screens/email_login_screen.dart';
import '../screens/email_signup_screen.dart';

class MainScaffold extends StatefulWidget {
  const MainScaffold({Key? key}) : super(key: key);

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _tabIndex = 0;

  Widget _screenForTab(int tabIndex) {
    switch (tabIndex) {
      case 0:
        return const HomeScreen();
      case 1:
        return const MenuScreen();
      case 2:
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          return ProfileScreenAuth(onLogout: _handleLogout);
        } else {
          return const ProfileScreen();
        }
      default:
        return const HomeScreen();
    }
  }

  void _handleLogout() {
    setState(() {
      _tabIndex = 2;
    });
    navigatorKey.currentState?.pushReplacementNamed('tab_2');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Navigator(
        key: navigatorKey,
        initialRoute: 'tab_$_tabIndex',
        onGenerateRoute: (RouteSettings settings) {
          final name = settings.name;
          // 1) табовые маршруты без анимации
          if (name != null && name.startsWith('tab_')) {
            final idx = int.tryParse(name.split('_').last) ?? 0;
            return PageRouteBuilder(
              settings: settings,
              pageBuilder: (_, __, ___) => _screenForTab(idx),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            );
          }
          // 2) прочие экраны со стандартной анимацией
          switch (name) {
            case '/cart':
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const CartScreen(),
              );
            case '/detail':
              final item = settings.arguments as dynamic;
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => MenuItemDetailScreen(item: item),
              );
            case '/checkout':
              final args = settings.arguments as Map<String, dynamic>;
              final total = args['totalSum'] as double;
              final comments =
                  (args['itemComments'] as Map).cast<String, String>();
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => CheckoutScreen(
                  totalSum: total,
                  itemComments: comments,
                ),
              );
            case '/history':
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const OrderHistoryScreen(),
              );
            case '/login':
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const EmailLoginScreen(),
              );
            case '/discounts':
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const DiscountsScreen(),
            );  
            case '/signup':
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const EmailSignupScreen(),
              );
            default:
              return null;
          }
        },
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: _tabIndex,
        onTap: (index) {
          setState(() {
            _tabIndex = index;
          });
          navigatorKey.currentState?.pushReplacementNamed('tab_$index');
        },
      ),
      extendBody: true,
      bottomSheet: WorkingHoursBanner(
        bottomInset:
            MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight,
      ),
    );
  }
}