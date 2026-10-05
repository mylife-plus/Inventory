import 'package:flutter/material.dart';
import 'package:inventory_app/core/theme/app_theme.dart';

/// Soft pulsing loader used across loading states.
class AppLoader extends StatefulWidget {
  const AppLoader({
    super.key,
    this.size = 42,
    this.label,
  });

  final double size;
  final String? label;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: FadeSlideLike(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_c.value);
                return Transform.scale(
                  scale: 0.92 + (t * 0.08),
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      valueColor: AlwaysStoppedAnimation(p.neon),
                      backgroundColor: p.stroke.withValues(alpha: 0.45),
                    ),
                  ),
                );
              },
            ),
            if (widget.label != null) ...[
              const SizedBox(height: 14),
              Text(
                widget.label!,
                style: TextStyle(
                  color: p.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tiny local fade — avoids importing app_widgets (circular risk).
class FadeSlideLike extends StatelessWidget {
  const FadeSlideLike({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
