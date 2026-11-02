import 'package:cloud_firestore/cloud_firestore.dart';

/// Studio details Admin saves at `settings/business` (see the Admin app's
/// `BusinessSettingsRepository`). The customer app only ever reads it — it
/// uses the GCash account to tell customers where to send their payment.
class BusinessSettings {
  final String studioName;
  final String gcashName;
  final String gcashNumber;

  const BusinessSettings({this.studioName = '', this.gcashName = '', this.gcashNumber = ''});

  bool get hasGcash => gcashNumber.isNotEmpty;

  factory BusinessSettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const BusinessSettings();
    String s(String key) => ((d[key] as String?) ?? '').trim();
    return BusinessSettings(
      studioName: s('studioName'),
      gcashName: s('gcashName'),
      gcashNumber: s('gcashNumber'),
    );
  }
}

class BusinessSettingsRepository {
  BusinessSettingsRepository._();

  /// Loads the details once. Any failure (offline, no document yet) returns
  /// empty details, so checkout is never blocked by this.
  static Future<BusinessSettings> fetch() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('settings').doc('business').get();
      return BusinessSettings.fromMap(snap.data());
    } catch (_) {
      return const BusinessSettings();
    }
  }
}
