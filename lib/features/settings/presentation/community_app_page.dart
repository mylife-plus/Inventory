import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/core/utils/open_link.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/scroll_chrome.dart';

/// Settings → Community App — same row/card design as main Settings.
class CommunityAppPage extends ConsumerWidget {
  const CommunityAppPage({super.key});

  static const _progressUrl =
      'https://github.com/mylife-plus/Inventory/issues';
  static const _expensesUrl =
      'https://mylife-plus.github.io/Inventory/costs_and_tips';
  static const _tipUrl =
      'https://buy.stripe.com/3cI14fdCpe0n4lS0WpeEo00';
  static const _feedbacksUrl =
      'https://mylife-plus.github.io/Inventory/feedback';
  static const _heartRed = Color(0xFFFF3B30);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);

    Future<void> open(String url, {String? title}) async {
      AppHaptics.selection();
      if (!context.mounted) return;
      await openInAppWebView(context, url, title: title);
    }

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_community',
      builder: (context, chrome) {
        return CustomScrollView(
          controller: chrome.scrollController,
          physics: kScrollChromePhysics,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) => ScrollChromeAppBar(
                chrome: chrome,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '❤️',
                      style:
                          TextStyle(fontSize: 20, color: _heartRed, height: 1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      t('community_app'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    t('community_app_body'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textPrimary.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w400,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _CommunitySettingsRow(
                          leading:
                              const Text('💪', style: TextStyle(fontSize: 18)),
                          title: t('community_progress'),
                          onTap: () => open(
                            _progressUrl,
                            title: t('community_progress'),
                          ),
                        ),
                        _divider(p),
                        _CommunitySettingsRow(
                          leading:
                              const Text('🤑', style: TextStyle(fontSize: 18)),
                          title: t('community_expenses_tips'),
                          onTap: () => open(
                            _expensesUrl,
                            title: t('community_expenses_tips'),
                          ),
                        ),
                        _divider(p),
                        _CommunitySettingsRow(
                          leading:
                              const Text('✍️', style: TextStyle(fontSize: 18)),
                          title: t('community_feedbacks'),
                          onTap: () => open(
                            _feedbacksUrl,
                            title: t('community_feedbacks'),
                          ),
                        ),
                        _divider(p),
                        // Tip last (client).
                        _CommunitySettingsRow(
                          leading:
                              const Text('🧧', style: TextStyle(fontSize: 18)),
                          title: t('community_make_tip'),
                          onTap: () => open(
                            _tipUrl,
                            title: t('community_make_tip'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

  static Widget _divider(AppPalette p) => Divider(
        height: 1,
        thickness: 0.7,
        indent: 16,
        endIndent: 16,
        color: p.stroke.withValues(alpha: 0.85),
      );
}

class _CommunitySettingsRow extends StatelessWidget {
  const _CommunitySettingsRow({
    required this.leading,
    required this.title,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(width: 28, child: Center(child: leading)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: p.textPrimary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: p.textPrimary.withValues(alpha: 0.55),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
