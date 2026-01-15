// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'firebase_options.dart';
import 'dart:io'; // Добавьте импорт для SocketException

import 'services/cart_service.dart';
import 'services/consent_service.dart';
import 'services/discount_service.dart';
import 'screens/email_login_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/cookie_settings_screen.dart';
import 'widgets/main_scaffold.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

/// Фоновый хендлер для пушей, когда приложение убито или свернуто
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Инициализируем Firebase, чтобы можно было обрабатывать сообщение
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

// Канал для Android heads-up уведомлений
const AndroidNotificationChannel _promoChannel = AndroidNotificationChannel(
  'promos_high', // новый канал, чтобы гарантировать звук
  'Promotions',
  description: 'Акции и уведомления City Pizza',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  ledColor: Color(0xFFFF9800),
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await _localNotifications.initialize(initSettings);

  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_promoChannel);
}

Future<void> _showLocalNotification(RemoteMessage message) async {
  final title = message.notification?.title ?? message.data['title'];
  final body = message.notification?.body ?? message.data['body'];
  if (title == null && body == null) return;

  final androidDetails = AndroidNotificationDetails(
    _promoChannel.id,
    _promoChannel.name,
    channelDescription: _promoChannel.description,
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    sound: const RawResourceAndroidNotificationSound('default'),
    icon: '@mipmap/ic_launcher',
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
    presentBadge: true,
    interruptionLevel: InterruptionLevel.timeSensitive,
    sound: 'default',
  );

  await _localNotifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title ?? '',
    body ?? '',
    NotificationDetails(android: androidDetails, iOS: iosDetails),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) Инициализируем Firebase
  // Исправление: используем DefaultFirebaseOptions для корректной инициализации на Android и iOS
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Инициализируем локальные уведомления для баннеров в foreground
  await _initLocalNotifications();

  // 2) Фиксируем ориентацию экрана портретом
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // 3) Инициализируем Supabase
  await Supabase.initialize(
    url: 'https://kwjbfxaoicmvdkrcgmpo.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt3amJmeGFvaWNtdmRrcmNnbXBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDYwOTAyNjIsImV4cCI6MjA2MTY2NjI2Mn0.MqdObfe9_4_kkWzMAywK7XZkYVVpin2HUts39rmv6lU',
  );
  await CartService.init();

  // 4) Запрос разрешения на пуш-уведомления (особенно важно для iOS)
  NotificationSettings settings = await FirebaseMessaging.instance.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: true,
    provisional: false,
    sound: true,
  );
  debugPrint('🔔 Push permission status: ${settings.authorizationStatus}');

  // Показываем баннеры даже в foreground на iOS
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // Подпишем все устройства на общий топик акций
  try {
    await FirebaseMessaging.instance.subscribeToTopic('promotions');
    debugPrint('📨 Subscribed to promotions topic');
  } catch (e) {
    debugPrint('⚠️ Failed to subscribe to promotions topic: $e');
  }

  // 5) Настройка Firebase Messaging
  // 5.1) Регистрируем фоновый хендлер
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // 5.2) Подписываемся на события, когда приложение в foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    // Обновляем скидки на лету при получении пуша
    triggerPromotionRefresh();
    await _showLocalNotification(message);
  });

  // 5.3) Когда пользователь открывает пуш из бэкграунда/килла
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
    triggerPromotionRefresh();
  });

  // 6) Определяем начальную страницу, опрашивая согласия пользователя
  final hasLegal = await ConsentService.hasAgreedLegal();
  final hasCookies = await ConsentService.hasAgreedCookies();
  Widget initialPage;
  if (!hasLegal) {
    initialPage = const WelcomeScreen();
  } else if (!hasCookies) {
    initialPage = const CookieSettingsScreen();
  } else {
    initialPage = const MainScaffold();
  }

  runApp(
    ThemeProvider(
      notifier: AppTheme(),
      child: MyApp(initialPage: initialPage),
    ),
  );
}

