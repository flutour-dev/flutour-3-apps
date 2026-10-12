# FluTour Driver App

A Flutter app for drivers managing Hantour and Felucca river ride requests in Luxor, Egypt.

## Current Version

**1.0.2+9** · October 12, 2026

## Store Status

| Platform | Status |
|----------|--------|
| Google Play | Not live — requires more testing before public release |
| App Store (iOS) | Pending — Apple Developer account migrating from Individual to Organization |

> **Apple account note:** The account is currently in migration from an Individual to an Organization account. This migration must complete before either app (Passenger or Driver) can be submitted to the App Store for production.

## Features

- **Auto-online** — driver status set to online automatically on login and after each trip
- Real-time trip request notifications with custom sounds
- Live GPS location map on the dashboard
- Offer / counter-offer negotiation with passengers
- Trip step tracking: en route → arrived → in progress → completed
- Earnings summary and trip history
- Firebase Auth session persistence (no re-login on app reopen)
- Sign in with Google and Sign in with Apple
- Account deletion support

## Notification Sounds

| Event | Sound |
|-------|-------|
| New trip request from passenger | `arrival_ding.mp3` |
| Passenger accepted driver's offer | `arrival_ding.mp3` |
| Driver arrived at pickup location | `arrived_pickup.mp3` (calendar alert) |

Sounds are deduplicated — the startup sound guard (`_soundReady` flag, 3 s delay) prevents false triggers on app open.

## Driver Status Flow

```
App open (logged in)
  └─ Dashboard loads → auto setStatus('online')

Trip completed
  └─ _nextStep() finalises trip → auto setStatus('online')
```

## Build

```bash
flutter pub get
flutter build apk --release        # APK for direct install
flutter build appbundle --release  # AAB for Google Play
```

Release artifacts:
- `flutour-driver-release.apk`
- `flutour-driver-release.aab`

## Tech Stack

- Flutter 3 / Dart
- Firebase Auth, Firestore, Realtime Database, Cloud Messaging
- `flutter_map` + OpenStreetMap with live `MapController`
- `audioplayers` for notification sounds
- `geolocator` for GPS broadcasting
- `google_sign_in`, `sign_in_with_apple`
- `provider` for state management
