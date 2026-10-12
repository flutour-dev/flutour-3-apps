# FluTour Passenger App

A Flutter ride-booking app for Hantour and Felucca river rides in Luxor, Egypt.

## Current Version

**1.0.2+10** · October 12, 2026

## Store Status

| Platform | Status |
|----------|--------|
| Google Play | Live ✓ |
| App Store (iOS) | Pending — Apple Developer account migrating from Individual to Organization |

> **Apple account note:** The account is currently in migration from an Individual to an Organization account. This migration must complete before either app (Passenger or Driver) can be submitted to the App Store for production.

## Features

- **Guest mode** — browse rides and see fare estimates without an account
- **Login-first flow** — app opens to the login screen on first install
- Hantour and Felucca vehicle types with fare estimation
- OpenStreetMap-based map (no Google Maps API key required)
- Location search with Egypt/Luxor-optimised geocoding via Nominatim
- Multiple payment methods: Cash, Credit Card, Mobile Wallet
- Real-time driver matching with live offer/counter-offer negotiation
- Trip status tracking with notification sounds
- Sign in with Google and Sign in with Apple
- Account deletion support
- Firebase Auth session persistence (no re-login on app reopen)
- Arabic and English localisation

## Onboarding Flow

```
App open
  └─ SplashScreen (2 s)
       ├─ Session exists  → PassengerHomeScreen (4 tabs)
       └─ No session      → LoginScreen
                               ├─ Log in / Register → PassengerHomeScreen (4 tabs)
                               └─ Browse without account → PassengerHomeScreen (guest mode, 2 tabs)
                                                                └─ Tap Pay → LoginScreen (auth required)
```

## Tabs

| Tab | Guest | Logged In |
|-----|-------|-----------|
| Home | ✓ | ✓ |
| Book Ride | ✓ (browse only, login at Pay) | ✓ |
| My Trips | — | ✓ |
| Profile | — | ✓ |

## Notification Sounds

| Event | Sound |
|-------|-------|
| Driver accepted offer | `arrival_ding.mp3` |
| Driver arrived at pickup | `arrived_pickup.mp3` (calendar alert) |
| Trip started | `arrival_ding.mp3` |

## Build

```bash
flutter pub get
flutter build apk --release        # APK for direct install
flutter build appbundle --release  # AAB for Google Play
```

Release artifacts:
- `flutour-passenger-release.apk`
- `flutour-passenger-release.aab`

## Tech Stack

- Flutter 3 / Dart
- Firebase Auth, Firestore, Realtime Database, Cloud Messaging
- `flutter_map` + OpenStreetMap
- `audioplayers` for notification sounds
- `geolocator` for GPS
- `google_sign_in`, `sign_in_with_apple`
- `provider` for state management
