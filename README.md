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

- **Flutter** 3.x (Android + iOS + Web)
- **Firebase** — Auth, Firestore, Realtime Database, FCM
- **flutter_map** + MapTiler Streets tiles
- **Geolocator** — GPS & location services

## Firebase Project

Project ID: `flutour-dev`
Firestore rules: `firestore.rules` (deployed via Firebase CLI)

---

## Progress — Day 42 of ~84

| Feature | Status |
|---------|--------|
| All UI screens (25 total) | ✅ Complete |
| Firebase Auth (all 3 apps) | ✅ Complete |
| Firestore E2E booking flow | ✅ Live |
| Realtime DB GPS broadcast | ✅ Live |
| FCM push notifications | ✅ Wired (client-side) |
| Driver online/offline toggle | ✅ Live |
| Admin approve/reject drivers | ✅ Live |
| Payment gateway (Vodafone Cash / InstaPay) | 🔜 Week 8 |
| Play Store release | 🔜 Week 11 |

**Overall progress: ~78%**

---

## Getting Started

### Passenger App
1. Open the app and tap **Create Account**
2. Enter your phone number and set a password
3. You can immediately book rides — no approval needed

### Driver App
1. Open the app and tap **Create Account**
2. Fill in your details and submit registration
3. Wait for **Admin approval** before you can go online and accept trips

### Admin Panel
1. Log in with the admin account (set up directly in Firebase Auth)
2. Go to **Driver Approvals** to review and approve pending drivers
3. Monitor live trips and manage the platform from the dashboard

---

*Flutour · Luxor, Egypt · 2026*
