import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/booking_record.dart';
import '../models/pos_transaction_record.dart';
import '../services/admin_service.dart';
import '../services/booking_repository.dart';
import '../services/pos_repository.dart';
import '../services/staff_repository.dart';
import '../models/staff_account_record.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// The signed-in admin's own profile: who they are (name, role,
/// email, status, member since), a few personal activity stats, and the
/// account actions (dark mode, change password, sign out).
///
class AdminProfileScreen extends StatelessWidget {
  final VoidCallback onOpenSettings;
  final VoidCallback onLogout;

  const AdminProfileScreen({super.key, required this.onOpenSettings, required this.onLogout});

  String _initials(String name) {
    final letters = name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase();
    return letters.isEmpty ? 'S' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminProfile>(
      future: AdminService.instance.getProfile(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final p = snap.data!;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(context, p),
                  const SizedBox(height: 22),
                  _stats(context),
                  const SizedBox(height: 22),
                  _card(context, [
                    _infoRow(context, Icons.badge_outlined, "Name", p.name),
                    _infoRow(context, Icons.mail_outline, "Email", p.email.isEmpty ? "—" : p.email),
                    _infoRow(context, Icons.work_outline, "Role", p.role),
                    _infoRow(context, Icons.verified_user_outlined, "Status", p.active ? "Active" : "Archived"),
                    _infoRow(
                      context,
                      Icons.event_outlined,
                      "Member since",
                      p.createdAt == null ? "—" : DateFormat('MMMM d, yyyy').format(p.createdAt!),
                      isLast: true,
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                    child: Text(
                      "Team accounts are managed from the Staff screen.",
                      style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _card(context, [
                    _actionRow(
                      context,
                      icon: Icons.settings_outlined,
                      label: "Settings",
                      onTap: onOpenSettings,
                      isLast: true,
                    ),
                  ]),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: onLogout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.accent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text("Sign out", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AdminProfile p) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, boxShadow: AppShadows.accentGlow),
          child: Text(_initials(p.name), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(height: 14),
        Text(
          p.name,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppPalette.textPrimary(context)),
        ),
        const SizedBox(height: 2),
        Text(p.email, style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.accentTint(0.10), borderRadius: BorderRadius.circular(999)),
          child: Text(p.role, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accent)),
        ),
      ],
    );
  }

  /// Studio-wide snapshot: total bookings, staff accounts, and today's
  /// POS sales.
  Widget _stats(BuildContext context) {
    return StreamBuilder<List<BookingRecord>>(
      stream: BookingRepository.watchAllBookings(),
      builder: (context, bookingSnap) {
        return StreamBuilder<List<StaffAccountRecord>>(
          stream: StaffRepository.watchAllStaff(),
          builder: (context, staffSnap) {
            return StreamBuilder<List<PosTransactionRecord>>(
              stream: PosRepository.watchAllTransactions(),
              builder: (context, posSnap) {
                final bookings = bookingSnap.data?.length ?? 0;
                final staff = (staffSnap.data ?? const <StaffAccountRecord>[]).where((a) => !a.archived).length;
                final now = DateTime.now();
                final todayTotal = (posSnap.data ?? const <PosTransactionRecord>[])
                    .where((t) => t.createdAt.year == now.year && t.createdAt.month == now.month && t.createdAt.day == now.day)
                    .fold<int>(0, (sum, t) => sum + t.total);
                final fmt = NumberFormat('#,##0');
                return Row(
                  children: [
                    _statTile(context, '$bookings', "Total bookings"),
                    const SizedBox(width: 12),
                    _statTile(context, '$staff', "Team accounts"),
                    const SizedBox(width: 12),
                    _statTile(context, '₱${fmt.format(todayTotal)}', "Sales today"),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _statTile(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
            ),
            const SizedBox(height: 3),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value, {bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context)))),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppColors.accent),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: trailing != null ? 8 : 15),
          decoration: BoxDecoration(border: isLast ? null : Border(bottom: BorderSide(color: AppPalette.divider(context)))),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)))),
              trailing ?? Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}
