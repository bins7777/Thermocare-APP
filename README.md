# ThermoCare

Flutter application and Arduino firmware for family skin-surface temperature check-ins, shared reminders and personal history. Version **1.0.2, build 4**.

Read [USER_GUIDE.md](USER_GUIDE.md) for everyday use, [ANDROID_INSTALL.md](ANDROID_INSTALL.md) for installing the APK, and [RELEASE.md](RELEASE.md) for packaging, signing and remaining physical-device verification.

## Application

- Real device readings only; first launch contains no generated measurements or profiles.
- First-use setup guidance and a remembered thermometer address, with readings requested on demand.
- Direct ThermoCare Wi-Fi connection at `192.168.4.1`, with local readings and saving independent of cloud access.
- Person-specific high temperature alerts from saved database records, with clinical confirmation guidance for fever concerns.
- Email/password family accounts, separate member profiles, archiving and restoration.
- Guided capture with a preparation checklist, three fresh stable samples and immutable capture context.
- Per-person notes, calendar, 7/30/90-day trends and CSV sharing.
- Shared reminder schedules with local phone notifications, timezone-aware scheduling and offline edits.
- Account-isolated local caches and a durable upload queue for Firebase Cloud Firestore.
- Responsive layout, large-text support, reduced motion, bundled fonts and consistent branding.

The client does not contain an exploration mode or generated history. Synthetic hardware and history used for validation live only in `test/`.

## Run and build

Requires Flutter 3.44 / Dart 3.12 or compatible newer versions. Dependencies are locked in `pubspec.lock`.

```powershell
flutter pub get
powershell -File tools/run.ps1
# Production web build, including analysis, tests and packaging:
powershell -File tools/release.ps1 -Target Web
```

The configured Firebase client file is `firebase-config.json`, which is local and ignored by version control. Both native application IDs are `com.thermocare.thermocare` and have matching registrations in **thermocare-family-f87c1**. The default Firestore database is in Singapore (`asia-southeast1`). Initial sign-in and cloud syncing require internet; local thermometer access does not.

An Android release supports Android 7.0+ (API 24+), and building it requires an installed Android SDK and a private release keystore configured in `android/key.properties`. Release builds cannot fall back to debug signing. An iOS release requires iOS 15+, macOS, Xcode and Apple signing. See [RELEASE.md](RELEASE.md) for commands and artifact locations.

## Database and offline behavior

Each family uses its Firebase Auth UID:

| Collection | Contents |
| --- | --- |
| `families/{UID}/members/{ID}` | Names, avatar IDs and archived status |
| `families/{UID}/readings/{base64url sample ID}` | Assigned sensor samples, notes and capture preparation/stability context |
| `families/{UID}/reminders/{ID}` | Member, time, weekdays and enabled state |

Family changes save locally first and enter a durable account-scoped outbox. Live listeners merge cloud changes while protecting pending local edits and deletions. Automatic unassigned device samples stay local. Trend summaries are derived from saved readings rather than duplicate aggregate documents. Reading notes can change; temperatures, time, member assignment and capture context remain immutable.

Reminder schedules sync when each phone opens the app online. Once downloaded, local notifications can fire with the app closed; updates are not pushed to a closed app. Each phone interprets shared schedule times in its own timezone. The editor supports up to eight family reminders. On the web, reminder prompts require the app to remain open. Notification permission does not prevent saving shared schedules.

Signed-out data is separate. The explicit profile-import action copies that family's profiles, assigned readings and reminders into the active account. Signing out preserves pending changes on this device for the next sign-in. Clearing readings while signed in also queues their deletion from the family database; profiles and reminders remain. Uninstalling loses local changes that have not uploaded.

Rules in `firebase/firestore.rules` enforce owner access, validate documents and protect immutable sample data. Client configuration contains no administrator credentials.

## Hardware setup

The firmware targets **Arduino Uno R4 WiFi**, **MLX90614 GY-906 BCC**, **16×2 I²C LCD at 0x27**, and **DS3231 using RTClib**. Disconnect power before wiring. Use each breakout's rated supply and appropriate I²C level shifting; a regulator alone does not establish 5 V-tolerant data pins.

| Uno R4 WiFi | LCD | DS3231 | MLX90614 breakout |
| --- | --- | --- | --- |
| GND | GND | GND | GND |
| A4 / SDA | SDA | SDA | SDA through level shifting if required |
| A5 / SCL | SCL | SCL | SCL through level shifting if required |
| Supply | Rated VCC, typically 5 V | Rated VCC | Exact breakout's specified VCC |

