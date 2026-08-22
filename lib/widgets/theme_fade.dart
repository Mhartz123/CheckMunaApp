import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/theme_controller.dart';

class ThemeFade extends StatefulWidget {
  final Widget child;

  static const Duration duration = Duration(milliseconds: 450);

  static const double _maxWash = 0.88;

  const ThemeFade({super.key, required this.child});

  @override
  State<ThemeFade> createState() => _ThemeFadeState();
}

class _ThemeFadeState extends State<ThemeFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ThemeFade.duration,
  );

  bool _isDark = ThemeController.instance.isDark;

  Color _outgoing = AppColors.bg;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    final isDarkNow = ThemeController.instance.isDark;
    if (isDarkNow == _isDark) return;

    setState(() {

      _outgoing = AppColors.bgFor(dark: _isDark);
      _isDark = isDarkNow;
    });
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,

        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                if (!_controller.isAnimating && _controller.value == 0) {
                  return const SizedBox.shrink();
                }
                final t = Curves.easeOutCubic.transform(_controller.value);
                return ColoredBox(
                  color: _outgoing.withValues(
                    alpha: (1 - t) * ThemeFade._maxWash,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
