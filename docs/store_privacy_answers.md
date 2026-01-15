# Store Privacy Answers (Draft)

Use this as a crib sheet for Play Data Safety and App Store Privacy.

## Data collected (yes unless stated otherwise)
- **Location:** Precise + Approximate (for delivery/address lookup).
- **Personal info:** Name, Email, Phone, Delivery address (street/house/city/postal code).
- **App activity:** App interactions (basic events/screens for stability/UX).
- **Device or other IDs:** Push token (FCM/APNs) for order/status notifications.
- **Other:** Order details (items, timestamps, store/branch).
- **Not collected:** Financial info (no in-app payments), Photos/Media, Health/Fitness, Messages, Contacts, Calendar, Files, Web browsing.

## Data sharing / selling
- **No data sold.**
- **Sharing:** Only to processors: Firebase (Messaging/Analytics-lite), Supabase (backend DB). No third-party advertising networks.

## Security and deletion
- Data encrypted in transit (HTTPS). At rest per Firebase/Supabase defaults.
- Account/data deletion: via support request (email). Order/history may be retained to comply with legal retention.

## Retention (declare in forms)
- Order & delivery data: 3 years (Verjährung). If invoices generated: 10 years.
- Push token: up to 12 months after last activity or revocation.
- Logs/metrics: 30–90 days.

## Permissions rationale
- Location: to suggest/validate delivery address and service area.
- Notifications: to send order status updates; marketing only with consent.

## Google Play Data Safety (suggested answers)
- **Collected:** Location (precise/approx), Personal info (name/email/phone/address), App activity (interactions), Device IDs (push token), Order info.
- **Shared:** No (only processors). Mark “not shared” if processors under your control; otherwise list Firebase/Supabase as service providers.
- **Purpose:** App functionality, Account management, Messages (service), Analytics (basic), Fraud prevention (if applicable).
- **Data security:** Data encrypted in transit = Yes.
- **Data deletion request:** Yes, via support email.
- **Optional flags:** No data sold; No independent tracking; Children’s app? (likely No).

## App Store Privacy (Nutrition Label)
- **Data Linked to User:** Yes (contact info, location, identifiers, usage, orders).
- **Used for:** App functionality; Analytics (basic); Product personalization if used; Not for third-party advertising.
- **Categories to check:**
  - Contact Info: Name, Email, Phone, Address (for fulfillment/support).
  - Location: Precise/Approximate.
  - Identifiers: Device ID / Push token.
  - Usage Data: Product Interaction.
  - Purchases/Financial: No (unless you add payments).
  - Sensitive data categories (Health, Fitness, Contacts, etc.): No.
- **Tracking across apps/sites:** No (if not using third-party ads/trackers or ATT frameworks). If you only use Firebase Messaging/Analytics without ad-id, mark tracking = No.

## Support contact for deletion/requests
- Email: do84arov@gmail.com
- Phone: +49 162 4514836
- Address: Härtelstraße 7, 04420 Leipzig
- Support page: https://dmytro8522.github.io/citypizza-legal/support.html

Adjust if you add payments, ads, or additional analytics later.
