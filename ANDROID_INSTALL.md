# Install ThermoCare on Android

Use `ThermoCare-1.0.2.apk` on an Android phone running Android 7.0 or later. This APK is for direct installation; it is not an iPhone app or a Play Store listing.

1. Transfer the APK to your phone, or download it there from a trusted copy you control.
2. Open it from Downloads or your file manager. If Android asks, allow that browser or file manager to install this APK, then select **Install**. You can turn that permission off afterward.
3. Open **ThermoCare**. Add your first family member and connect the thermometer from **My device**.
4. For shared records, create or sign in to your family account while your phone has internet. Use the same account on the other family phones.
5. Join the thermometer's home Wi-Fi, or its **ThermoCare** access point. Keep the connection if Android reports that the access point has no internet. Enter the address shown on the LCD; the access point address is **192.168.4.1**.
6. Enable notifications on each phone if you want reminders while the app is closed.

The app runs on your phone without this computer. The Arduino must already have the ThermoCare firmware uploaded and remain powered. Firebase sharing needs internet; local check-ins can be saved offline and uploaded later. See `USER_GUIDE.md` for the complete workflow.

Install later ThermoCare updates over the existing app to preserve local records. Do not uninstall or clear storage to troubleshoot an update until any pending changes are synced or exported. Updates must retain the same signing key.

The APK is compiled and signed here, but it still needs testing with your actual phone and thermometer. In particular, check Wi-Fi connectivity, capture, database sync and background reminders before relying on it.
