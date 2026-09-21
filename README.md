# FluTour — 3-App Flutter Platform
**Luxor, Egypt · Felucca & Hantour Ride-Hailing**

A complete ride-hailing platform for Luxor's iconic tourist vehicles — Felucca boats and Hantour horse carriages — built with Flutter + Firebase.

---

## Apps

| Folder | App | Description |
|--------|-----|-------------|
| `flu_tour_passenger/` | Passenger App | Book rides, track driver, rate trips |
| `flu_tour_driver/` | Driver App | Accept trips, GPS broadcast, earnings |
| `flu_tour_admin/` | Admin Panel | Driver approval, live map, trip dashboard |

---

## Tech Stack

- **Flutter** 3.x (Android + iOS)
- **Firebase** — Auth, Firestore, Realtime Database, FCM, Storage
- **flutter_map** + MapTiler Streets tiles
- **Geolocator** — GPS & background location services
- **flutter_localizations** — Full Arabic / English (RTL support)

## Firebase Project

Project ID: `flutour-dev`
Firestore rules: `firestore.rules`
Storage rules: `storage.rules`
Cloud Functions: `functions/`

---

## Progress — September 2026

| Feature | Status |
|---------|--------|
| All UI screens (25 total) | ✅ Complete |
| Firebase Auth (all 3 apps) | ✅ Complete |
| Firestore E2E booking flow | ✅ Live |
| Realtime DB GPS broadcast | ✅ Live |
| FCM push notifications | ✅ Wired (client-side) |
| Driver online/offline toggle | ✅ Live |
| Admin approve/reject drivers | ✅ Live |
| Arabic / English localization (RTL) | ✅ Complete |
| App icons (Android + iOS) | ✅ Updated |
| iOS background location entitlements | ✅ Configured |
| Route service (polyline navigation) | ✅ Added |
| Firebase Storage rules | ✅ Deployed |
| Geocoding search (worldwide Nominatim) | ✅ Complete |
| Audio notifications (trip requests & offers) | ✅ Complete |
| Live driver GPS tracking during ride | ✅ Fixed |
| Login persistence (no re-login on relaunch) | ✅ Fixed |
| Passenger count selection at booking | ✅ Complete |
| Felucca fare tiers (250 / 350 / 650 EGP) | ✅ Updated |
| 20% FluTour commission per trip | ✅ Applied |
| Sign in with Apple (iOS + Android) | ✅ Complete |
| Account deletion (GDPR / App Store compliant) | ✅ Complete |
| Bell/chime notification sounds | ✅ Updated |
| Driver splash screen always English | ✅ Fixed |
| Cloud Functions (earnings / notifications) | 🔧 In Progress |
| Payment gateway (Vodafone Cash / InstaPay) | 🔧 In Progress |
| Google Play Store | ✅ Live |
| Apple App Store | ⚠️ Pending Resubmission |
| Declined trip persistence across restarts | ✅ Fixed |
| Google sign-in button with official G logo | ✅ Fixed |

**Overall progress: ~97%**

---

## Store Status

| Store | App | Status | Notes |
|-------|-----|--------|-------|
| Google Play | FluTour — Book a Ride | ✅ Live | Active — v1.0.2 (Sep 21, 2026) |
| Google Play | FluTour Driver | ✅ Live | Active — v1.0.2 (Sep 21, 2026) |
| Apple App Store | FluTour | ⚠️ Pending | App Store IPA ready; awaiting account conversion |
| Apple App Store | FluTour Driver | ⚠️ Pending | App Store IPA ready; awaiting account conversion |

> **Apple rejection fixes applied:** Sign in with Apple (4.8), account deletion (5.1.1v), notification sounds, auth persistence — all code complete in v1.0.2.
> **Pending:** Apple Developer account conversion Individual → Organization (contacted Apple support Sep 21, 2026 — awaiting response).
> Review times: Google Play 1–3 days · Apple App Store 1–7 days

---

## Getting Started

### Passenger App
1. Open the app and tap **Create Account** (إنشاء حساب)
2. Enter your phone number and set a password
3. Book rides immediately — no approval needed
4. Switch language from the Profile tab (English / Arabic)

### Driver App
1. Open the app and tap **Create Account**
2. Fill in your details and submit registration
3. Wait for **Admin approval** before going online
4. Go online to start receiving trip requests

### Admin Panel
1. Log in with the admin account (created directly in Firebase Auth)
2. Go to **Driver Approvals** to review pending drivers
3. Monitor live trips and manage the platform from the dashboard

---

## Localization

Both the Driver and Passenger apps support **English** and **Arabic** with full RTL layout. Language can be switched at runtime from the Profile screen. All UI text — buttons, labels, dialogs, status messages — is fully translated.

---

*FluTour · Luxor, Egypt · 2026*
