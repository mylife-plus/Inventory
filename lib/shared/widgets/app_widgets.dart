import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/core/utils/contact_launch.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';
import 'package:inventory_app/shared/widgets/local_photo.dart';

/// Soft press scale for premium tactile feel.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.enabled = true,
    this.scale = 0.96,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;

  /// Pressed scale (closer to 1 = subtler).
  final double scale;
  final bool haptic;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _setDown(bool v) {
    if (_down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final canTap = widget.enabled && widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: canTap
          ? (_) {
              if (widget.haptic) AppHaptics.selection();
              _setDown(true);
            }
          : null,
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: canTap ? widget.onTap : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: !widget.enabled
              ? 0.45
              : _down
              ? 0.88
              : 1,
          duration: Duration(milliseconds: _down ? 90 : 200),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class FadeSlide extends StatefulWidget {
  const FadeSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeSlide> createState() => _FadeSlideState();
}

class _FadeSlideState extends State<FadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        // Opacity 0 skips hit-testing — keep a tiny floor so taps work mid-animation.
        return Opacity(
          opacity: v <= 0 ? 0.01 : v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * widget.offset),
            child: Transform.scale(scale: 0.985 + (0.015 * v), child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class ClientHeader extends ConsumerWidget {
  const ClientHeader({
    super.key,
    required this.section,
    required this.title,
    required this.titleAsset,
    this.subtitle,
    this.showSell = false,
    this.showListActions = true,
    this.onMenu,
    this.onSearch,
    this.onFilter,
    this.sortActive = false,
    this.filterActive = false,
    this.searchActive = false,
    this.trailing,
  });

  final int section;
  final String title;
  final String titleAsset;
  /// Optional professional line under the centered title.
  final String? subtitle;
  final bool showSell;
  final bool showListActions;
  final VoidCallback? onMenu;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final bool sortActive;
  final bool filterActive;
  final bool searchActive;
  final Widget? trailing;

  void _go(BuildContext context, int i) {
    AppHaptics.selection();
    switch (i) {
      case 0:
        context.go('/inventory');
      case 1:
        context.go('/customers');
      case 2:
        context.go('/turnover');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);

    // Unselected = previous + next (circular) so left order matches design.
    const tabs = <({int id, String asset})>[
      (id: 0, asset: AppAssets.inventory),
      (id: 1, asset: AppAssets.customer),
      (id: 2, asset: AppAssets.turnover),
    ];
    final leftTabs = [
      tabs[(section + 2) % 3], // previous
      tabs[(section + 1) % 3], // next
    ];

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              // Client (Oct 8): the title is left-aligned, right next to the
              // nav buttons (one small gap), not centered on the screen.
              child: Row(
                children: [
                  for (var i = 0; i < leftTabs.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    _NavIcon(
                      asset: leftTabs[i].asset,
                      onTap: () => _go(context, leftTabs[i].id),
                    ),
                  ],
                  const SizedBox(width: _HeaderTitle.gapAfterNav),
                  Expanded(
                    child: _HeaderTitle(
                      title: title,
                      titleAsset: titleAsset,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    onTap: () => context.push('/settings'),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: AppIcon(
                          AppAssets.settings,
                          size: 24,
                          opacity: section == -1 ? 1 : 0.85,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  2 * 44 + 10 + _HeaderTitle.gapAfterNav,
                  4,
                  48,
                  0,
                ),
                child: Text(
                  subtitle!,
                  textAlign: TextAlign.start,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    height: 1.25,
                    color: p.textMuted,
                  ),
                ),
              ),
            if (showListActions || showSell || trailing != null)
              Padding(
                // Figma: clear gap under title row before actions
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (showListActions) ...[
                        HeaderActionIcon(
                          asset: AppAssets.sort,
                          onTap: onMenu,
                          active: sortActive,
                        ),
                        // Figma measure: centers ~72px → 24px icon + 48 gap
                        const SizedBox(width: 48),
                        HeaderActionIcon(
                          asset: AppAssets.filter,
                          onTap: onFilter,
                          active: filterActive,
                        ),
                        const SizedBox(width: 48),
                        TextFieldTapRegion(
                          child: HeaderActionIcon(
                            asset: AppAssets.search,
                            onTap: onSearch,
                            active: searchActive,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (showSell)
                        _SellButton(
                          label: t('sell'),
                          onTap: () {
                            AppHaptics.light();
                            context.push('/sell');
                          },
                        ),
                      ?trailing,
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Highlight for active sort / filter / search icons (client: orange).
const Color kActiveOrange = Color(0xFFFF9F0A);

/// Sort / filter / search row icon — same size + gaps as inventory header.
class HeaderActionIcon extends StatelessWidget {
  const HeaderActionIcon({
    super.key,
    required this.asset,
    this.onTap,
    this.active = false,
    this.color = const Color(0xFF919191),
  });

  final String asset;
  final VoidCallback? onTap;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final iconColor = active ? kActiveOrange : color;
    return Pressable(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      // Exact 24 glyph width so SizedBox gaps match Figma centers.
      child: SizedBox(
        width: 24,
        height: 40,
        child: Center(child: AppIcon(asset, size: 24, color: iconColor)),
      ),
    );
  }
}

/// Inventory-style sort / filter / search row with equal Figma gaps.
class ListActionIconsRow extends StatelessWidget {
  const ListActionIconsRow({
    super.key,
    this.onSort,
    this.onFilter,
    this.onSearch,
    this.sortActive = false,
    this.filterActive = false,
    this.searchActive = false,
  });

  final VoidCallback? onSort;
  final VoidCallback? onFilter;
  final VoidCallback? onSearch;
  final bool sortActive;
  final bool filterActive;
  final bool searchActive;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HeaderActionIcon(
          asset: AppAssets.sort,
          onTap: onSort,
          active: sortActive,
        ),
        const SizedBox(width: 48),
        HeaderActionIcon(
          asset: AppAssets.filter,
          onTap: onFilter,
          active: filterActive,
        ),
        const SizedBox(width: 48),
        TextFieldTapRegion(
          child: HeaderActionIcon(
            asset: AppAssets.search,
            onTap: onSearch,
            active: searchActive,
          ),
        ),
      ],
    );
  }
}

/// Selected section icon + title, left-aligned in the space after the nav
/// buttons. Never truncated: scales down when the title is long.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({
    required this.title,
    required this.titleAsset,
    required this.color,
  });

  final String title;
  final String titleAsset;
  final Color color;

  /// Space between the last nav button and the title icon.
  static const double gapAfterNav = 10;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 18,
      height: 1.1,
      color: color,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(titleAsset, size: 26),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                title,
                maxLines: 1,
                softWrap: false,
                style: style,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search box shown under list headers. Hides itself when the user taps
/// anywhere outside it (all pages behave the same).
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onDismiss,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onDismiss;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => FocusManager.instance.primaryFocus?.unfocus(),
        onTapOutside: (_) {
          FocusManager.instance.primaryFocus?.unfocus();
          // Defer so a list-card tap under the finger still receives onTap.
          WidgetsBinding.instance.addPostFrameCallback((_) => onDismiss());
        },
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          isDense: true,
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.asset, required this.onTap});

  final String asset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.stroke.withValues(alpha: 0.55)),
        ),
        child: AppIcon(asset, size: 26),
      ),
    );
  }
}

