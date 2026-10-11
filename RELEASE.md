# ThermoCare 1.0.2 · build 4

The application contains real device and family-account flows only. Synthetic hardware and populated history are isolated in `test/`; they are not imported by the application. The production Android package and iOS bundle are `com.thermocare.thermocare`, with matching native app registrations in the existing ThermoCare Firebase project.

Version 1.0.1 removes idle device polling. A requested reading updates once; prepared guided sampling runs for up to one minute and stops on capture, page exit or backgrounding. Person-specific high temperature alerts use saved family readings and the account-scoped local reference preference. An alert appears when saving a high check-in and stays visible for the selected person's latest saved high reading. It directs users to confirm fever concerns with a clinical thermometer and does not diagnose fever or send background fever notifications. No Firestore schema or rules change is required: alerts derive from the same persisted readings already synced through the family database.

Version 1.0.2 adds **My device > Connect on ThermoCare Wi-Fi**, which explicitly selects the Arduino's local `192.168.4.1` address and requests a reading without internet. Explicit reconnects now wait for an earlier request to finish instead of being silently skipped; disconnecting cancels a queued reconnect. Device failures show the attempted address and an error beside the connection controls. Tests reproduce the pending-request race and verify the direct connection and local persistence without a cloud service. The phone's reported browser response confirms local reachability and `sensor_ok: true`; the complete response and an on-phone test of this APK are still needed to establish whether this change resolves that specific report.

## Reproducible builds

Keep the local `firebase-config.json` containing the web and native client configurations. It is ignored by version control. Release builds require the production project and reject emulator settings. The signing key and passwords are not included in source or web bundles.

```powershell
# Validate configuration without building:
powershell -File tools/release.ps1 -Target Web -ValidateOnly
# Analyze, test, build and package the web app:
powershell -File tools/release.ps1 -Target Web
# Build a signed APK or Play Store bundle after Android setup:
powershell -File tools/release.ps1 -Target Android
powershell -File tools/release.ps1 -Target AppBundle
```

Release artifacts and the user guide are written to `artifacts/release/`. The web archive must be served over HTTP(S), rather than opened directly as a file. An installed mobile app is the supported standalone hardware client; browser local-network permissions and HTTPS-to-HTTP restrictions can prevent web access to the thermometer.

The signed Android APK is `artifacts/release/ThermoCare-1.0.2.apk` for Android 7.0+ (API 24+), with ARM 32-bit, ARM 64-bit and x86-64 binaries. See [ANDROID_INSTALL.md](ANDROID_INSTALL.md). The APK uses the production family database configuration. `tools/verify-apk.ps1` checks release signing, application identity, minimum SDK, non-debuggable packaging, ZIP alignment, architectures and exclusion of private build files; its SHA-256 checksum is saved alongside the APK.

## Android signing

Install the Android SDK and confirm `flutter doctor` reports the Android toolchain ready. Create or use your private release keystore, copy `android/key.properties.example` to `android/key.properties`, and fill in its values. Use an absolute keystore path with forward slashes. Keep a secure backup of the keystore and passwords; updates must use the same signing identity. Release Gradle tasks fail if signing is missing, rather than using Flutter's debug key.

This workspace now has the SDK in `.tools/android-sdk`, a private release key in `.tools/signing/thermocare-release.jks`, and the ignored signing configuration in `android/key.properties`. Back up the key and signing configuration together securely. They are excluded from source control and release packages. The APK was built with the installed Temurin JDK 17; set `JAVA_HOME` to that JDK when rebuilding. The user approved the Android SDK licence during setup.

## iOS signing

Use macOS with Xcode, select the Apple development team in `ios/Runner.xcworkspace`, retain the registered bundle ID, and configure Apple signing. Build an IPA with the production Firebase file and version defines, or use the release script in a compatible PowerShell environment. Windows cannot produce a signed iOS build.

`powershell -File tools/package-ios.ps1` creates the portable iOS source archive `artifacts/release/ThermoCare-1.0.2-ios-project.zip`, containing the app, tests, iOS project, iOS-only Firebase client configuration and macOS build script. Windows-generated Flutter paths, Android keys, Arduino credentials and build caches are excluded. This is not an installer. See [IPHONE_BUILD.md](IPHONE_BUILD.md) for personal device and TestFlight routes. Run `bash tools/build-ios.sh prepare` on the Mac before opening Xcode; `device` installs to a connected iPhone after signing setup, and `ipa` builds an archive for subsequent distribution. None of these scripts publish or invite testers automatically.

## Verification before handing out phone builds

The iOS source package also includes `.github/workflows/ios.yml`, cloud signing scripts and [IOS_CLOUD_BUILD.md](IOS_CLOUD_BUILD.md). The workflow runs only when manually selected, with an optional App Store Connect upload. It has been checked statically on Windows, but has not run on a cloud Mac or used Apple credentials.

Software checks cover account-scoped persistence, offline uploads, reminder sync, readiness gates, stale readings, notes, personal trends, CSV export and responsive screens. Database rules tests and live Firebase tests verify owner isolation and two-session reminder changes.

The Android release build and package checks passed on 10 October 2026, alongside 49 Flutter tests and the live Firebase account/sync/isolation checks using the Android client configuration (`node firebase/test/live-smoke.mjs --android`). No Android phone was connected for runtime validation. There is no Apple signing environment here, and no iPhone installer has been produced. Before wider distribution, verify wall-powered startup, sensor position and accuracy for the actual enclosure, local Wi-Fi access, capture readiness, native sharing, notifications with the app closed, and offline-to-online syncing on the target phones.
