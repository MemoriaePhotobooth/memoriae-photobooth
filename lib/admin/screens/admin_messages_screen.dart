import '../../shared/top_toast.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/chat_media.dart';
import '../../shared/thread_read.dart';
import '../models/message_record.dart';
import '../services/activity_log_repository.dart';
import '../services/message_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/ref_card.dart';

enum _InboxFilter { open, unread, closed }

/// Raw user ids are ugly — show "Guest abc12" when a thread has no name.
String _displayName(String name, String userId) {
  if (name.trim().isEmpty || name == userId) {
    return 'Guest ${userId.length > 5 ? userId.substring(0, 5) : userId}';
  }
  return name;
}

String _initial(String name) => name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Inbox: one row per customer thread, most recently active first.
///
/// On wide screens it's a two-pane helpdesk layout — conversation list on
/// the left, the open chat on the right. On phones, tapping a thread pushes
/// [AdminMessageThreadScreen] full-screen. [isDesktop] forces one or the
/// other; leave it null to decide by the available width.
class AdminMessagesScreen extends StatefulWidget {
  final bool? isDesktop;
  const AdminMessagesScreen({super.key, this.isDesktop});

  @override
  State<AdminMessagesScreen> createState() => _AdminMessagesScreenState();
}

class _AdminMessagesScreenState extends State<AdminMessagesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  int _page = 0;
  _InboxFilter _filter = _InboxFilter.open;
  String? _selectedUserId;
  String? _selectedName;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ConversationSummary> _applyFilters(List<ConversationSummary> all) {
    final q = _query.trim().toLowerCase();
    return all.where((s) {
      switch (_filter) {
        case _InboxFilter.open:
          if (s.isClosed) return false;
          break;
        case _InboxFilter.unread:
          if (s.isClosed || !s.hasUnread) return false;
          break;
        case _InboxFilter.closed:
          if (!s.isClosed) return false;
          break;
      }
      if (q.isEmpty) return true;
      return s.customerName.toLowerCase().contains(q) || s.lastMessage.toLowerCase().contains(q);
    }).toList();
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    if (_sameDay(dt, now)) return DateFormat('h:mm a').format(dt);
    if (_sameDay(dt, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, DateTime>>(
      stream: MessageRepository.watchClosedThreads(),
      builder: (context, closedSnap) => StreamBuilder<Map<String, DateTime>>(
        stream: ThreadReadStatus.watch(asStaff: false),
        builder: (context, readSnap) => _buildInbox(
          context,
          closedSnap.data ?? const <String, DateTime>{},
          readSnap.data ?? const <String, DateTime>{},
        ),
      ),
    );
  }

  Widget _buildInbox(BuildContext context, Map<String, DateTime> closedAt, Map<String, DateTime> readAt) {
    return StreamBuilder<List<MessageRecord>>(
      stream: MessageRepository.watchAllMessages(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.accent));
        }
        final all = snapshot.data!;
        if (all.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.forum_outlined, size: 40, color: AppPalette.textMuted(context)),
                const SizedBox(height: 10),
                Text("No messages yet", style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                const SizedBox(height: 2),
                Text("Customer conversations will show up here.", style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
              ],
            ),
          );
        }

        final byUser = <String, List<MessageRecord>>{};
        for (final m in all) {
          byUser.putIfAbsent(m.userId, () => []).add(m);
        }

        final summaries = byUser.entries.map((e) {
          final thread = e.value..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          final last = thread.last;
          // Newest non-empty name wins (staff/admin replies carry no name).
          final name = thread.reversed.map((m) => m.customerName).firstWhere((n) => n.isNotEmpty, orElse: () => e.key);
          return ConversationSummary(
            userId: e.key,
            customerName: name,
            lastMessage: last.text,
            lastMessageAt: last.sentAt,
            hasUnread: ThreadReadStatus.isUnread(fromCustomer: !last.fromAdmin, sentAt: last.sentAt, readAt: readAt[e.key]),
            isClosed: closedAt[e.key] != null && !last.sentAt.isAfter(closedAt[e.key]!),
          );
        }).toList()
          ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

        final openCount = summaries.where((s) => !s.isClosed).length;
        final unreadCount = summaries.where((s) => s.hasUnread && !s.isClosed).length;
        final closedCount = summaries.where((s) => s.isClosed).length;
        final filtered = _applyFilters(summaries);

        return LayoutBuilder(
          builder: (context, constraints) {
            final split = widget.isDesktop ?? constraints.maxWidth >= 900;

            _page = PageWindow.clamp(_page, filtered.length);
            final listColumn = Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: _InboxToolbar(
                    searchController: _searchController,
                    onSearchChanged: (q) => setState(() {
                      _query = q;
                      _page = 0;
                    }),
                    filter: _filter,
                    onFilter: (f) => setState(() {
                      _filter = f;
                      _page = 0;
                    }),
                    openCount: openCount,
                    unreadCount: unreadCount,
                    closedCount: closedCount,
                  ),
                ),
                Expanded(child: _inboxList(context, PageWindow.slice(filtered, _page), split: split)),
                PaginationBar(
                  page: _page,
                  pageCount: PageWindow.pageCount(filtered.length),
                  onPageChanged: (p) => setState(() => _page = p),
                ),
              ],
            );

            if (!split) return listColumn;

            // Auto-select the first conversation so the pane isn't empty.
            if (_selectedUserId == null && filtered.isNotEmpty) {
              _selectedUserId = filtered.first.userId;
              _selectedName = filtered.first.customerName;
            }
            final stillExists = summaries.any((s) => s.userId == _selectedUserId);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 340, child: listColumn),
                VerticalDivider(width: 1, color: AppPalette.divider(context)),
                Expanded(
                  child: (_selectedUserId == null || !stillExists)
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.chat_bubble_outline_rounded, size: 40, color: AppPalette.textMuted(context)),
                              const SizedBox(height: 10),
                              Text("Select a conversation", style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context))),
                            ],
                          ),
                        )
                      : _ThreadPane(key: ValueKey(_selectedUserId), userId: _selectedUserId!, customerName: _selectedName ?? ''),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _inboxList(BuildContext context, List<ConversationSummary> filtered, {required bool split}) {
    if (filtered.isEmpty) {
      final text = _query.trim().isNotEmpty
          ? "No conversations match your search."
          : (_filter == _InboxFilter.closed
              ? "No closed conversations."
              : (_filter == _InboxFilter.unread ? "You're all caught up." : "No open conversations."));
      return Center(child: Text(text, style: TextStyle(color: AppPalette.textMuted(context))));
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(split ? 8 : 16, 2, split ? 8 : 16, 16),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final s = filtered[i];
        final selected = split && s.userId == _selectedUserId;
        final name = _displayName(s.customerName, s.userId);
        final isPhoto = s.lastMessage == kPhotoMessageText;
        final previewStyle = TextStyle(
          fontSize: 12.5,
          color: s.hasUnread ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
          fontWeight: s.hasUnread ? FontWeight.w600 : FontWeight.normal,
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: selected ? AppColors.accentTint(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (split) {
                  setState(() {
                    _selectedUserId = s.userId;
                    _selectedName = s.customerName;
                  });
                } else {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AdminMessageThreadScreen(userId: s.userId, customerName: s.customerName)));
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: AppColors.accentTint(0.12),
                          child: Text(_initial(name), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 15)),
                        ),
                        if (s.hasUnread)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle, border: Border.all(color: AppPalette.bg(context), width: 2)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 14, fontWeight: s.hasUnread ? FontWeight.w800 : FontWeight.w700, color: AppPalette.textPrimary(context)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _relativeTime(s.lastMessageAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: s.hasUnread ? AppColors.accent : AppPalette.textMuted(context),
                                  fontWeight: s.hasUnread ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (!s.hasUnread) Text('You: ', style: previewStyle),
                              if (isPhoto) ...[
                                Icon(Icons.photo_camera_outlined, size: 13, color: previewStyle.color),
                                const SizedBox(width: 4),
                                Text('Photo', style: previewStyle),
                              ] else
                                Expanded(child: Text(s.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis, style: previewStyle)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Search box + Open / Unread / Closed segmented filter.
class _InboxToolbar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final _InboxFilter filter;
  final ValueChanged<_InboxFilter> onFilter;
  final int openCount;
  final int unreadCount;
  final int closedCount;

  const _InboxToolbar({
    required this.searchController,
    required this.onSearchChanged,
    required this.filter,
    required this.onFilter,
    required this.openCount,
    required this.unreadCount,
    required this.closedCount,
  });

  @override
  Widget build(BuildContext context) {
    Widget seg(_InboxFilter f, String label, int n) {
      final selected = filter == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => onFilter(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: selected ? AppColors.accent : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(
              n == 0 ? label : '$label  $n',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppPalette.textSecondary(context)),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
          decoration: InputDecoration(
            isDense: true,
            hintText: "Search customer or message",
            hintStyle: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
            prefixIcon: Icon(Icons.search, size: 18, color: AppPalette.textMuted(context)),
            suffixIcon: searchController.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      searchController.clear();
                      onSearchChanged('');
                    },
                  ),
            filled: true,
            fillColor: AppPalette.surface(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(13)),
          child: Row(
            children: [
              seg(_InboxFilter.open, 'Open', openCount),
              seg(_InboxFilter.unread, 'Unread', unreadCount),
              seg(_InboxFilter.closed, 'Closed', closedCount),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ready-made replies for the questions customers ask most. Tapping one
/// drops it into the reply box so it can be tweaked before sending.
/// `{name}` is replaced with the customer's first name.
const List<(String, String)> kQuickReplies = [
  ('Greeting', 'Hi {name}! Thanks for reaching out to Memoriae Photobooth. How can we help you today?'),
  ('Booking received', 'Hi {name}, we received your booking. We\'ll confirm it as soon as we\'ve checked your payment receipt.'),
  ('Payment reminder', 'Hi {name}, a friendly reminder that your remaining balance is due on or before your event date. Let us know if you have any questions!'),
  ('Reschedule', 'Hi {name}, sure — please tell us your preferred new date and time and we\'ll check availability for you.'),
  ('Rental reminder', 'Hi {name}, a reminder that your camera rental is due soon. Late returns may be charged an overdue fee.'),
  ('Thank you', 'Thank you so much, {name}! It was a pleasure serving you. We\'d love to hear your feedback in the app.'),
  ('Closing', 'Glad we could help, {name}! We\'ll close this conversation for now — message us anytime if you need anything else.'),
];

/// Whether a customer's thread is currently closed (closed, and the
/// customer hasn't written since). Shared by the header, the close button
/// and the thread body so they always agree.
class _ThreadClosedBuilder extends StatelessWidget {
  final String userId;
  final Widget Function(BuildContext context, bool isClosed) builder;
  const _ThreadClosedBuilder({required this.userId, required this.builder});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, DateTime>>(
      stream: MessageRepository.watchClosedThreads(),
      builder: (context, closedSnap) => StreamBuilder<List<MessageRecord>>(
        stream: MessageRepository.watchAllMessages(),
        builder: (context, msgSnap) {
          final thread = (msgSnap.data ?? const <MessageRecord>[]).where((m) => m.userId == userId).toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
          final closedAt = closedSnap.data?[userId];
          final isClosed = closedAt != null && (thread.isEmpty || !thread.last.sentAt.isAfter(closedAt));
          return builder(context, isClosed);
        },
      ),
    );
  }
}

/// "Close / Reopen" button + a "⋮" menu with "Clear chat".
class _ThreadActions extends StatefulWidget {
  final String userId;
  final String customerName;

  /// Called after the chat was cleared (the phone layout uses it to leave
  /// the now-empty thread).
  final VoidCallback? onCleared;
  const _ThreadActions({required this.userId, required this.customerName, this.onCleared});

  @override
  State<_ThreadActions> createState() => _ThreadActionsState();
}

class _ThreadActionsState extends State<_ThreadActions> {
  bool _busy = false;

  Future<void> _toggleClosed(bool isClosed) async {
    setState(() => _busy = true);
    try {
      if (isClosed) {
        await MessageRepository.reopenThread(widget.userId);
        TopToast.show(null, 'Conversation reopened.');
      } else {
        await MessageRepository.closeThread(widget.userId);
        TopToast.show(null, 'Conversation closed. It reopens if the customer writes again.');
      }
    } catch (_) {
      TopToast.show(null, "Couldn't update the conversation. Check your connection and permissions.", kind: TopToastKind.error);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _clearChat() async {
    final name = _displayName(widget.customerName, widget.userId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: Text(
          'This permanently deletes every message and photo in your conversation with $name. '
          'Their chat will be empty too. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear chat'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MessageRepository.clearThread(widget.userId);
      await ActivityLogRepository.log(action: 'Cleared conversation', targetSummary: name);
      TopToast.show(null, 'Chat with $name cleared.');
      widget.onCleared?.call();
    } catch (e) {
      TopToast.show(null, "Couldn't clear the chat: ${e.toString().replaceFirst('Exception: ', '')}", kind: TopToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ThreadClosedBuilder(
          userId: widget.userId,
          builder: (context, isClosed) => TextButton.icon(
            onPressed: _busy ? null : () => _toggleClosed(isClosed),
            style: TextButton.styleFrom(foregroundColor: AppPalette.textPrimary(context)),
            icon: Icon(isClosed ? Icons.lock_open_rounded : Icons.check_circle_outline_rounded, size: 18),
            label: Text(isClosed ? 'Reopen' : 'Close', style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: Icon(Icons.more_vert, color: AppPalette.textSecondary(context)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (v) {
            if (v == 'clear') _clearChat();
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'clear',
              child: Row(
                children: [
                  Icon(Icons.delete_sweep_outlined, size: 18, color: AppColors.accent),
                  SizedBox(width: 10),
                  Text('Clear chat', style: TextStyle(color: AppColors.accent)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The message list + composer, with no Scaffold/AppBar of its own — used
/// inline in the wide layout ([_ThreadPane]) and inside a Scaffold on
/// phones ([AdminMessageThreadScreen]).
class _ThreadBody extends StatefulWidget {
  final String userId;
  final String customerName;
  const _ThreadBody({super.key, required this.userId, required this.customerName});

  @override
  State<_ThreadBody> createState() => _ThreadBodyState();
}

class _ThreadBodyState extends State<_ThreadBody> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  ChatPickedImage? _attachment;
  int _lastCount = -1;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _firstName {
    final n = widget.customerName.trim();
    if (n.isEmpty || n == widget.userId) return 'there';
    return n.split(RegExp(r'\s+')).first;
  }

  void _useQuickReply(String template) {
    final text = template.replaceAll('{name}', _firstName);
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _attach() async {
    final image = await ChatMedia.pickImage(context, centered: true);
    if (image != null && mounted) setState(() => _attachment = image);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final image = _attachment;
    if ((text.isEmpty && image == null) || _sending) return;
    setState(() => _sending = true);
    try {
      await MessageRepository.sendMessage(userId: widget.userId, text: text, fromAdmin: true, image: image);
      _controller.clear();
      if (mounted) setState(() => _attachment = null);
    } catch (e) {
      if (mounted) {
        TopToast.show(context, "Couldn't send: ${e.toString().replaceFirst('Exception: ', '')}", kind: TopToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    if (_sameDay(d, now)) return 'Today';
    if (_sameDay(d, now.subtract(const Duration(days: 1)))) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ThreadClosedBuilder(
          userId: widget.userId,
          builder: (context, isClosed) => isClosed
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: AppPalette.cardBg(context),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 14, color: AppPalette.textMuted(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This conversation is closed. It reopens if the customer messages again, or tap Reopen.',
                          style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: Container(
            color: AppPalette.surface(context),
            child: StreamBuilder<List<MessageRecord>>(
              stream: MessageRepository.watchAllMessages(),
              builder: (context, snapshot) {
                final thread = (snapshot.data ?? const <MessageRecord>[]).where((m) => m.userId == widget.userId).toList()
                  ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
                _markSeen(thread);
                return _messageList(context, thread);
              },
            ),
          ),
        ),
        _composer(context),
      ],
    );
  }

  String? _seenMarkedId;

  /// Marks this thread as read once the customer's newest message is on screen.
  void _markSeen(List<MessageRecord> thread) {
    if (thread.isEmpty) return;
    final latest = thread.last;
    if (latest.fromAdmin || latest.id == _seenMarkedId) return;
    _seenMarkedId = latest.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ThreadReadStatus.markRead(widget.userId, asStaff: false).catchError((_) {});
    });
  }

  Widget _messageList(BuildContext context, List<MessageRecord> thread) {
    if (thread.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 36, color: AppPalette.textMuted(context)),
            const SizedBox(height: 8),
            Text("No messages yet", style: TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textSecondary(context))),
          ],
        ),
      );
    }

    // Keep the newest message in view when something arrives.
    if (thread.length != _lastCount) {
      final first = _lastCount == -1;
      _lastCount = thread.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final end = _scrollController.position.maxScrollExtent;
        if (first) {
          _scrollController.jumpTo(end);
        } else {
          _scrollController.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });
    }

    return LayoutBuilder(
      builder: (context, c) {
        final maxBubble = (c.maxWidth * 0.74).clamp(240.0, 480.0).toDouble();
        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          itemCount: thread.length,
          itemBuilder: (context, i) {
            final m = thread[i];
            final prev = i > 0 ? thread[i - 1] : null;
            final next = i < thread.length - 1 ? thread[i + 1] : null;
            final mine = m.fromAdmin;
            final newDay = prev == null || !_sameDay(prev.sentAt, m.sentAt);
            final startsGroup = prev == null || !_sameDay(prev.sentAt, m.sentAt) || prev.fromAdmin != mine;
            final endsGroup = next == null || !_sameDay(next.sentAt, m.sentAt) || next.fromAdmin != mine;

            final bubble = Padding(
              padding: EdgeInsets.only(top: (startsGroup && i != 0) ? 10 : 3),
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: _MessageBubble(message: m, mine: mine, endsGroup: endsGroup, maxWidth: maxBubble),
              ),
            );
            if (!newDay) return bubble;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: AppPalette.cardBg(context), borderRadius: BorderRadius.circular(999), border: Border.all(color: AppPalette.divider(context))),
                      child: Text(_dayLabel(m.sentAt), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppPalette.textMuted(context))),
                    ),
                  ),
                ),
                bubble,
              ],
            );
          },
        );
      },
    );
  }

  Widget _composer(BuildContext context) {
    final canSend = !_sending && (_controller.text.trim().isNotEmpty || _attachment != null);
    return Container(
      decoration: BoxDecoration(color: AppPalette.cardBg(context), border: Border(top: BorderSide(color: AppPalette.divider(context)))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                itemCount: kQuickReplies.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final (label, text) = kQuickReplies[i];
                  return ActionChip(
                    label: Text(label),
                    onPressed: () => _useQuickReply(text),
                    labelStyle: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppPalette.textPrimary(context)),
                    backgroundColor: AppPalette.surface(context),
                    side: BorderSide(color: AppPalette.divider(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  );
                },
              ),
            ),
            if (_attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChatAttachmentPreview(image: _attachment!, onRemove: _sending ? null : () => setState(() => _attachment = null)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Send a photo',
                    onPressed: _sending ? null : _attach,
                    icon: Icon(Icons.add_photo_alternate_outlined, color: AppPalette.textSecondary(context)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontSize: 13.5, color: AppPalette.textPrimary(context)),
                      decoration: InputDecoration(
                        hintText: _attachment == null ? "Type a reply…" : "Add a caption…",
                        hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 13.5),
                        filled: true,
                        fillColor: AppPalette.surface(context),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: canSend ? AppColors.accent : AppColors.accentTint(0.35),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: canSend ? _send : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _sending
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.send_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One chat bubble. The corner on the sender's side is squared off on the
/// last bubble of a run, so consecutive messages read as a group.
class _MessageBubble extends StatelessWidget {
  final MessageRecord message;
  final bool mine;
  final bool endsGroup;
  final double maxWidth;
  const _MessageBubble({required this.message, required this.mine, required this.endsGroup, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final m = message;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !endsGroup ? 18 : 5),
      bottomRight: Radius.circular(!mine || !endsGroup ? 18 : 5),
    );
    final textColor = mine ? Colors.white : AppPalette.textPrimary(context);
    final timeColor = mine ? Colors.white.withValues(alpha: 0.72) : AppPalette.textMuted(context);
    final imageWidth = (maxWidth - 8) < 260 ? (maxWidth - 8) : 260.0;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: m.hasImage ? const EdgeInsets.all(4) : const EdgeInsets.fromLTRB(14, 9, 14, 7),
      decoration: BoxDecoration(
        color: mine ? AppColors.accent : AppPalette.cardBg(context),
        borderRadius: radius,
        border: mine ? null : Border.all(color: AppPalette.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (m.hasRef)
            Padding(
              padding: m.hasImage ? const EdgeInsets.fromLTRB(10, 8, 10, 0) : const EdgeInsets.only(bottom: 6),
              child: buildRefCard(context, m, mine: mine, textColor: textColor),
            ),
          if (m.hasImage) ChatImage(imageId: m.imageId, maxWidth: imageWidth, radius: 14),
          if (m.caption.isNotEmpty)
            Padding(
              padding: m.hasImage ? const EdgeInsets.fromLTRB(10, 7, 10, 0) : EdgeInsets.zero,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(m.caption, style: TextStyle(fontSize: 13.5, height: 1.35, color: textColor)),
              ),
            ),
          Padding(
            padding: m.hasImage ? const EdgeInsets.fromLTRB(10, 4, 8, 4) : const EdgeInsets.only(top: 3),
            child: Text(DateFormat('h:mm a').format(m.sentAt), style: TextStyle(fontSize: 10, color: timeColor)),
          ),
        ],
      ),
    );
  }
}

/// Wide layout: a header (avatar, name, open/closed, actions) over the body.
class _ThreadPane extends StatelessWidget {
  final String userId;
  final String customerName;
  const _ThreadPane({super.key, required this.userId, required this.customerName});

  @override
  Widget build(BuildContext context) {
    final name = _displayName(customerName, userId);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
          decoration: BoxDecoration(color: AppPalette.cardBg(context), border: Border(bottom: BorderSide(color: AppPalette.divider(context)))),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: AppColors.accentTint(0.12),
                child: Text(_initial(name), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppPalette.textPrimary(context))),
                    _ThreadClosedBuilder(
                      userId: userId,
                      builder: (context, isClosed) => Text(
                        isClosed ? 'Closed' : 'Open conversation',
                        style: TextStyle(fontSize: 11.5, color: AppPalette.textMuted(context)),
                      ),
                    ),
                  ],
                ),
              ),
              _ThreadActions(userId: userId, customerName: customerName),
            ],
          ),
        ),
        Expanded(child: _ThreadBody(key: ValueKey(userId), userId: userId, customerName: customerName)),
      ],
    );
  }
}

/// Phones: a single conversation pushed full-screen.
class AdminMessageThreadScreen extends StatelessWidget {
  final String userId;
  final String customerName;
  const AdminMessageThreadScreen({super.key, required this.userId, required this.customerName});

  @override
  Widget build(BuildContext context) {
    final name = _displayName(customerName, userId);
    return Scaffold(
      backgroundColor: AppPalette.bg(context),
      appBar: AppBar(
        backgroundColor: AppPalette.cardBg(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.accentTint(0.12),
              child: Text(_initial(name), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  _ThreadClosedBuilder(
                    userId: userId,
                    builder: (context, isClosed) => Text(
                      isClosed ? 'Closed' : 'Open conversation',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal, color: AppPalette.textMuted(context)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          _ThreadActions(userId: userId, customerName: customerName, onCleared: () => Navigator.of(context).maybePop()),
          const SizedBox(width: 4),
        ],
      ),
      body: _ThreadBody(userId: userId, customerName: customerName),
    );
  }
}
