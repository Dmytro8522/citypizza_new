# App Store Submission Cheatsheet (City Pizza)

## App Metadata
- **App Name:** City Pizza
- **Subtitle (optional):** Bestelle Pizza & mehr
- **Promotional Text (optional):** Schnelle Lieferung, frische Zutaten, einfache Bestellung.
- **Keywords:** pizza, lieferung, essen, city pizza, burger, pasta, suppe, salat
- **Support URL:** https://dmytro8522.github.io/citypizza-legal/support.html
- **Marketing URL (optional):** https://dmytro8522.github.io/citypizza-legal/
- **Privacy Policy URL:** https://dmytro8522.github.io/citypizza-legal/privacy.html
- **Copyright:** © 2025 City Pizza
- **Primary Category:** Food & Drink
- **Secondary Category (optional):** Lifestyle

## Long Description (DE)
"City Pizza" macht die Bestellung einfach: Menü ansehen, gewünschte Größe wählen, Extras hinzufügen und sicher zur gewünschten Adresse bestellen. Push-Benachrichtigungen informieren über Status und Aktionen. Standort hilft, deine Lieferzone schneller zu erkennen. Keine In-App-Zahlungen, Bestellung wird direkt im Restaurant abgewickelt.

## What’s New (für nächste Version)
- Push-Aktionen aus dem neuen Promotions-Modul
- Stabilitäts- und Performance-Verbesserungen

## App Privacy (Nutrition Label)
- **Daten verknüpft mit dem Nutzer:** Kontaktinfo (Name, E-Mail, Telefon, Adresse), Standort (genau/ungefähr), Kennungen (Geräte-/Push-Token), Nutzungsdaten (Interaktionen), Bestellinformationen.
- **Zwecke:** App-Funktionalität (Bestellung, Zustellung, Benachrichtigungen), Basis-Analytics, Personalisierung von Angeboten (eigene Promotions). Keine Drittanbieter-Werbung, kein Tracking über Apps/Websites.
- **Nicht erhoben:** Finanzdaten (keine In-App-Payments), Fotos/Medien, Gesundheit/Fitness, Kontakte, Kalender, Nachrichten, Browserverlauf, Dateien.

## Encryption / Export Compliance
- **Verwendet nur Standardverschlüsselung des OS und HTTPS (Firebase/Supabase).**
- In App Store Connect bei Export Compliance: „Nи один из вышеперечисленных алгоритмов“ / Standard OS crypto only, keine eigenen Algorithmen.

## Push / Permissions Texte (DE)
- **Ortungsdienste:** „Um Ihren Standort für Lieferungen zu bestimmen.“
- **Tracking:** „Wir nutzen Daten, um die App zu verbessern und Angebote zu personalisieren.“

## Interne Tests (Empfohlen über TestFlight)
- Prüfen: Login/Signup (E-Mail), Push-Empfang (topic promotions), Anzeige neuer Aktionen nach Push, Bestellung/Cart-Flows, Location-Prompt.

## Release-Checkliste (kurz)
1) Build number erhöhen (pubspec.yaml `+N`).
2) Archive in Xcode (Release, Apple Distribution, richtiger Provisioning Profile).
3) Upload via Organizer → App Store Connect.
4) In App Store Connect: warten „Ready to Test“, optional TestFlight intern testen.
5) App Privacy aus obigen Punkten, Screenshots, Beschreibung, Keywords, Support/Privacy-URLs.
6) Export Compliance: nur Standard-OS-Verschlüsselung.
7) Version auswählen → Submit for Review.

## Support (für Store-Formulare)
- E-Mail: do84arov@gmail.com
- Telefon: +49 162 4514836
- Adresse: Härtelstraße 7, 04420 Leipzig
- Support-Seite: https://dmytro8522.github.io/citypizza-legal/support.html

> Hinweis: Falls später Payments oder Ads hinzukommen, App Privacy aktualisieren.
