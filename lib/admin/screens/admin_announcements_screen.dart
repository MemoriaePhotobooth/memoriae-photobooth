import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/announcement_record.dart';
import '../services/announcement_repository.dart';
import '../services/admin_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';

/// A ready-made announcement staff can drop into the form with one tap.
class _Template {
  final String label;
  final String type;
  final String title;
  final String message;
  const _Template(this.label, this.type, this.title, this.message);
}

const List<_Template> _kTemplates = [
  _Template(
    'Closed today',
    'closed',
    'Photobooth is closed today',
    "We're closed today. Sorry for the inconvenience — we'll be back soon!",
  ),
  _Template(
    'Closing early',
    'closed',
    'Closing early today',
    'We will close earlier than usual today. Please plan your visit accordingly.',
  ),
  _Template(
    'Open again',
    'info',
    "We're open again!",
    'We are back to our regular hours. Book your session now!',
  ),
];

/// Admin-side announcements: write one (e.g. "Photobooth is closed
/// today"), pin it, or delete an old one. Every customer sees these in the
/// User app — on the Home screen while they're recent/pinned, and in the
/// Announcements tab always.
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() => _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  int _page = 0;
  static const int _pageSize = 5;

  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String _type = 'info';
  bool _pinned = false;
  bool _posting = false;
  // Realtime validation: a message shows once the field is touched and
  // updates on every keystroke.
  bool _titleTouched = false;
  bool _messageTouched = false;

  String? get _titleError => _titleController.text.trim().isEmpty ? 'Add a title.' : null;
  String? get _messageError => _messageController.text.trim().isEmpty ? 'Add a message.' : null;

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _applyTemplate(_Template t) {
    setState(() {
      _type = t.type;
      _titleController.text = t.title;
      _messageController.text = t.message;
    });
  }

  void _snack(String text) {
    TopToast.show(context, text);
  }

  Future<void> _post() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();
    if (title.isEmpty || message.isEmpty) {
      setState(() {
        _titleTouched = true;
        _messageTouched = true;
      });
      _snack('Please add both a title and a message.');
      return;
    }
    setState(() => _posting = true);
    try {
      final profile = await AdminService.instance.getProfile();
      final name = profile.name;
      await AnnouncementRepository.post(
        title: title,
        message: message,
        type: _type,
        pinned: _pinned,
        createdById: profile.uid.isEmpty ? null : profile.uid,
        createdByName: name,
      );
      if (!mounted) return;
      _titleController.clear();
      _messageController.clear();
      setState(() {
        _type = 'info';
        _pinned = false;
        _titleTouched = false;
        _messageTouched = false;
      });
      _snack('Announcement posted — customers can see it now.');
    } catch (e) {
      if (mounted) _snack("Couldn't post the announcement: $e");
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _togglePin(AnnouncementRecord a) async {
    try {
      await AnnouncementRepository.setPinned(a.id, !a.pinned);
    } catch (e) {
      if (mounted) _snack("Couldn't update the announcement: $e");
    }
  }

  Future<void> _confirmDelete(AnnouncementRecord a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete announcement?'),
        content: Text('"${a.title}" will be removed for all customers.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFB3261E)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AnnouncementRepository.delete(a.id);
      if (mounted) _snack('Announcement deleted.');
    } catch (e) {
      if (mounted) _snack("Couldn't delete the announcement: $e");
    }
  }

  InputDecoration _fieldDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13),
      filled: true,
      fillColor: AppPalette.surface(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }

  Widget _buildComposer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("New announcement", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
          const SizedBox(height: 4),
          Text("Customers will see this in their app.", style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _kTemplates)
                ActionChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 12)),
                  onPressed: () => _applyTemplate(t),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in AnnouncementType.all)
                ChoiceChip(
                  avatar: Icon(AnnouncementType.icon(type), size: 16, color: _type == type ? Colors.white : AnnouncementType.color(type)),
                  label: Text(
                    AnnouncementType.label(type),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _type == type ? Colors.white : AppPalette.textPrimary(context)),
                  ),
                  selected: _type == type,
                  selectedColor: AnnouncementType.color(type),
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleController,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _titleTouched = true),
            style: TextStyle(color: AppPalette.textPrimary(context)),
            decoration: _fieldDecoration(context, 'Title (e.g. Photobooth is closed today)').copyWith(
              counterText: '',
              errorText: _titleTouched ? _titleError : null,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _messageController,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() => _messageTouched = true),
            style: TextStyle(color: AppPalette.textPrimary(context)),
            decoration: _fieldDecoration(context, 'Message').copyWith(
              errorText: _messageTouched ? _messageError : null,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Switch(
                value: _pinned,
                activeThumbColor: AppColors.accent,
                onChanged: (v) => setState(() => _pinned = v),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Pin to top (stays on customers' Home screen)",
                  style: TextStyle(fontSize: 12.5, color: AppPalette.textSecondary(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _posting ? null : _post,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _posting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: Text(_posting ? 'Posting…' : 'Post announcement'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(BuildContext context, AnnouncementRecord a) {
    final color = AnnouncementType.color(a.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(AnnouncementType.icon(a.type), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.title,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                      ),
                    ),
                    if (a.pinned) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.push_pin_rounded, size: 14, color: AppPalette.textMuted(context)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(a.message, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppPalette.textSecondary(context))),
                const SizedBox(height: 8),
                Text(
                  "${AnnouncementType.label(a.type)} · ${a.createdByName.isEmpty ? 'Admin' : a.createdByName} · ${DateFormat('MMM d, h:mm a').format(a.createdAt)}",
                  style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: 20, color: AppPalette.textMuted(context)),
            tooltip: 'Options',
            onSelected: (v) {
              if (v == 'pin') _togglePin(a);
              if (v == 'delete') _confirmDelete(a);
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(value: 'pin', child: Text(a.pinned ? 'Unpin' : 'Pin to top')),
              const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _buildComposer(context),
        const SizedBox(height: 24),
        Text("Posted announcements", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
        const SizedBox(height: 12),
        StreamBuilder<List<AnnouncementRecord>>(
          stream: AnnouncementRepository.watchAll(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  "Couldn't load announcements. Check your Firestore rules for the 'announcements' collection.",
                  style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
              );
            }
            final list = snapshot.data!;
            if (list.isEmpty) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text("Nothing posted yet.", style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context))),
                    ),
                  ),
                  PaginationBar(page: 0, pageCount: 1, onPageChanged: (_) {}),
                ],
              );
            }
            _page = PageWindow.clamp(_page, list.length, pageSize: _pageSize);
            final pageItems = PageWindow.slice(list, _page, pageSize: _pageSize);
            return Column(
              children: [
                for (final a in pageItems) _buildTile(context, a),
                PaginationBar(
                  page: _page,
                  pageCount: PageWindow.pageCount(list.length, pageSize: _pageSize),
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
