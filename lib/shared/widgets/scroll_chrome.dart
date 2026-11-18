import 'package:flutter/material.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

/// Shared scroll physics: short lists still scroll.
const ScrollPhysics kScrollChromePhysics = AlwaysScrollableScrollPhysics(
  parent: ClampingScrollPhysics(),
);

/// Scroll-driven chrome: **one** menu bar painted as an overlay.
///
/// The scroll view only keeps a height spacer; the visible menu is always the
/// overlay, so returning to the top never reveals a second “fixed” bar and
/// never snaps. Mid-page upward scroll smoothly reveals it (sticky navbar).
class ScrollChromeController extends ChangeNotifier {
  ScrollChromeController() {
    scrollController.addListener(_onScroll);
  }

  bool _chromeVisible = true;
  bool _atTop = true;
  bool _showScrollTop = false;
  /// Mid-page sticky reveal (upward scroll). Cleared when scrolling down or
  /// when settled back at the top.
  bool _sticky = false;
  /// After sticky settles at top, keep the bar fully shown until the user
  /// scrolls the header away again (avoids a half-hide jump).
  bool _settleFromSticky = false;
  double _lastPixels = 0;
  double _pixels = 0;
  double _directionAccum = 0;
  double _lastMaxExtent = -1;
  double _headerBodyHeight = kToolbarHeight;
  bool _reevaluateScheduled = false;
  bool _programmaticScroll = false;
  bool _disposed = false;
  WidgetBuilder? _overlayHeaderBuilder;
  bool _overlayNotifyScheduled = false;

  bool get chromeVisible => _chromeVisible;
  bool get atTop => _atTop;
  bool get showScrollTop => _showScrollTop;
  bool get sticky => _sticky;
  bool get settleFromSticky => _settleFromSticky;
  double get pixels => _pixels;
  double get headerBodyHeight => _headerBodyHeight;

  WidgetBuilder? get overlayHeaderBuilder => _overlayHeaderBuilder;

  final ScrollController scrollController = ScrollController();

  static const double _hysteresis = 24;
  static const double _extentEpsilon = 1;

  void attachOverlayHeaderBuilder(WidgetBuilder builder) {
    _overlayHeaderBuilder = builder;
    if (_overlayNotifyScheduled) return;
    _overlayNotifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayNotifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void setHeaderBodyHeight(double height) {
    if (_disposed || height <= 0) return;
    if ((height - _headerBodyHeight).abs() < 0.5) return;
    _headerBodyHeight = height;
    notifyListeners();
  }

  void _onScroll() {
    if (_programmaticScroll) return;
    if (!scrollController.hasClients) return;
    final pos = scrollController.position;
    final raw = pos.pixels;
    final maxE = pos.maxScrollExtent;
    final pixels = raw.clamp(0.0, maxE < 0 ? 0.0 : maxE);
    if (raw < -0.5 || (maxE >= 0 && raw > maxE + 0.5)) {
      _lastPixels = pixels;
      _directionAccum = 0;
      return;
    }
    final delta = pixels - _lastPixels;
    _applyScroll(pixels: pixels, maxExtent: maxE, delta: delta);
    _lastPixels = pixels;
  }

  void handleNotification(ScrollNotification n) {
    if (_programmaticScroll) return;
    if (scrollController.hasClients) return;
    if (n.metrics.axis != Axis.vertical) return;
    if (n.depth > 0) return;
    final maxE = n.metrics.maxScrollExtent;
    final raw = n.metrics.pixels;
    final pixels = raw.clamp(0.0, maxE < 0 ? 0.0 : maxE);
    if (raw < -0.5 || (maxE >= 0 && raw > maxE + 0.5)) {
      _directionAccum = 0;
      return;
    }
    final delta = n is ScrollUpdateNotification ? (n.scrollDelta ?? 0.0) : 0.0;
    _applyScroll(pixels: pixels, maxExtent: maxE, delta: delta);
  }

  void _applyScroll({
    required double pixels,
    required double maxExtent,
    required double delta,
  }) {
    _pixels = pixels;
    final canScroll = maxExtent > _hysteresis;
    if (!canScroll) {
      _directionAccum = 0;
      _chromeVisible = true;
      _atTop = true;
      _sticky = false;
      _settleFromSticky = false;
      _showScrollTop = false;
      notifyListeners();
      return;
    }

    final atTop = pixels <= _hysteresis;
    final pastHeader = pixels > _headerBodyHeight;
    if (_settleFromSticky && pastHeader) {
      _settleFromSticky = false;
    }

    if (atTop) {
      _directionAccum = 0;
      _chromeVisible = true;
      _atTop = true;
      // Settle into the top bar — keep visible, drop sticky mode. No snap-hide.
      if (_sticky) {
        _sticky = false;
        _settleFromSticky = true;
      }
      _showScrollTop = false;
      notifyListeners();
      return;
    }

    _atTop = false;

    if (delta == 0) {
      notifyListeners();
      return;
    }

    if (_directionAccum != 0 && delta.sign != _directionAccum.sign) {
      _directionAccum = 0;
    }
    _directionAccum += delta;

    if (_directionAccum >= _hysteresis) {
      _directionAccum = 0;
      _chromeVisible = false;
      _showScrollTop = false;
      _sticky = false;
    } else if (_directionAccum <= -_hysteresis) {
      _directionAccum = 0;
      _chromeVisible = true;
      _showScrollTop = true;
      // Only enter sticky once the natural header has scrolled away.
      if (pastHeader) _sticky = true;
    }

    // Pixel changes always rebuild overlay (scroll-linked settle near top).
    notifyListeners();
  }

  Future<void> scrollToTop() async {
    AppHaptics.selection();
    if (!scrollController.hasClients) return;
    _programmaticScroll = true;
    try {
      await scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _programmaticScroll = false;
    }
    _chromeVisible = true;
    _atTop = true;
    _sticky = false;
    _settleFromSticky = false;
    _showScrollTop = false;
    _pixels = 0;
    _lastPixels = 0;
    _directionAccum = 0;
    notifyListeners();
  }

  void reevaluate() {
    if (!scrollController.hasClients) {
      if (!_chromeVisible || !_atTop || _sticky || _showScrollTop) {
        _chromeVisible = true;
        _atTop = true;
        _sticky = false;
        _settleFromSticky = false;
        _showScrollTop = false;
        _directionAccum = 0;
        notifyListeners();
      }
      return;
    }
    final maxE = scrollController.position.maxScrollExtent;
    if (_lastMaxExtent >= 0 &&
        (maxE - _lastMaxExtent).abs() <= _extentEpsilon) {
      return;
    }
    _lastMaxExtent = maxE;
    final pixels =
        scrollController.position.pixels.clamp(0.0, maxE < 0 ? 0.0 : maxE);
    _applyScroll(pixels: pixels, maxExtent: maxE, delta: 0);
  }

  void scheduleReevaluate() {
    if (_reevaluateScheduled) return;
    _reevaluateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reevaluateScheduled = false;
      if (!_disposed) reevaluate();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }
}

/// Provides [ScrollChromeController] to in-scroll headers.
class ScrollChromeScope extends InheritedWidget {
  const ScrollChromeScope({
    super.key,
    required this.chrome,
    required super.child,
  });

