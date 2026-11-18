import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// Shell without bottom nav — Figma uses top section icons instead.
/// Swipes move one step along the header icons, like a carousel.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchCount = 3;

  /// Branch a horizontal swipe lands on, or null (too slow).
  ///
  /// The header shows `[previous, next, CURRENT title]` (ClientHeader). A
  /// left→right swipe (v > 0) pulls in the icon right next to the title
  /// (`(i+1)%3`), right→left the outer one (`(i+2)%3`). E.g. on Customers
  /// (📦 💸 👤) left→right opens Cashflow, whose header is then 👤 📦 💸.
  static int? swipeTarget(int current, double velocity) {
    if (velocity.abs() < 280) return null;
    return velocity > 0
        ? (current + 1) % _branchCount
        : (current + 2) % _branchCount;
  }

  void _onSwipe(DragEndDetails details) {
    final i = navigationShell.currentIndex;
    final target = swipeTarget(i, details.primaryVelocity ?? 0);
    if (target == null || target == i) return;
    AppHaptics.selection();
    navigationShell.goBranch(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: _onSwipe,
        child: navigationShell,
      ),
    );
  }
}
