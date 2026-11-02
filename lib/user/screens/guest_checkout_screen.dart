import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../../shared/text_draft.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Fast, password-free registration used during checkout when someone
/// doesn't want to create a full account. Collects just enough to tie a
/// booking to a real person: First Name, Last Name, Email, Phone.
///
/// In a full backend this would also send a magic login link so the
/// guest can manage/cancel the booking later — that needs real email
/// infrastructure, so for now the screen just explains that the booking
/// will be looked up by the email address provided.
class GuestCheckoutScreen extends StatefulWidget {
  const GuestCheckoutScreen({super.key});

  @override
  State<GuestCheckoutScreen> createState() => _GuestCheckoutScreenState();
}

class _GuestCheckoutScreenState extends State<GuestCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _loading = false;
  String? _error;

  late final TextDraft _draft;

  @override
  void initState() {
    super.initState();
    _draft = TextDraft('guest_checkout_draft_v1', {
      'first': _firstNameController,
      'last': _lastNameController,
      'email': _emailController,
      'phone': _phoneController,
    });
    _draft.restore(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateFirstName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your first name.";
    if (!RegExp(r"^[a-zA-ZñÑ .'\-]+$").hasMatch(value)) return "Letters only, please.";
    return null;
  }

  String? _validateLastName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your last name.";
    if (!RegExp(r"^[a-zA-ZñÑ .'\-]+$").hasMatch(value)) return "Letters only, please.";
    return null;
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your email.";
    if (!RegExp(r"^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$").hasMatch(value)) return "Enter a valid email address.";
    return null;
  }

  String? _validatePhone(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your phone number.";
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!RegExp(r'^(?:\+63|0)9\d{9}$').hasMatch(digitsOnly)) {
      return "Enter a valid PH mobile number (e.g. 09171234567).";
    }
    return null;
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthService.instance.registerGuest(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
      );
      await _draft.clear();
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
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.arrow_back, color: AppPalette.textPrimary(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildHero(context),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, "First Name"),
                              const SizedBox(height: 6),
                              _field(
                                context,
                                controller: _firstNameController,
                                hint: "Juan",
                                icon: Icons.person_outline,
                                validator: _validateFirstName,
                                inputFormatters: _nameFormatters,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _label(context, "Last Name"),
                              const SizedBox(height: 6),
                              _field(
                                context,
                                controller: _lastNameController,
                                hint: "Dela Cruz",
                                icon: Icons.person_outline,
                                validator: _validateLastName,
                                inputFormatters: _nameFormatters,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label(context, "Email"),
                    const SizedBox(height: 6),
                    _field(
                      context,
                      controller: _emailController,
                      hint: "you@email.com",
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    _label(context, "Phone Number"),
                    const SizedBox(height: 6),
                    _field(
                      context,
                      controller: _phoneController,
                      hint: "09171234567",
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: AppPalette.textMuted(context)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              "No password needed. We'll use this email to look up your booking later "
                              "if you want to manage or cancel it.",
                              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppPalette.textMuted(context)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.accentTint(0.08), borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: Color(0xFFE5484D)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)))),
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
                          foregroundColor: AppColors.onAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                              )
                            : const Text("Continue as Guest", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)));
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8A2429), Color(0xFF3A1214)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.accentGlow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -18,
            child: Icon(Icons.flash_on, size: 90, color: Colors.white.withValues(alpha: 0.08)),
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
                "Quick Guest Checkout",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
              ),
              const SizedBox(height: 6),
              Text(
                "Book in seconds — no account or password required.",
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Same rule as the Register screen: letters, spaces, . ' - only, and typing
  /// stops once the name reaches 20 characters.
  static const int _maxNameLength = 20;
  static final List<TextInputFormatter> _nameFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑ .'\-]")),
    LengthLimitingTextInputFormatter(_maxNameLength),
  ];

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      inputFormatters: inputFormatters,
      style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
        filled: true,
        fillColor: AppPalette.surface(context),
        prefixIcon: Icon(icon, size: 18, color: AppPalette.textMuted(context)),
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.red.shade300)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.red.shade400)),
        errorStyle: const TextStyle(fontSize: 11),
      ),
    );
  }
}
