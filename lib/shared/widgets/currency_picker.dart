import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/currency/currencies.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

Future<String?> showCurrencyPicker(
  BuildContext context, {
  String? current,
}) async {
  final p = AppPalette.of(context);
  final selected = current ??
      (ProviderScope.containerOf(context)
              .read(shopSettingsProvider)
              .valueOrNull
              ?.currencySymbol ??
          '€');

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return _CurrencyPickerSheet(initial: selected);
    },
  );
}

Future<void> pickAndSaveCurrency(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(shopSettingsProvider).valueOrNull;
  if (settings == null) return;
  final picked = await showCurrencyPicker(
    context,
    current: settings.currencySymbol,
  );
  if (picked == null || picked.isEmpty) return;
  if (picked == settings.currencySymbol) return;
  AppHaptics.selection();
  await ref.read(shopSettingsProvider.notifier).save(
        settings.copyWith(currencySymbol: picked),
      );
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(tProvider).tr('currency_set_to', {'code': picked}))),
    );
  }
}

String decimalSeparatorLabel(String separator) =>
    separator == '.' ? '1,000.01' : '1.000,01';

Future<String?> showDecimalSeparatorPicker(
  BuildContext context, {
  String? current,
}) async {
  final p = AppPalette.of(context);
  final t = ProviderScope.containerOf(context).read(tProvider);
  final selected = current ??
      (ProviderScope.containerOf(context)
              .read(shopSettingsProvider)
              .valueOrNull
              ?.decimalSeparator ??
          ',');

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: p.cardElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.stroke,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t('decimal_separator'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              for (final sep in const [',', '.']) ...[
                Pressable(
                  onTap: () => Navigator.pop(ctx, sep),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: p.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected == sep ? p.fabBorder : p.stroke,
                        width: selected == sep ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            decimalSeparatorLabel(sep),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (selected == sep)
                          Icon(Icons.check_rounded, color: p.neon, size: 22),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Future<void> pickAndSaveDecimalSeparator(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(shopSettingsProvider).valueOrNull;
  if (settings == null) return;
  final picked = await showDecimalSeparatorPicker(
    context,
    current: settings.decimalSeparator,
  );
  if (picked == null || picked.isEmpty) return;
  if (picked == settings.decimalSeparator) return;
  AppHaptics.selection();
  await ref.read(shopSettingsProvider.notifier).save(
        settings.copyWith(decimalSeparator: picked),
      );
}

class _CurrencyPickerSheet extends ConsumerStatefulWidget {
  const _CurrencyPickerSheet({required this.initial});
  final String initial;

  @override
  ConsumerState<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends ConsumerState<_CurrencyPickerSheet> {
  late final TextEditingController _search;
  late String _selected;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _selected = widget.initial;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final q = _search.text.trim().toLowerCase();
    final list = kCurrencies.where((c) {
      if (q.isEmpty) return true;
      return c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q) ||
          c.symbol.toLowerCase().contains(q);
    }).toList();

    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.stroke,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Text(
                    t('currency'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: p.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: Text(
                      t('done'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: p.neon,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: t('search_currency'),
                  prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  if (i == list.length) {
                    return _CustomCurrencyTile(
                      onSubmit: (v) => Navigator.pop(context, v),
                    );
                  }
                  final c = list[i];
                  final active = c.display == _selected || c.code == _selected;
                  return Pressable(
                    onTap: () {
                      AppHaptics.selection();
                      setState(() => _selected = c.display);
                      Navigator.pop(context, c.display);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? p.neon.withValues(alpha: 0.12)
                            : p.cardElevated,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active ? p.neon : p.stroke,
                          width: active ? 1.4 : 0.9,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: p.stroke),
                            ),
                            child: Text(
                              c.display,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: c.display.length > 3 ? 11 : 14,
                                color: active ? p.neon : p.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                                Text(
                                  c.code,
                                  style: TextStyle(
                                    color: p.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (active)
                            Icon(Icons.check_circle_rounded, color: p.neon),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomCurrencyTile extends ConsumerStatefulWidget {
  const _CustomCurrencyTile({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  ConsumerState<_CustomCurrencyTile> createState() => _CustomCurrencyTileState();
}

class _CustomCurrencyTileState extends ConsumerState<_CustomCurrencyTile> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _c,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: ref.watch(tProvider)('currency'),
                hintText: ref.watch(tProvider)('custom_currency_hint'),
                isDense: true,
              ),
              onSubmitted: (v) {
                final t = v.trim();
                if (t.isNotEmpty) widget.onSubmit(t);
              },
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () {
              final t = _c.text.trim();
              if (t.isNotEmpty) widget.onSubmit(t);
            },
            icon: Icon(Icons.arrow_forward_rounded, color: p.neon),
          ),
        ],
      ),
    );
  }
}
