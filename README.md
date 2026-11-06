# memoriae_photobooth

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Map setup (free: flutter_map + MapTiler + LocationIQ)

The booking flow uses `flutter_map` (OpenStreetMap-based map). Keys are passed at run time, never hardcoded:

```
flutter run --dart-define=MAPTILER_KEY=xxxx --dart-define=LOCATIONIQ_KEY=xxxx
```

- `MAPTILER_KEY`: map tiles (https://cloud.maptiler.com). Without it the app falls back to public OpenStreetMap tiles, which are for testing only.
- `LOCATIONIQ_KEY`: address search and tap-to-address (https://locationiq.com). Without it, customers can still type the address and tap the map.


## Push notifications (User app)

Customers get a phone pop-up (even when the app is closed) for: a staff reply,
a booking approved / declined / rescheduled / refunded, and new announcements.

How it works: the phone saves its token on `users/{uid}.fcmTokens`
(`lib/user/services/push_notification_service.dart`); Cloud Functions in
`functions/index.js` watch `messages`, `bookings` and `announcements` and send
the push through Firebase Cloud Messaging.

One-time setup:
1. Upgrade the Firebase project to the **Blaze** plan (Cloud Functions require it; small usage is still ~free).
2. `cd functions && npm install && cd ..`
3. `firebase deploy --only functions` (if it complains about a region mismatch,
   add `{ region: "<your Firestore region>" }` as the first argument of the triggers in `functions/index.js`).
4. `flutter pub get`, then rebuild/reinstall the Android app and open it once
   (allow notifications when asked, log in).
5. iOS only: upload an APNs key in Firebase console > Project settings > Cloud Messaging.

Web is not covered (browsers need a service worker + VAPID key).

Android pop-up details:
- Uses its own channel `memoriae_alerts` with the custom chime
  `android/app/src/main/res/raw/memoriae_chime.wav` (replace the file to change
  the sound; if you change the channel id also change it in
  `functions/payload.js`, `AndroidManifest.xml` and `push_notification_service.dart`).
- `users/{uid}.unreadPush` counts unread pushes; the server sends it as the
  icon badge count and the app resets it to 0 when opened.
- Profile > Notifications is saved as `users/{uid}.pushEnabled`; the server
  skips customers who turned it off.
- After changing sound/channel, uninstall and reinstall the app once (Android
  remembers a channel's old sound).
- `cd functions && node --test payload.test.js` checks the push payload.

   ## Live sites
   - Admin: https://memoriae-admin.web.app
   - Staff: https://memoriae-staff.web.app
   - User: https://memoriae-user.web.app
