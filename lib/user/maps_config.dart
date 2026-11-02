/// Google Maps API key setup
/// =========================
///
/// `google_maps_flutter` reads its API key from **native platform config**,
/// not from Dart code — there's no `MapsConfig.apiKey` to set here. Put the
/// same key (or separate restricted keys per platform, which is the safer
/// option) in these three places:
///
/// 1. Android — android/app/src/main/AndroidManifest.xml
///    <meta-data
///        android:name="com.google.android.geo.API_KEY"
///        android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
///
/// 2. iOS — ios/Runner/AppDelegate.swift
///    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
///
/// 3. Web — web/index.html (before flutter_bootstrap.js)
///    <script src="https://maps.googleapis.com/maps/api/js?key=YOUR_GOOGLE_MAPS_API_KEY"></script>
///
/// All three are already wired up in this project with a
/// `YOUR_GOOGLE_MAPS_API_KEY` placeholder — search for that string and
/// swap in your real key from the Google Cloud Console (enable the "Maps
/// SDK for Android", "Maps SDK for iOS", and "Maps JavaScript API"
/// products on the same key, or use separate restricted keys per
/// platform).
///
/// Note: `google_maps_flutter` only ships platform implementations for
/// Android, iOS, and Web. It does not run on native Windows/macOS/Linux
/// desktop builds — if you build for those, the map screens would need a
/// different plugin (or to be skipped) there. The "desktop" experience
/// this app targets is a wide browser window (Web), which is fully
/// supported.
library maps_config;
