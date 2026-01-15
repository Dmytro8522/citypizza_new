# Store Release Checklist (City Pizza)

## Project snapshot
- Flutter 3.16, version 1.0.0+1.
- Android: applicationId/namespace `com.citypizza.order`, release keystore настроен, AAB собран; deep links: `citypizza://`, `com.citypizza.app://`.
- iOS: bundle id `com.citypizza.order`, team `AVS3L48N66`, URL schemes `citypizza`, `com.citypizza.app`; App Store Connect app создан (в подготовке).
- Внешние страницы (DE) на GitHub Pages: Privacy/Terms/Support `https://dmytro8522.github.io/citypizza-legal/`.

## Priority order (remaining)
1) Store privacy forms: Play Data Safety + App Store Privacy (данные: локация, push-token, заказ/контактные данные, Supabase/Firebase).
2) App metadata/assets: названия/описания, скриншоты, 1024x1024 иконка, категории, контакты.
3) iOS signing/provisioning: Apple Distribution/Automatic, сертификат/profiles под `com.citypizza.order`, Archive/TestFlight.
4) Build & smoke-test: release IPA + актуальный AAB; проверить deeplinks, локацию, пуши, основные флоу на девайсах.
5) Submission: загрузка в Play (internal/closed → prod) и App Store (TestFlight → Review).

## Required before publish (both stores)
- Bump `pubspec.yaml` version (X.Y.Z+build) for каждый релиз.
- Финальные иконки/launch screen (`flutter_launcher_icons`).
- Secrets не в git; env/CI vars.

## Android (Google Play)
- Release keystore настроен; при новых сборках держать `keystore.properties` локально.
- Optional: `minifyEnabled`/`shrinkResources`, ProGuard правила для Firebase/Messaging.
- Build & test: `flutter build appbundle --release` (готово), `flutter build apk --release` при необходимости.
- Manifest permissions: INTERNET, LOCATION, POST_NOTIFICATIONS — описать в Play Data Safety/permissions.
- Тест deep links `citypizza://` и `com.citypizza.app://` на устройстве.

## iOS (App Store)
- Bundle id финальный `com.citypizza.order`; требуется provisioning/сертификат Apple Distribution.
- Final App Icons/LaunchScreen в Assets.
- Проверить `NSLocation*`, `NSUserTrackingUsageDescription` тексты; при необходимости локализация.
- Build & test: `flutter build ipa --release` или Xcode Archive; TestFlight на устройстве.

## Content, policies, support
- Внешние страницы готовы (DE): Privacy/Terms/Support на GitHub Pages.
- Обновить стор-листинги ссылками и контактами (email/телефон/адрес).
/** If app texts need update, adjust in-app legal content accordingly. */

## Store assets & metadata
- Name, subtitle, short/full description, keywords (iOS), categories.
- Screenshots (phone; iPad for iOS), localized if needed. 1024x1024 icon w/o alpha. Optional feature graphic (Play) and preview video.
- Developer/Support contact email for both stores.

## Compliance
- Play Data Safety: declare location, notifications, analytics/logs, Firebase/Supabase usage, data retention/deletion. Note if account/data deletion is absent.
- App Store Privacy: same data categories, purposes, linked vs not linked to user/device.
- Permission justification: Location (delivery), Notifications (order status), Background fetch/remote-notification (push).
- If using tracking/ads, handle ATT; if only analytics, note appropriately.

## Functional validation
- Auth flows, ordering, payments (if any), push notifications, deep links, location, localization/currency.
- Offline/poor network handling, error messages.
- Test minSdk 21+ Android, iOS 12+.
- Remove debug banners/logs; no test payment endpoints in release.

## Build commands (reference)
```bash
flutter clean
flutter pub get
flutter build appbundle --release
flutter build ipa --release
```

## Must-fix before submitting
- Заполнить Play Data Safety и App Store Privacy.
- Подготовить стор-метаданные/ассеты и добавить ссылки на Privacy/Terms/Support.
- Собрать IPA (и актуальный AAB при изменениях версии) + смоук-тест на устройствах.
- Обновить `pubspec.yaml` версии перед сабмитом.