class _SellButton extends StatelessWidget {
  const _SellButton({required this.onTap, required this.label});
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 88, minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: p.stroke, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 16, color: p.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                height: 1.1,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SquareFab extends StatelessWidget {
  const SquareFab({
    super.key,
    required this.onPressed,
    this.heroTag,
    this.icon = Icons.add_rounded,
  });

  final VoidCallback onPressed;
  /// Kept for call-site compatibility; Heroes are intentionally unused
  /// (duplicate tags crash with shell + stacked routes).
  final Object? heroTag;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      scale: 0.92,
      onTap: () {
        AppHaptics.medium();
        onPressed();
      },
      child: Material(
        color: p.fab,
        elevation: 4,
        shadowColor: p.fab.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Center(child: Icon(icon, size: 28, color: Colors.white)),
        ),
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(12),
    this.borderColor,
  });

  /// Shared list-card corner radius (inventory / customers / sell / turnover).
  static const double radius = 8;

  /// Shared left thumbnail width — same as inventory cards.
  static const double thumbWidth = 100;

  /// Shared card body height so image / empty thumbs match.
  static const double minHeight = 96;

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final radius = BorderRadius.circular(AppCard.radius);
    // Container + clipBehavior clips the left image to rounded corners.
    // Material shape clip was leaving left top/bottom square on list thumbs.
    final card = Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? p.stroke, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;

    return Pressable(
      onTap: () {
        AppHaptics.selection();
        onTap!();
      },
      child: card,
    );
  }
}

