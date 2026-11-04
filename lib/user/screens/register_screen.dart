import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../shared/birthdate_picker.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/otp_verification_sheet.dart';
import 'info_pages.dart';
import 'login_screen.dart';
import '../widgets/circle_back_button.dart';

/// Sign-up screen for the customer app, styled to match the rest of the
/// app (gradient accent hero with the Memoriae logo, rounded surfaces,
/// accent glow on the primary button) instead of a plain generic form.
///
/// Every field is validated: Full Name, Email, Contact Number, Birthdate,
/// Password, and Confirm Password all have their own inline error message
/// via a `Form` + `TextFormField`/`FormField` — submit is blocked until
/// all of them pass.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _middleInitialController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _confirmKey = GlobalKey<FormFieldState<String>>();
  // Each field gets its own key and is checked when the person leaves it, so
  // errors never show before the field has been used.
  final Map<TextEditingController, GlobalKey<FormFieldState<String>>> _fieldKeys = {};
  final Set<TextEditingController> _touched = {};

  String _suffix = ''; // '' = none, otherwise one of [_suffixOptions]
  DateTime? _birthDate;
  bool _obscure = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  String? _error;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleInitialController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  static int _ageOn(DateTime birthDate, DateTime today) {
    int age = today.year - birthDate.year;
    final hadBirthdayThisYear =
        (today.month > birthDate.month) || (today.month == birthDate.month && today.day >= birthDate.day);
    if (!hadBirthdayThisYear) age--;
    return age;
  }

  /// Youngest age allowed to register.
  static const int _minAge = 10;

  /// Max characters allowed in the First Name and Last Name fields.
  static const int _maxNameLength = 20;

  // ---- Field validators ----

  static const List<String> _suffixOptions = ['Jr.', 'Sr.', 'II', 'III', 'IV', 'V'];

  static final RegExp _nameChars = RegExp(r"^[a-zA-ZñÑ][a-zA-ZñÑ .'\-]*$");

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Capitalises the first letter of every word ("dela cruz" -> "Dela Cruz")
  /// and collapses stray spaces, but leaves the rest of each word alone so
  /// names like "McDonald" aren't mangled.
  static String _tidyName(String input) {
    return input
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Obvious placeholder / keyboard-mash names nobody actually has.
  static const Set<String> _fakeNames = {
    'test', 'tester', 'testing', 'asdf', 'asdfg', 'asdfgh', 'asdfghjkl', 'qwerty', 'qwe', 'qwert',
    'sample', 'none', 'name', 'firstname', 'lastname', 'unknown', 'dummy', 'fake', 'abc', 'xyz',
    'wala', 'lorem', 'ipsum', 'sdfg', 'zxcv', 'zxcvb',
  };

  String? _validateName(String? v, String label) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your $label.";
    final letters = value.replaceAll(RegExp(r"[^a-zA-ZñÑ]"), '');
    if (letters.length < 2) return "${_cap(label)} is too short.";
    if (value.length > _maxNameLength) return "${_cap(label)} is too long (max $_maxNameLength characters).";
    if (!_nameChars.hasMatch(value)) {
      return "${_cap(label)} must start with a letter and only use letters, spaces, and - ' .";
    }
    if (RegExp(r'\s{2,}').hasMatch(value)) return "Remove the extra spaces in your $label.";
    // "d s s s s" — spaced-out single letters. Every part of the name
    // (split on spaces) needs at least two letters.
    final parts = value.split(' ').where((w) => w.isNotEmpty);
    if (parts.any((w) => w.replaceAll(RegExp(r"[^a-zA-ZñÑ]"), '').length < 2)) {
      return "Each part of your $label needs at least 2 letters.";
    }
    if (parts.any((w) => _fakeNames.contains(w.toLowerCase().replaceAll(RegExp(r"[^a-zA-ZñÑ]"), '')))) {
      return "Please enter your real $label.";
    }
    // "aaa", "xxxx" etc. — nobody's name has the same letter three times in a row.
    if (RegExp(r'([a-zA-ZñÑ])\1{2,}', caseSensitive: false).hasMatch(value)) {
      return "That doesn't look like a valid $label.";
    }
    return null;
  }

  String? _validateFirstName(String? v) => _validateName(v, 'first name');

  String? _validateLastName(String? v) => _validateName(v, 'last name');

  // Middle initial is optional — one letter, with or without a trailing period.
  String? _validateMiddleInitial(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    if (!RegExp(r"^[a-zA-ZñÑ]\.?$").hasMatch(value)) {
      return "One letter only.";
    }
    return null;
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your email.";
    if (value.length > 254) return "Email is too long.";
    if (RegExp(r'\s').hasMatch(value)) return "Email can't contain spaces.";
    if (value.contains('..')) return "Email can't have two dots in a row.";
    final atIndex = value.indexOf('@');
    if (atIndex > 0 && value.substring(0, atIndex).endsWith('.')) {
      return "Enter a valid email address.";
    }
    if (!RegExp(
      r"^[A-Za-z0-9][A-Za-z0-9._%+\-]*@(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$",
    ).hasMatch(value)) {
      return "Enter a valid email address.";
    }
    final suggestion = _suggestEmailFix(value);
    if (suggestion != null) return "Did you mean $suggestion?";
    return null;
  }

  /// Common domain typos -> the domain people almost certainly meant.
  static const Map<String, String> _domainTypos = {
    'gmial.com': 'gmail.com', 'gmai.com': 'gmail.com', 'gmal.com': 'gmail.com', 'gamil.com': 'gmail.com',
    'gmaill.com': 'gmail.com', 'gmail.co': 'gmail.com', 'gmail.cm': 'gmail.com', 'gmil.com': 'gmail.com',
    'gnail.com': 'gmail.com', 'yaho.com': 'yahoo.com', 'yahho.com': 'yahoo.com', 'yahoo.co': 'yahoo.com',
    'yahooo.com': 'yahoo.com', 'hotmial.com': 'hotmail.com', 'hotmal.com': 'hotmail.com',
    'outlok.com': 'outlook.com', 'outloo.com': 'outlook.com', 'iclod.com': 'icloud.com', 'icoud.com': 'icloud.com',
  };

  /// Returns the corrected address if the domain looks like a typo of a
  /// well-known provider (or ends in ".con"), otherwise null.
  static String? _suggestEmailFix(String email) {
    final at = email.lastIndexOf('@');
    if (at < 1) return null;
    final local = email.substring(0, at);
    final domain = email.substring(at + 1).toLowerCase();
    final fixed = _domainTypos[domain];
    if (fixed != null) return '$local@$fixed';
    if (domain.endsWith('.con')) return '$local@${domain.substring(0, domain.length - 1)}m';
    return null;
  }

  String? _validateContact(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return "Please enter your contact number.";
    if (!value.startsWith('09')) return "Mobile number must start with 09 (e.g. 09171234567).";
    if (value.length != 11) return "Mobile number must be exactly 11 digits.";
    // 09999999999, 09111111111 … obviously fake.
    if (RegExp(r'^09(\d)\1{8}$').hasMatch(value)) return "That doesn't look like a real mobile number.";
    return null;
  }

  // ---- Password rules ----

  static const List<String> _commonPasswords = [
    'password', 'passw0rd', 'p@ssw0rd', 'p@ssword', '12345678', '123456789',
    'qwerty', 'qwertyuiop', 'iloveyou', 'admin123', 'welcome', 'letmein',
    'abc12345', 'monkey', 'dragon', 'football', 'baseball',
    'memoriae', 'photobooth',
  ];

  List<_PwRule> _passwordRules(String v) => [
        _PwRule('8+ characters', v.length >= 8),
        _PwRule('Uppercase (A-Z)', RegExp(r'[A-Z]').hasMatch(v)),
        _PwRule('Lowercase (a-z)', RegExp(r'[a-z]').hasMatch(v)),
        _PwRule('Number (0-9)', RegExp(r'[0-9]').hasMatch(v)),
        _PwRule('Symbol (! @ # ?)', RegExp(r'[^A-Za-z0-9\s]').hasMatch(v)),
      ];

  /// 4+ letters/digits in a row going up or down by one ("1234", "abcd", "9876").
  static bool _hasSequence(String input) {
    final lower = input.toLowerCase();
    bool isAlnum(int c) => (c >= 48 && c <= 57) || (c >= 97 && c <= 122);
    int run = 1;
    int dir = 0;
    for (int i = 1; i < lower.length; i++) {
      final a = lower.codeUnitAt(i - 1);
      final b = lower.codeUnitAt(i);
      final diff = b - a;
      if (isAlnum(a) && isAlnum(b) && (diff == 1 || diff == -1)) {
        if (dir == diff) {
          run++;
        } else {
          run = 2;
          dir = diff;
        }
      } else {
        run = 1;
        dir = 0;
      }
      if (run >= 4) return true;
    }
    return false;
  }

  /// Checks beyond the five basic rules: too common, repeated characters,
  /// easy sequences, or built from the person's own name / email.
  String? _passwordExtraProblem(String value) {
    final lower = value.toLowerCase();
    if (_commonPasswords.any((w) => lower.contains(w))) {
      return "That password is too common. Pick something harder to guess.";
    }
    if (RegExp(r'(.)\1{3,}').hasMatch(value)) {
      return "Avoid repeating the same character 4+ times in a row.";
    }
    if (_hasSequence(value)) {
      return "Avoid easy sequences like 1234 or abcd.";
    }
    final year = _birthDate?.year.toString();
    if (year != null && lower.contains(year)) {
      return "Password shouldn't contain your birth year.";
    }
    final contact = _contactController.text.trim();
    if (contact.length >= 7 && (lower.contains(contact) || lower.contains(contact.substring(contact.length - 7)))) {
      return "Password shouldn't contain your phone number.";
    }
    final parts = [
      _emailController.text.trim().split('@').first,
      _firstNameController.text,
      _lastNameController.text,
    ];
    for (final part in parts) {
      final clean = part.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (clean.length >= 3 && lower.contains(clean)) {
        return "Password shouldn't contain your name or email.";
      }
    }
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return "Please enter a password.";
    if (value.length < 8) return "Password must be at least 8 characters.";
    if (value.length > 64) return "Password is too long (max 64 characters).";
    if (RegExp(r'\s').hasMatch(value)) return "Password can't contain spaces.";
    if (!RegExp(r'[A-Z]').hasMatch(value)) return "Add at least one uppercase letter (A-Z).";
    if (!RegExp(r'[a-z]').hasMatch(value)) return "Add at least one lowercase letter (a-z).";
    if (!RegExp(r'[0-9]').hasMatch(value)) return "Add at least one number (0-9).";
    if (!RegExp(r'[^A-Za-z0-9\s]').hasMatch(value)) return "Add at least one symbol (like ! @ # ?).";
    return _passwordExtraProblem(value);
  }

  /// 0 = empty, 1 = weak, 2 = fair, 3 = good, 4 = strong.
  int _passwordStrength(String v) {
    if (v.isEmpty) return 0;
    if (v.length < 8) return 1;
    final met = _passwordRules(v).where((r) => r.met).length;
    if (met <= 2) return 1;
    if (met < 5) return 2;
    if (RegExp(r'\s').hasMatch(v) || _passwordExtraProblem(v) != null) return 2;
    return v.length >= 12 ? 4 : 3;
  }

  String? _validateConfirm(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return "Please confirm your password.";
    if (value != _passwordController.text) return "Passwords don't match.";
    return null;
  }

  String? _validateBirthDate(DateTime? value) {
    if (value == null) return "Please select your birthdate.";
    if (value.isAfter(DateTime.now())) return "Birthdate can't be in the future.";
    if (value.year < 1970) return "Birth year must be 1970 or later.";
    if (_ageOn(value, DateTime.now()) < _minAge) return "You must be at least $_minAge years old to register.";
    return null;
  }

  Future<void> _pickBirthDate(ValueChanged<DateTime> onPicked) async {
    final now = DateTime.now();
    // The picker blocks anyone younger than [_minAge] (calendar and typing).
    final picked = await showBirthDatePicker(
      context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1970),
      minAge: _minAge,
      helpText: "Select your birthdate",
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _submit() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      setState(() => _error = null);
      return;
    }
    if (!_agreedToTerms) {
      setState(() => _error = "Please agree to the Terms of Service and Privacy Policy to continue.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    // Check for an existing (non-guest) account with this email *before*
    // sending an OTP — otherwise someone re-registering with an email
    // they already used gets a real code, types it back correctly, and
    // only then finds out registration fails. Catching it here means
    // no wasted email and no confusing "verified but rejected" moment.
    final alreadyRegistered = await AuthService.instance.emailHasAccount(_emailController.text.trim());
    if (!mounted) return;
    if (alreadyRegistered) {
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.error_outline, color: Color(0xFFE5484D), size: 32),
          title: const Text("Account Already Exists", textAlign: TextAlign.center),
          content: const Text(
            "There's already an account registered with that email. Try logging in instead, or use a different email to sign up.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Use a Different Email"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
              child: const Text("Log In"),
            ),
          ],
        ),
      );
      return;
    }

    // Email is verified via a real one-time code before the account is
    // created at all — the bottom sheet below sends the code, and only
    // calls AuthService.register (wired in as onVerified) once the user
    // has typed the matching code.
    final verified = await showOtpVerificationSheet(
      context,
      email: _emailController.text.trim(),
      onVerified: () async {
        final firstName = _tidyName(_firstNameController.text);
        final lastName = _tidyName(_lastNameController.text);
        final middleInitial = _middleInitialController.text.trim().replaceAll('.', '');
        // First Name, Middle Initial, Last Name and Suffix are separate fields
        // on the form, but they're still stitched into one combined "fullName"
        // string (e.g. "Juan D. Cruz Jr.") since that's what the rest of the
        // app expects.
        final base = middleInitial.isEmpty ? "$firstName $lastName" : "$firstName ${middleInitial.toUpperCase()}. $lastName";
        final fullName = _suffix.isEmpty ? base : "$base $_suffix";

        await AuthService.instance.register(
          fullName: fullName,
          email: _emailController.text.trim(),
          password: _passwordController.text,
          birthDate: _birthDate!,
          contactNumber: _contactController.text.trim(),
          emailVerified: true,
          termsVersion: kPoliciesVersion,
        );
      },
    );

    if (!mounted) return;

    if (verified == true) {
      // Account is created but the person is signed out on purpose —
      // send them straight to the login page (email pre-filled) instead
      // of dropping them into the app.
      final loggedIn = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LoginScreen(
            prefillEmail: _emailController.text.trim(),
            successNotice: "Account created! Log in to continue.",
          ),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(loggedIn == true); // true = logged in, so the caller can open the app
      return;
    }

    // Sheet was dismissed without completing (back button, tapped outside,
    // or gave up after an error) — let them try Create Account again.
    setState(() => _loading = false);
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
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                      const CircleBackButton(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildHero(context),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label(context, "First Name"),
                              const SizedBox(height: 8),
                              _field(
                                context,
                                controller: _firstNameController,
                                hint: "Juan",
                                icon: Icons.person_outline,
                                validator: _validateFirstName,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: _nameFormatters,
                                maxLength: _maxNameLength,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label(context, "M.I."),
                              const SizedBox(height: 8),
                              _field(
                                context,
                                controller: _middleInitialController,
                                hint: "D",
                                icon: Icons.short_text,
                                validator: _validateMiddleInitial,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑ]")),
                                  LengthLimitingTextInputFormatter(1),
                                ],
                                maxLength: 1,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label(context, "Last Name"),
                              const SizedBox(height: 8),
                              _field(
                                context,
                                controller: _lastNameController,
                                hint: "Dela Cruz",
                                icon: Icons.person_outline,
                                validator: _validateLastName,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: _nameFormatters,
                                maxLength: _maxNameLength,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _label(context, "Suffix"),
                              const SizedBox(height: 8),
                              _buildSuffixField(context),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label(context, "Email"),
                    const SizedBox(height: 8),
                    _field(
                      context,
                      controller: _emailController,
                      hint: "you@email.com",
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      validator: _validateEmail,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(254),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label(context, "Contact Number"),
                    const SizedBox(height: 8),
                    _field(
                      context,
                      controller: _contactController,
                      hint: "09171234567",
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: _validateContact,
                      inputFormatters: [_PhNumberFormatter(), LengthLimitingTextInputFormatter(11)],
                      maxLength: 11,
                    ),
                    const SizedBox(height: 18),
                    _label(context, "Birthdate"),
                    const SizedBox(height: 8),
                    _buildBirthDateField(context),
                    const SizedBox(height: 18),
                    _label(context, "Password"),
                    const SizedBox(height: 8),
                    _field(
                      context,
                      controller: _passwordController,
                      hint: "At least 8 characters",
                      icon: Icons.lock_outline,
                      obscure: _obscure,
                      onToggleObscure: () => setState(() => _obscure = !_obscure),
                      validator: _validatePassword,
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(RegExp(r'\s')),
                        LengthLimitingTextInputFormatter(64),
                      ],
                      // Rebuild the strength meter, and re-check only the
                      // confirm field (not the whole form) if it's been filled.
                      onChanged: (_) {
                        setState(() {});
                        if (_confirmController.text.isNotEmpty) {
                          _confirmKey.currentState?.validate();
                        }
                      },
                    ),
                    _buildPasswordStrength(context),
                    const SizedBox(height: 18),
                    _label(context, "Confirm Password"),
                    const SizedBox(height: 8),
                    _field(
                      context,
                      controller: _confirmController,
                      fieldKey: _confirmKey,
                      hint: "Re-enter your password",
                      icon: Icons.lock_outline,
                      obscure: _obscureConfirm,
                      onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: _validateConfirm,
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                    ),
                    const SizedBox(height: 20),
                    _buildTermsCheckbox(context),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: const Color(0xFFE5484D).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
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
                      height: 58,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.onAccent,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent),
                              )
                            : const Text("Create Account", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: GestureDetector(
                        onTap: _loading
                            ? null
                            : () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                );
                              },
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                            children: const [
                              TextSpan(text: "Already have an account? "),
                              TextSpan(text: "Log In", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
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
    return Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context)));
  }

  // Facebook-style inputs: tall (≈58px), 17px text, a thin visible outline
  // and a strong accent outline on focus — easy to read and to tap on a
  // phone. Shared by every field on this screen so they all line up.
  static const double _fieldRadius = 12;
  static const EdgeInsets _fieldPadding = EdgeInsets.symmetric(vertical: 19, horizontal: 16);

  OutlineInputBorder _outline(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: BorderSide(color: color, width: width),
      );

  InputDecoration _fieldDecoration(BuildContext context, {String? hint, Widget? prefix, Widget? suffix, bool hasCounter = false}) {
    final line = AppPalette.divider(context);
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 16),
      filled: true,
      fillColor: AppPalette.surface(context),
      prefixIcon: prefix,
      suffixIcon: suffix,
      counterText: hasCounter ? '' : null,
      contentPadding: _fieldPadding,
      border: _outline(line),
      enabledBorder: _outline(line),
      focusedBorder: _outline(AppColors.accent, 1.8),
      errorBorder: _outline(Colors.red.shade300, 1.4),
      focusedErrorBorder: _outline(Colors.red.shade400, 1.8),
      errorStyle: const TextStyle(fontSize: 12.5),
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
                "Create Your Account",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: -0.4),
              ),
              const SizedBox(height: 8),
              Text(
                "Sign up to save your bookings and get updates.",
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static final List<TextInputFormatter> _nameFormatters = [
    FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑ .'\-]")),
    LengthLimitingTextInputFormatter(_maxNameLength),
  ];

  Widget _buildSuffixField(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: _suffix.isEmpty ? null : _suffix,
      isExpanded: true,
      icon: Icon(Icons.expand_more, size: 22, color: AppPalette.textMuted(context)),
      hint: Text("N/A", style: TextStyle(color: AppPalette.textMuted(context), fontSize: 16)),
      style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 17),
      dropdownColor: AppPalette.surface(context),
      borderRadius: BorderRadius.circular(16),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text("N/A")),
        for (final option in _suffixOptions) DropdownMenuItem<String>(value: option, child: Text(option)),
      ],
      onChanged: (v) => setState(() => _suffix = v ?? ''),
      decoration: _fieldDecoration(context),
    );
  }

  /// Live strength bar + checklist under the password field.
  Widget _buildPasswordStrength(BuildContext context) {
    final value = _passwordController.text;
    final level = _passwordStrength(value);
    const labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];
    final colors = <Color>[
      Colors.grey,
      Colors.red.shade400,
      Colors.orange.shade600,
      Colors.green.shade500,
      Colors.green.shade700,
    ];
    final color = colors[level];
    final muted = AppPalette.textMuted(context);
    final rules = _passwordRules(value);

    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 1; i <= 4; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: i <= level ? color : muted.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                child: Text(
                  labels[level],
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final r in rules)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      r.met ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 13,
                      color: r.met ? Colors.green.shade600 : muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      r.label,
                      style: TextStyle(fontSize: 11, color: r.met ? Colors.green.shade700 : muted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBirthDateField(BuildContext context) {
    return FormField<DateTime>(
      initialValue: _birthDate,
      validator: _validateBirthDate,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(_fieldRadius),
              onTap: () => _pickBirthDate((picked) {
                setState(() => _birthDate = picked);
                field.didChange(picked);
              }),
              child: Container(
                width: double.infinity,
                padding: _fieldPadding,
                decoration: BoxDecoration(
                  color: AppPalette.surface(context),
                  borderRadius: BorderRadius.circular(_fieldRadius),
                  border: Border.all(
                    color: field.hasError ? Colors.red.shade300 : AppPalette.divider(context),
                    width: field.hasError ? 1.4 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cake_outlined, size: 22, color: AppPalette.textMuted(context)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _birthDate != null ? DateFormat('MMMM d, yyyy').format(_birthDate!) : "Select your birthdate",
                        style: TextStyle(
                          fontSize: _birthDate != null ? 17 : 16,
                          color: _birthDate != null ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
                        ),
                      ),
                    ),
                    Icon(Icons.calendar_month_outlined, size: 22, color: AppPalette.textMuted(context)),
                  ],
                ),
              ),
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(field.errorText!, style: TextStyle(fontSize: 12.5, color: Colors.red.shade400)),
              ),
          ],
        );
      },
    );
  }

  /// Required "I agree to the Terms of Service" checkbox — tapping the
  /// link opens the same [PolicyScreen] the Home screen's footer links
  /// to, so there's only one copy of the actual terms text to keep
  /// up to date.
  Widget _buildTermsCheckbox(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (v) => setState(() {
              _agreedToTerms = v ?? false;
              if (_agreedToTerms) _error = null;
            }),
            activeColor: AppColors.accent,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _agreedToTerms = !_agreedToTerms;
              if (_agreedToTerms) _error = null;
            }),
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 13.5, color: AppPalette.textSecondary(context), height: 1.4),
                children: [
                  const TextSpan(text: "I agree to the "),
                  TextSpan(
                    text: "Terms of Service",
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PolicyScreen(title: "Terms of Service", sections: kTermsOfServiceSections),
                            ),
                          ),
                  ),
                  const TextSpan(text: " and "),
                  TextSpan(
                    text: "Privacy Policy",
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PolicyScreen(
                                title: "Privacy Policy",
                                sections: kPrivacyPolicySections,
                                lastUpdated: kPrivacyPolicyLastUpdated,
                              ),
                            ),
                          ),
                  ),
                  const TextSpan(text: ", and confirm the information I've provided is accurate."),
                ],
              ),
            ),
          ),
        ),
      ],
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
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    TextCapitalization textCapitalization = TextCapitalization.none,
    GlobalKey<FormFieldState<String>>? fieldKey,
  }) {
    final fk = fieldKey ?? _fieldKeys.putIfAbsent(controller, () => GlobalKey<FormFieldState<String>>());
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) return;
        setState(() => _touched.add(controller));
        fk.currentState?.validate();
      },
      child: TextFormField(
      key: fk,
      controller: controller,
      textCapitalization: textCapitalization,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
      autovalidateMode: _touched.contains(controller) ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      style: TextStyle(color: AppPalette.textPrimary(context), fontSize: 17),
      decoration: _fieldDecoration(
        context,
        hint: hint,
        hasCounter: maxLength != null,
        prefix: Icon(icon, size: 22, color: AppPalette.textMuted(context)),
        suffix: onToggleObscure == null
            ? null
            : IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 22, color: AppPalette.textMuted(context)),
                onPressed: onToggleObscure,
              ),
      ),
      ),
    );
  }
}

/// Keeps only digits, and turns a pasted "+63 917 123 4567" / "63917…" into
/// the local "0917…" form the rest of the app expects. Only kicks in once
/// 12 digits are present (i.e. a paste), so typing a number that starts
/// with 6 by hand isn't rewritten mid-way.
class _PhNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 12 && digits.startsWith('639')) {
      digits = '0${digits.substring(2)}';
    }
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

/// One line of the live password checklist.
class _PwRule {
  final String label;
  final bool met;
  const _PwRule(this.label, this.met);
}