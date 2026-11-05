import 'dart:async';
import 'package:flutter/material.dart';
import '../../shared/send_cooldown.dart';
import '../services/auth_service.dart';
import '../services/connection_test.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'register_screen.dart';
import '../widgets/otp_verification_sheet.dart';
import '../widgets/circle_back_button.dart';

/// Sign-in screen for the customer app, styled to match the rest of the
/// app (gradient accent hero with the Memoriae logo, rounded surfaces,
/// accent glow on the primary button) instead of a plain generic form.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.prefillEmail, this.successNotice});

  /// Pre-fills the email field (used right after registering).
  final String? prefillEmail;

  /// Green banner shown above the form (e.g. "Account created").
  final String? successNotice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.prefillEmail != null) _emailController.text = widget.prefillEmail!;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = "Enter your email and password.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.login(email: email, password: password);
      if (!mounted) return;

      // Password was right — now check whether the 30-day verification
      // window has run out. If so, ask for a fresh emailed code.
      if (await AuthService.instance.isOtpDue()) {
        if (!mounted) return;
        final verified = await showOtpVerificationSheet(
          context,
          email: email,
          title: "Verify it's you",
          buttonLabel: "Verify & Log In",
          onVerified: () => AuthService.instance.markVerifiedNow(),
        );
        if (!mounted) return;
        if (verified != true) {
          await AuthService.instance.logout();
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = "Verification is required to log in. Please try again.";
          });
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      CircleBackButton(),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildHero(context),
                  if (widget.successNotice != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(widget.successNotice!, style: const TextStyle(fontSize: 12, color: Colors.green))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    "Email",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)),
                  ),
                  const SizedBox(height: 6),
                  _field(
                    context,
                    controller: _emailController,
                    hint: "you@email.com",
                    icon: Icons.mail_outline,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Password",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)),
                  ),
                  const SizedBox(height: 6),
                  _field(
                    context,
                    controller: _passwordController,
                    hint: "Your password",
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                    onToggleObscure: () => setState(() => _obscure = !_obscure),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _loading ? null : () => _showForgotPasswordDialog(context, _emailController.text),
                      style: TextButton.styleFrom(padding: const EdgeInsets.only(top: 8), minimumSize: const Size(0, 0)),
                      child: const Text(
                        "Forgot password?",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.accent))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text("Log In", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: GestureDetector(
                      onTap: _loading
                          ? null
                          : () {
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              );
                            },
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                          children: const [
                            TextSpan(text: "Don't have an account? "),
                            TextSpan(text: "Register", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton.icon(
                      onPressed: _loading
                          ? null
                          // Straight in — no form. Name/email/phone are only
                          // asked for later, at booking time (see
                          // PhotoboothBookingScreen._handleBookNow).
                          : () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.flash_on, size: 16, color: AppColors.accent),
                      label: const Text(
                        "Browse as Guest",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => showConnectionTestDialog(context),
                      child: const Text(
                        "Connection test",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, Color(0xFF9A3236)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.accentGlow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(Icons.camera_alt, size: 90, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(16)),
                child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
              ),
              const SizedBox(height: 16),
              const Text(
                "Welcome Back",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
              ),
              const SizedBox(height: 6),
              Text(
                "Log in to manage your bookings.",
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscure = false,
    VoidCallback? onToggleObscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
        filled: true,
        fillColor: AppPalette.surface(context),
        prefixIcon: Icon(icon, size: 18, color: AppPalette.textMuted(context)),
        suffixIcon: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: AppPalette.textMuted(context)),
                onPressed: onToggleObscure,
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      ),
    );
  }
}

/// Opens the "Forgot password?" dialog, pre-filled with whatever the
/// person had already typed into the email field on the login screen (if
/// anything). Sends a real reset-link email via
/// `AuthService.sendPasswordReset` — no OTP code, just Firebase's
/// built-in link flow.
Future<void> _showForgotPasswordDialog(BuildContext context, String prefillEmail) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ForgotPasswordDialog(prefillEmail: prefillEmail),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  final String prefillEmail;
  const _ForgotPasswordDialog({required this.prefillEmail});

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _emailController;
  bool _sending = false;
  bool _sent = false;
  String? _error;
  Timer? _ticker;

  static const Duration _cooldown = Duration(seconds: 60);

  String get _key => 'reset:${SendCooldown.norm(_emailController.text)}';
  int get _waitSeconds => SendCooldown.remainingSeconds(_key);

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.prefillEmail);
    // Re-draw once a second so the "Send again in 45s" label counts down.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final left = _waitSeconds;
    if (left > 0) {
      setState(() => _error = "Please wait ${left}s before sending another link.");
      return;
    }
    final waitMin = SendCooldown.hourlyWaitMinutes(_key);
    if (waitMin != null) {
      setState(() => _error = "Too many reset links requested. Please try again in $waitMin min.");
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AuthService.instance.sendPasswordReset(_emailController.text);
      SendCooldown.record(_key);
      SendCooldown.start(_key, _cooldown);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text("Forgot Password"),
      content: SizedBox(
        width: 340,
        child: _sent
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.mark_email_read_outlined, color: AppColors.accent, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    "If ${_emailController.text.trim()} has an account, a reset link is on its way — check your inbox (and spam folder).",
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Enter your account email and we'll send you a link to reset your password.",
                    style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "you@email.com",
                      hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
                      filled: true,
                      fillColor: AppPalette.surface(context),
                      prefixIcon: Icon(Icons.mail_outline, size: 18, color: AppPalette.textMuted(context)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                  ],
                ],
              ),
      ),
      actions: _sent
          ? [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Done"),
              ),
            ]
          : [
              TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text("Cancel")),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                onPressed: (_sending || _waitSeconds > 0) ? null : _send,
                child: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_waitSeconds > 0 ? "Send again in ${_waitSeconds}s" : "Send Link"),
              ),
            ],
    );
  }
}