class MyApp extends StatefulWidget {
  final Widget initialPage;
  const MyApp({Key? key, required this.initialPage}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _supabase = Supabase.instance.client;
  // Исправлено: navigatorKey теперь глобальный для всего приложения
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    _initAppLinks();
    _listenAuthChanges();
    _listenTokenRefresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _saveFcmToken();
    });
    _checkDiscountNotifications();
  }

  void _listenAuthChanges() {
    _supabase.auth.onAuthStateChange.listen((_) {
      _saveFcmToken();
    });
  }

  void _listenTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final user = _supabase.auth.currentUser;
      debugPrint('🛰️ FCM token refreshed (guest allowed): $token');
      if (user == null) return; // не сохраняем токен для неавторизованных
      await _upsertFcmToken(token);
    });
  }

  void _initAppLinks() async {
    _appLinks = AppLinks();
    final uri = await _appLinks.getInitialAppLink();
    if (uri != null) await _handleIncomingLink(uri);
    _appLinks.uriLinkStream.listen((u) {
      // Поток не отдает null, обрабатываем напрямую
      _handleIncomingLink(u);
    });
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    final code = uri.queryParameters['code'];
    if (code != null) {
      try {
        await _supabase.auth.exchangeCodeForSession(code);
      } catch (_) {}
    }
    final at = uri.queryParameters['access_token'];
    if (at != null) {
      try {
        await _supabase.auth.setSession(at);
      } catch (_) {}
    }
    if (uri.scheme == 'citypizza' && uri.host == 'reset-password') {
      navigatorKey.currentState?.pushNamed('reset_password');
    }
  }

  Future<void> _saveFcmToken() async {
    final user = _supabase.auth.currentUser;
    // На iOS нужно дождаться APNs-токена, иначе getToken кидает apns-token-not-set
    if (Platform.isIOS) {
      // Ждём появления APNs токена с таймаутом
      String? apns;
      for (var i = 0; i < 10; i++) {
        apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (apns == null) {
        debugPrint('⚠️ APNs token is not available yet; skipping FCM getToken for now');
        return;
      }
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    // Всегда логируем токен, чтобы гость тоже мог получать пуши по топику или прямому токену
    debugPrint('🛰️ FCM token (guest allowed): $token');

    // В базу пишем только для авторизованных
    if (user != null) {
      await _upsertFcmToken(token);
      debugPrint('✅ FCM token saved on init');
    }
  }

  Future<void> _upsertFcmToken(String token) async {
    try {
      await _supabase
          .from('user_tokens')
          .upsert(
            {'user_id': _supabase.auth.currentUser!.id, 'fcm_token': token},
            onConflict: 'user_id',
          )
          .select();
      debugPrint('🛰️ Upsert FCM token: $token');
    } catch (e) {
      debugPrint('❌ Failed to upsert token: $e');
    }
  }

  Future<void> _checkDiscountNotifications() async {
    await Future.delayed(const Duration(milliseconds: 600));
    final userId = _supabase.auth.currentUser?.id;
    await checkAndNotifyDiscounts(userId);
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = ThemeProvider.of(context);
    return MaterialApp(
      navigatorKey: navigatorKey, // используем глобальный ключ
      debugShowCheckedModeBanner: false,
      title: 'City Pizza',
      theme: ThemeData(
        scaffoldBackgroundColor: appTheme.backgroundColor,
        primaryColor: appTheme.primaryColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: appTheme.primaryColor,
          brightness: appTheme.backgroundColor.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: widget.initialPage,
      routes: {
        'reset_password': (_) => const ResetPasswordScreen(),
        'tab_0': (_) => const EmailLoginScreen(),
      },
    );
  }
}

// —————— вспомогательные функции ниже ——————

Future<List<Map<String, dynamic>>> fetchApplicableDiscounts(
    String? userId) async {
  try {
    final now = DateTime.now().toIso8601String();
    final res = await Supabase.instance.client
        .from('discounts')
        .select()
        .eq('active', true)
        .lte('start_at', now)
        .order('start_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>().where((d) {
      return d['user_id'] == null || d['user_id'] == userId;
    }).toList();
  } on SocketException {
    // Нет интернета — возвращаем пустой список, чтобы не падало приложение
    return [];
  } catch (e) {
    // Любая другая ошибка — тоже возвращаем пустой список
    return [];
  }
}

Future<void> checkAndNotifyDiscounts(String? userId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final shownIds = prefs.getStringList('shown_discount_ids') ?? [];
    final discounts = await fetchApplicableDiscounts(userId);
    for (final d in discounts) {
      final id = d['id'].toString();
      if (!shownIds.contains(id)) {
        // Удалено: showDiscountNotification и любые локальные уведомления
        shownIds.add(id);
      }
    }
    await prefs.setStringList('shown_discount_ids', shownIds);
  } on SocketException {
    // Нет интернета — просто не показываем уведомления
    return;
  } catch (e) {
    // Любая другая ошибка — игнорируем
    return;
  }
}

// Проверка на бесконечные циклы, тяжелые операции и неправильную работу с потоками/плагинами:

// 1. Нет бесконечных циклов: 
// В main.dart нет ни одного while(true), for(;;) или рекурсивных вызовов без выхода.

// 2. Нет тяжелых синхронных операций в main isolate:
// Все тяжелые операции (инициализация Firebase, Supabase, SharedPreferences, CartService, локальные уведомления) выполняются асинхронно через await.
// Нет больших циклов или синхронных вычислений в build или initState.

// 3. Нет неправильной работы с потоками/плагинами:
// Все слушатели (FirebaseMessaging, AppLinks) корректно подписываются и не вызывают тяжелых операций в своих колбэках.
// Нет ручного создания Isolate или работы с потоками.
// Все обращения к SharedPreferences, Supabase, Firebase — асинхронные.

// 4. Нет повторяющихся setState или бесконечных вызовов setState в цикле.

// 5. Нет бесконечных Future.delayed или Timer.periodic без контроля.

// 6. Нет бесконечных вызовов Navigator или других навигационных ловушек.

// 7. Нет тяжелых операций в build-методах — только стандартный MaterialApp и роутинг.
