import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';

/// First launch after splash — pick language, currency + company, then enter app.
class PrefsSetupPage extends ConsumerStatefulWidget {
  const PrefsSetupPage({super.key});

  @override
  ConsumerState<PrefsSetupPage> createState() => _PrefsSetupPageState();
}

class _PrefsSetupPageState extends ConsumerState<PrefsSetupPage> {
  static const _flags = <String, String>{
    'en': '🇬🇧',
    'de': '🇩🇪',
    'es': '🇪🇸',
    'fr': '🇫🇷',
    'pt': '🇵🇹',
  };

  static const _fieldHeight = 48.0;
  static const _sectionGap = 14.0;
  static const _labelGap = 8.0;

  late final TextEditingController _company;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _company = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final name =
          ref.read(shopSettingsProvider).valueOrNull?.companyName.trim();
      if (name != null && name.isNotEmpty && mounted) {
        _company.text = name;
      }
    });
  }

  @override
  void dispose() {
    _company.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;

    final t = ref.read(tProvider);
    if (_company.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('company_required'))),
      );
      return;
    }

    final settings = ref.read(shopSettingsProvider).valueOrNull;
    if (settings == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(shopSettingsProvider.notifier).save(
            settings.copyWith(
              companyName: _company.text.trim(),
              // Full address / VAT collected later on first receipt.
              setupComplete: false,
            ),
          );
      await ref.read(appPrefsProvider.notifier).markPrefsSetupDone();
      if (!mounted) return;
      context.go('/inventory');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCurrency() async {
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    if (settings == null) return;
    final picked = await showCurrencyPicker(
      context,
      current: settings.currencySymbol,
    );
    if (picked == null || picked.isEmpty) return;
    await ref.read(shopSettingsProvider.notifier).save(
          settings.copyWith(currencySymbol: picked),
        );
  }

  Future<void> _pickDecimal() async {
    await pickAndSaveDecimalSeparator(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final prefs = ref.watch(appPrefsProvider).valueOrNull ?? const AppPrefs();
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final currency = settings?.currencySymbol ?? '€';
    final decimalLabel =
        decimalSeparatorLabel(settings?.decimalSeparator ?? ',');
    final locale = S.supported.containsKey(prefs.localeCode)
        ? prefs.localeCode
        : 'en';

    final fieldDecoration = BoxDecoration(
      color: p.cardElevated,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: p.stroke),
    );
    final fieldLabelStyle = TextStyle(
      color: p.textPrimary,
      fontWeight: FontWeight.w700,
      fontSize: 15,
    );
    final fieldValueStyle = TextStyle(
      color: p.textPrimary,
      fontWeight: FontWeight.w700,
      fontSize: 16,
    );

    Widget labeledField({
      required String label,
      required Widget field,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: fieldLabelStyle),
          const SizedBox(height: _labelGap),
          field,
        ],
      );
    }

    Widget selectField({
      required VoidCallback onTap,
      required Widget leading,
      required String value,
    }) {
      return Pressable(
        onTap: onTap,
        child: Container(
          height: _fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: fieldDecoration,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(child: Text(value, style: fieldValueStyle)),
              Icon(Icons.arrow_drop_down_rounded, color: p.textSecondary),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            Text(
              t('app_name'),
              style: TextStyle(
                color: p.fabBorder,
                fontWeight: FontWeight.w800,
                fontSize: 32,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t('prefs_setup_sub'),
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 28),
            labeledField(
              label: t('company_name'),
              field: Container(
                height: _fieldHeight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: fieldDecoration,
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _company,
                  textAlign: TextAlign.start,
                  textCapitalization: TextCapitalization.words,
                  keyboardType: TextInputType.name,
                  textInputAction: TextInputAction.done,
                  style: fieldValueStyle,
                  onSubmitted: (_) => _continue(),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    filled: false,
                    // Theme padding assumes a prefix icon — keep hint flush left.
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    hintText: t('company_name'),
                    hintStyle: fieldValueStyle.copyWith(
                      color: p.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),
            labeledField(
              label: t('language'),
              field: Container(
                height: _fieldHeight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: fieldDecoration,
                alignment: Alignment.center,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: locale,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: p.cardElevated,
                    icon: Icon(
                      Icons.arrow_drop_down_rounded,
                      color: p.textSecondary,
                    ),
                    style: fieldValueStyle,
                    items: [
                      for (final e in S.supported.entries)
                        DropdownMenuItem<String>(
                          value: e.key,
                          child: Row(
                            children: [
                              Text(
                                _flags[e.key] ?? '🌐',
                                style: const TextStyle(fontSize: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(e.value),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (code) {
                      if (code == null) return;
                      ref.read(appPrefsProvider.notifier).setLocale(code);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),
            labeledField(
              label: t('currency'),
              field: selectField(
                onTap: _pickCurrency,
                leading: Icon(
                  Icons.payments_outlined,
                  color: p.textSecondary,
                  size: 22,
                ),
                value: currency,
              ),
            ),
            const SizedBox(height: _sectionGap),
            labeledField(
              label: t('decimal_separator'),
              field: selectField(
                onTap: _pickDecimal,
                leading: Icon(
                  Icons.pin_outlined,
                  color: p.textSecondary,
                  size: 22,
                ),
                value: decimalLabel,
              ),
            ),
            const SizedBox(height: 28),
            AccentButton(
              label: _saving ? '…' : t('continue_btn'),
              onPressed: _saving ? null : _continue,
            ),
          ],
        ),
      ),
    );
  }
}
