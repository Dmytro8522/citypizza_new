## City Pizza — мобильное приложение доставки

City Pizza — Flutter‑приложение для заказа пиццы и блюд доставки (в т.ч. для немецкого рынка).
Клиентское приложение подключено к Supabase (меню, заказы, акции) и Firebase (push‑уведомления).

Основные возможности:
- онбординг с видео и юридическими текстами (AGB & Datenschutzerklärung);
- экран настроек cookies и согласий (ConsentService);
- главная вкладка с промо‑секциями, рекомендациями и текущим заказом;
- экран меню с категориями, поиском, бандлами и промо‑ценами;
- корзина, чекаут, трекинг статуса заказа;
- профиль гостя/авторизованного пользователя (Supabase auth);
- push‑уведомления по статусу заказа и акциям;
- Deep Links / App Links для открытия приложения из внешних ссылок.

Подробнее о релизе и сторах см.:
- [docs/store_release_checklist.md](docs/store_release_checklist.md)
- [PLAY_RELEASE.md](PLAY_RELEASE.md)

---

## Технологический стек

- **Flutter** (Dart, Material Design);
- **Supabase** (Postgres, Auth, RPC) — меню, заказы, промо;
- **Firebase** (Firebase Core, Firebase Messaging) — пуши;
- **SharedPreferences** — локальный кэш меню и настроек;
- **Geolocator / Geocoding** — определение адреса доставки и зон;
- **App Links** — deep‑links `citypizza://` и `com.citypizza.app://`;
- **Video Player, Google Fonts** — онбординг и стилизованный UI.

---

## Структура проекта

Корень:
- `lib/main.dart` — входная точка приложения, инициализация Firebase, Supabase, push‑логики и выбор стартового экрана (welcome / cookie settings / MainScaffold);
- `lib/widgets/main_scaffold.dart` — нижняя навигация (Home / Menü / Profil), внутренний `Navigator` и маршруты (`/cart`, `/checkout`, `/history`, `/login`, `/signup`, и т.д.);
- `lib/constants/` — константы и юридические тексты (например, `legal_texts.dart`);
- `lib/models/menu_item.dart` — доменная модель для пунктов меню и бандлов;
- `lib/screens/` — экраны приложения (welcome, cookie settings, home, menu, детали, профиль, корзина и др.);
- `lib/services/` — бизнес‑логика (корзина, скидки, зоны доставки, заказы, согласия и т.п.);
- `lib/widgets/` — переиспользуемые виджеты (AppBar, баннеры, карусели, плитки результатов поиска и т.д.);
- `lib/theme/` — тема приложения (`app_theme.dart`, `theme_provider.dart`);
- `lib/utils/` — утилиты (`globals.dart` с `navigatorKey`, расчёт рабочих часов и т.п.);
- `assets/` — логотип, иконки, Lottie/JSON, видео онбординга;
- `android/`, `ios/`, `macos/`, `web/`, `windows/`, `linux/` — платформенные части Flutter.

Ключевые экраны (`lib/screens`):
- `welcome_screen.dart` — видео‑онбординг, показ AGB & Datenschutzerklärung, переход к настройкам cookies или в приложение;
- `cookie_settings_screen.dart` — управление согласием на cookies и переход в основной каркас (`MainScaffold`);
- `home_screen.dart` — главная вкладка: промо‑блоки, недавние заказы, подборки, поиск по меню;
- `menu_screen.dart` — список категорий и блюд из Supabase с поиском, промо‑ценами и переходом в детали;
- `menu_item_detail_screen.dart`, `bundle_detail_screen.dart` — экраны деталей блюда/набора с добавлением в корзину;
- `cart_screen.dart`, `checkout_screen.dart`, `order_status_screen.dart`, `order_history_screen.dart` — корзина, оформление, статус и история заказов;
- `profile_screen.dart`, `profile_screen_auth.dart` — профиль гостя/авторизованного пользователя (Supabase auth);
- `discounts_screen.dart` и различные секции‑карусели (top items, bundles, recent orders).

Сервисы (`lib/services`):
- `cart_service.dart` — состояние корзины, подсчёт сумм и количества, нотификатор для UI;
- `discount_service.dart`, `promotion_service.dart`, `upsell_service.dart` — промо‑логика, акции и upsell‑предложения;
- `order_service.dart` — работа с заказами (создание/загрузка, статус, история);
- `delivery_zone_service.dart`, `app_config_service.dart` — зоны доставки, конфигурация приложения;
- `consent_service.dart` — согласия на юридические тексты и cookies;
- `auth_service.dart` — вспомогательная логика вокруг Supabase Auth;
- `delivery_mode_prompt.dart` — сценарий выбора режима/зоны доставки.

Утилиты и тема:
- `utils/globals.dart` — глобальный `navigatorKey` и прочие вспомогательные сущности;
- `utils/working_hours.dart` — расчёт и отображение рабочих часов (баннер внизу);
- `theme/app_theme.dart`, `theme/theme_provider.dart` — цвета, шрифты, доступ к теме через InheritedWidget.

---

## Локальный запуск

1. Установить Flutter (совместимую версию, см. `environment.flutter` в `pubspec.yaml`).
2. Установить зависимости:
	 ```bash
	 flutter pub get
	 ```
3. Запустить на устройстве/эмуляторе (Android/iOS):
	 ```bash
	 flutter run
	 ```

Firebase и Supabase уже сконфигурированы через `lib/firebase_options.dart` и сервисы в `lib/services/`. Для полноценной работы требуется доступ к соответствующим backend‑проектам.

---

## Сборка и релиз

Android:
- релизный App Bundle:
	```bash
	flutter build appbundle --release
	```
- keystore и подпись настроены через `android/keystore.properties` и `android/app/build.gradle.kts`;
- подробный чек‑лист для Google Play: [PLAY_RELEASE.md](PLAY_RELEASE.md).

iOS (кратко):
- архив/IPA через Xcode или:
	```bash
	flutter build ipa --release
	```
- детали по App Store см. в [docs/app_store_submission.md](docs/app_store_submission.md).

Общий чек‑лист по сторам: [docs/store_release_checklist.md](docs/store_release_checklist.md).

---

## Полезные ссылки

- Репозиторий: https://github.com/Dmytro8522/citypizza_new
- Страницы политики/условий (DE): https://dmytro8522.github.io/citypizza-legal/

