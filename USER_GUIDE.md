# ThermoCare

Family care, one check-in at a time.

## Start here

1. Open **Settings → Your family account → Sign in / Create family account**. Use the same family account on phones that should share profiles, check-ins and reminders. Initial sign-in needs internet.
2. Add a family member from Home or Settings. Give each person their own profile.
3. Power the configured thermometer through USB-C using a 5 V USB adapter or power bank.
4. Open **My device** and follow the connection steps. At home, join the same Wi-Fi as the thermometer and enter the address on its screen. Away from home, wait about 20 seconds, join its **ThermoCare** network using its separate password, then tap **Connect on ThermoCare Wi-Fi**. This sets **192.168.4.1** and requests a reading directly. Stay connected if the phone says this network has no internet. Internet and mobile data are not required for Arduino readings or local saves; initial account sign-in and cloud sync need internet.
5. Tap **Sync device clock** after first setup. ThermoCare remembers the address next time it opens. **Get reading** requests one update; opening or resuming the app does not start automatic readings.

## Save a check-in

Choose **Start guided check-in** or **Save reading**. Choose a person and complete the preparation checklist. Use the same exposed skin site and the distance established for your thermometer. Hold the sensor steady until **Ready to capture** appears.

Capture waits for three fresh, stable readings. Add an optional note and save. The captured person and sample stay fixed while you write. Preparation and stability details appear in the reading's details. A stable reading does not establish clinical accuracy. These are skin-surface temperatures; use a clinical thermometer for body-temperature concerns.

Automatic sampling starts only after you complete the guided checklist. It stops when you capture, leave the check-in, put the app in the background, or reach one minute. Tap **Try again** to restart a paused capture. The Home reading stays visible with its timestamp until you request another update; it is not a live monitor.

## High temperature alerts

A check-in at or above **Settings > Your temperature reference** shows an alert naming the person, the temperature and the reading time. The initial reference is 38°C; it is a configurable skin-temperature reference, not a validated fever cutoff. Saving that check-in shows an alert dialog. The selected person's latest saved high check-in also appears on Home and in its reading details. A newer saved check-in below the reference clears the Home alert. Earlier high readings stay in History.

Alerts come from saved records in the local database and the family records received through Firebase. The reference preference is stored on this phone for the current account. These are in-app alerts, not background fever notifications. Skin temperature alone cannot confirm or rule out fever; use a clinical thermometer to check a fever concern.

## History, notes and trends

**History → Everyone** shows saved family check-ins. Choose one person to see their history, or choose **Unassigned** for automatic thermometer samples. Open a reading to view its details or edit its note. **Share these readings** exports the current selection as a CSV file.

**Personal trends** shows one person's saved check-ins over 7, 30 or 90 days: latest value, period average, first-to-latest change, daily averages and notes. Daily-average lines connect saved days and do not represent continuous monitoring. Archived profiles keep their history.

**Family calendar** groups saved check-ins by day and shows planned reminders.

## Family reminders

Open **Reminders**, choose a person, time and weekdays, and save. Reminders sync across phones using the same account. Each phone interprets the shared time in its own local timezone.

On each installed phone, select **Enable notifications on this phone**. Open the app online on each phone to receive schedule changes. Once received, that phone schedules reminders locally, including while the app is closed. Battery settings can delay notifications. On the web, reminders appear while ThermoCare is open. Archiving a profile pauses that person's reminders.

## Offline use and your records

After initial sign-in, check-ins and reminder edits save locally when internet is unavailable. Family changes upload when internet returns. **Settings → Your family account** shows pending uploads and **Sync now**. Automatic unassigned samples stay on the current phone.

You can use ThermoCare without an account. To bring those profiles, assigned readings and reminders into a family later, sign in and choose **Add this phone's local profiles to account**. Only import records that belong to that family.

Signing out keeps that account's pending changes on this phone for its next sign-in. Clearing saved readings while signed in also deletes those family readings from the shared account after reconnecting; profiles and reminders remain. Export any records you want to keep before clearing. Uninstalling the app or clearing its storage loses changes that have not uploaded.

## If something needs attention

- **No connection:** check the thermometer's power, the phone's Wi-Fi network, and the address shown on the thermometer. Enter its current address in **My device** and reconnect.
- **Home Wi-Fi was turned off:** join the thermometer's ThermoCare Wi-Fi, then use **My device > Connect on ThermoCare Wi-Fi** to replace the old home address. A Chrome visit to `http://192.168.4.1/api/temperature` checks whether the phone can reach the thermometer. If Chrome shows data but the app fails, retain the full response and the app's connection error for troubleshooting.
- **Reading not ready:** complete the checklist, hold position, avoid drafts, and wait for fresh stable readings. Check the sensor connection if the app reports it unavailable.
- **Sharing has not updated:** reconnect to internet, confirm both phones use the same family account, and check **Sync now**.
- **No reminder notification:** enable notifications on that phone, open ThermoCare online to refresh its schedules, and check the phone's notification and battery settings.
- **Forgot your password:** enter the family email on the sign-in screen and choose **Forgot password?**