/// Left image strip for inventory-style list cards (fixed width + left radii).
class CardThumb extends StatelessWidget {
  const CardThumb({
    super.key,
    this.path,
    this.badge,
    this.placeholderIcon = Icons.image_rounded,
    this.badgeColor,
    this.badgeTextColor = Colors.white,
  });

  final String? path;
  final String? badge;
  final IconData placeholderIcon;
  final Color? badgeColor;
  final Color badgeTextColor;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final r = AppCard.radius;
    final leftRadius = BorderRadius.only(
      topLeft: Radius.circular(r),
      bottomLeft: Radius.circular(r),
    );
    final screenW = MediaQuery.sizeOf(context).width;
    // Same look on small Android phones — slightly narrower thumb only.
    final thumbW = screenW < 360 ? 88.0 : AppCard.thumbWidth;
    return SizedBox(
      width: thumbW,
      height: AppCard.minHeight,
      child: ClipRRect(
        borderRadius: leftRadius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: p.cardElevated),
            LocalPhoto(path: path, placeholderIcon: placeholderIcon),
            if (badge != null && badge!.isNotEmpty)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor ?? Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: badgeTextColor,
                      height: 1.1,
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

/// Shared inventory-style horizontal media card row.
class MediaListCard extends StatelessWidget {
  const MediaListCard({
    super.key,
    required this.thumb,
    required this.child,
    this.onTap,
    this.borderColor,
  });

  final Widget thumb;
  final Widget child;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      borderColor: borderColor,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: AppCard.minHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            thumb,
            Expanded(child: ClipRect(child: child)),
          ],
        ),
      ),
    );
  }
}

class NeonText extends StatelessWidget {
  const NeonText(
    this.text, {
    super.key,
    this.size = 14,
    this.weight = FontWeight.w700,
  });

  final String text;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Text(
      text,
      style: TextStyle(color: p.neon, fontWeight: weight, fontSize: size),
    );
  }
}

class MoneyText extends ConsumerWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.size = 14,
    this.weight = FontWeight.w700,
    this.color,
    this.pickCurrency = false,
  });

  final String value;
  final double size;
  final FontWeight weight;
  final Color? color;
  final bool pickCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final text = Text(
      value,
      style: TextStyle(
        color: color ?? p.neon,
        fontWeight: weight,
        fontSize: size,
      ),
    );
    // Default: plain amount (currency already inside formatted value).
    // Only TotalLine / explicit pickers open currency sheet.
    if (!pickCurrency) return text;
    return Pressable(
      onTap: () => pickAndSaveCurrency(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: text,
      ),
    );
  }
}

class GreenPill extends StatelessWidget {
  const GreenPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => NeonText(label, size: 13);
}

