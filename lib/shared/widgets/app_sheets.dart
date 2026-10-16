import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// Darker modal scrim so popups stand out clearly (client review Oct 5).
const Color kAppScrim = Color(0xB3000000); // black @ 70%

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
    barrierColor: kAppScrim,
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
    barrierColor: kAppScrim,
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
    barrierColor: kAppScrim,
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
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
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
                  tooltip: ProviderScope.containerOf(context)
                      .read(tProvider)('close'),
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: p.textMuted),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: Column(
                  children: [
                    AppSheetTitle(title, padding: EdgeInsets.zero),
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
        const SizedBox(height: AppSheetTitle.gapBelow),
      ],
    );
  }
}

/// The one title style for every bottom sheet / popup (client, Oct 16):
/// 17 pt bold, centered, [gapAbove] under the drag handle and [gapBelow]
/// before the first row.
class AppSheetTitle extends StatelessWidget {
  const AppSheetTitle(this.title, {super.key, this.padding});

  static const double gapAbove = 14;
  static const double gapBelow = 18;

  final String title;

  /// Defaults to [gapAbove] / [gapBelow].
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.only(top: gapAbove, bottom: gapBelow),
      child: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 17,
          color: p.textPrimary,
        ),
      ),
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
    // Floating top panel is not at the screen bottom — no home-indicator gap.
    final fromTop = AppSheetStyle.maybeOf(context)?.fromTop ?? false;
    return SafeArea(
      top: false,
      bottom: !fromTop,
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


// ---------------------------------------------------------------------------
// Shared sort sheet — identical on Inventory, Sell, Customers, Turnover,
// Receipts. Each option has two directions toggled by a switch; the label
// shows the active direction (no arrows / check marks). Tapping the field
// selects it, tapping it again flips the switch. Reset + Sort buttons.
// ---------------------------------------------------------------------------

/// One sort criterion with two directions (e.g. Name A–Z / Name Z–A).
class SortOption<K> {
  const SortOption({
    required this.key,
    required this.icon,
    required this.label,
    required this.reversedLabel,
  });

  final K key;
  final IconData icon;

  /// Label for the default direction (toggle off).
  final String label;

  /// Label for the second direction (toggle on).
  final String reversedLabel;
}

/// Selected sort criterion + direction.
@immutable
class SortState<K> {
  const SortState(this.key, {this.reversed = false});

  final K key;
  final bool reversed;

  @override
  bool operator ==(Object other) =>
      other is SortState<K> && other.key == key && other.reversed == reversed;

  @override
  int get hashCode => Object.hash(key, reversed);
}

/// Opens the shared sort sheet. Returns the chosen state when the user taps
/// Sort, [defaultState] on Reset, or `null` when dismissed.
Future<SortState<K>?> showSortSheet<K>({
  required BuildContext context,
  required List<SortOption<K>> options,
  required SortState<K> current,
  required SortState<K> defaultState,
}) {
  return showAppSheet<SortState<K>>(
    context: context,
    alignTop: true,
    heightFactor: 0.8,
    builder: (ctx) => _SortSheetBody<K>(
      options: options,
      current: current,
      defaultState: defaultState,
    ),
  );
}

class _SortSheetBody<K> extends ConsumerStatefulWidget {
  const _SortSheetBody({
    required this.options,
    required this.current,
    required this.defaultState,
  });

  final List<SortOption<K>> options;
  final SortState<K> current;
  final SortState<K> defaultState;

  @override
  ConsumerState<_SortSheetBody<K>> createState() => _SortSheetBodyState<K>();
}

class _SortSheetBodyState<K> extends ConsumerState<_SortSheetBody<K>> {
  late K _selected = widget.current.key;
  late final Map<K, bool> _reversed = {
    for (final o in widget.options)
      o.key: o.key == widget.current.key ? widget.current.reversed : false,
  };

  /// Tapping the option field: the first tap selects the criterion, every
  /// further tap on the already-selected field flips its direction (same as
  /// tapping the toggle).
  void _select(K key) {
    AppHaptics.selection();
    setState(() {
      if (_selected == key) {
        _reversed[key] = !(_reversed[key] ?? false);
      } else {
        _selected = key;
      }
    });
  }

  void _toggle(K key, bool value) {
    AppHaptics.selection();
    setState(() {
      _reversed[key] = value;
      _selected = key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: t('sort')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.options.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _SortRow(
                    option: widget.options[i],
                    selected: widget.options[i].key == _selected,
                    reversed: _reversed[widget.options[i].key] ?? false,
                    palette: p,
                    onTap: () => _select(widget.options[i].key),
                    onToggle: (v) => _toggle(widget.options[i].key, v),
                  ),
                ],
              ],
            ),
          ),
        ),
        AppSheetActions(
          applyLabel: t('sort'),
          onReset: () => Navigator.pop(context, widget.defaultState),
          onApply: () => Navigator.pop(
            context,
            SortState<K>(_selected, reversed: _reversed[_selected] ?? false),
          ),
        ),
      ],
    );
  }
}

