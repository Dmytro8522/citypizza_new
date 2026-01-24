# Архитектура приложения City Pizza

Этот документ описывает архитектуру мобильного приложения City Pizza: основные слои, модули и потоки данных.

## 1. Общий обзор

Приложение City Pizza построено на Flutter и использует:
- **Supabase** как основное backend‑API (меню, категории, заказы, промо, профиль);
- **Firebase** (Firebase Core, Firebase Messaging) для push‑уведомлений;
- **SharedPreferences** для локального кэша меню и настроек пользователя;
- **Geolocator/Geocoding** для определения адреса доставки и работы с зонами.

Основные пользовательские сценарии:
- первый запуск и прием юридических условий/политики;
- выбор и настройка cookies;
- просмотр главной страницы с промо и рекомендациями;
- просмотр меню, поиск по блюдам, просмотр бандлов;
- работа с корзиной и оформление заказа;
- отслеживание статуса текущего заказа и история заказов;
- работа с профилем пользователя (гость / авторизованный пользователь Supabase).

## 2. Слои приложения

### 2.1. Презентационный слой (UI)

Находится в `lib/screens/` и `lib/widgets/`.

Ключевые компоненты:
- `WelcomeScreen` (`lib/screens/welcome_screen.dart`) — анимированный онбординг с видео и юридическими текстами;
- `CookieSettingsScreen` (`lib/screens/cookie_settings_screen.dart`) — управление согласием на cookies и переход в основной каркас;
- `MainScaffold` (`lib/widgets/main_scaffold.dart`) — каркас с нижней навигацией (табы Home / Menü / Profil) и внутренним `Navigator`;
- `HomeScreen` (`lib/screens/home_screen.dart`) — главная вкладка с промо‑секциями, рекомендациями, текущим заказом и поиском;
- `MenuScreen` (`lib/screens/menu_screen.dart`) — просмотр категорий и блюд с Supabase, поиск, отображение промо‑цен;
- `MenuItemDetailScreen`, `BundleDetailScreen` — экраны деталей блюда/набора с добавлением в корзину;
- `CartScreen`, `CheckoutScreen`, `OrderStatusScreen`, `OrderHistoryScreen` — корзина, оформление заказа, статус и история;
- `ProfileScreen`, `ProfileScreenAuth` — профиль неавторизованного / авторизованного пользователя;
- вспомогательные виджеты (`lib/widgets/`): `BottomNav`, `WorkingHoursBanner`, `CreativeCtaSection`, различные карусели и плитки.

Темизация и общие стили:
- `lib/theme/app_theme.dart` — описание цветовой палитры, стилей и размеров;
- `lib/theme/theme_provider.dart` — доступ к теме через InheritedWidget/провайдер;
- шрифты и оформление — через `google_fonts` и кастомные цвета.

### 2.2. Сервисный/доменный слой

Находится в `lib/services/` и частично в `lib/models/`.

Основные сервисы:
- `cart_service.dart` — модель корзины, хранение позиций, подсчёт суммы и количества, `ValueNotifier`/`ChangeNotifier` для обновления UI;
- `order_service.dart` — создание, загрузка и обновление заказов в Supabase, получение истории заказов;
- `discount_service.dart`, `promotion_service.dart`, `upsell_service.dart` — работа с промо‑акциями, расчетом скидок и предложениями upsell;
- `delivery_zone_service.dart` — логика зон доставки (проверка адреса, доступность доставки, интеграция с геолокацией);
- `app_config_service.dart` — загрузка конфигурации приложения (например, рабочие часы, тексты баннеров, глобальные настройки);
- `consent_service.dart` — хранение и проверка согласий (юридические тексты, cookies);
- `auth_service.dart` — вспомогательные операции вокруг Supabase Auth (логин/логаут, состояние пользователя);
- `delivery_mode_prompt.dart` — сценарий выбора режима/зоны доставки и взаимодействие с UI.

Модели:
- `lib/models/menu_item.dart` — описание сущности блюда/набора (ценовые поля, промо‑информация, связи с категориями и бандлами);
- дополнительные модели (история заказов, статусы, промо и т.д.) определены внутри соответствующих экранов и сервисов.

Утилиты:
- `lib/utils/globals.dart` — глобальный `navigatorKey` и другие общие вспомогательные сущности;
- `lib/utils/working_hours.dart` — структуры и функции для расчёта и отображения рабочих часов (используется в `WorkingHoursBanner`);
- `lib/utils/address_localization.dart` — вспомогательные функции для работы с адресами/локализацией.

### 2.3. Инфраструктурный слой

