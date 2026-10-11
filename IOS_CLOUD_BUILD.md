# Build ThermoCare for TestFlight using GitHub

The cloud workflow is prepared but has not run. It uses a GitHub-hosted Mac, Flutter 3.44.6, Xcode and Codemagic CLI signing tools. The resulting App Store distribution IPA is delivered to an iPhone through TestFlight, rather than installed by tapping the IPA file.

## 1. Create the private repository

Open https://github.com/new, name it **ThermoCare**, choose **Private**, enable **Add a README**, and create it. Share the repository URL with the assistant so the prepared source can be uploaded. Keep signing credentials out of the repository. If the GitHub connector cannot see the new repository, grant it access in GitHub's installed-app settings.

The source upload needs `lib/`, `assets/`, `test/`, `ios/`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.metadata`, `.gitignore`, `.github/workflows/ios.yml`, `tools/cloud-ios.sh` and `tools/ios_preflight.dart`. Do not upload `.tools/`, build caches, Android signing files or Apple keys. The iOS source ZIP includes the required files and a public Firebase client configuration; restore that configuration using the secret below rather than committing it.

## 2. Configure your Apple account

Use your existing Apple Developer Program membership. Register the explicit bundle ID **com.thermocare.thermocare** to your team and create a **ThermoCare** iOS app record in App Store Connect using that ID. If the ID is unavailable, stop and update the project and Firebase registration to a unique ID before building.

Create an App Store Connect **team API key** with App Manager access. Keep the issuer ID, key ID and downloaded `.p8` key securely. The key must have access to signing certificates and profiles as well as the app; resolve any Apple account role or agreement requirements before running the workflow.

Run `node tools/create-ios-signing-key.cjs` locally once. This generates an ignored RSA private key at `.tools/apple-signing/distribution-private-key.pem`. Back it up and reuse it for every build. It is separate from Apple's `.p8` API key. The workflow can create a distribution certificate and provisioning profile on your Apple account using this key; it does not revoke existing certificates or profiles.

## 3. Add repository secrets

In GitHub, open **Settings > Secrets and variables > Actions > New repository secret**. Add these values directly in GitHub, never in chat:

| Secret | Value |
| --- | --- |
| `FIREBASE_IOS_CONFIG_JSON` | Entire `firebase-config.json` from the iOS source ZIP. This is SDK client configuration, not an Apple signing credential. |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID for the Apple team API key. |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Apple API key ID. |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Entire downloaded Apple `.p8` file, including PEM header and footer. |
| `IOS_CERTIFICATE_PRIVATE_KEY` | Entire generated `distribution-private-key.pem`, including PEM header and footer. |

## 4. Build, upload and install

1. Open **Actions > iPhone release > Run workflow** on the default branch. Enter a new positive build number (start with `4`). Keep **Upload to App Store Connect for TestFlight processing** unchecked for the first build. This runs validation, tests, signing and IPA export. GitHub's hosted macOS usage is subject to your account's Actions allowance and billing settings.
2. A successful run provides an IPA and debug symbols as an artifact retained for 7 days. This confirms compilation/export; it does not yet confirm behavior on your phone.
3. When ready to send the build to Apple, run the workflow again with a new build number and the upload option checked. It validates the package and uploads it for processing. It does not submit an App Store release, submit external beta review, or send invitations automatically.
4. In App Store Connect, open **ThermoCare > TestFlight**, complete any required compliance information and add the processed build to your internal tester group. Add your Apple Account as an eligible internal tester. External testers may require beta review.
5. Install Apple's **TestFlight** app on your iPhone 17 Pro, accept the invitation, then install ThermoCare. Allow local-network access and test the thermometer, saved measurements, account sync and reminders. TestFlight builds expire after 90 days; upload a newer build when needed.

If a run fails, inspect the failed step before rerunning. Increase the build number after an upload has succeeded. No signed IPA, Apple upload or TestFlight invitation exists from the Windows preparation step.

References: [Flutter iOS release and cloud signing guide](https://docs.flutter.dev/deployment/ios), [GitHub manual workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), [Apple TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
