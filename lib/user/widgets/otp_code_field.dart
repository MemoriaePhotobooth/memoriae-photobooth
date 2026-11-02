import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Code input made of separate boxes. The accent outline sits on the box
/// that is being typed in and glides to the next one after every digit,
/// while the digit pops into its box. A hidden [TextField] does the real
/// typing, so the keyboard, paste and backspace all behave normally.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final int length;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onSubmitted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _focus]),
      builder: (context, _) {
        final text = widget.controller.text;
        final focused = _focus.hasFocus && widget.enabled;
        // The box being typed in; none once the code is complete.
        final active = text.length.clamp(0, widget.length);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focus.requestFocus(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < widget.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _box(context, i < text.length ? text[i] : '', focused && i == active),
                  ],
                ],
              ),
              // Invisible field on top that receives the typing.
              Positioned.fill(
                child: Opacity(
                  opacity: 0,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    autofocus: widget.autofocus,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    maxLength: widget.length,
                    showCursor: false,
                    enableInteractiveSelection: false,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                    onSubmitted: (_) => widget.onSubmitted?.call(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _box(BuildContext context, String digit, bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: 46,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? AppColors.accent : AppPalette.divider(context),
          width: isActive ? 1.8 : 1.2,
        ),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, anim) => ScaleTransition(
          scale: anim,
          child: FadeTransition(opacity: anim, child: child),
        ),
        child: digit.isEmpty
            ? const SizedBox.shrink(key: ValueKey('empty'))
            : Text(
                digit,
                key: ValueKey(digit),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppPalette.textPrimary(context)),
              ),
      ),
    );
  }
}
