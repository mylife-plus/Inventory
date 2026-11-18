import 'package:flutter/widgets.dart';

/// While a text field has focus (keyboard open), the first tap anywhere in
/// [child] should only close the keyboard — not also trigger the button or
/// card under the finger (client, Nov 11: tapping another item on Sell →
/// Add items added it instead of just hiding the keyboard).
///
/// Wrap the scrollable, then guard tap handlers with
/// `if (guardKey.currentState?.consumeDismissTap() ?? false) return;`.
///
/// The pointer-down is seen here before the app-level tap-outside handling
/// unfocuses the field (this Listener sits deeper in the hit-test path), so
/// "was a text field focused when this tap started" is reliable on Android
/// and iOS alike.
class KeyboardTapGuard extends StatefulWidget {
  const KeyboardTapGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardTapGuard> createState() => KeyboardTapGuardState();
}

class KeyboardTapGuardState extends State<KeyboardTapGuard> {
  bool _dismissTap = false;

  static bool textFieldFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  /// True (and closes the keyboard) when the current tap started while a
  /// text field was focused; the caller then skips its action.
  bool consumeDismissTap() {
    if (!_dismissTap) return false;
    _dismissTap = false;
    FocusManager.instance.primaryFocus?.unfocus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _dismissTap = textFieldFocused(),
      child: widget.child,
    );
  }
}
