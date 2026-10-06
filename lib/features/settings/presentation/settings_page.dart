import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/backup/app_backup_service.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _langFlags = <String, String>{
    'en': '🇬🇧',
    'de': '🇩🇪',
    'es': '🇪🇸',
    'fr': '🇫🇷',
    'pt': '🇵🇹',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final settings = ref.watch(shopSettingsProvider);
    final prefs = ref.watch(appPrefsProvider).valueOrNull ?? const AppPrefs();
    final t = ref.watch(tProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppAssets.settings, size: 26),
            const SizedBox(width: 8),
            Text(
              t('settings'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
      ),
      body: settings.when(
        loading: () => const AppLoader(),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
            children: [
              FadeSlide(
                child: _SettingsGroup(
                  children: [
                    _SettingsRow(
                      leading: const Text('❤️', style: TextStyle(fontSize: 20)),
                      title: t('open_source'),
                      onTap: () => launchUrl(
                        Uri.parse('https://www.gnu.org/licenses/gpl-3.0.html'),
                      ),
                    ),
                    _SettingsRow(
                      leading: const Text('🤝', style: TextStyle(fontSize: 20)),
                      title: t('feedback'),
                      onTap: () => launchUrl(
                        Uri.parse('mailto:sales@softthrive.com'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(emoji: '✅', label: t('preferences')),
              const SizedBox(height: 8),
              FadeSlide(
                delay: const Duration(milliseconds: 40),
                child: _SettingsGroup(
                  children: [
                    _SettingsRow(
                      title: t('language'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _langFlags[prefs.localeCode] ?? '🌐',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            S.supported[prefs.localeCode] ?? 'English',
                            style: TextStyle(
                              color: p.textPrimary.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _pickLanguage(context, ref, t),
                    ),
                    _SettingsSwitchRow(
                      title: t('dark_mode'),
                      value: prefs.darkMode,
                      onChanged: (v) =>
                          ref.read(appPrefsProvider.notifier).setDarkMode(v),
                    ),
                    _SettingsRow(
                      title: t('decimal_separator'),
                      value: decimalSeparatorLabel(s.decimalSeparator),
                      onTap: () => pickAndSaveDecimalSeparator(context, ref),
                    ),
                    _SettingsRow(
                      title: t('currency'),
                      value: s.currencySymbol,
                      onTap: () => _pickCurrency(context, ref, s),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(asset: AppAssets.security, label: t('security')),
              const SizedBox(height: 8),
              FadeSlide(
                delay: const Duration(milliseconds: 80),
                child: _SettingsGroup(
                  children: [
                    _SettingsSwitchRow(
                      title: t('pin_lock'),
                      value: prefs.pinLock,
                      onChanged: (v) async {
                        if (v) {
                          final auth = LocalAuthentication();
                          try {
                            final ok = await auth.authenticate(
                              localizedReason: 'Enable app lock',
                              options: const AuthenticationOptions(
                                biometricOnly: false,
                                stickyAuth: true,
                              ),
                            );
                            if (!ok) return;
                          } catch (_) {}
                        }
                        await ref.read(appPrefsProvider.notifier).setPinLock(v);
                      },
                    ),
                    _SettingsRow(
                      title: t('synced_devices'),
                      value: '0',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(t('coming_sync'))),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(asset: AppAssets.data, label: t('data')),
              const SizedBox(height: 8),
              FadeSlide(
                delay: const Duration(milliseconds: 120),
                child: _SettingsGroup(
                  children: [
                    _SettingsRow(
                      leading: const AppIcon(AppAssets.turnover, size: 26),
                      title: t('export_turnover'),
                      onTap: () => context.go('/turnover'),
                    ),
                    _SettingsRow(
                      leading: Icon(Icons.receipt_long_rounded,
                          color: p.textPrimary, size: 22),
                      title: t('receipt_details'),
                      onTap: () => context.push('/settings/receipt'),
                    ),
                    _SettingsRow(
                      leading: Icon(Icons.qr_code_2_rounded,
                          color: p.textPrimary, size: 22),
                      title: t('qr_link'),
                      trailing: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * 0.38,
                        ),
                        child: Text(
                          s.receiptQrLink.trim().isEmpty
                              ? t('not_set')
                              : s.receiptQrLink.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: p.textPrimary.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      onTap: () => _editQrLink(context, ref, s),
                    ),
                    _SettingsRow(
                      leading: Icon(Icons.description_rounded,
                          color: p.textPrimary, size: 22),
                      title: t('receipts'),
                      onTap: () => context.push('/receipts'),
                    ),
                    _SettingsRow(
                      leading: const Text('💾', style: TextStyle(fontSize: 18)),
                      title: t('save_app_data'),
                      onTap: () => _saveAppData(context, ref, t),
                    ),
                    _SettingsRow(
                      leading: const Text('⬆️', style: TextStyle(fontSize: 18)),
                      title: t('upload_app_data'),
                      onTap: () => _uploadAppData(context, ref, t),
                    ),
                    _SettingsRow(
                      title: t('erase_all'),
                      titleColor: p.danger,
                      onTap: () => _erase(context, ref, t),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    S t,
  ) async {
    final p = AppPalette.of(context);
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final prefs =
            ref.read(appPrefsProvider).valueOrNull ?? const AppPrefs();
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text(
                  t('language'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: p.textPrimary,
                  ),
                ),
              ),
              ...S.supported.entries.map(
                (e) {
                  final selected = e.key == prefs.localeCode;
                  return ListTile(
                    leading: Text(
                      _langFlags[e.key] ?? '🌐',
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(
                      e.value,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    trailing: selected
                        ? Icon(Icons.check_circle_rounded, color: p.neon)
                        : null,
                    onTap: () => Navigator.pop(ctx, e.key),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
    if (code != null) {
      await ref.read(appPrefsProvider.notifier).setLocale(code);
    }
  }

  /// Same stored value as the QR-Link field on the receipt details page.
  Future<void> _editQrLink(
    BuildContext context,
    WidgetRef ref,
    ShopSettings s,
  ) async {
    final t = ref.read(tProvider);
    final controller = TextEditingController(text: s.receiptQrLink);
    final result = await showAppSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppSheetHeader(title: t('qr_link')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: t('qr_link'),
                      hintText: 'https://…',
                      helperText: t('receipt_qr_link_helper'),
                      helperMaxLines: 2,
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                  ),
                ),
                AppSheetActions(
                  applyLabel: t('done'),
                  onReset: () => Navigator.pop(ctx, ''),
                  onApply: () => Navigator.pop(ctx, controller.text.trim()),
                ),
              ],
            ),
          ),
        );
      },
    );
    // Not disposed here: the sheet's closing animation may still use it.
    if (result == null) return;
    final current = await ref.read(shopRepositoryProvider).get();
    await ref
        .read(shopSettingsProvider.notifier)
        .save(current.copyWith(receiptQrLink: result));
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    ShopSettings s,
  ) async {
    final value = await showCurrencyPicker(
      context,
      current: s.currencySymbol,
    );
    if (value != null && value.isNotEmpty) {
      await ref
          .read(shopSettingsProvider.notifier)
          .save(s.copyWith(currencySymbol: value));
    }
  }

  Future<void> _saveAppData(
    BuildContext context,
    WidgetRef ref,
    S t,
  ) async {
    try {
      await AppBackupService(ref.read(databaseProvider)).shareBackup(context: context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('backup_saved'))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('backup_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _uploadAppData(
    BuildContext context,
    WidgetRef ref,
    S t,
  ) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('upload_app_data'),
      message: t('restore_confirm'),
      cancelLabel: t('cancel'),
      confirmLabel: t('done'),
    );
    if (!ok) return;

    try {
      final restored =
          await AppBackupService(ref.read(databaseProvider)).pickAndRestore();
      if (!restored) return;
      ref.invalidate(shopSettingsProvider);
      ref.invalidate(inventoryItemsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(salesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('backup_restored'))),
        );
        context.go('/inventory');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t('backup_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _erase(BuildContext context, WidgetRef ref, S t) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('erase_all'),
      message: t('cannot_undo'),
      cancelLabel: t('cancel'),
      confirmLabel: t('delete'),
      destructive: true,
    );
    if (!ok) return;
    await ref.read(dataRepositoryProvider).eraseAll();
    ref.invalidate(shopSettingsProvider);
    ref.invalidate(inventoryItemsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(customersProvider);
    ref.invalidate(salesProvider);
    if (context.mounted) context.go('/inventory');
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    this.emoji,
    this.asset,
  });

  final String label;
  final String? emoji;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          if (asset != null)
            AppIcon(asset!, size: 22)
          else if (emoji != null)
            Text(emoji!, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 0.7,
                indent: 16,
                endIndent: 16,
                color: p.stroke.withValues(alpha: 0.85),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.onTap,
    this.leading,
    this.value,
    this.trailing,
    this.titleColor,
  });

  final String title;
  final VoidCallback onTap;
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final Color? titleColor;

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
              if (leading != null) ...[
                SizedBox(width: 28, child: Center(child: leading)),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: titleColor ?? p.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
              if (value != null)
                Text(
                  value!,
                  style: TextStyle(
                    color: p.textPrimary.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              const SizedBox(width: 4),
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

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
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
          Switch.adaptive(
            value: value,
            activeColor: const Color(0xFF0A84FF),
            onChanged: (v) {
              AppHaptics.selection();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class ReceiptDetailsSettingsPage extends ConsumerStatefulWidget {
  const ReceiptDetailsSettingsPage({super.key});

  @override
  ConsumerState<ReceiptDetailsSettingsPage> createState() =>
      _ReceiptDetailsSettingsPageState();
}

class _ReceiptDetailsSettingsPageState
    extends ConsumerState<ReceiptDetailsSettingsPage> {
  static const _nrSep = '\u001F';

  final _formKey = GlobalKey<FormState>();
  late TextEditingController _company;
  late TextEditingController _street;
  late TextEditingController _nr;
  late TextEditingController _zip;
  late TextEditingController _city;
  late TextEditingController _phone;
  late TextEditingController _vat;
  late TextEditingController _qrLink;
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  (String, String) _splitStreet(String raw) {
    final i = raw.indexOf(_nrSep);
    if (i < 0) return (raw, '');
    return (raw.substring(0, i), raw.substring(i + 1));
  }

  String _joinStreet(String street, String nr) {
    final s = street.trim();
    final n = nr.trim();
    if (n.isEmpty) return s;
    return '$s$_nrSep$n';
  }

  Future<void> _hydrate() async {
    final s = await ref.read(shopRepositoryProvider).get();
    final (street, nr) = _splitStreet(s.street);
    _company = TextEditingController(text: s.companyName);
    _street = TextEditingController(text: street);
    _nr = TextEditingController(text: nr);
    _zip = TextEditingController(text: s.zip);
    _city = TextEditingController(text: s.city);
    _phone = TextEditingController(text: s.phone);
    final vat = s.vatRate == s.vatRate.roundToDouble()
        ? '${s.vatRate.round()}%'
        : '${s.vatRate}%';
    _vat = TextEditingController(text: s.vatRate == 0 ? '' : vat);
    _qrLink = TextEditingController(text: s.receiptQrLink);
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    if (_ready) {
      _company.dispose();
      _street.dispose();
      _nr.dispose();
      _zip.dispose();
      _city.dispose();
      _phone.dispose();
      _vat.dispose();
      _qrLink.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    try {
      final current = await ref.read(shopRepositoryProvider).get();
      final vatRaw = _vat.text.replaceAll('%', '').replaceAll(',', '.').trim();
      await ref.read(shopSettingsProvider.notifier).save(
            current.copyWith(
              companyName: _company.text.trim(),
              street: _joinStreet(_street.text, _nr.text),
              zip: _zip.text.trim(),
              city: _city.text.trim(),
              phone: _phone.text.trim(),
              vatRate: double.tryParse(vatRaw) ?? 0,
              receiptQrLink: _qrLink.text.trim(),
              setupComplete: true,
            ),
          );
      if (!mounted) return;
      // Pop first — SnackBar on a popping route caused first-time confirm bugs.
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(tProvider)('backup_failed'))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    if (!_ready) {
      return const Scaffold(body: AppLoader());
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 18, color: p.textPrimary),
            const SizedBox(width: 8),
            Text(t('receipt_details')),
          ],
        ),
      ),
      bottomNavigationBar: ConfirmCancelBar(
        onCancel: () => context.pop(false),
        onConfirm: _save,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Text(
              'This info will be displayed on the Receipts',
              style: TextStyle(
                color: p.textPrimary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _company,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Company Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? t('required') : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _street,
                    textCapitalization: TextCapitalization.words,
                    keyboardType: TextInputType.streetAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Street'),
                                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _nr,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Nr.'),
                                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _zip,
                    decoration: const InputDecoration(labelText: 'ZIP'),
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                                      ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _city,
                    textCapitalization: TextCapitalization.words,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'City'),
                                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width * 0.42,
                child: TextFormField(
                  controller: _vat,
                  decoration:
                      const InputDecoration(labelText: 'VAT Tax Rate'),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    // Optional — but must be a number when filled in.
                    if (v == null || v.trim().isEmpty) return null;
                    final raw =
                        v.replaceAll('%', '').replaceAll(',', '.').trim();
                    if (double.tryParse(raw) == null) return t('required');
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qrLink,
              decoration: InputDecoration(
                labelText: t('qr_link'),
                hintText: 'https://…',
                helperText: t('receipt_qr_link_helper'),
                helperMaxLines: 2,
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ],
        ),
      ),
    );
  }
}