class DangerPill extends StatelessWidget {
  const DangerPill(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Text(
      label,
      style: TextStyle(
        color: p.danger,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }
}

class TotalLine extends ConsumerWidget {
  const TotalLine({
    super.key,
    required this.label,
    required this.value,
    this.pickCurrency = true,
  });

  final String label;
  final String value;
  final bool pickCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 20,
              height: 1.1,
              color: p.textPrimary,
            ),
          ),
          const Spacer(),
          Pressable(
            enabled: pickCurrency,
            onTap: pickCurrency
                ? () => pickAndSaveCurrency(context, ref)
                : null,
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                height: 1.1,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TotalBanner extends StatelessWidget {
  const TotalBanner({
    super.key,
    required this.label,
    required this.value,
    this.icon = Icons.inventory_2_outlined,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => TotalLine(label: label, value: value);
}

class CardTotalLine extends ConsumerWidget {
  const CardTotalLine({
    super.key,
    required this.value,
    this.color,
    this.labelColor,
  });

  final String value;

  /// Amount color — inventory Figma uses white; turnover/customers use neon.
  final Color? color;
  final Color? labelColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final amountColor = color ?? p.textPrimary;
    final lbl = labelColor ?? p.textMuted;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${t('total')} ',
            style: TextStyle(
              color: lbl,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.1,
              letterSpacing: 0,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              color: amountColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
    );
  }
}

/// Unit price line: amount + currency bright; only "per" muted.
class PriceUnitLine extends ConsumerWidget {
  const PriceUnitLine({
    super.key,
    required this.amount,
    required this.symbol,
    this.unit,
  });

  final String amount;
  final String symbol;
  final String? unit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final hasUnit = unit != null && unit!.isNotEmpty;
    final per = ref.watch(tProvider)('per');
    final bright = TextStyle(
      color: p.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.15,
    );
    final muted = TextStyle(
      color: p.textMuted,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.15,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: amount, style: bright),
          TextSpan(text: ' $symbol', style: bright),
          if (hasUnit) ...[
            TextSpan(text: ' $per ', style: muted),
            TextSpan(text: unit, style: bright),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.expanded,
    this.onToggle,
  });

  final String title;
  final Widget? trailing;

  /// When set with [onToggle], title + arrow expand/collapse the section.
  final bool? expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 16,
      height: 1.15,
      color: p.textPrimary.withValues(alpha: 0.92),
    );

    final isExpandable = expanded != null && onToggle != null;
    final isOpen = expanded ?? true;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: titleStyle,
          ),
        ),
        if (isExpandable)
          AnimatedRotation(
            turns: isOpen ? 0 : 0.5,
            duration: const Duration(milliseconds: 180),
            child: Icon(
              Icons.arrow_drop_down_rounded,
              size: 36,
              color: p.textMuted,
            ),
          ),
      ],
    );

    final titleWidget = !isExpandable
        ? label
        : Pressable(onTap: onToggle, scale: 0.98, child: label);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 6),
      child: Row(
        children: [
          Expanded(child: titleWidget),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// Figma customer list / select-customer card.
class CustomerListCard extends ConsumerWidget {
  const CustomerListCard({
    super.key,
    required this.name,
    required this.money,
    this.stats,
    this.onTap,
    this.naStats = false,
    this.photoPath,
    this.subtitle,
    this.subtitleIcon,
    this.onSubtitleTap,
    this.contacts = const [],
    this.onContactTap,
    this.contactsInteractive = true,
  });

  final String name;
  final MoneyFormatter money;
  final CustomerStats? stats;
  final VoidCallback? onTap;

  /// Guest row: no purchase/total stats (a guest has no profile); shows a
  /// short localized "Walk-in customer" note instead.
  final bool naStats;
  final String? photoPath;

  /// Legacy single contact line (ignored when [contacts] is non-empty).
  final String? subtitle;
  final String? subtitleIcon;
  final VoidCallback? onSubtitleTap;

  /// Contact icons under the name (tap opens, long-press copies).
  final List<CustomerContact> contacts;

  /// Override default contact launch (e.g. attach receipt message).
  final ValueChanged<CustomerContact>? onContactTap;

  /// False: contact icons are display-only (taps fall through to [onTap]).
  final bool contactsInteractive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);

    final purchaseCount = '${stats?.purchaseCount ?? '…'}';
    const purchaseSize = 13.0;

    final amountText = stats == null
        ? '…'
        : money.formatAmount(stats!.totalSpent);

    final contactIcons = contacts;
    final sub = subtitle?.trim();

    Future<void> copyContact(CustomerContact c) async {
      await Clipboard.setData(ClipboardData(text: c.raw));
      AppHaptics.light();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ProviderScope.containerOf(context).read(tProvider)('copied'))),
        );
      }
    }

    void openContact(CustomerContact c) {
      if (onContactTap != null) {
        onContactTap!(c);
      } else {
        launchContact(c);
      }
    }

    // Whole card opens customer; only contact icons intercept taps.
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: AppCard.minHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardThumb(
              path: photoPath,
              placeholderIcon: Icons.person_rounded,
            ),
            Expanded(
              child: Padding(
                // Same title-to-photo padding as the Inventory item card.
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        height: 1.1,
                        color: p.textPrimary,
                      ),
                    ),
                    if (contactIcons.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 30,
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < contactIcons.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: contactsInteractive
                                      ? () => openContact(contactIcons[i])
                                      : null,
                                  onLongPress: contactsInteractive
                                      ? () => copyContact(contactIcons[i])
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: contactIcons[i].kind ==
                                            CustomerContactKind.phone
                                        ? const Icon(
                                            Icons.phone_rounded,
                                            size: 22,
                                            color: Color(0xFF34C759),
                                          )
                                        : AppIcon(
                                            contactIcons[i].iconAsset,
                                            size: 22,
                                          ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ] else if (sub != null && sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onSubtitleTap,
                        child: Row(
                          children: [
                            if (subtitleIcon == AppAssets.phone ||
                                subtitleIcon == null)
                              const Icon(
                                Icons.phone_rounded,
                                size: 14,
                                color: Color(0xFF34C759),
                              )
                            else
                              AppIcon(
                                subtitleIcon!,
                                size: 14,
                              ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  height: 1.15,
                                  color: p.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (naStats)
                      Text(
                        t('walk_in_customer'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textSecondary,
                          fontWeight: FontWeight.w500,
                          fontSize: purchaseSize,
                        ),
                      )
                    else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: purchaseCount,
                                  style: TextStyle(
                                    color: p.neon,
                                    fontWeight: FontWeight.w700,
                                    fontSize: purchaseSize,
                                  ),
                                ),
                                TextSpan(
                                  text: ' ${t(purchaseCount == '1' ? 'purchase' : 'purchases')}',
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: purchaseSize,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${t('total')} ',
                                style: TextStyle(
                                  color: p.textMuted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                              TextSpan(
                                text: amountText,
                                style: TextStyle(
                                  color: p.neon,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              TextSpan(
                                text: ' ${money.symbol}',
                                style: TextStyle(
                                  color: p.neon,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Center(
      child: FadeSlide(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.cardElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: p.stroke),
                ),
                child: Icon(icon, size: 32, color: p.fabBorder),
              ),
              const SizedBox(height: 14),
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
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textSecondary, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = true,
    this.color,
    this.foreground = Colors.white,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;
  final Color? color;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final enabled = onPressed != null;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          );
    final btn = Pressable(
      enabled: enabled,
      scale: 0.97,
      onTap: enabled
          ? () {
              AppHaptics.light();
              onPressed!();
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: expanded ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? (color ?? p.fab) : p.stroke,
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: (color ?? p.fab).withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: foreground,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
          child: IconTheme(
            data: IconThemeData(color: foreground, size: 18),
            child: child,
          ),
        ),
      ),
    );
    return expanded ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final btn = Pressable(
      enabled: onPressed != null,
      scale: 0.9,
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? (color ?? p.fab) : p.cardElevated,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : p.textPrimary,
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

class ConfirmCancelBar extends StatelessWidget {
  const ConfirmCancelBar({
    super.key,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete,
    this.confirmLabel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback? onDelete;
  /// When set, confirm is a wide labeled button (e.g. Sell → Items Sold).
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final labeled = confirmLabel != null && confirmLabel!.trim().isNotEmpty;
    // Figma: 2-btn gap ≈ 78 on ~62px buttons; 3-btn equal gaps ≈ 40.
    final gap = onDelete != null ? 36.0 : (labeled ? 16.0 : 72.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
        child: Row(
          mainAxisAlignment:
              labeled ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: [
            _SquareAction(
              icon: Icons.close_rounded,
              iconColor: p.danger,
              onTap: () {
                AppHaptics.light();
                onCancel();
              },
            ),
            if (onDelete != null) ...[
              SizedBox(width: gap),
              _SquareAction(
                icon: Icons.delete_outline_rounded,
                iconColor: Colors.white,
                background: p.danger,
                size: 48,
                iconSize: 24,
                onTap: () {
                  AppHaptics.medium();
                  onDelete!();
                },
              ),
            ],
            SizedBox(width: gap),
            if (labeled)
              Expanded(
                child: Pressable(
                  scale: 0.97,
                  onTap: () {
                    AppHaptics.medium();
                    onConfirm();
                  },
                  child: Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.stroke),
                    ),
                    child: Text(
                      confirmLabel!,
                      style: TextStyle(
                        color: p.neon,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
              )
            else
              _SquareAction(
                icon: Icons.check_rounded,
                iconColor: p.neon,
                onTap: () {
                  AppHaptics.medium();
                  onConfirm();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.background,
    this.size = 56,
    this.iconSize = 28,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final Color? background;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      scale: 0.9,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background ?? p.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: background != null ? background! : p.stroke,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}

class QtyStepper extends StatefulWidget {
  const QtyStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max,
    this.step = 1,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double? max;
  final double step;

  @override
  State<QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<QtyStepper> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _editing = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focus = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant QtyStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && !_disposed && oldWidget.value != widget.value) {
      final next = _format(widget.value);
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_disposed || !mounted) return;
    if (_focus.hasFocus) {
      _editing = true;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else if (_editing) {
      _editing = false;
      _commit();
    }
  }

  String _format(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  double? _parse(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double _clamp(double v) {
    var next = v;
    if (next < widget.min) next = widget.min;
    if (widget.max != null && next > widget.max!) next = widget.max!;
    if ((next - next.roundToDouble()).abs() < 1e-9) {
      next = next.roundToDouble();
    }
    return next;
  }

  void _emit(double next) {
    if (_disposed || !mounted) return;
    final clamped = _clamp(next);
    if ((clamped - widget.value).abs() < 1e-9) {
      final text = _format(widget.value);
      if (_controller.text != text) _controller.text = text;
      return;
    }
    widget.onChanged(clamped);
  }

  void _commit() {
    if (_disposed || !mounted) return;
    final parsed = _parse(_controller.text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    _emit(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final canDec = widget.value > widget.min + 1e-9;
    final canInc = widget.max == null || widget.value < widget.max! - 1e-9;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _box(
          context,
          Icons.remove_rounded,
          canDec ? () => _emit(widget.value - widget.step) : null,
        ),
        Container(
          width: 52,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.stroke),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              inputDecorationTheme: const InputDecorationTheme(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
            child: TextField(
            controller: _controller,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: p.textPrimary,
              height: 1.1,
            ),
            decoration: const InputDecoration(
              isDense: true,
              isCollapsed: true,
              filled: false,
              fillColor: Colors.transparent,
              hoverColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            ),
            onSubmitted: (_) {
              _commit();
              _focus.unfocus();
            },
          ),
          ),
        ),
        _box(
          context,
          Icons.add_rounded,
          canInc ? () => _emit(widget.value + widget.step) : null,
          accent: true,
        ),
      ],
    );
  }

  Widget _box(
    BuildContext context,
    IconData icon,
    VoidCallback? onTap, {
    bool accent = false,
  }) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap == null
          ? null
          : () {
              _focus.unfocus();
              onTap();
            },
      enabled: onTap != null,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: accent ? p.fabBorder : p.stroke),
        ),
        child: Icon(
          icon,
          size: 18,
          color: onTap == null
              ? p.textMuted
              : (accent ? p.fabBorder : p.textPrimary),
        ),
      ),
    );
  }
}

class SellChipButton extends ConsumerWidget {
  const SellChipButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return _SellButton(label: t('sell'), onTap: onPressed);
  }
}

class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionAppBar({
    super.key,
    required this.title,
    required this.section,
    this.trailing = const [],
  });

  final String title;
  final int section;
  final List<Widget> trailing;

  @override
  Size get preferredSize => const Size.fromHeight(0);

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ---------------------------------------------------------------------------
// Top notice — a short warning banner drawn at the top of the screen in the
// root overlay, so the keyboard (or a bottom bar) can never cover it.
// ---------------------------------------------------------------------------

OverlayEntry? _topNoticeEntry;

/// Shows [message] as a banner under the status bar for [duration].
/// A new notice replaces the current one.
void showTopNotice(
  BuildContext context,
  String message, {
  IconData icon = Icons.warning_amber_rounded,
  Duration duration = const Duration(milliseconds: 2800),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _topNoticeEntry?.remove();
  _topNoticeEntry = null;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TopNotice(
      message: message,
      icon: icon,
      duration: duration,
      onDone: () {
        if (_topNoticeEntry == entry) {
          entry.remove();
          _topNoticeEntry = null;
        }
      },
    ),
  );
  _topNoticeEntry = entry;
  overlay.insert(entry);
}

class _TopNotice extends StatefulWidget {
  const _TopNotice({
    required this.message,
    required this.icon,
    required this.duration,
    required this.onDone,
  });

  final String message;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDone;

  @override
  State<_TopNotice> createState() => _TopNoticeState();
}

class _TopNoticeState extends State<_TopNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final top = MediaQuery.paddingOf(context).top + 8;
    final curved = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.4),
            end: Offset.zero,
          ).animate(curved),
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: _dismiss,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: p.cardElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: p.danger, width: 1.2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: p.danger, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
