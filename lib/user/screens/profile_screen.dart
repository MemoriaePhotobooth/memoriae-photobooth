import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../shared/birthdate_picker.dart';
import '../services/auth_service.dart';
import '../services/booking_repository.dart';
import '../services/camera_rental_repository.dart';
import '../models/camera_rental.dart';
import '../services/payment_info.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/centered_modal.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'user_settings_screen.dart';
import 'event_photos_list_screen.dart';
import 'login_screen.dart';
import 'my_bookings_screen.dart';
import 'payment_methods_screen.dart';
import 'register_screen.dart';
import '../widgets/app_toast.dart';

/// Port of the default-exported `Profile` component.
///
/// Rendered as the `child` content inside `AppLayoutShell` (tab index 2).
/// Added beyond the original static markup: a working Notifications toggle,
/// a Dark Mode toggle, snackbar feedback on menu taps, and a confirm step
/// before logging out.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  AppUser? _user;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    // Port of: useEffect(() => { base44.auth.me().then(setUser).catch(() => setUser(null)); }, [])
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _user = u);
    }).catchError((_) {
      if (mounted) setState(() => _user = null);
    });
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Log out?"),
        content: const Text("You'll need to sign in again to manage your bookings."),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text("Log Out", style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loggingOut = true);
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
  }

  Future<void> _goToLogin() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    if (result == true) _refreshUser();
  }

  Future<void> _goToRegister() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
    );
    if (result == true) _refreshUser();
  }

  void _refreshUser() {
    AuthService.instance.me().then((u) {
      if (mounted) setState(() => _user = u);
    });
  }

  Future<void> _editProfile(AppUser user) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => CenteredModal(child: _EditProfileSheet(user: user)),
    );
    if (saved == true && mounted) {
      _refreshUser();
      AppToast.show(context, "Profile updated.");
    }
  }

  static const int _maxPhotoBytes = 200 * 1024;

  static String _mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// Tapping the avatar: pick a new picture from the gallery,
  /// or remove the current one.
  Future<void> _changePhoto() async {
    if (!AuthService.instance.isLoggedIn) {
      AppToast.show(context, "Log in to add a profile picture.");
      return;
    }
    final hasPhoto = AuthService.photo.value != null;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => CenteredModal(color: Colors.transparent, child: _PhotoSheet(hasPhoto: hasPhoto)),
    );
    if (choice == null || !mounted) return;

    if (choice == 'remove') {
      await _savePhoto(null);
      return;
    }

    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't open the photo picker. Please try again.");
      }
      return;
    }
    if (picked == null || !mounted) return;

    final Uint8List bytes = await picked.readAsBytes();
    if (bytes.lengthInBytes > _maxPhotoBytes) {
      if (mounted) {
        AppToast.show(context, "That photo is too large (${(bytes.lengthInBytes / 1024).round()} KB). Please pick a smaller one.");
      }
      return;
    }
    await _savePhoto(bytes, mimeType: _mimeFor(picked.name));
  }

  Future<void> _savePhoto(Uint8List? bytes, {String mimeType = 'image/jpeg'}) async {
    try {
      await AuthService.instance.updateProfilePhoto(bytes: bytes, mimeType: mimeType);
      if (mounted) {
        AppToast.show(context, bytes == null ? "Profile picture removed." : "Profile picture updated.");
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, "Couldn't save your profile picture. Check your connection and try again.");
      }
    }
  }

  void _showComingSoon(String label) {
    AppToast.show(context, "$label — coming soon");
  }

  @override
  Widget build(BuildContext context) {
    final name = _user?.fullName ?? "Guest User";
    final email = (_user?.email.isNotEmpty ?? false) ? _user!.email : "Anonymous session · no email on file";
    final initials = name
        .split(" ")
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _changePhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ProfileAvatar(
                      size: 80,
                      color: AppColors.accent,
                      shadow: AppShadows.accentGlow,
                      fallback: Text(
                        initials,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.onAccent),
                      ),
                    ),
                    if (AuthService.instance.isLoggedIn)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppPalette.surface(context),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppPalette.bg(context), width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 14, color: AppColors.accent),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
              const SizedBox(height: 2),
              Text(email, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
            ],
          ),
          if (AuthService.instance.isLoggedIn && _user != null) ...[
            const SizedBox(height: 20),
            _buildPersonalInfoCard(context, _user!),
          ],
          const SizedBox(height: 24),
          _ProfileStats(uid: _user?.uid),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(24)),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _menuRow(
                  context: context,
                  icon: Icons.calendar_today,
                  label: "My Bookings",
                  hint: "",
                  onTap: () {
                    if (AuthService.instance.isLoggedIn) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
                    } else {
                      _showComingSoon("Log in to view your bookings");
                    }
                  },
                ),
                if (AuthService.instance.isLoggedIn)
                  _menuRow(
                    context: context,
                    icon: Icons.photo_library_outlined,
                    label: "Event Photos",
                    hint: "",
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EventPhotosListScreen()),
                    ),
                  ),
                _menuRow(
                  context: context,
                  icon: Icons.credit_card,
                  label: "Payment Methods",
                  hint: (_user?.gcashNumber ?? "").isNotEmpty ? "GCash saved" : "GCash",
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()));
                    _refreshUser(); // pick up a newly saved refund account
                  },
                ),
                _menuRow(
                  context: context,
                  icon: Icons.settings_outlined,
                  label: "Settings",
                  hint: "",
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UserSettingsScreen())),
                  isLast: !AuthService.instance.isLoggedIn,
                ),
                if (AuthService.instance.isLoggedIn)
                  _menuRow(
                    context: context,
                    icon: Icons.logout_rounded,
                    label: _loggingOut ? "Logging out…" : "Log Out",
                    hint: "",
                    onTap: _loggingOut ? () {} : _handleLogout,
                    isLast: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (!AuthService.instance.isLoggedIn) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.accentTint(0.06), borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  Text(
                    "Create an account to save your bookings and get updates.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _goToRegister,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.onAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Create Account", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _goToLogin,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text("Log In", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard(BuildContext context, AppUser user) {
    final birthDateLabel = user.birthDate != null ? DateFormat('MMMM d, yyyy').format(user.birthDate!) : "Not set";
    final contactLabel = (user.contactNumber != null && user.contactNumber!.isNotEmpty) ? user.contactNumber! : "Not set";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Row(
            children: [
              Text("Personal info",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
              const Spacer(),
              Material(
                color: AppColors.accentTint(0.10),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _editProfile(user),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 14, color: AppColors.accent),
                        SizedBox(width: 6),
                        Text("Edit", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.accent)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppPalette.divider(context)),
          const SizedBox(height: 14),
          _infoRow(context, icon: Icons.person_outline, label: "Name", value: user.fullName.isEmpty ? "Not set" : user.fullName),
          const SizedBox(height: 10),
          _infoRow(context, icon: Icons.phone_outlined, label: "Contact Number", value: contactLabel),
          const SizedBox(height: 10),
          _infoRow(context, icon: Icons.cake_outlined, label: "Birthdate", value: birthDateLabel),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, {required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
        const Spacer(),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
      ],
    );
  }

  Widget _menuRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback onTap,
    Widget? trailing,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context))),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppPalette.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppShadows.soft,
                ),
                child: Icon(icon, size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context))),
              ),
              if (trailing != null)
                trailing
              else ...[
                if (hint.isNotEmpty) ...[
                  Text(hint, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  const SizedBox(width: 4),
                ],
                Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Live Bookings / Rentals / Spent numbers for the profile page, computed
/// from the user's own `bookings` and `cameraRentals` documents.
///
/// - Bookings: submitted bookings that are still valid — pending review,
///   confirmed, or completed. Unpaid holds (`awaiting_receipt`), cancelled and
///   refunded bookings are not counted.
/// - Rentals: every camera rental the user has made (active or returned).
/// - Spent: money paid on confirmed or completed bookings (a downpayment
///   counts only the amount paid so far, via [PaymentInfo]) plus the total
///   price of camera rentals. Set [_includeRentalsInSpent] to false to leave
///   rentals out of the total.
class _ProfileStats extends StatefulWidget {
  final String? uid;
  const _ProfileStats({required this.uid});

  @override
  State<_ProfileStats> createState() => _ProfileStatsState();
}

class _ProfileStatsState extends State<_ProfileStats> {
  static const bool _includeRentalsInSpent = true;
  static const _counted = {'pending_confirmation', 'confirmed', 'completed'};
  static const _paidStatuses = {'confirmed', 'completed'};

  Stream<List<Map<String, dynamic>>>? _bookings;
  Stream<List<CameraRental>>? _rentals;

  @override
  void initState() {
    super.initState();
    _open(widget.uid);
  }

  @override
  void didUpdateWidget(covariant _ProfileStats old) {
    super.didUpdateWidget(old);
    // Logged in / out / switched account -> listen to the new user's data.
    if (old.uid != widget.uid) _open(widget.uid);
  }

  void _open(String? uid) {
    final has = uid != null && uid.isNotEmpty;
    _bookings = has ? BookingRepository.watchBookingsForUser(uid) : null;
    _rentals = has ? CameraRentalRepository.watchRentalsForUser(uid) : null;
  }

  static String _peso(int amount) {
    if (amount >= 1000000) return "₱${(amount / 1000000).toStringAsFixed(1)}M";
    if (amount >= 100000) return "₱${(amount / 1000).round()}K";
    return "₱${NumberFormat('#,##0').format(amount)}";
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _bookings,
      builder: (context, bSnap) {
        return StreamBuilder<List<CameraRental>>(
          stream: _rentals,
          builder: (context, rSnap) {
            // "–" while loading (or if a read fails) rather than a misleading 0.
            String bookings = "–", rentals = "–", spent = "–";

            int bookingCount = 0, bookingPaid = 0, rentalCount = 0, rentalTotal = 0;
            if (bSnap.hasData) {
              for (final b in bSnap.data!) {
                final status = b['status'] as String? ?? '';
                if (!_counted.contains(status)) continue;
                bookingCount++;
                if (_paidStatuses.contains(status)) bookingPaid += PaymentInfo.fromBooking(b).paid;
              }
              bookings = "$bookingCount";
            }
            if (rSnap.hasData) {
              rentalCount = rSnap.data!.length;
              rentalTotal = rSnap.data!.fold<int>(0, (sum, r) => sum + r.totalPrice);
              rentals = "$rentalCount";
            }
            if (bSnap.hasData && (rSnap.hasData || !_includeRentalsInSpent)) {
              spent = _peso(bookingPaid + (_includeRentalsInSpent ? rentalTotal : 0));
            }

            return Row(
              children: [
                _StatCard(value: bookings, label: "Bookings"),
                const SizedBox(width: 12),
                _StatCard(value: rentals, label: "Rentals"),
                const SizedBox(width: 12),
                _StatCard(value: spent, label: "Spent"),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppPalette.textMuted(context))),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet where a signed-in customer edits their own details.
class _EditProfileSheet extends StatefulWidget {
  final AppUser user;
  const _EditProfileSheet({required this.user});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  static const int _minAge = 10; // same rule as registration
  static const int _maxNameLength = 50; // room for first + M.I. + last + suffix
  static final RegExp _nameChars = RegExp(r"^[a-zA-ZñÑ][a-zA-ZñÑ .'\-]*$");

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.user.fullName);
  late final TextEditingController _contact = TextEditingController(text: widget.user.contactNumber ?? '');
  late DateTime? _birthDate = widget.user.birthDate;
  bool _saving = false;
  String? _error;
  String? _birthError;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  static int _ageOn(DateTime birth, DateTime today) {
    var age = today.year - birth.year;
    if (today.month < birth.month || (today.month == birth.month && today.day < birth.day)) age--;
    return age;
  }

  String? _validateName(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Please enter your name.';
    if (value.replaceAll(RegExp(r"[^a-zA-ZñÑ]"), '').length < 2) return 'Name is too short.';
    if (value.length > _maxNameLength) return 'Name is too long (max $_maxNameLength characters).';
    if (!_nameChars.hasMatch(value)) return "Use letters, spaces, and - ' . only, starting with a letter.";
    if (RegExp(r'\s{2,}').hasMatch(value)) return 'Remove the extra spaces.';
    return null;
  }

  String? _validateContact(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'Please enter your contact number.';
    if (!value.startsWith('09')) return 'Mobile number must start with 09 (e.g. 09171234567).';
    if (value.length != 11) return 'Mobile number must be exactly 11 digits.';
    if (RegExp(r'^09(\d)\1{8}$').hasMatch(value)) return "That doesn't look like a real mobile number.";
    return null;
  }

  String? _checkBirthDate() {
    final d = _birthDate;
    if (d == null) return 'Please select your birthdate.';
    if (d.isAfter(DateTime.now())) return "Birthdate can't be in the future.";
    if (d.year < 1970) return 'Birth year must be 1970 or later.';
    if (_ageOn(d, DateTime.now()) < _minAge) return 'You must be at least $_minAge years old.';
    return null;
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showBirthDatePicker(
      context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1970),
      minAge: _minAge,
      helpText: 'Select your birthdate',
    );
    if (picked != null) setState(() {
      _birthDate = picked;
      _birthError = _checkBirthDate(); // realtime: check right after picking
    });
  }

  Future<void> _save() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final birthError = _checkBirthDate();
    setState(() {
      _birthError = birthError;
      _error = null;
    });
    if (!formOk || birthError != null) return;
    setState(() => _saving = true);
    try {
      final tidy = _name.text.trim().split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
      await AuthService.instance.updateProfile(fullName: tidy, contactNumber: _contact.text.trim(), birthDate: _birthDate!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = "Couldn't save your changes. Check your connection and try again.";
        });
      }
    }
  }

  /// Shared field style. The label is drawn above the box by [_labeled] so it
  /// lines up with the box edge and every field has the same height/padding.
  InputDecoration _decoration(BuildContext context, IconData icon, {String? hint}) {
    return InputDecoration(
      hintText: hint,
      counterText: '',
      prefixIcon: Icon(icon, size: 20, color: AppPalette.textMuted(context)),
      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      filled: true,
      fillColor: AppPalette.surface(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  Widget _labeled(BuildContext context, String label, Widget field) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
        ),
        field,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomInset),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                ),
                IconButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 14),
            _labeled(context, 'Full name', TextFormField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              validator: _validateName,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r"[a-zA-ZñÑ .'\-]")),
                LengthLimitingTextInputFormatter(_maxNameLength),
              ],
              style: const TextStyle(fontSize: 15),
              decoration: _decoration(context, Icons.person_outline),
            )),
            const SizedBox(height: 14),
            _labeled(context, 'Contact number', TextFormField(
              controller: _contact,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              validator: _validateContact,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(11),
              ],
              style: const TextStyle(fontSize: 15),
              decoration: _decoration(context, Icons.phone_outlined, hint: '09XXXXXXXXX'),
            )),
            const SizedBox(height: 14),
            _labeled(context, 'Birthdate', InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _saving ? null : _pickBirthDate,
              child: InputDecorator(
                decoration: _decoration(context, Icons.cake_outlined).copyWith(errorText: _birthError),
                child: Text(
                  _birthDate == null ? 'Select your birthdate' : DateFormat('MMMM d, yyyy').format(_birthDate!),
                  style: TextStyle(fontSize: 15, color: _birthDate == null ? AppPalette.textMuted(context) : AppPalette.textPrimary(context)),
                ),
              ),
            )),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 12.5, color: Color(0xFFB3261E))),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAccent))
                  : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for changing the profile picture: a rounded card with an
