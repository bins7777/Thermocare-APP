#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'The cloud iPhone build requires macOS.' >&2; exit 1; }
[[ "${IOS_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]] || { echo 'Enter a positive numeric iOS build number.' >&2; exit 1; }
[[ -n "${RUNNER_TEMP:-}" ]] || { echo 'Use this script on the configured GitHub runner.' >&2; exit 1; }
version="$(awk '/^version:/ {split($2, parts, "+"); print parts[1]}' pubspec.yaml)"
[[ -n "$version" ]] || { echo 'Set the app version in pubspec.yaml.' >&2; exit 1; }
defines=(--dart-define-from-file=firebase-config.json "--dart-define=APP_VERSION=$version" "--dart-define=APP_BUILD=$IOS_BUILD_NUMBER" "--build-name=$version" "--build-number=$IOS_BUILD_NUMBER")
dart tools/ios_preflight.dart
case "${1:-}" in
  prepare)
    flutter pub get
    flutter analyze
    flutter test
    flutter build ios --release --config-only --no-codesign "${defines[@]}"
    ;;
  sign)
    for name in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY IOS_CERTIFICATE_PRIVATE_KEY; do
      [[ -n "${!name:-}" ]] || { echo "Missing repository secret: $name" >&2; exit 1; }
    done
    # Reuse the same certificate private key on every run. Never echo credentials.
    keychain initialize
    trap 'keychain use-login >/dev/null 2>&1 || true' EXIT
    app-store-connect fetch-signing-files com.thermocare.thermocare \
      --platform IOS --type IOS_APP_STORE --strict-match-identifier \
      --certificate-key @env:IOS_CERTIFICATE_PRIVATE_KEY --create
    keychain add-certificates
    export_options="$RUNNER_TEMP/thermocare-export.plist"
    xcode-project use-profiles --project ios/Runner.xcodeproj --export-options-plist "$export_options"
    flutter build ipa --release "${defines[@]}" --export-options-plist "$export_options"
    # Flutter may finish after archiving even when export fails; require the IPA.
    shopt -s nullglob
    packages=(build/ios/ipa/*.ipa)
    [[ ${#packages[@]} -eq 1 ]] || { echo 'Expected one exported, signed IPA.' >&2; exit 1; }
    codesign --verify --deep --strict build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
    echo 'Signed iPhone archive exported. TestFlight upload is a separate workflow option.'
    ;;
  *) echo 'Choose prepare or sign.' >&2; exit 1 ;;
esac
