import '../../shared/top_toast.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
import '../models/staff_account_record.dart';
import '../services/staff_repository.dart';
import '../widgets/pagination_bar.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Admin-only: manage the team — add people, change roles,
/// archive/restore, send password resets. Admins can manage other admins
/// too (never themselves, and never the last active admin — see
/// [StaffRepository] for the safety rules).
///
/// The page title here is "Team members" on purpose: the dashboard's own
/// header (desktop) / app bar (mobile) already says "Staff", and repeating
/// it looked like a bug.
///
/// Layout: summary cards -> filter tabs + search -> one rounded table card
/// (Member / Role / Status / Added / actions). On narrow screens each row
/// collapses into a stacked card-style row.
class AdminStaffScreen extends StatefulWidget {
  const AdminStaffScreen({super.key});

  @override
  State<AdminStaffScreen> createState() => _AdminStaffScreenState();
}

/// `all` = everyone who isn't archived; archived accounts only show under
/// their own tab.
enum _StaffFilter { all, active, inactive, archived }

class _AdminStaffScreenState extends State<AdminStaffScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _StaffFilter _filter = _StaffFilter.all;
  int _page = 0;
  static const int _pageSize = 10;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String? get _myUid => fb.FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StaffAccountRecord>>(
      stream: StaffRepository.watchAllStaff(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                "Couldn't load the team list.\n${snapshot.error}",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }

        final everyone = snapshot.data!;
        final current = everyone.where((s) => !s.archived).toList();
        final archived = everyone.where((s) => s.archived).toList();
        final adminCount = current.where((s) => s.role == AccessRole.admin).length;
        final staffCount = current.length - adminCount;
        final inactiveCount = current.where((s) => !s.active).length;
        final activeCount = current.length - inactiveCount;

        List<StaffAccountRecord> pool;
        switch (_filter) {
          case _StaffFilter.active:
            pool = current.where((s) => s.active).toList();
            break;
          case _StaffFilter.inactive:
            pool = current.where((s) => !s.active).toList();
            break;
          case _StaffFilter.archived:
            pool = archived;
            break;
          case _StaffFilter.all:
            pool = current;
            break;
        }

        final q = _query.trim().toLowerCase();
        final rows = q.isEmpty
            ? pool
            : pool.where((s) => s.name.toLowerCase().contains(q) || s.email.toLowerCase().contains(q)).toList();
        // Admins first, then by name — keeps the people with the most access at the top.
        rows.sort((a, b) {
          if (a.role != b.role) return a.role == AccessRole.admin ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        _page = PageWindow.clamp(_page, rows.length, pageSize: _pageSize);
        final pageRows = PageWindow.slice(rows, _page, pageSize: _pageSize);

        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 760;
            return ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, 24, wide ? 28 : 16, 40),
              children: [
                _buildHeader(context),
                const SizedBox(height: 22),
                _buildSummary(context, admins: adminCount, staff: staffCount, inactive: inactiveCount, archived: archived.length),
                const SizedBox(height: 22),
                _buildToolbar(
                  context,
                  wide: wide,
                  all: current.length,
                  active: activeCount,
                  inactive: inactiveCount,
                  archived: archived.length,
                ),
                const SizedBox(height: 14),
                _buildTable(context, pageRows, wide: wide),
                PaginationBar(
                  page: _page,
                  pageCount: PageWindow.pageCount(rows.length, pageSize: _pageSize),
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------ header

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Team members",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppPalette.textPrimary(context)),
              ),
              const SizedBox(height: 4),
              Text(
                "Everyone who can sign in to the Staff and Admin apps.",
                style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _AddMemberButton(onPressed: () => _showAddDialog(context)),
      ],
    );
  }

  // ----------------------------------------------------------------- summary

  Widget _buildSummary(BuildContext context, {required int admins, required int staff, required int inactive, required int archived}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          _summaryCard(context, icon: Icons.shield_outlined, label: 'Admins', value: admins, tint: true),
          _summaryCard(context, icon: Icons.badge_outlined, label: 'Staff', value: staff),
          _summaryCard(context, icon: Icons.archive_outlined, label: 'Archived', value: archived),
        ];
        final twoColumns = constraints.maxWidth < 560;
        if (twoColumns) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), const Spacer()]),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 14),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _summaryCard(BuildContext context, {required IconData icon, required String label, required int value, bool tint = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint ? AppColors.accentTint(0.10) : AppPalette.surface(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: tint ? AppColors.accent : AppPalette.textSecondary(context)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$value', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.1, color: AppPalette.textPrimary(context))),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- toolbar

  Widget _buildToolbar(BuildContext context, {required bool wide, required int all, required int active, required int inactive, required int archived}) {
    final tabs = _buildTabs(context, all: all, active: active, inactive: inactive, archived: archived);
    final search = _buildSearchField(context);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: tabs),
          const SizedBox(height: 12),
          search,
        ],
      );
    }
    return Row(
      children: [
        tabs,
        const Spacer(),
        SizedBox(width: 280, child: search),
      ],
    );
  }

  Widget _buildTabs(BuildContext context, {required int all, required int active, required int inactive, required int archived}) {
    Widget tab(_StaffFilter f, String label, int n) {
      final selected = _filter == f;
      return GestureDetector(
        onTap: () => setState(() { _filter = f; _page = 0; }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppPalette.cardBg(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected ? AppShadows.soft : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.accent : AppPalette.textSecondary(context),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$n',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: selected ? AppColors.accent : AppPalette.textMuted(context)),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          tab(_StaffFilter.all, 'All', all),
          tab(_StaffFilter.active, 'Active', active),
          tab(_StaffFilter.archived, 'Archived', archived),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() { _query = v; _page = 0; }),
        style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
        decoration: InputDecoration(
          isDense: true,
          hintText: "Search name or email",
          hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
          prefixIcon: Icon(Icons.search, size: 18, color: AppPalette.textMuted(context)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close, size: 16, color: AppPalette.textMuted(context)),
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _query = '';
                  }),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- table

  Widget _buildTable(BuildContext context, List<StaffAccountRecord> rows, {required bool wide}) {
    final divider = Divider(height: 1, thickness: 1, color: AppPalette.divider(context).withValues(alpha: 0.6));

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            _tableHeader(context),
            divider,
          ],
          if (rows.isEmpty)
            _buildEmptyState(context)
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) divider,
              wide ? _wideRow(context, rows[i]) : _narrowRow(context, rows[i]),
            ],
        ],
      ),
    );
  }

  static const _flexMember = 5;
  static const _flexRole = 2;
  static const _flexStatus = 2;
  static const _flexAdded = 2;
  static const _menuWidth = 48.0;

  Widget _tableHeader(BuildContext context) {
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppPalette.textMuted(context));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
      child: Row(
        children: [
          Expanded(flex: _flexMember, child: Text('MEMBER', style: style)),
          Expanded(flex: _flexRole, child: Text('ROLE', style: style)),
          Expanded(flex: _flexStatus, child: Text('STATUS', style: style)),
          Expanded(flex: _flexAdded, child: Text('ADDED', style: style)),
          const SizedBox(width: _menuWidth),
        ],
      ),
    );
  }

  Widget _wideRow(BuildContext context, StaffAccountRecord s) {
    final isAdmin = s.role == AccessRole.admin;
    return Opacity(
      opacity: s.archived ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Row(
          children: [
            Expanded(flex: _flexMember, child: _memberCell(context, s)),
            Expanded(flex: _flexRole, child: Align(alignment: Alignment.centerLeft, child: _roleChip(isAdmin))),
            Expanded(flex: _flexStatus, child: Align(alignment: Alignment.centerLeft, child: _statusChip(context, s.status))),
            Expanded(flex: _flexAdded, child: Text(_formatDate(s.createdAt), style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(context)))),
            SizedBox(width: _menuWidth, child: Align(alignment: Alignment.centerRight, child: _actionsMenu(context, s, isAdmin))),
          ],
        ),
      ),
    );
  }

  Widget _narrowRow(BuildContext context, StaffAccountRecord s) {
    final isAdmin = s.role == AccessRole.admin;
    return Opacity(
      opacity: s.archived ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _avatar(name: s.name, isAdmin: isAdmin, active: s.active),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _nameLine(context, s),
                  const SizedBox(height: 2),
                  Text(s.email, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _roleChip(isAdmin),
                      _statusChip(context, s.status),
                      if (s.createdAt != null)
                        Text('Added ${_formatDate(s.createdAt)}', style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                    ],
                  ),
                ],
              ),
            ),
            _actionsMenu(context, s, isAdmin),
          ],
        ),
      ),
    );
  }

  Widget _memberCell(BuildContext context, StaffAccountRecord s) {
    return Row(
      children: [
        _avatar(name: s.name, isAdmin: s.role == AccessRole.admin, active: s.active),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _nameLine(context, s),
              const SizedBox(height: 2),
              Text(s.email, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nameLine(BuildContext context, StaffAccountRecord s) {
    final hasName = s.name.trim().isNotEmpty && s.name != '(no name)';
    return Row(
      children: [
        Flexible(
          child: Text(
            hasName ? s.name : 'Unnamed account',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontStyle: hasName ? FontStyle.normal : FontStyle.italic,
              color: s.active && hasName ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
            ),
          ),
        ),
        if (s.id == _myUid) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.highlight.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(6)),
            child: const Text('YOU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Color(0xFF8A6A12))),
          ),
        ],
      ],
    );
  }

  String _formatDate(DateTime? d) => d == null ? '\u2014' : DateFormat('MMM d, y').format(d);

  Widget _buildEmptyState(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final String message;
    if (searching) {
      message = "No one matches \u201c$_query\u201d";
    } else {
      switch (_filter) {
        case _StaffFilter.archived:
          message = "Nothing in the archive";
          break;
        case _StaffFilter.inactive:
          message = "No inactive accounts";
          break;
        case _StaffFilter.active:
        case _StaffFilter.all:
          message = "No team members yet";
          break;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(searching ? Icons.search_off : Icons.groups_2_outlined, size: 36, color: AppPalette.textMuted(context)),
          const SizedBox(height: 10),
          Text(message, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(context))),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ small pieces

  Widget _avatar({required String name, required bool isAdmin, required bool active}) {
    final initial = name.trim().isNotEmpty && name != '(no name)' ? name.trim()[0].toUpperCase() : '?';
    final colors = isAdmin ? [AppColors.accent, const Color(0xFF9A3236)] : [AppColors.stone400, AppColors.stone500];
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        boxShadow: active && isAdmin ? AppShadows.accentGlowSmall : null,
      ),
      child: Opacity(
        opacity: active ? 1 : 0.55,
        child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
    );
  }

  Widget _roleChip(bool isAdmin) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin ? AppColors.accentTint(0.12) : AppColors.stone200,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isAdmin ? Icons.shield : Icons.badge, size: 10, color: isAdmin ? AppColors.accent : AppColors.stone500),
          const SizedBox(width: 4),
          Text(
            isAdmin ? 'Admin' : 'Staff',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: isAdmin ? AppColors.accent : AppColors.stone500),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, AccountStatus status) {
    late final String label;
    late final IconData icon;
    late final Color fg;
    late final Color bg;
    switch (status) {
      case AccountStatus.active:
        label = 'Active';
        icon = Icons.check_circle;
        fg = const Color(0xFF15803D);
        bg = const Color(0xFF15803D).withValues(alpha: 0.12);
        break;
      case AccountStatus.inactive:
        label = 'Inactive';
        icon = Icons.pause_circle_outline;
        fg = AppPalette.textMuted(context);
        bg = AppPalette.surface(context);
        break;
      case AccountStatus.archived:
        label = 'Archived';
        icon = Icons.archive_outlined;
        fg = AppPalette.textMuted(context);
        bg = AppPalette.surface(context);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- actions

  /// Runs a repository action and shows its error (e.g. "You can't
  /// demote the last active admin") as a snackbar instead of failing
  /// silently.
  Future<void> _run(BuildContext context, Future<void> Function() action, {String? success}) async {
    try {
      await action();
      if (success != null) TopToast.show(null, success);
    } catch (e) {
      TopToast.show(null, e.toString().replaceFirst('Exception: ', ''), kind: TopToastKind.error);
    }
  }

  Future<bool> _confirm(BuildContext context, {required String title, required String message, required String confirmLabel}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<String?> _askName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Widget _actionsMenu(BuildContext context, StaffAccountRecord s, bool isAdmin) {
    final isMe = s.id == _myUid;

    PopupMenuItem<String> item(String value, IconData icon, String label, {bool enabled = true, bool danger = false}) {
      final color = danger ? AppColors.accent : AppPalette.textSecondary(context);
      return PopupMenuItem<String>(
        value: value,
        enabled: enabled,
        child: Row(children: [
          Icon(icon, size: 16, color: enabled ? color : AppPalette.textMuted(context)),
          const SizedBox(width: 10),
          Text(label, style: danger && enabled ? const TextStyle(color: AppColors.accent) : null),
        ]),
      );
    }

    final items = <PopupMenuEntry<String>>[];
    if (s.archived) {
      items.add(item('restore', Icons.unarchive_outlined, 'Restore'));
      // Admins are never permanently deleted; and never delete yourself.
      if (!isAdmin && !isMe) {
        items.add(const PopupMenuDivider());
        items.add(item('delete', Icons.delete_forever_outlined, 'Delete permanently', danger: true));
      }
    } else {
      // Admin accounts are protected: no demoting ("Make Staff") and no
      // archiving. Staff can still be promoted to admin.
      if (!(isAdmin && StaffRepository.protectAdminAccounts)) {
        items.add(item('toggle_role', isAdmin ? Icons.badge_outlined : Icons.shield_outlined, isAdmin ? 'Make Staff' : 'Make Admin',
            enabled: !(isAdmin && isMe)));
      }
      // "Deactivate" was replaced by Archive. Only accounts that were
      // deactivated before still need a way back in.
      if (!s.active) {
        items.add(item('toggle_active', Icons.unarchive_outlined, 'Restore'));
      }
      items.add(item('edit', Icons.edit_outlined, 'Edit name'));
      items.add(item('reset_password', Icons.lock_reset, 'Send password reset'));
      if (!(isAdmin && StaffRepository.protectAdminAccounts)) {
        items.add(const PopupMenuDivider());
        items.add(item('archive', Icons.archive_outlined, 'Archive', enabled: !isMe, danger: true));
      }
    }

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.more_horiz, size: 18, color: AppPalette.textMuted(context)),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) async {
        switch (value) {
          case 'toggle_role':
            final makingStaff = isAdmin;
            final okRole = await _confirm(
              context,
              title: makingStaff ? 'Change ${s.name} to Staff?' : 'Make ${s.name} an Admin?',
              message: makingStaff
                  ? 'They will lose access to the Admin app (pricing, team management). They can still use the Staff app.'
                  : 'They will get full access to the Admin app, including pricing and managing the team.',
              confirmLabel: makingStaff ? 'Change to Staff' : 'Make Admin',
            );
            if (okRole && context.mounted) {
              await _run(context, () => StaffRepository.setRole(s, makingStaff ? AccessRole.staff : AccessRole.admin));
            }
            break;
          case 'toggle_active':
            await _run(context, () => StaffRepository.setActive(s, true), success: '${s.name} restored');
            break;
          case 'edit':
            final newName = await _askName(context, s.name);
            if (newName != null && context.mounted) {
              await _run(context, () => StaffRepository.updateName(s, newName), success: 'Name updated');
            }
            break;
          case 'reset_password':
            await _run(context, () => StaffRepository.sendPasswordReset(s), success: 'Password reset email sent to ${s.email}');
            break;
          case 'archive':
            final ok = await _confirm(
              context,
              title: 'Archive ${s.name}?',
              message: 'They won\u2019t be able to log in anymore and will be moved to the Archived tab. You can restore them anytime.',
              confirmLabel: 'Archive',
            );
            if (ok && context.mounted) await _run(context, () => StaffRepository.archive(s), success: '${s.name} archived');
            break;
          case 'restore':
            await _run(context, () => StaffRepository.restore(s),
                success: '${s.name} restored \u2014 they can log in again.');
            break;
          case 'delete':
            final okDelete = await _confirm(
              context,
              title: 'Delete ${s.name} permanently?',
              message: 'This removes their access record for good and can\u2019t be undone.',
              confirmLabel: 'Delete',
            );
            if (okDelete && context.mounted) await _run(context, () => StaffRepository.removeStaff(s), success: '${s.name} deleted');
            break;
        }
      },
      itemBuilder: (context) => items,
    );
  }

  // ------------------------------------------------------------- add dialog

  static final RegExp _emailPattern = RegExp(r'^[\w\.\-\+]+@[\w\-]+\.[\w\-\.]+$');

  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    AccessRole role = AccessRole.staff;
    bool submitting = false;
    String? error;
    // Realtime validation: a field's message shows as soon as it's touched
    // and updates on every keystroke.
    bool nameTouched = false;
    bool emailTouched = false;

    String? nameError(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return 'Enter a name.';
      if (v.replaceAll(RegExp(r"[^a-zA-ZñÑ]"), '').length < 2) return 'Name is too short.';
      if (v.length > 60) return 'Name is too long (max 60 characters).';
      if (!RegExp(r"^[a-zA-ZñÑ][a-zA-ZñÑ .'\-]*$").hasMatch(v)) return "Use letters, spaces, and - ' . only.";
      return null;
    }

    String? emailError(String raw) {
      final v = raw.trim();
      if (v.isEmpty) return 'Enter an email address.';
      if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address.';
      return null;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> submit() async {
              final name = nameController.text.trim();
              final email = emailController.text.trim();
              if (nameError(name) != null || emailError(email) != null) {
                setState(() {
                  nameTouched = true;
                  emailTouched = true;
                });
                return;
              }

              setState(() {
                submitting = true;
                error = null;
              });

              try {
                final password = await StaffRepository.addStaff(name: name, email: email, role: role);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                _showGeneratedPasswordDialog(context, name: name, email: email, password: password);
              } catch (e) {
                setState(() {
                  submitting = false;
                  error = e.toString().replaceFirst('Exception: ', '');
                });
              }
            }

            InputDecoration field(String label, IconData icon) => InputDecoration(
                  labelText: label,
                  prefixIcon: Icon(icon, size: 18),
                  filled: true,
                  fillColor: AppPalette.surface(dialogContext),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                );

            Widget roleOption(AccessRole value, IconData icon, String title, String subtitle) {
              final selected = role == value;
              return Expanded(
                child: GestureDetector(
                  onTap: submitting ? null : () => setState(() => role = value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.accentTint(0.08) : AppPalette.surface(dialogContext),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, size: 16, color: selected ? AppColors.accent : AppPalette.textSecondary(dialogContext)),
                            const SizedBox(width: 6),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: selected ? AppColors.accent : AppPalette.textPrimary(dialogContext),
                              ),
                            ),
                            const Spacer(),
                            if (selected) const Icon(Icons.check_circle, size: 16, color: AppColors.accent),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(subtitle, style: TextStyle(fontSize: 11, height: 1.3, color: AppPalette.textMuted(dialogContext))),
                      ],
                    ),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Add team member'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !submitting,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => setState(() {
                        nameTouched = true;
                        error = null;
                      }),
                      decoration: field('Full name', Icons.person_outline).copyWith(
                        errorText: nameTouched ? nameError(nameController.text) : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: !submitting,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => setState(() {
                        emailTouched = true;
                        error = null;
                      }),
                      decoration: field('Email', Icons.mail_outline).copyWith(
                        hintText: 'name@gmail.com',
                        errorText: emailTouched ? emailError(emailController.text) : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use a real email they can open (e.g. Gmail). It\u2019s their login, and where "Forgot password?" sends the reset link.',
                      style: TextStyle(fontSize: 11, color: AppPalette.textMuted(dialogContext)),
                    ),
                    const SizedBox(height: 18),
                    Text('Access level', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.textSecondary(dialogContext))),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        roleOption(AccessRole.staff, Icons.badge_outlined, 'Staff', 'Day-to-day work: bookings, rentals and POS.'),
                        const SizedBox(width: 10),
                        roleOption(AccessRole.admin, Icons.shield_outlined, 'Admin', 'Full access, including pricing and managing the team.'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'A temporary password is created for them. You\u2019ll see it once after adding.',
                      style: TextStyle(fontSize: 11, color: AppPalette.textMuted(dialogContext)),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.error_outline, size: 16, color: AppColors.accent),
                          const SizedBox(width: 6),
                          Expanded(child: Text(error!, style: const TextStyle(fontSize: 12, color: AppColors.accent))),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Add member'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shown exactly once, right after [StaffRepository.addStaff] succeeds —
  /// Firebase never lets the password be read back out again, so this is
  /// the only chance to hand it to whoever's setting the new hire up.
  void _showGeneratedPasswordDialog(BuildContext context, {required String name, required String email, required String password}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$name\u2019s account is ready'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: const TextStyle(fontSize: 12, color: AppColors.stone500)),
            const SizedBox(height: 16),
            const Text(
              'Temporary password \u2014 shown once, share it now:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: AppColors.surfaceGrey, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      password,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: password));
                      TopToast.show(context, 'Password copied', duration: const Duration(seconds: 2));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ask them to change it from their Profile after the first sign-in. If it\u2019s lost, use \u201cSend password reset\u201d on their row.',
              style: TextStyle(fontSize: 11, color: AppColors.stone500),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

/// Prominent inline "Add member" button used in the header instead of a
/// floating action button — a flatter, more modern dashboard pattern.
class _AddMemberButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _AddMemberButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.person_add_alt_1, size: 18),
      label: const Text("Add member", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}
