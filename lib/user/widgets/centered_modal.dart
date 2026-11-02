import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The customer app's modal container: a rounded card that opens in the middle
/// of the screen (with a soft backdrop), instead of sliding up from the bottom.
/// Pass the content as [child]; it's limited to the screen height and should
/// scroll itself if it can get tall.
class CenteredModal extends StatelessWidget {
  final Widget child;
  final Color? color;
  final double maxWidth;

  const CenteredModal({super.key, required this.child, this.color, this.maxWidth = 420});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: color ?? AppPalette.cardBg(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: height * 0.85),
        child: child,
      ),
    );
  }
}