class _SortRow<K> extends StatelessWidget {
  const _SortRow({
    required this.option,
    required this.selected,
    required this.reversed,
    required this.palette,
    required this.onTap,
    required this.onToggle,
  });

  final SortOption<K> option;
  final bool selected;
  final bool reversed;
  final AppPalette palette;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? p.fabBorder : p.stroke,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
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
                  option.icon,
                  size: 20,
                  color: selected ? p.fabBorder : p.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: Text(
                    reversed ? option.reversedLabel : option.label,
                    key: ValueKey(reversed),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.2,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Transform.scale(
                scale: 0.85,
                child: Switch.adaptive(
                  value: reversed,
                  onChanged: onToggle,
                  activeTrackColor: p.fabBorder,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared filter sheet layout: header, scrollable body, Reset + Filter.
/// Use inside [showAppSheet] with `alignTop: true` (same as the sort sheet).
class AppFilterSheet extends ConsumerWidget {
  const AppFilterSheet({
    super.key,
    required this.child,
    required this.onReset,
    required this.onApply,
  });

  final Widget child;
  final VoidCallback onReset;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppSheetHeader(title: t('filter')),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: child,
          ),
        ),
        AppSheetActions(onReset: onReset, onApply: onApply),
      ],
    );
  }
}

/// Labeled group inside [AppFilterSheet] (e.g. "Category", "Contact").
class AppFilterSection extends StatelessWidget {
  const AppFilterSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: p.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Date field used by every date-range filter.
class AppFilterDateField extends StatelessWidget {
  const AppFilterDateField({
    super.key,
    required this.placeholder,
    required this.value,
    required this.onTap,
  });

  final String placeholder;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final v = value;
    final text = v == null
        ? placeholder
        : '${v.day.toString().padLeft(2, '0')}.'
            '${v.month.toString().padLeft(2, '0')}.${v.year}';
    return InkWell(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: p.cardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.stroke),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: v == null ? p.textMuted : p.textPrimary,
                ),
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 22, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Category dropdown used by inventory-style filters (only existing ones).
class AppCategoryDropdown extends ConsumerWidget {
  const AppCategoryDropdown({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  /// (id, name) pairs, already filtered to categories that still exist.
  final List<({String id, String name})> categories;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final safeValue =
        categories.any((c) => c.id == value) ? value : null;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.cardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.stroke),
      ),
      alignment: Alignment.center,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: safeValue,
          hint: Text(
            t('all_categories'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: p.textMuted,
            ),
          ),
          icon: Icon(Icons.arrow_drop_down_rounded, color: p.textMuted),
          dropdownColor: p.cardElevated,
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(t('all_categories')),
            ),
            for (final c in categories)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text(c.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Date picker helper shared by filters.
Future<DateTime?> pickFilterDate(BuildContext context, DateTime? initial) {
  return showDatePicker(
    context: context,
    initialDate: initial ?? DateTime.now(),
    firstDate: DateTime(2000),
    lastDate: DateTime.now().add(const Duration(days: 365)),
    barrierColor: kAppScrim,
  );
}
