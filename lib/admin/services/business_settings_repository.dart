import 'package:cloud_firestore/cloud_firestore.dart';

/// The studio's own details, stored in Firestore at `settings/business`.
/// Admin edits them on the Settings screen; the customer app reads the same
/// document to show where to send GCash payments.
class BusinessSettings {
  final String studioName;
  final String contactNumber;
  final String contactEmail;
  final String address;

  /// Where customers send their payment.
  final String gcashName;
  final String gcashNumber;

  const BusinessSettings({
    this.studioName = '',
    this.contactNumber = '',
    this.contactEmail = '',
    this.address = '',
    this.gcashName = '',
    this.gcashNumber = '',
  });

  factory BusinessSettings.fromMap(Map<String, dynamic>? d) {
    if (d == null) return const BusinessSettings();
    String s(String key) => ((d[key] as String?) ?? '').trim();
    return BusinessSettings(
      studioName: s('studioName'),
      contactNumber: s('contactNumber'),
      contactEmail: s('contactEmail'),
      address: s('address'),
      gcashName: s('gcashName'),
      gcashNumber: s('gcashNumber'),
    );
  }
}

/// Admin's read/write access to `settings/business`.
class BusinessSettingsRepository {
  BusinessSettingsRepository._();

  static DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('settings').doc('business');

  /// Loads the current details once; any failure falls back to empty values
  /// so the Settings screen still opens.
  static Future<BusinessSettings> fetch() async {
    try {
      final snap = await _doc.get();
      return BusinessSettings.fromMap(snap.data());
    } catch (_) {
      return const BusinessSettings();
    }
  }

  /// Saves the details. Throws if the write is rejected (only an admin may
  /// write `settings/{id}`).
  static Future<void> save(BusinessSettings b) {
    return _doc.set({
      'studioName': b.studioName.trim(),
      'contactNumber': b.contactNumber.trim(),
      'contactEmail': b.contactEmail.trim(),
      'address': b.address.trim(),
      'gcashName': b.gcashName.trim(),
      'gcashNumber': b.gcashNumber.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