Expected I²C addresses are LCD `0x27`, sensor `0x5A` and RTC `0x68`. Use the battery type required by the RTC module; charging modules require suitable batteries or a disabled charging circuit.

1. Install Arduino UNO R4 Boards, Adafruit MLX90614 Library, Adafruit BusIO, RTClib and LiquidCrystal_I2C.
2. Copy `firmware/thermocare/arduino_secrets.example.h` to `arduino_secrets.h`. Set the home 2.4 GHz Wi-Fi credentials and a separate 8–63-character device-network password. Keep this ignored file private.
3. Upload `firmware/thermocare/thermocare.ino` once using USB-C. The sketch does not wait for a computer or Serial Monitor.
4. Power the device through USB-C using a regulated 5 V USB adapter or power bank. A 5 V adapter is for USB-C; VIN/barrel power uses the board's specified higher input range.
5. Join the same Wi-Fi and enter the address on the LCD in **My device**. Sync the clock after first setup.

If home Wi-Fi is unavailable for about 20 seconds, the device creates the **ThermoCare** network at **192.168.4.1**. It stays in this mode until restart. A lost home connection also falls back to this network. The sensor is retried if disconnected. Restart to retry home Wi-Fi, and update the app's saved address if the router assigns a new one.

The sensor's target distance and field of view must be established for the actual breakout and enclosure. The target must fill the field of view. No fixed distance, clinical calibration or body-temperature correction is assumed. The readiness gate is a repeatability aid: three distinct samples over 3–8 seconds, surface variation at most 0.3°C, and ambient variation at most 1°C. It does not establish clinical accuracy.

## Device history and transport

The firmware reads every second and retains the latest 120 one-minute samples in RAM, approximately two hours. These samples are lost on power loss or reset and do not identify who was measured. The app requests one reading on **Get reading** or an explicit connection check. Only a prepared guided capture polls every two seconds, for at most one minute; capture, leaving the page and backgrounding stop sampling. Resuming restarts sampling only if a guided capture is still active. Buffered history is imported on an explicit history refresh or during active capture when needed. Device ID, persistent boot counter and sequence deduplicate samples across connections. Explicit guided capture assigns a reading to a person.

The thermometer uses HTTP on a trusted local network. Do not expose its port to the internet. App-level encrypted local storage and authenticated/encrypted device transport have not been implemented. The application is a surface-temperature check-in tool and has not been clinically validated.

| Endpoint | Purpose |
| --- | --- |
| `/api/temperature` | Latest raw surface and ambient sample, clock and sample-age metadata |
| `/api/history` | Latest 120 buffered samples |
| `/api/time?epoch=...` | Set the RTC to UTC from the phone |
| `/api/health` | Device identity, sensor/RTC state and network mode |

Live samples older than five seconds are rejected. Missing device time uses the phone's estimate, which is identified in reading details and CSV exports. The DS3231 stores UTC and the app displays local time.

## Verification

```powershell
flutter analyze
flutter test
cd firebase
npm ci
npm run test:rules
# Creates and deletes temporary accounts and test data:
npm run test:live
# Deploy changed security rules when needed:
npm exec -- firebase deploy --only firestore:rules
```

Rules tests use Node 20+ and Java 21+. For local backend development, run `npm run emulators` in `firebase/` and use the `FIREBASE_EMULATOR` Dart define in debug builds only. Release tooling rejects emulator configuration. The emulator ports are Auth 9099 and Firestore 8085.

Tests cover empty startup, restoring the saved address without polling, bounded guided sampling, database-restored person-specific alerts, malformed/stale readings, duplicate samples, readiness gates, frozen captures, notes, calendar, reminders, account isolation, offline recovery, cross-phone syncing, trends, exports and layout at phone/desktop sizes with large text and reduced motion. UI screenshots are written to `artifacts/`.

Firmware was compiled with Arduino `renesas_uno` 1.6.0, MLX90614 2.1.6, RTClib 2.1.4, LiquidCrystal_I2C 2.0.0 and BusIO 1.17.4. Native builds and physical sensor/network/notification behavior still require verification on actual devices as listed in [RELEASE.md](RELEASE.md).

## Source layout

`lib/ui/` contains product screens, accessibility-aware motion and custom illustrations. `lib/controller.dart` coordinates device sessions and family care. `lib/data/` implements device transport, local persistence, account access, cloud syncing and native notifications. `lib/models.dart` and `lib/care_models.dart` define stored data and care calculations. `test/` contains isolated test fixtures. `firmware/thermocare/` contains the sketch and credential template.
