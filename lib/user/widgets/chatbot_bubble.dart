import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/chatbot_controller.dart';
import '../screens/my_bookings_screen.dart';
import '../services/chatbot_engine.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Floating "Ask Memoriae" button that expands into a chat panel.
///
/// Must be a direct child of a [Stack] (it uses [Positioned.fill]). Drop it
/// into `AppLayoutShell` so it shows on every tab. Empty areas of the overlay
/// let taps through to the page underneath.
///
/// The conversation itself lives in [ChatbotController] (a singleton), so it
/// survives tab switches even though the shell is rebuilt for each route.
class ChatbotBubble extends StatelessWidget {
  /// Distance of the round button from the bottom (raise it on mobile so it
  /// clears the floating bottom nav).
  final double fabBottom;

  /// Distance of the open panel from the bottom.
  final double panelBottom;

  /// Distance from the right edge.
  final double right;

  final double panelMaxWidth;

  const ChatbotBubble({
    super.key,
    this.fabBottom = 24,
    this.panelBottom = 24,
    this.right = 20,
    this.panelMaxWidth = 380,
  });

  @override
  Widget build(BuildContext context) {
    final c = ChatbotController.instance;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ValueListenableBuilder<bool>(
            valueListenable: c.expanded,
            builder: (context, open, _) {
              if (!open) {
                // Draggable "chat head": drag it anywhere, it snaps to the
                // nearest side on release and remembers where you left it
                // (even when you switch tabs).
                return _DraggableFab(
                  area: constraints.biggest,
                  right: right,
                  bottom: fabBottom,
                  onTap: c.open,
                );
              }
              final width = math.min(panelMaxWidth, constraints.maxWidth - right * 2);
              final height = math.max(220.0, math.min(560.0, constraints.maxHeight - panelBottom - 12));
              // Open the panel on the same side the chat head was left on.
              return Align(
                alignment: _chatFabOnLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                child: Padding(
                  padding: EdgeInsets.only(left: right, right: right, bottom: panelBottom),
                  child: SizedBox(width: width, height: height, child: const _ChatPanel()),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Which side the chat head was last left on (drives where the panel opens).
bool _chatFabOnLeft = false;

/// Last spot of the chat head as fractions (0..1) of the free area, so it
/// survives tab switches (the shell is rebuilt per route) and window resizes.
Offset? _chatFabSaved;

/// The round chat button that can be dragged anywhere on screen, like a
/// Messenger chat head. A tap (without dragging) opens the chat.
class _DraggableFab extends StatefulWidget {
  final Size area;
  final double right;
  final double bottom;
  final VoidCallback onTap;

  const _DraggableFab({required this.area, required this.right, required this.bottom, required this.onTap});

  @override
  State<_DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends State<_DraggableFab> {
  static const double _size = 56;
  static const double _margin = 10;

  Offset? _pos; // pixels, only while / right after dragging
  bool _dragging = false;

  double get _maxX => math.max(_margin, widget.area.width - _size - _margin);
  double get _maxY => math.max(_margin, widget.area.height - _size - _margin);

  Offset _clamp(Offset o) => Offset(o.dx.clamp(_margin, _maxX).toDouble(), o.dy.clamp(_margin, _maxY).toDouble());

  Offset _resolve() {
    if (_pos != null) return _clamp(_pos!);
    final saved = _chatFabSaved;
    if (saved != null) {
      return _clamp(Offset(saved.dx * (widget.area.width - _size), saved.dy * (widget.area.height - _size)));
    }
    // First time: bottom-right, where the old fixed button used to be.
    return _clamp(Offset(widget.area.width - _size - widget.right, widget.area.height - _size - widget.bottom));
  }

  void _onPanStart(DragStartDetails d) {
    setState(() {
      _pos = _resolve();
      _dragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _pos = _clamp((_pos ?? _resolve()) + d.delta));
  }

  void _onPanEnd(DragEndDetails d) {
    final cur = _resolve();
    final onLeft = cur.dx + _size / 2 < widget.area.width / 2;
    final snapped = Offset(onLeft ? _margin : _maxX, cur.dy);
    final w = widget.area.width - _size;
    final h = widget.area.height - _size;
    _chatFabOnLeft = onLeft;
    _chatFabSaved = Offset(w <= 0 ? 1 : snapped.dx / w, h <= 0 ? 1 : snapped.dy / h);
    setState(() {
      _pos = snapped;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pos = _resolve();
    // Keep the panel's side in sync even before the first drag.
    _chatFabOnLeft = pos.dx + _size / 2 < widget.area.width / 2;
    return Stack(
      children: [
        AnimatedPositioned(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: AnimatedScale(
              scale: _dragging ? 1.12 : 1,
              duration: const Duration(milliseconds: 120),
              child: _Fab(onTap: widget.onTap),
            ),
          ),
        ),
      ],
    );
  }
}

class _Fab extends StatelessWidget {
  final VoidCallback onTap;
  const _Fab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Chat with us',
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: AppShadows.accentGlowSmall),
        child: Material(
          color: AppColors.accent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.support_agent, color: AppColors.onAccent, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatPanel extends StatefulWidget {
  const _ChatPanel();

  @override
  State<_ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<_ChatPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _bot = ChatbotController.instance;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    _bot.send(text);
    _focus.requestFocus();
  }

  /// Switches tab (and closes the panel so it doesn't cover the new page).
  /// Skips the navigation when the customer is already on that tab, so e.g.
  /// tapping "Book now" while booking doesn't reset their half-filled form.
  void _go(String route, Object? arguments) {
    final nav = Navigator.of(context);
    final current = ModalRoute.of(context)?.settings.name;
    _bot.close();
    if (current == route && arguments == null) return;
    nav.pushReplacementNamed(route, arguments: arguments);
  }

  Future<void> _onAction(ChatAction a) async {
    switch (a.kind) {
      case ChatActionKind.suggest:
        await _bot.send(a.payload ?? a.label);
        break;
      case ChatActionKind.navigate:
        _go(a.route!, a.arguments);
        break;
      case ChatActionKind.myBookings:
        final nav = Navigator.of(context);
        _bot.close();
        nav.push(MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
        break;
      case ChatActionKind.handoff:
        final result = await _bot.handoffToStaff();
        if (result == HandoffResult.sent && mounted) _go('/messages', null);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.cardBg(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.divider(context)),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildMessages()),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppColors.accent,
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.onAccent.withValues(alpha: 0.14),
            child: const Icon(Icons.support_agent, color: AppColors.onAccent, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Memoriae Assistant', style: TextStyle(color: AppColors.onAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Packages, rentals & booking help', style: TextStyle(color: AppColors.onAccent, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.refresh, color: AppColors.onAccent, size: 20),
            onPressed: _bot.reset,
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: AppColors.onAccent, size: 22),
            onPressed: _bot.close,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    return ValueListenableBuilder<List<ChatMessage>>(
      valueListenable: _bot.messages,
      builder: (context, msgs, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: _bot.typing,
          builder: (context, typing, _) {
            // reverse:true keeps the newest message pinned to the bottom.
            final items = msgs.reversed.toList();
            final count = items.length + (typing ? 1 : 0);
            return ListView.builder(
              reverse: true,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              itemCount: count,
              itemBuilder: (context, i) {
                if (typing && i == 0) return const _TypingBubble();
                final index = typing ? i - 1 : i;
                final m = items[index];
                final isLatestBot = !typing && index == 0 && m.fromBot;
                return _MessageRow(message: m, showActions: isLatestBot, onAction: _onAction);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: AppPalette.divider(context)))),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context)),
              decoration: InputDecoration(
                hintText: 'Type your question…',
                hintStyle: TextStyle(color: AppPalette.textMuted(context), fontSize: 14),
                filled: true,
                fillColor: AppPalette.surface(context),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _submit,
            style: IconButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: AppColors.onAccent),
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final ChatMessage message;
  final bool showActions;
  final Future<void> Function(ChatAction) onAction;

  const _MessageRow({required this.message, required this.showActions, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final fromBot = message.fromBot;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final bubble = Align(
      alignment: fromBot ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: fromBot ? AppPalette.surface(context) : AppColors.accent,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(fromBot ? 4 : 16),
              bottomRight: Radius.circular(fromBot ? 16 : 4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: fromBot ? AppPalette.textPrimary(context) : AppColors.onAccent,
                ),
              ),
              if (message.isAi)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'AI answer · may not be 100% accurate',
                    style: TextStyle(fontSize: 10.5, color: AppPalette.textMuted(context)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          bubble,
          if (showActions && message.actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in message.actions) _ActionButton(action: a, dark: dark, onTap: () => onAction(a)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final ChatAction action;
  final bool dark;
  final VoidCallback onTap;

  const _ActionButton({required this.action, required this.dark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Quick-reply chips are outlined; buttons that *do* something (go to a
    // tab, contact staff) are filled so they stand out.
    final filled = action.kind != ChatActionKind.suggest;
    final outline = dark ? AppColors.highlight : AppColors.accent;
    return Material(
      color: filled ? AppColors.accent : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: filled ? AppColors.accent : outline.withValues(alpha: 0.6))),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            action.label,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: filled ? AppColors.onAccent : outline),
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppPalette.surface(context),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
            ),
          ),
          child: Text('Typing…', style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: AppPalette.textMuted(context))),
        ),
      ),
    );
  }
}