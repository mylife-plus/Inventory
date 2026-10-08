import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/currency/currencies.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

Future<String?> showCurrencyPicker(
  BuildContext context, {
  String? current,
}) async {
  final selected =
      current ??
      (ProviderScope.containerOf(
            context,
          ).read(shopSettingsProvider).valueOrNull?.currencySymbol ??
          '€');

  // Shared sheet shell (drag handle + close X) like every other picker.
  return showAppSheet<String>(
    context: context,
    builder: (ctx) => _CurrencyPickerSheet(initial: selected),
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
  await ref
      .read(shopSettingsProvider.notifier)
      .save(settings.copyWith(currencySymbol: picked));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.read(tProvider).tr('currency_set_to', {'code': picked}),
        ),
      ),
    );
  }
}

String decimalSeparatorLabel(String separator) =>
    separator == '.' ? '1,000.01' : '1.000,01';

Future<String?> showDecimalSeparatorPicker(
  BuildContext context, {
  String? current,
}) async {
  final t = ProviderScope.containerOf(context).read(tProvider);
  final selected =
      current ??
      (ProviderScope.containerOf(
            context,
          ).read(shopSettingsProvider).valueOrNull?.decimalSeparator ??
          ',');

  // Shared sheet shell (drag handle + close X) like every other picker.
  return showAppSheet<String>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeader(title: t('decimal_separator')),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final sep in const [',', '.'])
                    PickerOptionRow(
                      label: decimalSeparatorLabel(sep),
                      selected: selected == sep,
                      onTap: () => Navigator.pop(ctx, sep),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// One choice row in a picker sheet: rounded card, highlighted border and a
/// check on the current choice (language, decimal separator, currency).
class PickerOptionRow extends StatelessWidget {
  const PickerOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.subtitle,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: p.cardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? p.fabBorder : p.stroke,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 16,
                      color: p.textPrimary,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: p.neon, size: 22),
          ],
        ),
      ),
    );
  }
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
  await ref
      .read(shopSettingsProvider.notifier)
      .save(settings.copyWith(decimalSeparator: picked));
}

class _CurrencyPickerSheet extends ConsumerStatefulWidget {
  const _CurrencyPickerSheet({required this.initial});
  final String initial;

  @override
  ConsumerState<_CurrencyPickerSheet> createState() =>
      _CurrencyPickerSheetState();
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

    // showAppSheet already lifts the sheet above the keyboard.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.72,
      child: Column(
        children: [
          AppSheetHeader(title: t('currency')),
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
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: list.length + 1,
              itemBuilder: (context, i) {
                if (i == list.length) {
                  return _CustomCurrencyTile(
                    onSubmit: (v) => Navigator.pop(context, v),
                  );
                }
                final c = list[i];
                final active = c.display == _selected || c.code == _selected;
                return PickerOptionRow(
                  label: c.name,
                  subtitle: c.code,
                  selected: active,
                  onTap: () {
                    AppHaptics.selection();
                    setState(() => _selected = c.display);
                    Navigator.pop(context, c.display);
                  },
                  leading: Container(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomCurrencyTile extends ConsumerStatefulWidget {
  const _CustomCurrencyTile({required this.onSubmit});
  final ValueChanged<String> onSubmit;

  @override
  ConsumerState<_CustomCurrencyTile> createState() =>
      _CustomCurrencyTileState();
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