- `lib/firebase_options.dart` — сгенерированная конфигурация Firebase для разных платформ;
- инициализация Firebase, Supabase и push‑уведомлений — в `lib/main.dart`;
- deep links / app links настроены через AndroidManifest и Info.plist (см. каталоги `android/` и `ios/`).

В `main.dart` выполняется:
- инициализация Firebase (`Firebase.initializeApp`);
- инициализация Supabase (`Supabase.initialize`);
- настройка Firebase Messaging (фоновые и foreground‑обработчики, локальные нотификации через `flutter_local_notifications`);
- выбор стартового экрана на основе согласий (`ConsentService`): `WelcomeScreen` → `CookieSettingsScreen` → `MainScaffold`.

## 3. Навигация и роутинг

Навигация реализована через:
- корневой `MaterialApp` с глобальным `navigatorKey` (см. `utils/globals.dart`);
- внутренний `Navigator` внутри `MainScaffold`, который обрабатывает:
  - табовые маршруты `tab_0`, `tab_1`, `tab_2` без анимации;
  - обычные маршруты `/cart`, `/detail`, `/checkout`, `/history`, `/login`, `/signup`, `/discounts` и др.

Для внешних ссылок используются deep‑links (`citypizza://`, `com.citypizza.app://`), настроенные в Android и iOS. Их обработка реализована через пакет `app_links` и обработчики в `main.dart`/сервисах.

## 4. Потоки данных

### 4.1. Меню и промо

1. UI‑экран (например, `HomeScreen` или `MenuScreen`) запрашивает данные через Supabase‑клиент.
2. Результаты кэшируются в `SharedPreferences` (для быстрого старта и оффлайн‑поддержки).
3. Дополнительная логика по промо и upsell реализована в `discount_service.dart`, `promotion_service.dart`, `upsell_service.dart`.
4. UI наблюдает за состоянием через локальное состояние виджетов или нотификаторы сервисов.

### 4.2. Корзина и заказы

1. Добавление/удаление позиций происходит через методы `CartService`.
2. Сервис хранит текущее состояние и уведомляет UI при изменениях.
3. При оформлении заказа `OrderService` отправляет данные в Supabase и получает идентификатор заказа/статус.
4. Статус текущего заказа и история подтягиваются из Supabase и отображаются на соответствующих экранах.

### 4.3. Согласия и юридические требования

1. При первом запуске пользователь видит `WelcomeScreen` с AGB & Datenschutzerklärung.
2. После принятия показывается `CookieSettingsScreen` для выбора cookie‑настроек.
3. `ConsentService` сохраняет флаги в локальном хранилище и влияет на стартовый экран при следующих запусках.

### 4.4. Push‑уведомления

1. Firebase Messaging получает токен и передаёт его backend’у (через Supabase/сервисы).
2. При получении push‑уведомления:
   - в фоне/при убитом приложении — обработчик `_firebaseMessagingBackgroundHandler`;
   - в foreground — локальные нотификации через `flutter_local_notifications`.
3. При открытии пуша приложение может обновлять промо‑данные и/или переходить к релевантному экрану (например, статус заказа).

## 5. Сборка и конфигурация

Подробные шаги по релизу описаны в:
- `PLAY_RELEASE.md` — чек‑лист для Google Play;
- `docs/store_release_checklist.md` — общий чек‑лист по сторам.

Ключевые моменты:
- Android:
  - `applicationId`/`namespace`: `com.citypizza.order`;
  - релизный keystore: `android/app/release.keystore`, параметры — в `android/keystore.properties`;
  - сборка AAB: `flutter build appbundle --release`;
  - deep links описаны в `android/app/src/main/AndroidManifest.xml`.
- iOS:
  - bundle id: `com.citypizza.order`;
  - URL‑схемы и пуш‑настройки в `ios/Runner` и `GoogleService-Info.plist`;
  - сборка: через Xcode Archive или `flutter build ipa --release`.

## 6. Как расширять проект

Рекомендуемый подход к добавлению новых возможностей:
- **Новый экран** — создать файл в `lib/screens/`, вынести повторно используемые части в `lib/widgets/`;
- **Новая бизнес‑логика** — добавить сервис в `lib/services/` и экспонировать только необходимые методы наружу;
- **Новые модели** — разместить в `lib/models/` и использовать типы во всех слоях, избегая `dynamic`/`Map` в UI;
- **Навигация** — регистрировать новые маршруты в `MainScaffold` (внутреннем Navigator’е) и использовать `navigatorKey` при необходимости глобальных переходов.

Такой подход помогает держать UI, бизнес‑логику и инфраструктуру достаточно изолированными и облегчает поддержку проекта.
