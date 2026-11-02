import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/admin_push_service.dart';
import '../../shared/send_cooldown.dart';
import '../../shared/reset_daily_limit.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'admin_dashboard_screen.dart';

/// Entry point for the Admin app. A separate app/project from the
/// customer app and from the Staff app — its own build, its own URL.
/// Anyone who signs in here gets full access.
///
/// Same split-screen look as the Staff login: a bold, oversized headline
/// on a flat accent-colored panel (its content fades/slides in with a
/// staggered entrance when the screen opens), the sign-in form grounded in
/// a soft white card on the other side. Collapses to a single centered
/// column on narrow/mobile widths.
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;
  bool _revealed = false;

  static final _emailPattern = RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$');

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return "Email is required.";
    if (!_emailPattern.hasMatch(v)) return "Enter a valid email address.";
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return "Password is required.";
    if (v.length < 6) return "Password must be at least 6 characters.";
    return null;
  }

  @override
  void initState() {
    super.initState();
    _restoreEmail();
    _emailController.addListener(_saveEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) setState(() => _revealed = true);
      });
    });
  }

  // Only the email is remembered between refreshes. The password is never
  // stored and is always typed again.
  static const _emailKey = 'admin_login_email_v1';

  Future<void> _restoreEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_emailKey);
      if (!mounted || saved == null || _emailController.text.isNotEmpty) return;
      _emailController.text = saved;
    } catch (_) {}
  }

  Future<void> _saveEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_emailKey, _emailController.text.trim());
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AdminService.instance.signIn(email: email, password: password);

      final isAdmin = await AdminService.instance.isCurrentUserAdmin();
      if (!isAdmin) {
        await AdminService.instance.signOutAdmin();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = "This account doesn't have admin access.";
        });
        return;
      }

      if (!mounted) return;
      AdminPushService.register();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [const Color(0xFF121212), const Color(0xFF121212)]
                : [AppColors.brandCream.withValues(alpha: 0.55), Colors.white],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 900;
              if (isWide) {
                return Row(
                  children: [
                    Expanded(flex: 6, child: _HeroPanel(revealed: _revealed)),
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: _reveal(_formCard(context)),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              // Mobile: one centered column — small logo mark up top,
              // then the form card, everything vertically centered.
              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: AppColors.brandCream, borderRadius: BorderRadius.circular(14)),
                          child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
                        ),
                        const SizedBox(height: 32),
                        _reveal(_formCard(context, centered: true)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _reveal(Widget child) {
    return AnimatedOpacity(
      opacity: _revealed ? 1 : 0,
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _revealed ? Offset.zero : const Offset(0, 0.04),
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  /// The form, grounded in a soft white card with a gentle shadow so it
  /// reads as a distinct surface rather than floating on plain white.
  Widget _formCard(BuildContext context, {bool centered = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card,
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: _buildForm(context, centered: centered),
    );
  }

  Widget _buildForm(BuildContext context, {bool centered = false}) {
    final crossAxis = centered ? CrossAxisAlignment.center : CrossAxisAlignment.stretch;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    return Form(
      key: _formKey,
      child: Column(
      crossAxisAlignment: crossAxis,
      children: [
        Text(
          "Welcome back",
          textAlign: textAlign,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
        ),
        const SizedBox(height: 6),
        Text(
          "Sign in to manage bookings, staff & pricing.",
          textAlign: textAlign,
          style: TextStyle(fontSize: 13, color: AppPalette.textSecondary(context)),
        ),
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Text("Email", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: _validateEmail,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
          decoration: InputDecoration(
            hintText: "you@gmail.com",
            hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
            filled: true,
            fillColor: AppPalette.surface(context),
            prefixIcon: Icon(Icons.mail_outline, size: 18, color: AppPalette.textMuted(context)),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.2)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.accent),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Text("Password", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          validator: _validatePassword,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          onFieldSubmitted: (_) => _submit(),
          style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
          decoration: InputDecoration(
            hintText: "Your password",
            hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
            filled: true,
            fillColor: AppPalette.surface(context),
            prefixIcon: Icon(Icons.lock_outline, size: 18, color: AppPalette.textMuted(context)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18, color: AppPalette.textMuted(context)),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.2)),
            focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.accent, width: 1.4)),
            errorStyle: const TextStyle(fontSize: 11.5, color: AppColors.accent),
          ),
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
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _error == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error ?? '', style: const TextStyle(fontSize: 12, color: AppColors.accent))),
                      ],
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
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
                : const Text("Sign In", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Admin accounts are provisioned by the platform owner.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
        ),
      ],
      ),
    );
  }
}

/// Accent-colored hero panel with big, bold display type — plain flat
/// maroon field, same as the Staff login. Everything (logo, badge, headline,
/// body text) fades/slides in with a short stagger the moment the screen
/// opens, driven by [revealed].
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.revealed});

  final bool revealed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.accent,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _staggered(
                    delayMs: 0,
                    child: Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: AppShadows.soft,
                      ),
                      child: Image.asset('assets/images/memoriae_logo.webp', fit: BoxFit.contain),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _staggered(
                    delayMs: 70,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        "ADMIN PORTAL",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 0.8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _staggered(
                    delayMs: 140,
                    child: const Text(
                      "Manage it all,\nrun the show.",
                      style: TextStyle(
                        fontSize: 56,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _staggered(
                    delayMs: 220,
                    child: const SizedBox(
                      width: 360,
                      child: Text(
                        "Bookings, staff accounts, pricing and camera rentals — all in one dashboard built for the people who keep Memoriae running.",
                        style: TextStyle(fontSize: 14.5, height: 1.55, color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staggered({required int delayMs, required Widget child}) {
    return AnimatedOpacity(
      opacity: revealed ? 1 : 0,
      duration: Duration(milliseconds: 520 + delayMs),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: revealed ? Offset.zero : const Offset(0, 0.08),
        duration: Duration(milliseconds: 520 + delayMs),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}

/// Opens the "Forgot password?" dialog, pre-filled with whatever was
/// already typed into the email field. Sends a real Firebase reset-link
/// email via `AdminService.sendPasswordReset` — no code to type, the person
/// just taps the link in their inbox and picks a new password.
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
    if (!await ResetDailyLimit.canRequest(_emailController.text)) {
      if (!mounted) return;
      setState(() => _error = ResetDailyLimit.limitMessage);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AdminService.instance.sendPasswordReset(_emailController.text);
      await ResetDailyLimit.recordRequest(_emailController.text);
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
                      hintText: "you@gmail.com",
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
