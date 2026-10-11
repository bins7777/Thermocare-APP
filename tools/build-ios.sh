#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-prepare}"
if [[ $# -gt 0 ]]; then shift; fi
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'An iPhone build requires macOS and Xcode. This package is source, not an installer.' >&2
  exit 1
fi
command -v flutter >/dev/null || { echo 'Install Flutter and add it to PATH.' >&2; exit 1; }
xcodebuild -version
dart tools/ios_preflight.dart
version="$(awk '/^version:/ {split($2, parts, "+"); print parts[1]}' pubspec.yaml)"
build="$(awk '/^version:/ {split($2, parts, "+"); print parts[2]}' pubspec.yaml)"
[[ -n "$version" && -n "$build" ]] || { echo 'Set the app version in pubspec.yaml.' >&2; exit 1; }
defines=(--dart-define-from-file=firebase-config.json "--dart-define=APP_VERSION=$version" "--dart-define=APP_BUILD=$build")
flutter pub get
case "$mode" in
  prepare)
    flutter build ios --release --config-only --no-codesign "${defines[@]}"
    echo 'Prepared. Open ios/Runner.xcworkspace, select your Apple Team under Signing & Capabilities, then connect your iPhone.'
    ;;
  device)
    [[ $# -gt 0 ]] || { echo 'Usage: bash tools/build-ios.sh device <iPhone-device-ID>' >&2; flutter devices; exit 1; }
    device_id="$1"; shift
    flutter run --release -d "$device_id" "${defines[@]}" "$@"
    ;;
  ipa)
    flutter analyze
    flutter test
    flutter build ipa --release "${defines[@]}" "$@"
    echo 'Signed output, if Apple signing/export succeeded: build/ios/ipa/. Upload through Xcode Organizer for TestFlight; this script does not publish it.'
    ;;
  *) echo 'Choose prepare, device <iPhone-device-ID>, or ipa.' >&2; exit 1 ;;
esac
