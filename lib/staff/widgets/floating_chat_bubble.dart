import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../shared/chat_media.dart';
import '../../shared/thread_read.dart';
import '../models/message_record.dart';
import 'ref_card.dart';
import '../services/message_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// A Facebook-Messenger-style floating chat widget for the Staff
/// desktop layout — a small round bubble anchored bottom-right that
/// expands into a compact panel without leaving whatever section
/// (Bookings, POS, etc.) is currently open. Reads/writes the exact same
/// `messages` collection as the full Messages section (see
/// [MessageRepository]), so nothing here is a separate inbox — it's just
/// another way into the same conversations.
///
/// Meant to be dropped directly into a `Stack` at the top of the
/// desktop `Scaffold`'s body, so it survives section changes instead of
/// being rebuilt (and losing its expanded/collapsed state) every time
/// the user switches tabs.
class FloatingChatBubble extends StatefulWidget {
  /// Called when the user taps "Open full view" from the panel header —
  /// the host screen should switch to its own full Messages section.
  final VoidCallback onOpenFullMessages;

  /// Distance from the bottom edge. The host raises this while the full
  /// Messages section is open so the bubble doesn't cover its Send button.
  final double bottomOffset;

  const FloatingChatBubble({super.key, required this.onOpenFullMessages, this.bottomOffset = 20});

  @override
  State<FloatingChatBubble> createState() => _FloatingChatBubbleState();
}

class _FloatingChatBubbleState extends State<FloatingChatBubble> {
  bool _expanded = false;
  String? _openUserId;
  String _openCustomerName = '';
  final _composerController = TextEditingController();
  final _threadScrollController = ScrollController();
  // Where the bubble sits, measured from the bottom-right corner. Null means the default spot.
  double? _right;
  double? _bottom;
  String? _seenMarkedId;

  @override
  void dispose() {
    _composerController.dispose();
    _threadScrollController.dispose();
    super.dispose();
  }

  void _openThread(String userId, String customerName) {
    setState(() {
      _openUserId = userId;
      _openCustomerName = customerName;
    });
  }

  void _backToList() => setState(() => _openUserId = null);

  Future<void> _send() async {
    final text = _composerController.text.trim();
    final userId = _openUserId;
    if (text.isEmpty || userId == null) return;
    _composerController.clear();
    await MessageRepository.sendMessage(userId: userId, customerName: _openCustomerName, text: text, fromStaff: true);
    if (_threadScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_threadScrollController.hasClients) {
          _threadScrollController.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, DateTime>>(
      stream: ThreadReadStatus.watch(asStaff: true),
      builder: (context, readSnap) {
        final readAt = readSnap.data ?? const <String, DateTime>{};
        return StreamBuilder<List<MessageRecord>>(
          stream: MessageRepository.watchAllMessages(),
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <MessageRecord>[];

            final byUser = <String, List<MessageRecord>>{};
            for (final m in all) {
              byUser.putIfAbsent(m.userId, () => []).add(m);
            }
            final summaries = byUser.entries.map((e) {
              final thread = e.value..sort((a, b) => a.sentAt.compareTo(b.sentAt));
              final last = thread.last;
              final name = thread.reversed.map((m) => m.customerName).firstWhere((n) => n.isNotEmpty, orElse: () => e.key);
              return ConversationSummary(
                userId: e.key,
                customerName: name,
                lastMessage: last.text,
                lastMessageAt: last.sentAt,
                hasUnread: ThreadReadStatus.isUnread(
                  fromCustomer: !last.fromStaff,
                  sentAt: last.sentAt,
                  readAt: readAt[e.key],
                ),
              );
            }).toList()
              ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
            final unreadCount = summaries.where((s) => s.hasUnread).length;

            final openId = _openUserId;
            final threadMessages = openId == null
                ? <MessageRecord>[]
                : (byUser[openId] ?? const <MessageRecord>[]).toList();
            threadMessages.sort((a, b) => b.sentAt.compareTo(a.sentAt)); // newest first, for a reversed ListView
            _markSeen(threadMessages);

            final size = MediaQuery.sizeOf(context);
            final panelW = _panelWidth(size);
            // Keep the panel fully on screen when open (it anchors bottom-right).
            final maxRight = size.width - panelW - _edge;
            final maxBottom = size.height - _minPanelH - _edge;
            final right = _expanded
                ? (_right ?? 20.0).clamp(_edge, maxRight < _edge ? _edge : maxRight).toDouble()
                : (_right ?? 20.0);
            final bottom = _expanded
                ? (_bottom ?? widget.bottomOffset).clamp(_edge, maxBottom < _edge ? _edge : maxBottom).toDouble()
                : (_bottom ?? widget.bottomOffset);
            final panelH = (size.height - bottom - 24).clamp(_minPanelH, _maxPanelH).toDouble();
            return Positioned(
              right: right,
              bottom: bottom,
              child: _expanded
                  ? _panel(context, summaries, threadMessages, width: panelW, height: panelH)
                  : GestureDetector(onPanUpdate: _dragBy, child: _bubble(unreadCount)),
            );
          },
        );
      },
    );
  }

  static const double _edge = 8, _bubbleSize = 56;
  // The open panel shrinks to fit the screen, but never below _minPanelH,
  // so its header (with Minimize) always stays reachable.
  static const double _minPanelH = 260, _maxPanelH = 460;

