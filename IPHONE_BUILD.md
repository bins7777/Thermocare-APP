# ThermoCare for iPhone

`ThermoCare-1.0.2-ios-project.zip` contains the iOS project and app source. It is **not** an installable iPhone app. No signed IPA or TestFlight invitation has been created here.

The project targets iOS 15+ and includes the ThermoCare interface, persistent local database, production Firebase family service configuration, native reminders and local-network permission for the Arduino. Its minimum iOS version includes an iPhone 17 Pro, but compilation and actual phone behavior still need verification on Apple tools.

## Install on your own iPhone using a Mac

1. Unzip the package on a Mac. Install a compatible Flutter SDK (this project uses Flutter 3.44.6 / Dart 3.12.2) and Xcode with support for your phone's installed iOS version. Complete Xcode setup and check `flutter doctor`. CocoaPods may be required for plugins that have not migrated to Swift Package Manager.
2. In Terminal, enter the extracted `ThermoCare` folder and run `bash tools/build-ios.sh prepare`. This regenerates local Flutter/plugin configuration; no Windows-specific generated paths are bundled.
3. Open `ios/Runner.xcworkspace`. In Xcode, sign in to your Apple Account and select your Team under **Runner → Signing & Capabilities**. Retain the registered bundle ID `com.thermocare.thermocare`. If Apple reports that this identifier is unavailable to your team, a new unique ID and matching Firebase iOS registration will be required before building.
4. Connect and trust your iPhone; enable Developer Mode if Xcode/iOS requests it. Run `flutter devices`, then `bash tools/build-ios.sh device YOUR_DEVICE_ID` to install the release build with the production configuration.
5. Allow local-network access when ThermoCare connects to the thermometer. Sign in to the family account while internet is available, then connect to the thermometer's Wi-Fi. See `USER_GUIDE.md`.

A free Apple Account can use Xcode's Personal Team for personal device testing, subject to Apple's limits. Personal Team provisioning expires after 7 days and requires rebuilding/reinstalling. [Apple's account and Personal Team guidance](https://developer.apple.com/help/account/basics/about-your-developer-account)

## Make a downloadable TestFlight version

For your Apple Developer membership and a cloud Mac, use the prepared [GitHub cloud build instructions](IOS_CLOUD_BUILD.md). The manual workflow validates, signs and exports an IPA; an optional upload sends it to App Store Connect for TestFlight processing. It still requires a private repository and secure Apple signing setup.

Use an Apple Developer Program membership and a Mac build machine (local or an authorized cloud macOS service). Configure the signing team, certificate and provisioning profile, and create the app record in App Store Connect. Run `bash tools/build-ios.sh ipa` after signing is ready, then validate and distribute the archive through Xcode Organizer. The script only builds; it does not upload, publish, or invite anyone.

After the build is processed and the required testing/review steps are complete, TestFlight provides an invitation or public link that lets your iPhone download the app. A generic ZIP or unsigned IPA cannot replace signing and provisioning. [Flutter's iOS release guide](https://docs.flutter.dev/deployment/ios), [Apple's TestFlight process](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

Do not put Apple passwords, signing keys, certificates or private App Store Connect keys into chat or source control. Use Xcode's account management or your build service's credential setup.

## Verification status

The shared app passed 49 Flutter tests, and the Android release was compiled and signature-verified. The iOS bundle ID, target version, local-network permission and Firebase client configuration were checked on Windows. No iOS compilation, Apple signing or iPhone runtime test has run in this workspace. Test thermometer access, saving, offline recovery, family sync, sharing and closed-app reminders on the iPhone before wider use.