  final ScrollChromeController chrome;

  static ScrollChromeController? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<ScrollChromeScope>()
      ?.chrome;

  @override
  bool updateShouldNotify(ScrollChromeScope oldWidget) =>
      chrome != oldWidget.chrome;
}

/// Status bar + header spacer slivers for [CustomScrollView].
abstract final class ScrollChrome {
  /// Pinned strip matching [MediaQuery.padding.top] so content never scrolls
  /// under the status bar.
  static Widget statusBar(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return PinnedHeaderSliver(
      child: ColoredBox(
        color: bg,
        child: SizedBox(height: top, width: double.infinity),
      ),
    );
  }

  /// Reserves header height in the scroll extent; the visible menu is the
  /// overlay (see [_StickyOverlayMenu]) so there is never a second bar.
  static Widget floatingHeader({
    required BuildContext context,
    required WidgetBuilder header,
    ScrollChromeController? chrome,
  }) {
    final c = chrome ?? ScrollChromeScope.maybeOf(context);
    c?.attachOverlayHeaderBuilder(header);
    return SliverToBoxAdapter(
      child: _HeaderHeightSpacer(chrome: c, header: header),
    );
  }

  /// Convenience: [statusBar] then [floatingHeader].
  static List<Widget> headerSlivers({
    required BuildContext context,
    required WidgetBuilder header,
    ScrollChromeController? chrome,
  }) =>
      [
        statusBar(context),
        floatingHeader(context: context, header: header, chrome: chrome),
      ];
}

/// Measures [header] offstage and keeps an equal-height spacer in the list.
class _HeaderHeightSpacer extends StatefulWidget {
  const _HeaderHeightSpacer({required this.chrome, required this.header});

  final ScrollChromeController? chrome;
  final WidgetBuilder header;

  @override
  State<_HeaderHeightSpacer> createState() => _HeaderHeightSpacerState();
}

class _HeaderHeightSpacerState extends State<_HeaderHeightSpacer> {
  final GlobalKey _key = GlobalKey();

  /// Height this spacer was last built with.
  double? _builtHeight;

  @override
  void initState() {
    super.initState();
    widget.chrome?.addListener(_onChrome);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant _HeaderHeightSpacer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chrome != widget.chrome) {
      oldWidget.chrome?.removeListener(_onChrome);
      widget.chrome?.addListener(_onChrome);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    widget.chrome?.removeListener(_onChrome);
    super.dispose();
  }

