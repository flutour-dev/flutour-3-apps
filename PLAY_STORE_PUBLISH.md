# FluTour — Google Play Store Publishing Guide

Two apps to publish:
- **FluTour - Book a Ride** (passenger app)
- **FluTour Driver** (driver app)

## Current Status — Sep 21, 2026

| App | Status |
|-----|--------|
| FluTour — Book a Ride | 🔄 **In Review** — Awaiting Google Play approval |
| FluTour Driver | 🔄 **In Review** — Awaiting Google Play approval |

> Both APKs built and submitted on Sep 21, 2026. Google Play review typically takes 1–3 days.

---

## Before You Start

### Secure the ORS API Key

In both `flu_tour_passenger/lib/route_service.dart` and `flu_tour_driver/lib/route_service.dart`, change:

```dart
// Before (hardcoded — unsafe)
static const _orsKey = 'eyJvcmci...';

// After (compiled into binary — not visible as plain text)
static const _orsKey = String.fromEnvironment('ORS_KEY');
```

Then always build with the key injected:
```bash
flutter build appbundle --release --dart-define=ORS_KEY=eyJvcmci...
```

---

### Set App Versions

In `flu_tour_passenger/pubspec.yaml` and `flu_tour_driver/pubspec.yaml`:

```yaml
version: 1.0.0+1
```

> Every new upload to Play Store requires a higher `+N` number. Example: next update = `1.0.1+2`.

---

### Confirm Package Names

Check `android/app/build.gradle` in each project:

| App | applicationId |
|---|---|
| Passenger | `com.flutour.passenger` |
| Driver | `com.flutour.driver` |

---

## Step 1 — Create Google Play Developer Account

