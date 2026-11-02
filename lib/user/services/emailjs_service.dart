import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Sends the one-time verification code by email via EmailJS — a service
/// specifically built to send email directly from client-side code (no
/// backend/server needed), unlike a normal SMTP relay which browsers
/// can't talk to directly and which would expose real email credentials
/// if attempted client-side.
///
/// FILL THESE IN after setting up a free account at https://emailjs.com:
/// 1. Email Services > Add New Service (connect your Gmail/etc) → copy
///    the Service ID it gives you.
/// 2. Email Templates > Create New Template, with a `{{otp_code}}`
///    variable somewhere in the body → copy the Template ID.
/// 3. Account > General > copy the Public Key.
class EmailJsService {
  EmailJsService._();

  // Filled in from the EmailJS dashboard (Gmail service, "One-Time
  // Password" template, Account > General public key).
  static const String serviceId = "service_ufw2v8z";
  static const String templateId = "template_cblk5li";
  static const String publicKey = "qvFOYkYpATKQy0omY";

  static const String _endpoint = "https://api.emailjs.com/api/v1.0/email/send";

  /// Generates a random 6-digit code (as a zero-padded string, so it's
  /// always exactly 6 digits — e.g. "003491", never "3491") and returns
  /// it. The caller is responsible for remembering this value to compare
  /// against what the user types back in — nothing is stored anywhere
  /// beyond that (no Firestore doc, no server), so it only lives for as
  /// long as the registration screen stays open.
  static String generateCode() {
    final code = Random.secure().nextInt(1000000); // 0–999999
    return code.toString().padLeft(6, '0');
  }

  /// Sends [code] to [toEmail] via the configured EmailJS template. This
  /// matches the field names used by EmailJS's own "One-Time Password"
  /// starter template — `{{email}}` for the recipient and `{{passcode}}`
  /// for the code itself, plus `{{time}}` for the "valid until" line it
  /// shows. If you swap in a different template with different variable
  /// names, update the keys below to match.
  ///
  /// Throws a plain [Exception] with a human-readable message on failure
  /// (bad credentials, network error, EmailJS quota hit, etc).
  static Future<void> sendCode({required String toEmail, required String code}) async {
    if (serviceId == "" || templateId == "" || publicKey == "") {
      throw Exception("EmailJS isn't configured yet — fill in serviceId/templateId/publicKey in emailjs_service.dart.");
    }

    final validUntil = DateTime.now().add(const Duration(minutes: 15));
    final validUntilLabel =
        "${validUntil.hour % 12 == 0 ? 12 : validUntil.hour % 12}:${validUntil.minute.toString().padLeft(2, '0')} ${validUntil.hour >= 12 ? 'PM' : 'AM'}";

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': publicKey,
        'template_params': {
          'email': toEmail,
          'passcode': code,
          'time': validUntilLabel,
        },
      }),
    ).timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw Exception(
          "Sending the email timed out. Check your internet connection and try again."),
    );

    if (response.statusCode != 200) {
      throw Exception("Couldn't send the email (${response.statusCode}): ${response.body}");
    }
  }
}