  /// The measured header height lands after the first frame. Rebuild only
  /// when it actually changed (not on every scroll notification), otherwise
  /// the list keeps the old reserved height and the first cards sit under
  /// the header until something else happens to rebuild the page.
  void _onChrome() {
    final h = widget.chrome?.headerBodyHeight;
    if (!mounted || h == null || h == _builtHeight) return;
    setState(() {});
  }

  void _measure() {
    if (!mounted) return;
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    widget.chrome?.setHeaderBodyHeight(box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.chrome?.headerBodyHeight ?? kToolbarHeight;
    _builtHeight = h;
    // Measure unconstrained, then reserve that height in the scroll extent.
    return SizedBox(
      height: h,
      width: double.infinity,
      child: OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: Alignment.topCenter,
        child: Opacity(
          opacity: 0,
          child: IgnorePointer(
            child: KeyedSubtree(
              key: _key,
              child: widget.header(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of [ConfirmCancelBar] (56 buttons + 10/20 padding) without the
/// bottom safe area — room a list leaves for a [ScrollChromeHost.floatingBottomBar].
const double kFloatingBottomBarHeight = 86;

/// Scaffold host: FABs + single overlay menu.
class ScrollChromeHost extends StatefulWidget {
  const ScrollChromeHost({
    super.key,
    required this.builder,
    this.primaryFab,
    this.primaryFabLocation = FloatingActionButtonLocation.centerFloat,
    this.scrollTopHeroTag = 'scroll_top_fab',
    this.bottomNavigationBar,
    this.floatingBottomBar,
  });

  final Widget Function(BuildContext context, ScrollChromeController chrome)
      builder;

  final Widget? primaryFab;
  final FloatingActionButtonLocation primaryFabLocation;
  final Object scrollTopHeroTag;
  final Widget? bottomNavigationBar;

  /// Bottom buttons drawn over the list (no bar background). They hide on
  /// scroll down and come back on scroll up, like [primaryFab], and stay
  /// away while the keyboard is open. The list must leave room for them at
  /// its end ([kFloatingBottomBarHeight] + bottom safe area).
  final Widget? floatingBottomBar;

  @override
  State<ScrollChromeHost> createState() => _ScrollChromeHostState();
}

class _ScrollChromeHostState extends State<ScrollChromeHost> {
  late final ScrollChromeController _chrome = ScrollChromeController();

  @override
  void dispose() {
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        if (n.metrics.axis != Axis.vertical) return false;
        _chrome.scheduleReevaluate();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _chrome.handleNotification(n);
          return false;
        },
        child: ScrollChromeScope(
          chrome: _chrome,
          child: Builder(
            builder: (scopedContext) =>
                widget.builder(scopedContext, _chrome),
          ),
        ),
      ),
    );

    // Read above the Scaffold: its body no longer sees the keyboard inset.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      floatingActionButtonLocation: widget.primaryFabLocation,
      floatingActionButton: widget.primaryFab == null
          ? null
          : ListenableBuilder(
              listenable: _chrome,
              builder: (_, _) {
                final show = _chrome.chromeVisible;
                return IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    opacity: show ? 1 : 0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      offset: show ? Offset.zero : const Offset(0, 0.2),
                      child: widget.primaryFab!,
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          // Below the pinned status-bar sliver — one menu, no duplicate.
          Positioned(
            top: MediaQuery.paddingOf(context).top,
            left: 0,
            right: 0,
            child: _StickyOverlayMenu(chrome: _chrome),
          ),
          if (widget.floatingBottomBar != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ListenableBuilder(
                listenable: _chrome,
                builder: (_, _) {
                  final show = _chrome.chromeVisible && !keyboardOpen;
                  return IgnorePointer(
                    ignoring: !show,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      opacity: show ? 1 : 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut,
                        offset: show ? Offset.zero : const Offset(0, 0.35),
                        child: widget.floatingBottomBar!,
                      ),
                    ),
                  );
                },
              ),
            ),
          ListenableBuilder(
            listenable: _chrome,
            builder: (_, _) {
              final show = _chrome.showScrollTop;
              return Positioned(
                right: 16,
                bottom: 24,
                child: IgnorePointer(
                  ignoring: !show,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    opacity: show ? 1 : 0,
                    child: AnimatedSlide(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      offset: show ? Offset.zero : const Offset(0, 0.35),
                      child: SafeArea(
                        child: _ScrollTopFab(
                          heroTag: widget.scrollTopHeroTag,
                          onPressed: _chrome.scrollToTop,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Single menu bar: scroll-linked near top, sticky reveal mid-page.
/// Never snaps away at the top — it *is* the top bar (elevation settles to 0).
class _StickyOverlayMenu extends StatefulWidget {
  const _StickyOverlayMenu({required this.chrome});

  final ScrollChromeController chrome;

  @override
  State<_StickyOverlayMenu> createState() => _StickyOverlayMenuState();
}

class _StickyOverlayMenuState extends State<_StickyOverlayMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sticky;

  @override
  void initState() {
    super.initState();
    _sticky = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 280),
    )..addListener(() => setState(() {}));
    widget.chrome.addListener(_onChrome);
  }

  @override
  void dispose() {
    widget.chrome.removeListener(_onChrome);
    _sticky.dispose();
    super.dispose();
  }

  void _onChrome() {
    final c = widget.chrome;
    if (c.sticky) {
      if (_sticky.status != AnimationStatus.forward &&
          _sticky.status != AnimationStatus.completed) {
        _sticky.forward();
      }
    } else if (c.pixels <= c.headerBodyHeight) {
      // Settling into the top — hand off to scroll-linked fraction (no reverse
      // snap). Keep controller at 0 so hideFraction uses pixels.
      if (_sticky.value != 0) _sticky.value = 0;
      setState(() {});
    } else if (_sticky.status != AnimationStatus.reverse &&
        _sticky.status != AnimationStatus.dismissed) {
      _sticky.reverse();
    } else {
      setState(() {});
    }
  }

  /// 0 = fully shown, 1 = fully hidden.
  double get _hideFraction {
    final c = widget.chrome;
    final h = c.headerBodyHeight.clamp(1.0, 400.0);
    final stickyT = _sticky.value;

    if (c.sticky || stickyT > 0.001) {
      return 1.0 - stickyT;
    }

    // Sticky just settled at top — stay fully shown (it *is* the menu bar).
    if (c.settleFromSticky) return 0;

    // Natural scroll-linked collapse from the top.
    if (c.pixels <= 0) return 0;
    if (c.pixels >= h) return 1;
    return (c.pixels / h).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chrome;
    final headerBuilder = c.overlayHeaderBuilder;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final h = c.headerBodyHeight;
    // Snap fully away once nearly hidden so a sub-pixel sliver never peeks.
    var hide = _hideFraction;
    if (hide >= 0.98) hide = 1.0;
    final shown = 1.0 - hide;

    if (hide >= 1.0 || headerBuilder == null) {
      return const SizedBox.shrink();
    }

    // Flat at top; shadow only while sticky mid-page (not while collapsing).
    final elev = (c.sticky || _sticky.value > 0.01)
        ? 3.0 * Curves.easeOut.transform(shown.clamp(0.0, 1.0))
        : 0.0;

    // Extra 2px overshoot so Material/antialias never peeks at the top edge.
    final travel = h + 2;

    return ClipRect(
      child: IgnorePointer(
        ignoring: shown < 0.05,
        child: Transform.translate(
          offset: Offset(0, -hide * travel),
          child: Material(
            color: bg,
            elevation: elev,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            child: headerBuilder(context),
          ),
        ),
      ),
    );
  }
}

class _ScrollTopFab extends StatelessWidget {
  const _ScrollTopFab({required this.onPressed, required this.heroTag});

  final VoidCallback onPressed;
  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: 'Top',
      backgroundColor: p.cardElevated,
      foregroundColor: p.textPrimary,
      elevation: 3,
      onPressed: onPressed,
      child: const Text('⬆️', style: TextStyle(fontSize: 18)),
    );
  }
}

/// Box header content for [ScrollChrome.floatingHeader] (not a sliver).
class ScrollChromeHeader extends StatelessWidget {
  const ScrollChromeHeader({
    super.key,
    required this.chrome,
    required this.child,
  });

  final ScrollChromeController chrome;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// AppBar-shaped header **content** (no top SafeArea — use
/// [ScrollChrome.statusBar] for that).
class ScrollChromeAppBar extends StatelessWidget {
  const ScrollChromeAppBar({
    super.key,
    required this.chrome,
    this.leading,
    this.title,
    this.actions,
    this.centerTitle = true,
    this.automaticallyImplyLeading = true,
  });

  final ScrollChromeController chrome;
  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    final canPop = parentRoute?.canPop ?? false;
    Widget? lead = leading;
    if (lead == null && automaticallyImplyLeading && canPop) {
      lead = const BackButton();
    }

    return ScrollChromeHeader(
      chrome: chrome,
      child: SizedBox(
        height: kToolbarHeight,
        child: NavigationToolbar(
          leading: lead,
          middle: title == null
              ? null
              : DefaultTextStyle(
                  style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                  child: title!,
                ),
          trailing: actions == null || actions!.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!,
                ),
          centerMiddle: centerTitle,
          middleSpacing: 16,
        ),
      ),
    );
  }
}
