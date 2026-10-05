import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// Style hint for sheet headers (bottom sheet vs floating header panel).
class AppSheetStyle extends InheritedWidget {
  const AppSheetStyle({
    super.key,
    required this.fromTop,
    required super.child,
  });

  final bool fromTop;

  static AppSheetStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSheetStyle>();

  @override
  bool updateShouldNotify(AppSheetStyle oldWidget) =>
      fromTop != oldWidget.fromTop;
}

/// Polished modal sheet shell used by filters / pickers across the app.
///
/// When [alignTop] is true, shows a floating panel under the app header
/// (not a clipped top-anchored bottom sheet).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  double? heightFactor,
  bool isDismissible = true,
  bool alignTop = false,
}) {
  if (alignTop) {
    return _showHeaderPanel<T>(
      context: context,
      builder: builder,
      heightFactor: heightFactor ?? 0.52,
      isDismissible: isDismissible,
    );
  }

  final p = AppPalette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final maxH = mq.size.height * (heightFactor ?? 0.78);
      return Stack(
        children: [
          if (isDismissible)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(ctx),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: Material(
                  color: p.cardElevated,
                  elevation: 12,
                  shadowColor: Colors.black54,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: AppSheetStyle(
                    fromTop: false,
                    child: builder(ctx),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// Floating sort/filter panel under the header — inset, rounded, no clipping.
Future<T?> _showHeaderPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required double heightFactor,
  required bool isDismissible,
}) {
  final p = AppPalette.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.42),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final mq = MediaQuery.of(ctx);
      // Sit just under ClientHeader (safe area + title + action row).
      final topInset = mq.padding.top + 102;
      final maxH = (mq.size.height - topInset - 24)
          .clamp(180.0, mq.size.height * heightFactor);

      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              top: topInset,
              left: 14,
              right: 14,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxH),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Material(
                      color: p.cardElevated,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: p.stroke),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: AppSheetStyle(
                        fromTop: true,
                        child: builder(ctx),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Confirm / alert dialog that is not a full-bleed black panel.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? cancelLabel,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final p = AppPalette.of(context);
  final t = ProviderScope.containerOf(context).read(tProvider);
  final cancel = cancelLabel ?? t('cancel');
  final confirm = confirmLabel ?? t('done');
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) {
      return Dialog(
        backgroundColor: p.cardElevated,
        elevation: 10,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.stroke),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(
                  color: p.textSecondary,
                  height: 1.35,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        cancel,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: p.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: destructive ? p.danger : p.fab,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        confirm,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}

class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.showClose = true,
  });

  final String title;
  final String? subtitle;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final fromTop = AppSheetStyle.maybeOf(context)?.fromTop ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!fromTop) ...[
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: p.stroke,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ] else
          const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.fromLTRB(8, fromTop ? 4 : 6, 8, 0),
          child: Row(
            children: [
              if (showClose)
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: p.textMuted),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: p.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: p.textMuted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }
}

class AppSheetActions extends ConsumerWidget {
  const AppSheetActions({
    super.key,
    required this.onReset,
    required this.onApply,
    this.resetLabel,
    this.applyLabel,
  });

  final VoidCallback onReset;
  final VoidCallback onApply;
  final String? resetLabel;
  final String? applyLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final reset = resetLabel ?? t('reset');
    final apply = applyLabel ?? t('filter');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  AppHaptics.selection();
                  onReset();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.danger,
                  backgroundColor: p.card,
                  side: BorderSide(color: p.stroke),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  reset,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: p.danger,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  AppHaptics.light();
                  onApply();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.fabBorder,
                  backgroundColor: p.card,
                  side: BorderSide(color: p.stroke),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  apply,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: p.fabBorder,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppChoiceChip extends StatelessWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return PressableChip(
      label: label,
      selected: selected,
      onTap: onTap,
      selectedColor: p.fabBorder.withValues(alpha: 0.22),
      unselectedColor: p.card,
      borderColor: selected ? p.fabBorder : p.stroke,
      textColor: selected ? p.textPrimary : p.textSecondary,
    );
  }
}

class PressableChip extends StatelessWidget {
  const PressableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.selectedColor,
    required this.unselectedColor,
    required this.borderColor,
    required this.textColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color selectedColor;
  final Color unselectedColor;
  final Color borderColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? selectedColor : unselectedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.1,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class AppRadioRow<T> extends StatelessWidget {
  const AppRadioRow({
    super.key,
    required this.label,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final T value;
  final T groupValue;
  final ValueChanged<T> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final selected = value == groupValue;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onChanged(value);
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? p.fabBorder : p.stroke,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? p.fabBorder.withValues(alpha: 0.18)
                        : p.cardElevated,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected ? p.fabBorder : p.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 22,
                color: selected ? p.fabBorder : p.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
