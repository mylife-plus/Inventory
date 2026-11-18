import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:local_auth/local_auth.dart';

/// Optional phone PIN / biometrics gate when enabled in Settings.
///
/// The app (and its navigation stack) always stays mounted underneath; the
/// lock screen is an opaque overlay. Previously the whole app was swapped
/// out whenever the app went "inactive" — which also happens for the system
/// print sheet, share sheet, permission prompts and Face ID — so the user
/// lost their screen and could get stuck after printing.
class PinGate extends ConsumerStatefulWidget {
  const PinGate({super.key, required this.child});

  final Widget child;

  /// After this long in background, resume requires PIN again.
  /// Closing the app (or a cold start) requires PIN immediately.
  static const lockAfter = Duration(seconds: 30);

  @override
  ConsumerState<PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<PinGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _checking = false;
  bool _initialCheckDone = false;
  DateTime? _backgroundedAt;

  /// Set when the process is closing (`detached`). Next resume locks
  /// immediately (no 30s grace). Cold start also locks immediately.
  bool _closed = true;

  bool get _pinEnabled =>
      ref.read(appPrefsProvider).valueOrNull?.pinLock ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialCheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Cold start: lock once prefs are known (they load asynchronously).
  void _initialCheck() {
    if (_initialCheckDone || !mounted) return;
    if (!ref.read(appPrefsProvider).hasValue) return;
    _initialCheckDone = true;
    _closed = false;
    if (_pinEnabled) {
      // Closed / cold start: require PIN immediately.
      setState(() => _unlocked = false);
      _maybeUnlock();
    } else {
      setState(() => _unlocked = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The biometric prompt itself pauses / resumes the app — ignore that.
    if (_checking) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
        break;
      case AppLifecycleState.detached:
        // App is being closed — next open must prompt immediately.
        _closed = true;
        break;
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        final wasClosed = _closed;
        _backgroundedAt = null;
        _closed = false;
        if (!_pinEnabled) break;
        final awayLongEnough =
            since != null &&
            DateTime.now().difference(since) >= PinGate.lockAfter;
        // Immediate after close; after 30s when only backgrounded.
        if (wasClosed || awayLongEnough) {
          setState(() => _unlocked = false);
          _maybeUnlock();
        }
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _maybeUnlock() async {
    if (!_pinEnabled) {
      setState(() => _unlocked = true);
      return;
    }
    if (_unlocked || _checking) return;
    setState(() => _checking = true);
    try {
      final auth = LocalAuthentication();
      final ok = await auth.authenticate(
        localizedReason: ref.read(tProvider)('unlock_reason'),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (mounted) setState(() => _unlocked = ok);
    } catch (e) {
      // Stay locked — never silently open the app if the system prompt fails.
      debugPrint('PinGate auth failed: $e');
      if (mounted) setState(() => _unlocked = false);
    } finally {
      _backgroundedAt = null;
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appPrefsProvider, (_, next) {
      if (!_initialCheckDone && next.hasValue) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _initialCheck());
      }
    });
    final prefs = ref.watch(appPrefsProvider);
    final pin = prefs.valueOrNull?.pinLock ?? false;
    // Until prefs load on cold start, keep content gated (immediate lock path).
    final locked = (!_unlocked) && (!prefs.hasValue || pin);
    final t = ref.watch(tProvider);

    // expand: keep the navigator Overlay under tight full-screen constraints
    // (MaterialApp.builder uses SizedBox.expand for the same reason on web).
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the app (and navigator state) alive under the lock screen.
        ExcludeFocus(
          excluding: locked,
          child: IgnorePointer(ignoring: locked, child: widget.child),
        ),
        if (locked)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 40),
                    const SizedBox(height: 12),
                    Text(
                      t('app_locked'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _checking ? null : _maybeUnlock,
                      child: Text(_checking ? '…' : t('continue_btn')),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
