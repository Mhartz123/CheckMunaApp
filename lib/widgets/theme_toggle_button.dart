import 'package:flutter/material.dart';
import '../services/theme_controller.dart';
import '../theme/app_colors.dart';

/// The light/dark switch, extracted so every screen can carry it instead of
/// only the Homepage. Shows the icon for whichever mode tapping will switch
/// *to*, not the current mode, following the usual convention: a moon
/// invites going dark, a sun invites going back to light.
///
/// Screens reached by `Navigator.push` (the packaging picker, the record
/// detail screen) are rebuilt from scratch after the theme is already set,
/// so a toggle there repaints correctly on the way back without any extra
/// wiring. The two permanently mounted tabs — Homepage and Records — are
/// rebuilt by the AnimatedBuilder at the root of main.dart, which is why
/// this widget must never be constructed as `const`: an identical const
/// instance is exactly what makes Flutter skip the rebuild that would
/// otherwise re-read [AppColors].
class ThemeToggleButton extends StatelessWidget {
  /// Matches the 20px icon buttons already used in the app bars.
  final double iconSize;

  /// The Homepage packs this next to the help icon in a tight custom header,
  /// so it needs the compact treatment. A standard AppBar has room for the
  /// default touch target.
  final bool compact;

  const ThemeToggleButton({
    super.key,
    this.iconSize = 20,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark;

    return IconButton(
      onPressed: () => ThemeController.instance.toggle(),
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      color: AppColors.muted,
      iconSize: iconSize,
      visualDensity: compact ? VisualDensity.compact : null,
      padding: compact ? EdgeInsets.zero : null,
      constraints: compact
          ? const BoxConstraints(minWidth: 36, minHeight: 36)
          : null,
      tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
    );
  }
}