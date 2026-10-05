import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/data/repositories/repositories.dart';

/// Branded splash — logo + app name, holds ~2.5s, then routes onward.
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  static const asset = 'assets/images/splash.png';
  static const minDuration = Duration(milliseconds: 2600);

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with TickerProviderStateMixin {
  late final AnimationController _enter;
  late final AnimationController _pulse;
  late final AnimationController _exit;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _loaderOpacity;
  late final Animation<double> _glow;
  late final Animation<double> _exitFade;

  final _started = DateTime.now();
  bool _navigated = false;
  bool _settingsReady = false;
  bool _prefsReady = false;

  @override
  void initState() {
    super.initState();

    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _exit = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _logoScale = Tween(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(
        parent: _enter,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _enter,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _enter,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );
    _titleSlide = Tween(begin: const Offset(0, 0.35), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _enter,
        curve: const Interval(0.35, 0.8, curve: Curves.easeOutCubic),
      ),
    );
    _loaderOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _enter,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
      ),
    );
    _glow = Tween(begin: 0.16, end: 0.34).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    _exitFade = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exit, curve: Curves.easeInCubic),
    );

    _enter.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncReadyFlags();
    });

    // Hard safety — never trap the user on splash.
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (!mounted || _navigated) return;
      _settingsReady = true;
      _prefsReady = true;
      unawaited(_finishWhenReady());
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _pulse.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _syncReadyFlags() {
    final settings = ref.read(shopSettingsProvider);
    final prefs = ref.read(appPrefsProvider);
    if (settings.hasValue || settings.hasError) _settingsReady = true;
    if (prefs.hasValue || prefs.hasError) _prefsReady = true;
    unawaited(_finishWhenReady());
  }

  Future<void> _finishWhenReady() async {
    if (_navigated || !_settingsReady || !_prefsReady) return;

    final elapsed = DateTime.now().difference(_started);
    final remaining = SplashPage.minDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted || _navigated) return;

    _navigated = true;
    await _exit.forward();
    if (!mounted) return;

    final prefsDone =
        ref.read(appPrefsProvider).valueOrNull?.prefsSetupDone ?? false;
    // First launch only: language / currency. Later launches → main app.
    context.go(prefsDone ? '/inventory' : '/setup');
  }

  @override
  Widget build(BuildContext context) {
    // Same as original logo plate + native launch (#003362).
    const brandBg = Color(0xFF003362);
    const brandAccent = Color(0xFF4A7FA8);
    final name = ref.watch(tProvider)('app_name');
    final size = MediaQuery.sizeOf(context);
    final logo = (size.shortestSide * 0.4).clamp(156.0, 220.0);

    ref.listen(shopSettingsProvider, (_, __) => _syncReadyFlags());
    ref.listen(appPrefsProvider, (_, __) => _syncReadyFlags());

    return Scaffold(
      backgroundColor: brandBg,
      body: FadeTransition(
        opacity: _exitFade,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: brandBg),
            AnimatedBuilder(
              animation: _glow,
              builder: (context, _) {
                return Align(
                  alignment: const Alignment(0, -0.18),
                  child: Container(
                    width: logo * 1.55,
                    height: logo * 1.55,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          brandAccent.withValues(alpha: _glow.value * 0.45),
                          brandAccent.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: AnimatedBuilder(
                animation: Listenable.merge([_enter, _pulse]),
                builder: (context, _) {
                  return Column(
                    children: [
                      const Spacer(flex: 3),
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: SizedBox(
                            width: logo,
                            height: logo,
                            child: Image.asset(
                              SplashPage.asset,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.inventory_2_rounded,
                                size: logo * 0.45,
                                color: brandAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _titleOpacity,
                          child: Text(
                            name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 36,
                              letterSpacing: -0.9,
                              height: 1.05,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(flex: 4),
                      FadeTransition(
                        opacity: _loaderOpacity,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: brandAccent.withValues(alpha: 0.95),
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
