import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/send_cooldown.dart';
import '../services/emailjs_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'otp_code_field.dart';

/// Self-contained "enter the emailed code" dialog (centered on screen). Generates a
/// 6-digit code, sends it via EmailJS to [email] as soon as it opens,
/// and lets the user type it back in. The correct code only ever lives
/// in this widget's local state — never written to Firestore or any
/// server — so there's nothing to clean up afterward and nothing a
/// signed-out user could ever read back later.
///
/// [onVerified] is expected to actually finish creating the account
/// (calling `AuthService.register(...)`) — if it throws, this sheet
/// shows the error inline and stays open so the user doesn't need a
/// whole new email just to fix an unrelated problem (e.g. a weak
/// password). Only pops (with `true`) once [onVerified] completes
/// without throwing.
Future<bool?> showOtpVerificationSheet(
  BuildContext context, {
  required String email,
  required Future<void> Function() onVerified,
  String title = "Verify your email",
  String buttonLabel = "Verify & Create Account",
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _OtpSheet(email: email, onVerified: onVerified, title: title, buttonLabel: buttonLabel),
  );
}

class _OtpSheet extends StatefulWidget {
  const _OtpSheet({required this.email, required this.onVerified, required this.title, required this.buttonLabel});

  final String email;
  final Future<void> Function() onVerified;
  final String title;
  final String buttonLabel;

  @override
  State<_OtpSheet> createState() => _OtpSheetState();
}

class _OtpSheetState extends State<_OtpSheet> {
  final _codeController = TextEditingController();
  String? _correctCode;
  String? _error;
  bool _sending = true; // sending the initial email
  bool _verifying = false; // checking a submitted code
  int _resendSeconds = 30;
  Timer? _resendTimer;

  static const int _maxWrongTries = 5;
  static const Duration _resendCooldown = Duration(seconds: 30);

  String get _key => 'otp:${SendCooldown.norm(widget.email)}';

  @override
  void initState() {
    super.initState();
    // Re-opened within the cooldown? Reuse the code that was just emailed
    // and keep the countdown running instead of mailing another one.
    final left = SendCooldown.remainingSeconds(_key);
    final saved = SendCooldown.codes[_key];
    if (left > 0 && saved != null) {
      _correctCode = saved;
      _sending = false;
      _startResendCooldown(left);
    } else {
      _send();
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _send() async {
    // Throttle: one send per cooldown window (survives closing the sheet).
    final left = SendCooldown.remainingSeconds(_key);
    if (left > 0) {
      setState(() {
        _sending = false;
        _error = "Please wait ${left}s before requesting a new code.";
      });
      _startResendCooldown(left);
      return;
    }
    // Throttle: at most 5 codes per hour for the same email.
    final waitMin = SendCooldown.hourlyWaitMinutes(_key);
    if (waitMin != null) {
      setState(() {
        _sending = false;
        _error = "Too many codes requested. Please try again in $waitMin min.";
      });
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    // The cooldown starts the moment we try to send — even if the send
    // fails — so the button can't be hammered.
    SendCooldown.record(_key);
    SendCooldown.start(_key, _resendCooldown);
    _startResendCooldown(_resendCooldown.inSeconds);
    final code = EmailJsService.generateCode();
    try {
      await EmailJsService.sendCode(toEmail: widget.email, code: code);
      if (!mounted) return;
      SendCooldown.codes[_key] = code;
      SendCooldown.wrongTries[_key] = 0;
      setState(() {
        _correctCode = code;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _submit() async {
    final typed = _codeController.text.trim();
    if (typed.length != 6) {
      setState(() => _error = "Enter the 6-digit code.");
      return;
    }
    if (_correctCode == null) {
      setState(() => _error = "Request a new code first.");
      return;
    }
    if (typed != _correctCode) {
      final tries = (SendCooldown.wrongTries[_key] ?? 0) + 1;
      SendCooldown.wrongTries[_key] = tries;
      setState(() {
        if (tries >= _maxWrongTries) {
          // Too many guesses: throw this code away, a new one is needed.
          _correctCode = null;
          SendCooldown.codes.remove(_key);
          _error = "Too many wrong tries. Please request a new code.";
        } else {
          _error = "That code doesn't match — ${_maxWrongTries - tries} ${_maxWrongTries - tries == 1 ? 'try' : 'tries'} left.";
        }
        _codeController.clear();
      });
      return;
    }

    setState(() {
      _verifying = true;
      _error = null;
    });

    try {
      await widget.onVerified();
      SendCooldown.codes.remove(_key);
      SendCooldown.wrongTries.remove(_key);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.cardBg(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.mail_outline, color: AppColors.accent, size: 26),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
            ),
            const SizedBox(height: 6),
            Text(
              _sending ? "Sending a code to ${widget.email}…" : "Enter the 6-digit code sent to ${widget.email}.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(context)),
            ),
            const SizedBox(height: 22),
            if (_sending)
              const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 12), child: CircularProgressIndicator(strokeWidth: 2)))
            else ...[
              OtpCodeField(
                controller: _codeController,
                enabled: !_verifying,
                onSubmitted: _submit,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline, size: 16, color: Color(0xFFE5484D)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)))),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _verifying ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _verifying
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                      : Text(widget.buttonLabel, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: _resendSeconds > 0 || _verifying || _sending ? null : _send,
                  child: Text(
                    _resendSeconds > 0 ? "Resend code in ${_resendSeconds}s" : "Resend code",
                    style: TextStyle(fontSize: 12.5, color: _resendSeconds > 0 ? AppPalette.textMuted(context) : AppColors.accent),
                  ),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}