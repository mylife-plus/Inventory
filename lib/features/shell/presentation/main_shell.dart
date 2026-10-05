import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// Shell without bottom nav — Figma uses top section icons instead.
/// Swipes follow the left header icons (not linear tab index).
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _branchCount = 3;

  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 280) return;

    final i = navigationShell.currentIndex;
    // Match ClientHeader left icons: [(i+2)%3, (i+1)%3]
    // Inventory home → left icon = turnover, next = customers.
    // Swipe left→right (v > 0) → first left icon; right→left → second.
    final leftFirst = (i + 2) % _branchCount;
    final leftSecond = (i + 1) % _branchCount;
    final target = v > 0 ? leftFirst : leftSecond;
    if (target == i) return;
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
