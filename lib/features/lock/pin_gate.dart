import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:local_auth/local_auth.dart';

/// Optional phone PIN / biometrics gate when enabled in Settings.
class PinGate extends ConsumerStatefulWidget {
  const PinGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PinGate> createState() => _PinGateState();
}

class _PinGateState extends ConsumerState<PinGate> with WidgetsBindingObserver {
  bool _unlocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      final pin = ref.read(appPrefsProvider).valueOrNull?.pinLock ?? false;
      if (pin) setState(() => _unlocked = false);
    } else if (state == AppLifecycleState.resumed) {
      _maybeLock();
    }
  }

  Future<void> _maybeLock() async {
    final pin = ref.read(appPrefsProvider).valueOrNull?.pinLock ?? false;
    if (!pin) {
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
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pin = ref.watch(appPrefsProvider).valueOrNull?.pinLock ?? false;
    if (!pin || _unlocked) return widget.child;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 12),
            Text(ref.watch(tProvider)('app_locked'), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _checking ? null : _maybeLock,
              child: Text(_checking ? '…' : ref.watch(tProvider)('continue_btn')),
            ),
          ],
        ),
      ),
    );
  }
}
