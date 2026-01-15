# Google Play релиз — чек‑лист

## 1. Версия
- Обновить `pubspec.yaml` `version: x.y.z+code` (code > предыдущего). Уже выставлено: `1.0.1+4`.

## 2. Подпись
- Если нет ключа: 
  - `keytool -genkey -v -keystore ~/keys/citypizza.jks -keyalg RSA -keysize 2048 -validity 10000 -alias citypizza`
- Скопировать `android/keystore.template.properties` → `android/keystore.properties` и заполнить пути/пароли.
- Файл `keystore.properties` и *.jks не коммитить (уже в .gitignore).

## 3. Сборка релизного bundle
```bash
flutter clean
flutter pub get
flutter build appbundle --release
```
Результат: `build/app/outputs/bundle/release/app-release.aab`.

Для локального теста APK: `flutter build apk --release`.

## 4. Быстрая проверка
- `flutter analyze`
- Установить релизный APK на устройство, smoke-тест: запуск, авторизация/гость, корзина → заказ, пуш.
- Убедиться, что пуши идут с каналом `promos_high` и `sound=default` в payload.

## 5. Play Console (вручную)
- Store listing: название, краткое/полное описание, иконка 512×512, скриншоты (телефон), контактный email, категория.
- Content Rating: пройти опрос.
- Data Safety: указать сбор FCM токена, аккаунта (email/user id), геоданные если запрашиваются; без сторонней рекламы — отметить «нет», если не используете.
- Permissions: INTERNET, FCM; Location — только если используете; без лишних.
- App Integrity: включить Play App Signing (рекомендуется) либо загрузить свой ключ (первый аплоад).
- Release: загрузить `.aab`, release notes, выбрать трек (Internal/Production) → Submit.

## 6. Тестовые треки
- Сначала Internal testing: пригласить тестеров, проверить установку из Play и пуши.
- Затем Production.

## 7. Полезно
- `google-services.json` должен быть корректным для prod (лежит в `android/app/`).
- targetSdk / compileSdk подтягивается из Flutter; при обновлении Flutter проверь, что targetSdk соответствует требованиям Play.
