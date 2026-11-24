// Provides the shared resize affordance icon.
// Used by resize handles across the application.

import 'package:elseplane/theme/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

// ---------- Widgets ----------

class ResizeIcon extends StatelessWidget {
  const ResizeIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.8,
      child: SvgPicture.asset(
        'assets/icons/resize.svg',
        width: BSizes.defaultIconSize,
        height: BSizes.defaultIconSize,
        colorFilter: ColorFilter.mode(
          BTheme.of(context).colors.resizeHandle,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}