  static double _panelWidth(Size s) => (s.width - 16).clamp(260.0, 320.0).toDouble();

  /// Moves the bubble (or the open panel, from its header) with the finger,
  /// keeping it fully on screen.
  void _dragBy(DragUpdateDetails d) {
    final size = MediaQuery.sizeOf(context);
    final w = _expanded ? _panelWidth(size) : _bubbleSize;
    final h = _expanded ? _minPanelH : _bubbleSize;
    final maxRight = (size.width - w - _edge).clamp(_edge, double.infinity).toDouble();
    final maxBottom = (size.height - h - _edge).clamp(_edge, double.infinity).toDouble();
    setState(() {
      _right = ((_right ?? 20) - d.delta.dx).clamp(_edge, maxRight).toDouble();
      _bottom = ((_bottom ?? widget.bottomOffset) - d.delta.dy).clamp(_edge, maxBottom).toDouble();
    });
  }

  /// Marks the open thread as read once its newest message is on screen.
  /// Runs after the frame so the write doesn't happen mid-build.
  void _markSeen(List<MessageRecord> newestFirst) {
    if (newestFirst.isEmpty) return;
    final latest = newestFirst.first;
    if (latest.fromStaff || latest.id == _seenMarkedId) return;
    _seenMarkedId = latest.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ThreadReadStatus.markRead(latest.userId, asStaff: true).catchError((_) {});
    });
  }

  Widget _bubble(int unreadCount) {
    return Material(
      color: AppColors.accent,
      shape: const CircleBorder(),
      elevation: 6,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _expanded = true),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Center(child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 24)),
              if (unreadCount > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 18),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(999), border: Border.all(color: Colors.white, width: 1.5)),
                    child: Text('$unreadCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel(
    BuildContext context,
    List<ConversationSummary> summaries,
    List<MessageRecord> threadMessages, {
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          GestureDetector(onPanUpdate: _dragBy, child: _panelHeader(context)),
          Expanded(
            child: _openUserId == null ? _conversationList(context, summaries) : _threadView(context, threadMessages),
          ),
        ],
      ),
    );
  }

  Widget _panelHeader(BuildContext context) {
    return Container(
      color: AppColors.accent,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          if (_openUserId != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 19),
              onPressed: _backToList,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          if (_openUserId != null) const SizedBox(width: 10),
          Expanded(
            child: Text(
              _openUserId == null ? "Messages" : _openCustomerName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_full, color: Colors.white, size: 16),
            tooltip: "Open full view",
            onPressed: () {
              setState(() => _expanded = false);
              widget.onOpenFullMessages();
            },
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white, size: 19),
            tooltip: "Minimize",
            onPressed: () => setState(() => _expanded = false),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _conversationList(BuildContext context, List<ConversationSummary> summaries) {
    if (summaries.isEmpty) {
      return Center(child: Text("No conversations yet.", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: summaries.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: AppPalette.divider(context)),
      itemBuilder: (context, i) {
        final s = summaries[i];
        return InkWell(
          onTap: () => _openThread(s.userId, s.customerName),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.accentTint(0.12),
                  child: Text(
                    s.customerName.isNotEmpty ? s.customerName[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                      const SizedBox(height: 1),
                      Text(
                        s.lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: s.hasUnread ? AppPalette.textPrimary(context) : AppPalette.textMuted(context),
                          fontWeight: s.hasUnread ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(DateFormat('h:mm a').format(s.lastMessageAt), style: TextStyle(fontSize: 9.5, color: AppPalette.textMuted(context))),
                    if (s.hasUnread) ...[
                      const SizedBox(height: 4),
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _threadView(BuildContext context, List<MessageRecord> newestFirst) {
    return Column(
      children: [
        Expanded(
          child: newestFirst.isEmpty
              ? Center(child: Text("Say hello 👋", style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context))))
              : ListView.builder(
                  controller: _threadScrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: newestFirst.length,
                  itemBuilder: (context, i) {
                    final m = newestFirst[i];
                    return Align(
                      alignment: m.fromStaff ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: const BoxConstraints(maxWidth: 240),
                        decoration: BoxDecoration(
                          color: m.fromStaff ? AppColors.accent : AppPalette.surface(context),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (m.hasRef) ...[
                              buildRefCard(context, m, mine: m.fromStaff, textColor: m.fromStaff ? Colors.white : AppPalette.textPrimary(context)),
                              const SizedBox(height: 6),
                            ],
                            if (m.hasImage) ...[
                              ChatImage(imageId: m.imageId, maxWidth: 216, radius: 10),
                              if (m.caption.isNotEmpty) const SizedBox(height: 6),
                            ],
                            if (!m.hasImage || m.caption.isNotEmpty)
                              Text(
                                m.hasImage ? m.caption : m.text,
                                style: TextStyle(fontSize: 12.5, color: m.fromStaff ? Colors.white : AppPalette.textPrimary(context)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Divider(height: 1, color: AppPalette.divider(context)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _composerController,
                  onSubmitted: (_) => _send(),
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "Type a message…",
                    hintStyle: TextStyle(fontSize: 12.5, color: AppPalette.textMuted(context)),
                    filled: true,
                    fillColor: AppPalette.surface(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: AppColors.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _send,
                  child: const Padding(padding: EdgeInsets.all(9), child: Icon(Icons.send_rounded, size: 16, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}