/// icon row per action, a drag handle, and a Cancel button.
class _PhotoSheet extends StatelessWidget {
  final bool hasPhoto;
  const _PhotoSheet({required this.hasPhoto});

  static const Color _danger = Color(0xFFB3261E);

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool danger = false,
    bool isLast = false,
  }) {
    final textColor = danger ? _danger : AppPalette.textPrimary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context))),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: danger ? _danger.withValues(alpha: 0.10) : AppColors.accentTint(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: danger ? _danger : AppColors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),
              if (!danger) Icon(Icons.chevron_right_rounded, size: 20, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Each row gets a divider except the last one.
    final specs = <({IconData icon, String label, String value, bool danger})>[
      (icon: Icons.photo_library_outlined, label: 'Choose from gallery', value: 'gallery', danger: false),
      if (hasPhoto)
        (icon: Icons.delete_outline_rounded, label: 'Remove photo', value: 'remove', danger: true),
    ];
    final options = [
      for (var i = 0; i < specs.length; i++)
        _row(
          context,
          icon: specs[i].icon,
          label: specs[i].label,
          value: specs[i].value,
          danger: specs[i].danger,
          isLast: i == specs.length - 1,
        ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: AppPalette.cardBg(context),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppPalette.divider(context), borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Profile picture',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how you want to update your photo.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(context)),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(children: options),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}