1. Go to [play.google.com/console](https://play.google.com/console)
2. Sign in with **flutour.dev@gmail.com**
3. Click **Get started**
4. Account type: **Organization** → name: `FluTour`
5. Pay the **$25 one-time registration fee**
6. Fill in contact details → Submit
7. Wait for approval (usually instant, up to 24h)

---

## Step 2 — Create the Release Keystore

Run this once in Terminal. **Back up the `.jks` file — losing it means you can never update the app.**

```bash
keytool -genkey -v \
  -keystore ~/flutour-release.jks \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias flutour
```

When prompted:
- Keystore password: choose a strong password and save it
- First/last name: `FluTour`
- Organization: `FluTour`
- City: `Luxor`
- Country code: `EG`
- Type `yes` to confirm

> Save `flutour-release.jks` to Google Drive or another backup location immediately.

---

## Step 3 — Configure Signing in Both Apps

Add this to the `android { }` block in both `android/app/build.gradle` files:

```gradle
signingConfigs {
    release {
        storeFile file('/Users/sarah/flutour-release.jks')
        storePassword 'YOUR_KEYSTORE_PASSWORD'
        keyAlias 'flutour'
        keyPassword 'YOUR_KEYSTORE_PASSWORD'
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled true
        shrinkResources true
    }
}
```

---

## Step 4 — Register Release SHA-1 in Firebase

Get the SHA-1 fingerprint of your keystore:

```bash
keytool -list -v -keystore ~/flutour-release.jks -alias flutour
```

Copy the **SHA-1** line, then:

1. Go to [Firebase Console](https://console.firebase.google.com) → project **flutour-3fc69**
2. Project Settings → Your apps
3. For each Android app → **Add fingerprint** → paste the SHA-1
4. Download updated `google-services.json` for each app and replace the existing files

---

## Step 5 — Upgrade Firebase to Blaze Plan

The free Spark plan limits (50,000 reads/day, 20,000 writes/day) will be hit quickly with real users. Blaze is pay-as-you-go — with small traffic the bill is $0–$5/month.

1. Firebase Console → bottom-left plan badge → **Upgrade**
2. Select **Blaze** → add a credit card → confirm

---

## Step 6 — Build Release AABs

Google Play requires AAB format (not APK).

```bash
# Passenger
cd ~/Documents/flutour/flutter/flu_tour_passenger
flutter build appbundle --release --dart-define=ORS_KEY=YOUR_ORS_KEY_HERE

# Driver
cd ~/Documents/flutour/flutter/flu_tour_driver
flutter build appbundle --release --dart-define=ORS_KEY=YOUR_ORS_KEY_HERE
```

Output files:
- `flu_tour_passenger/build/app/outputs/bundle/release/app-release.aab`
- `flu_tour_driver/build/app/outputs/bundle/release/app-release.aab`

---

## Step 7 — Test on a Real Android Device

Build a release APK (not AAB) and install it on a physical phone before submitting:

```bash
# Passenger
cd flu_tour_passenger
flutter build apk --release --dart-define=ORS_KEY=YOUR_ORS_KEY_HERE

# Driver
cd flu_tour_driver
flutter build apk --release --dart-define=ORS_KEY=YOUR_ORS_KEY_HERE
```

Transfer the APK to your phone and test the full flow:
- [ ] Register / login
- [ ] Book a trip (passenger)
- [ ] Accept / refuse a trip (driver)
- [ ] Complete a trip end to end
- [ ] Check route appears on map
- [ ] Check fare is correct

---

## Step 8 — Prepare Store Assets

Prepare these for each app before creating listings:

| Asset | Size | Notes |
|---|---|---|
| App icon | 512×512 PNG | No transparency, no rounded corners (Play adds them) |
| Feature graphic | 1024×500 PNG | Banner shown at top of listing |
| Phone screenshots | Min 2, max 8 | At least 1080×1920 px, take from real device |
| Short description | Max 80 chars | e.g. "Book felucca & horse carriage rides in Luxor" |
| Full description | Max 4,000 chars | In English + Arabic |

**Privacy Policy** — required. Generate one free at [privacypolicygenerator.info](https://privacypolicygenerator.info) and host it on Google Sites, Notion, or GitHub Pages. Copy the URL.

---

## Step 9 — Create App Listings in Play Console

Do this twice — once for each app.

1. Play Console → **Create app**
2. Fill in:
   - App name: `FluTour - Book a Ride` or `FluTour Driver`
   - Default language: English
   - Type: App
   - Free or paid: Free
3. Accept policies → **Create app**

---

## Step 10 — Fill In Required Sections

In the left menu, complete every section with a warning icon:

### Main store listing
- Add icon, feature graphic, screenshots
- Write short and full descriptions

### App content
- **Privacy policy**: paste your hosted URL
- **Ads**: No ads
- **Content rating**: complete questionnaire → Submit (result should be "Everyone" or "Teen")
- **Target audience**: 18+
- **Data safety**: declare what data you collect (location, name, phone number)

### Store settings
- **Category**: Travel & Local (passenger) / Transportation (driver)
- **Contact email**: flutour.dev@gmail.com
- **Website**: optional

---

## Step 11 — Upload AAB and Submit

1. Go to **Release → Production → Create new release**
2. Click **Upload** → select `app-release.aab`
3. Release name: `1.0.0` (auto-filled)
4. Release notes (shown to users on Play Store):
   ```
   Initial release of FluTour for Luxor, Egypt.
   Book felucca and horse carriage rides instantly.
   ```
5. Click **Next** → review warnings → **Save and publish**

---

## Step 12 — Wait for Review

- New apps: **1–3 business days**
- You will receive an email at flutour.dev@gmail.com when approved
- After approval the app goes live in the countries you selected

---

## After Publishing — Future Updates

Every time you release a new version:

1. Increment version in `pubspec.yaml`: e.g. `1.0.1+2`
2. Build new AAB: `flutter build appbundle --release --dart-define=ORS_KEY=...`
3. Play Console → Production → Create new release → Upload new AAB
4. Add release notes → Save and publish
5. Updates are reviewed faster (usually same day)

---

## Summary Checklist

- [ ] ORS key moved to `--dart-define`
- [ ] `version: 1.0.0+1` set in both `pubspec.yaml` files
- [ ] Package names confirmed (`com.flutour.passenger` / `com.flutour.driver`)
- [ ] Keystore `flutour-release.jks` created and backed up
- [ ] Signing configured in both `build.gradle` files
- [ ] Release SHA-1 added to Firebase and `google-services.json` updated
- [ ] Firebase upgraded to Blaze plan
- [ ] Both AABs built with `flutter build appbundle --release`
- [ ] Tested on real Android device
- [ ] Play Console account created ($25)
- [ ] Privacy policy URL ready
- [ ] App icons and screenshots prepared
- [ ] Two app listings created and store listings filled
- [ ] Data safety form completed
- [ ] Content rating completed
- [ ] Both AABs uploaded to Production
- [ ] Submitted for review
