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

  /// Short trips to other apps / system sheets don't re-lock.
  static const lockAfter = Duration(seconds: 30);

  @override
  ConsumerState<PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<PinGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _checking = false;
  bool _initialCheckDone = false;
  DateTime? _backgroundedAt;

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
    if (_pinEnabled) {
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
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            _pinEnabled &&
            DateTime.now().difference(since) >= PinGate.lockAfter) {
          setState(() => _unlocked = false);
          _maybeUnlock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
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
        localizedReason: 'Unlock Inventory',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (mounted) setState(() => _unlocked = ok);
    } catch (_) {
      if (mounted) setState(() => _unlocked = true);
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
    final pin = ref.watch(appPrefsProvider).valueOrNull?.pinLock ?? false;
    final locked = pin && !_unlocked;
    final t = ref.watch(tProvider);

    return Stack(
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
