# Tech Stack — City Pizza (project overview)

Это человекочитаемое описание технологического стека проекта `citypizza_new`.

---

## Основные технологии

- Язык приложения: Dart (Flutter framework)
  - Flutter SDK: проект требует Flutter >= 3.16.0 (см. `pubspec.yaml`)
  - Dart SDK: совместимость `>=3.0.0 <4.0.0`

- Платформы
  - Android (Android App Bundle / APK)
  - iOS (App Store)
  - Web: проект содержит web-папку, но основной фокус — мобильные платформы

## Ключевые зависимости (Flutter / pubspec)
(берутся из `pubspec.yaml` — основное, релевантное для сборки и функционала)

- firebase_core — инициализация Firebase
- firebase_messaging — push-уведомления (FCM)
- flutter_local_notifications — локальные нотификации (foreground banners)
- supabase_flutter — бэкенд (аутентификация, БД и функции)
- shared_preferences — локальное хранение простых настроек
- google_fonts — кастомные шрифты
- http — HTTP-клиент
- geolocator / geocoding — геолокация и обратное геокодирование
- url_launcher — открытие внешних ссылок (карты, email, телефон)
- video_player, lottie — медиакомпоненты / анимации
- intl — форматирование дат/чисел

Dev / tooling:
- flutter_test, flutter_lints, flutter_launcher_icons

(Полный список — см. `pubspec.yaml`.)

## Нативные настройки и сборка

Android:
- Gradle Kotlin DSL: `build.gradle.kts` находится в `android/` и `android/app/`.
- Kotlin + Android Gradle Plugin используются (плагин `kotlin-android`).
- Java compatibility: `sourceCompatibility` и `targetCompatibility` = Java 11.
- minSdkVersion: 21 (в `android/app/build.gradle.kts`).
- compileSdk / targetSdk берутся из Flutter (`flutter.compileSdkVersion`, `flutter.targetSdkVersion`).
- Подписание: `android/keystore.properties` (не коммитить), `android/app/release.keystore` — upload key.
- Команды сборки:
  - Debug APK: `flutter build apk --debug` (обычно `flutter run` для dev)
  - Release App Bundle: `flutter build appbundle --release` (файл: `build/app/outputs/bundle/release/app-release.aab`)
  - Release APK: `flutter build apk --release`

iOS:
- Podfile: iOS deployment target 12.0 (см. `ios/Podfile`).
- Требуется Xcode + CocoaPods.
- Команды сборки и архивации: `flutter build ipa` или собрать через Xcode для App Store.

## Бэкенд / интеграции

- Supabase (Postgres + Auth + Functions): используется для авторизации, хранения пользовательских данных и вызова функций (например, `delete_user` Edge Function).
  - `supabase_flutter` клиент и вызовы функций через `Supabase.instance.client.functions.invoke`.
- Firebase
  - Firebase Core + Firebase Messaging используются для пушей и APNs
  - Firebase iOS: `firebase_options.dart` сгенерирован (см. `lib/firebase_options.dart`) — файл содержит настройки проекта Firebase.
- Push: FCM topics (`promotions`) и token management (`user_tokens` в Supabase).
- Уведомления: для foreground — `flutter_local_notifications` + FCM handling (в `lib/main.dart`).

## Политика безопасности / хранение данных

- Все сетевые запросы идут по HTTPS (TLS).
- Токены FCM и сессии Supabase хранятся локально (`shared_preferences` или плагин Supabase).
- Keystore (`.jks`) хранится локально и не коммитится (в `.gitignore` добавлено правило для `android/keystore.properties` и `*.jks`).

## Архитектура приложения (коротко)

- UI: Flutter widgets, экраны находятся в `lib/screens/`.
- Services: `lib/services/` содержит авторизацию, работу с корзиной, скидками и т.д.
- Widgets: переиспользуемые виджеты в `lib/widgets/`.
- Главный вход: `lib/main.dart` — инициализация Firebase, Supabase, push-логики и роутинга.

## Полезные скрипты / команды (для разработчика)

- Установить зависимости:
```bash
flutter pub get
```
- Запустить на устройстве (debug):
```bash
flutter run
```
- Сборка релизного AAB (для загрузки в Play Console):
```bash
flutter clean
flutter pub get
flutter build appbundle --release
# итог: build/app/outputs/bundle/release/app-release.aab
```
- Сборка релизного iOS пакета: (потребуется Xcode и профиль подписи)
```bash
flutter build ipa --release
```

## Где искать важные файлы в проекте

- `pubspec.yaml` — зависимости
- `lib/main.dart` — init Firebase/FirebaseMessaging, Supabase и flow
- `android/app/build.gradle.kts` — android конфиг и подпись
- `android/keystore.properties` и `android/app/release.keystore` — релизный ключ (локально)
- `ios/Podfile` — iOS pods
- `build/app/outputs/bundle/release/app-release.aab` — собранный App Bundle

## Замечания и рекомендации

- Плагин `flutter_local_notifications` был временно откорректирован в локальном pub cache для устранения ошибки компиляции, поэтому при `flutter pub upgrade`/`flutter pub get` на другой машине необходимо убедиться, что версия плагина совместима с используемой версией Android SDK/AGP или применить аналогичный патч/override.
- Храните `release.keystore` и `keystore.properties` в защищённом месте и не пушьте в репозиторий.
- Для CI можно настроить GitHub Actions/Bitrise, где `release.keystore` подаётся как секрет и записывается в `android/app/release.keystore` перед сборкой.

---

Если хочешь, я дополню этот файл примерами `gradle.properties`/`keystore.properties` шаблоном, или добавлю секцию с рекомендуемыми версиями Android SDK/Flutter в CI (например, конкретная версия Flutter stable).