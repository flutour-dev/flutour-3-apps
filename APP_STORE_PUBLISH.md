# FluTour — Apple App Store Submission Guide

> Covers both apps: **FluTour Passenger** (`flu_tour_passenger`) and **FluTour Driver** (`flu_tour_driver`)

---

## Checklist Overview

| # | Phase | Status |
|---|---|---|
| 1 | Apple Developer Account | ✅ Done |
| 2 | Firebase iOS Config | ✅ Done |
| 3 | Xcode Setup | ✅ Done |
| 4 | iOS-Specific Code Fixes | ✅ Done |
| 5 | Testing on Real iPhone | ✅ Done — Sep 21, 2026 |
| 6 | Build the IPA | ✅ Done — Sep 21, 2026 |
| 7 | App Store Connect Metadata | ✅ Done |
| 8 | Upload & Submit | 🔄 In Review — Awaiting Apple Approval |

> **Current status:** Both apps submitted to App Store Connect on Sep 21, 2026. Awaiting Apple review (estimated 1–7 days).

---

## Phase 1 — Apple Developer Account ✅

- Enrolled at [developer.apple.com/programs](https://developer.apple.com/programs)
- Fee: $99/year
- **Done.**

---

## Phase 2 — Firebase iOS Config ✅

Both apps have real `GoogleService-Info.plist` files with correct bundle IDs and client IDs:
- Passenger: `com.flutour.passenger` → `flu_tour_passenger/ios/Runner/GoogleService-Info.plist`
- Driver: `com.flutour.driver` → `flu_tour_driver/ios/Runner/GoogleService-Info.plist`

---

## Phase 3 — Xcode Setup

Open each app's workspace in Xcode:

```bash
cd flu_tour_passenger && open ios/Runner.xcworkspace
cd flu_tour_driver && open ios/Runner.xcworkspace
```

### For each app in Xcode:

1. Select **Runner** in the project navigator
2. Go to **Signing & Capabilities** tab:
   - **Bundle Identifier**: match what you registered in Firebase (`com.flutour.passenger` / `com.flutour.driver`)
   - **Team**: select your Apple Developer account
   - **Automatically manage signing**: enabled
3. Go to **General** tab:
   - **Version**: `1.0.0`
   - **Build**: `1`
4. Add **Capabilities**:
   - Push Notifications
   - Background Modes → check:
     - Location updates
     - Remote notifications

---

## Phase 4 — iOS-Specific Code Fixes ✅

All code fixes applied:

### 4.1 — Location Permission Strings
All three keys present in both `Info.plist` files:
- `NSLocationWhenInUseUsageDescription` ✅
- `NSLocationAlwaysAndWhenInUseUsageDescription` ✅
- `NSLocationAlwaysUsageDescription` ✅

App display names fixed: `FluTour` (passenger), `FluTour Driver` (driver).

### 4.2 — Google Sign-In URL Scheme
`CFBundleURLTypes` added to both `Info.plist` files with the correct `REVERSED_CLIENT_ID`:
- Passenger: `com.googleusercontent.apps.258397191065-ia735egkerkrrgqj3ri3qg9a7o8lnbhb`
- Driver: `com.googleusercontent.apps.258397191065-usppb664m2hdb5acaa6ob8klb6ec1mb4`

### 4.3 — Firebase AppDelegate
Both `AppDelegate.swift` files updated with `import Firebase` and `FirebaseApp.configure()`.

---

## Phase 5 — Testing on Real iPhone

> **Do not skip this.** Apple reviewers test on real devices. Crashes during review = rejection.

### 5.1 — Register Your iPhone as a Test Device

1. Connect your iPhone to your Mac via USB
2. In Xcode → **Window** → **Devices and Simulators** → confirm your device appears
3. In [Apple Developer Portal](https://developer.apple.com) → **Devices** → register your iPhone UDID

### 5.2 — Run on Device (Debug)

```bash
# List connected devices
flutter devices

# Run passenger app on iPhone
cd flu_tour_passenger
flutter run -d <your-iphone-device-id>

# Run driver app on iPhone
cd flu_tour_driver
flutter run -d <your-iphone-device-id>
```

### 5.3 — Test Checklist (both apps)

**Passenger App**
- [ ] App launches and splash screen resolves correctly
- [ ] Google Sign-In works (requires real device, not simulator)
- [ ] Location permission prompt appears
- [ ] Map loads with current location
- [ ] Can request a Felucca / Hantour trip
- [ ] Receives driver acceptance notification
- [ ] Booking confirmed screen shows driver photo and fare
- [ ] InstaPay panel shown when driver has instapay phone
- [ ] Trip history loads
- [ ] Profile photo loads on startup

**Driver App**
- [ ] App launches and splash screen resolves correctly
- [ ] Google Sign-In works
- [ ] Location permission prompt appears (including background)
- [ ] Trip requests appear (correct vehicle type filter)
- [ ] Can accept a trip
- [ ] Navigation/map works with address fallback when GPS coords are null
- [ ] Earnings and history load
- [ ] Push notification received when new trip is available
- [ ] Profile and vehicle photos load

**Both Apps**
- [ ] No crashes on launch or during core flows
- [ ] Arabic + English locale switching works
- [ ] Support contact (`support@app.flutour.com`) is reachable
- [ ] App works on iOS 15+ (minimum deployment target)

### 5.4 — Run Release Build on Device

Test the release build specifically before submitting — it behaves differently from debug:

```bash
flutter build ios --release
# Then in Xcode: Product → Run (with release scheme selected)
```

---

## Phase 6 — Build the IPA

Once testing passes, build the final IPA for each app:

```bash
# Passenger
cd flu_tour_passenger
flutter build ipa --release

# Driver
cd flu_tour_driver
flutter build ipa --release
```

Output files:
```
flu_tour_passenger/build/ios/ipa/flu_tour_passenger.ipa
flu_tour_driver/build/ios/ipa/flu_tour_driver.ipa
```

---

## Phase 7 — App Store Connect Metadata

Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com) and create a new app entry for each.

### Required for Both Apps

| Field | Passenger | Driver |
|---|---|---|
| App Name | FluTour — Luxor Rides | FluTour Driver |
| Subtitle | Felucca & Hantour Booking | Earn with FluTour |
| Category | Travel | Travel |
| Secondary Category | Transportation | Transportation |
| Language | English + Arabic | English + Arabic |
| Pricing | Free | Free |

### Screenshots Required

Apple requires screenshots at these sizes (minimum):
- **6.9" Display** (iPhone 16 Pro Max) — 1320 × 2868 px
- **5.5" Display** (iPhone 8 Plus) — 1242 × 2208 px

Capture at least 3–5 screenshots per app showing:
- Home / map screen
- Trip request / booking screen
- Booking confirmed screen
- Trip history

> Use a simulator if you don't have the exact device sizes.

### Description (Passenger App — example)

```
FluTour brings Luxor's iconic Felucca boats and Hantour horse carriages to your phone.

Book a Felucca ride on the Nile or a Hantour carriage through Luxor's historic streets in seconds. See real-time driver location, agree on a fare, and pay with InstaPay or cash.

— Real-time GPS tracking
— Felucca & Hantour booking
— Arabic & English support
— InstaPay & cash payment
```

### Privacy Policy

> A privacy policy URL is **mandatory** for apps that collect location data.

Host a simple privacy policy page at your domain (e.g. `https://app.flutour.com/privacy`) before submitting.

### App Review Information

Provide a test account for Apple reviewers:
- Login method: Google Sign-In or email/password
- Create a dedicated reviewer account in your Firebase Console before submitting

---

## Phase 8 — Upload & Submit

### Upload the IPA

Use **Transporter** (free from Mac App Store):
1. Open Transporter
2. Sign in with your Apple ID (developer account)
3. Drag and drop each `.ipa` file
4. Click **Deliver**

Or upload directly from **Xcode Organizer**:
- Xcode → **Window** → **Organizer** → select archive → **Distribute App** → App Store Connect

### Submit for Review

1. In App Store Connect, go to your app
2. Select the uploaded build
3. Complete all metadata sections (no red warnings)
4. Click **Submit for Review**

---

## Timeline

| Phase | Estimated Time |
|---|---|
| ~~Apple Developer Account~~ | ~~Done~~ |
| Firebase iOS config (both apps) | 1–2 hours |
| Xcode setup (both apps) | 2–4 hours |
| iOS code fixes (Info.plist, AppDelegate) | 2–3 hours |
| Testing on real iPhone | 1–2 days |
| Build IPAs | 30 minutes |
| App Store Connect metadata + screenshots | 2–4 hours |
| Apple review | **1–7 days** |
| **Total (from today)** | **~3–5 days work + review wait** |

---

## Common Rejection Reasons to Avoid

| Reason | How to Prevent |
|---|---|
| Missing privacy policy | Host one before submitting |
| Crash during review | Test release build on real iPhone first |
| Vague location permission description | Use clear descriptions in Info.plist |
| Missing test account for reviewers | Create a reviewer account in Firebase |
| Incomplete screenshots | Fill all required screenshot sizes |
| Background location without justification | Explain in App Store Connect review notes |

---

## Key Differences vs. Google Play

| | Google Play | Apple App Store |
|---|---|---|
| Build file | `.aab` | `.ipa` |
| Firebase config | `google-services.json` | `GoogleService-Info.plist` |
| Developer fee | $25 one-time | $99/year |
| Review time | 1–3 days | 1–7 days |
| Strictness | Moderate | High |
