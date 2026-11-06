import 'package:community_package/community_package.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/sync/sync_controller.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/backup/app_backup_service.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:inventory_app/core/utils/date_bounds.dart';
import 'package:inventory_app/data/export/sales_csv_export.dart';
import 'package:inventory_app/shared/widgets/date_range_fields.dart';
import 'package:share_plus/share_plus.dart';
import 'package:inventory_app/data/reset/app_reset.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
import 'package:inventory_app/shared/widgets/scroll_chrome.dart';
import 'package:inventory_app/core/utils/open_link.dart';

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

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_settings',
      builder: (context, chrome) {
        return CustomScrollView(
          controller: chrome.scrollController,
          physics: kScrollChromePhysics,
          slivers: [
            ...ScrollChrome.headerSlivers(
              context: context,
              chrome: chrome,
              header: (_) => SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    const BackButton(),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const AppIcon(AppAssets.settings, size: 26),
                          const SizedBox(width: 8),
                          Text(
                            t('settings'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: p.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
            ...settings.when(
                loading: () => const [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppLoader(),
                  ),
                ],
                error: (e, _) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: Text('$e')),
                  ),
                ],
                data: (s) {
                  return [SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
                    sliver: SliverList(
                    delegate: SliverChildListDelegate([
              FadeSlide(
                child: _SettingsGroup(
                  children: [
                    _SettingsRow(
                      leading: const Text(
                        '❤️',
                        style: TextStyle(
                          fontSize: 20,
                          color: Color(0xFFFF3B30),
                          height: 1,
                        ),
                      ),
                      title: t('community_app'),
                      onTap: () => context.push('/settings/community'),
                    ),
                    _SettingsRow(
                      leading: const Text(
                        '✍️',
                        style: TextStyle(fontSize: 18, height: 1),
                      ),
                      title: t('feedback'),
                      onTap: () async {
                        await openInAppWebView(
                          context,
                          'https://tally.so/r/kbbyKr',
                          title: t('feedback'),
                        );
                      },
                    ),
                    _SettingsRow(
                      // Inter has its own plain ❤, so name the color emoji
                      // fonts (iOS, then Android) to get the red heart.
                      leading: const Text(
                        '❤️',
                        style: TextStyle(
                          fontSize: 20,
                          fontFamily: 'Apple Color Emoji',
                          fontFamilyFallback: ['Noto Color Emoji'],
                        ),
                      ),
                      title: t('community_app'),
                      onTap: () => CommunityPackage.openCommunity(context),
                    ),
                    _SettingsRow(
                      leading: const Text(
                        '✍️',
                        style: TextStyle(
                          fontSize: 20,
                          fontFamily: 'Apple Color Emoji',
                          fontFamilyFallback: ['Noto Color Emoji'],
                        ),
                      ),
                      title: t('give_feedback'),
                      onTap: () => CommunityPackage.openNewFeedback(context),
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
                              localizedReason: t('enable_lock_reason'),
                              options: const AuthenticationOptions(
                                biometricOnly: false,
                                stickyAuth: true,
                              ),
                            );
                            if (!ok) return;
                          } catch (e) {
                            debugPrint('Enable PIN auth failed: $e');
                            return;
                          }
                        }
                        await ref.read(appPrefsProvider.notifier).setPinLock(v);
                      },
                    ),
                    _SettingsRow(
                      title: t('synced_devices'),
                      value: '${ref.watch(syncControllerProvider).activeCount}',
                      onTap: () => context.push('/settings/sync'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Client: Data 🗂️ vs invoices/Receipts 📁 (distinct folder emojis).
              _SectionHeader(emoji: '🗂️', label: t('data')),
              const SizedBox(height: 8),
              FadeSlide(
                delay: const Duration(milliseconds: 120),
                child: _SettingsGroup(
                  children: [
                    _SettingsRow(
                      leading: const AppIcon(AppAssets.turnover, size: 26),
                      title: t('export_turnover'),
                      onTap: () => _exportTurnover(context, ref, t),
                    ),
                    _SettingsRow(
                      leading: const Text('📁', style: TextStyle(fontSize: 18)),
                      title: t('receipts'),
                      onTap: () => context.push('/receipts'),
                    ),
                    _SettingsRow(
                      leading: const Text('🧾', style: TextStyle(fontSize: 18)),
                      title: t('receipt_details'),
                      onTap: () => context.push('/settings/receipt'),
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
                    ]),
                    ),
                  )];
                },
              ),
          ],
        );
      },
    );
  }

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, S t) async {
    // Shared sheet shell (drag handle + close button) like every other picker.
    final code = await showAppSheet<String>(
      context: context,
      builder: (ctx) {
        final prefs =
            ref.read(appPrefsProvider).valueOrNull ?? const AppPrefs();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(title: t('language')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  children: [
                    for (final e in S.supported.entries)
                      PickerOptionRow(
                        label: e.value,
                        selected: e.key == prefs.localeCode,
                        onTap: () => Navigator.pop(ctx, e.key),
                        leading: Text(
                          _langFlags[e.key] ?? '🌐',
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (code != null) {
      AppHaptics.selection();
      await ref.read(appPrefsProvider.notifier).setLocale(code);
    }
  }

  Future<void> _pickCurrency(
    BuildContext context,
    WidgetRef ref,
    ShopSettings s,
  ) async {
    final value = await showCurrencyPicker(context, current: s.currencySymbol);
    if (value != null && value.isNotEmpty) {
      await ref
          .read(shopSettingsProvider.notifier)
          .save(s.copyWith(currencySymbol: value));
    }
  }

  Future<void> _saveAppData(BuildContext context, WidgetRef ref, S t) async {
    try {
      await AppBackupService(
        ref.read(databaseProvider),
      ).shareBackup(
            context: context,
            shareText: ref.read(tProvider)('backup_share_text'),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('backup_saved'))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${t('backup_failed')}: $e')));
      }
    }
  }

  Future<void> _uploadAppData(BuildContext context, WidgetRef ref, S t) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('upload_app_data'),
      message: t('restore_confirm'),
      cancelLabel: t('cancel'),
      confirmLabel: t('done'),
    );
    if (!ok) return;

    // Pick first (needs user gesture), then block UI only during restore+warm.
    // withData: true — Chrome/web (and some Android SAF picks) return bytes
    // with a null path; path-only reads silently no-op there.
    final chosen = await AppBackupService.pickBackupFile();
    if (chosen == null) return;
    String? raw;
    try {
      raw = await AppBackupService.readPickedBackup(chosen);
    } catch (_) {
      raw = null; // not a text file → same message as an empty pick
    }
    if (raw == null || raw.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('backup_failed'))),
        );
      }
      return;
    }

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: AppLoader()),
      ),
    );

    try {
      // Tables first; photos continue in background so screens fill ASAP.
      await AppBackupService(ref.read(databaseProvider)).restoreFromJson(
        raw,
        awaitPhotos: false,
      );
      // Inventory + sales first (Turnover uses sales) — then the rest.
      await Future.wait([
        ref.read(inventoryItemsProvider.notifier).refresh(),
        ref.read(salesProvider.notifier).refresh(),
        ref.read(categoriesProvider.notifier).refresh(),
      ]);
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('backup_restored'))));
        context.go('/inventory');
      }
      // Warm remaining providers without blocking navigation.
      // ignore: unawaited_futures
      Future.wait([
        ref.read(customersProvider.notifier).refresh(),
        ref.read(shopSettingsProvider.notifier).refresh(),
      ]);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${t('backup_failed')}: $e')));
      }
    }
  }

  /// Settings > Export Turnover: pop-up with From / To (default: first →
  /// last sale), loading wheel while the CSV is written, then share.
  Future<void> _exportTurnover(
    BuildContext context,
    WidgetRef ref,
    S t,
  ) async {
    final sales = await ref.read(saleRepositoryProvider).list();
    if (!context.mounted) return;
    final bounds = DateBounds.of(sales.map((s) => s.createdAt));
    if (bounds == null) {
      showTopNotice(context, t('export_no_data'));
      return;
    }
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    final file = await showCsvExportSheet(
      context: context,
      title: t('export_turnover'),
      bounds: bounds,
      build: (from, to) => SalesCsvExport.write(
        SalesCsvExport.fileName('Turnover', from, to),
        SalesCsvExport.turnover(
          sales: SalesCsvExport.inRange(sales, from, to),
          decimalSeparator: settings?.decimalSeparator ?? ',',
          currencySymbol: settings?.currencySymbol ?? '€',
          t: t.call,
        ),
      ),
    );
    if (file == null || !context.mounted) return;
    try {
      await shareWithOrigin(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: file.uri.pathSegments.last.replaceAll('.csv', ''),
        ),
        context,
      );
    } catch (e) {
      debugPrint('Export share failed: $e');
      if (context.mounted) showTopNotice(context, t('export_failed'));
    }
  }

  /// Settings > Reset App: erase business data; keep shop info and settings.
  Future<void> _erase(BuildContext context, WidgetRef ref, S t) async {
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('reset_app_title'),
      message: t('reset_app_body'),
      cancelLabel: t('cancel'),
      confirmLabel: t('reset_action'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await AppRoot.resetApp(context);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, this.emoji, this.asset});

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
              ?trailing,
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
          // Same switch styling as the sort popup.
          Transform.scale(
            scale: 0.85,
            child: Switch.adaptive(
              value: value,
              activeTrackColor: p.fabBorder,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) {
                AppHaptics.selection();
                onChanged(v);
              },
            ),
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
      await ref
          .read(shopSettingsProvider.notifier)
          .save(
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
        SnackBar(content: Text(ref.read(tProvider)('save_failed'))),
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

    return ScrollChromeHost(
      scrollTopHeroTag: 'scroll_top_receipt_details',
      bottomNavigationBar: ConfirmCancelBar(
        onCancel: () => context.pop(false),
        onConfirm: _save,
      ),
      builder: (context, chrome) {
        return Form(
          key: _formKey,
          child: CustomScrollView(
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
                    Icon(
                      Icons.receipt_long_rounded,
                      size: 18,
                      color: p.textPrimary,
                    ),
                    const SizedBox(width: 8),
                    Text(t('receipt_details')),
                  ],
                ),
              ),
            ),
            SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
            Text(
              t('receipt_info_hint'),
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
              decoration: InputDecoration(labelText: t('company_name')),
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
                    decoration: InputDecoration(labelText: t('street')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _nr,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(labelText: t('house_nr')),
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
                    decoration: InputDecoration(labelText: t('zip')),
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
                    decoration: InputDecoration(labelText: t('city')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: InputDecoration(labelText: t('phone_number')),
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
                  decoration: InputDecoration(labelText: t('vat_rate')),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    // Optional — but must be a number when filled in.
                    if (v == null || v.trim().isEmpty) return null;
                    final raw = v
                        .replaceAll('%', '')
                        .replaceAll(',', '.')
                        .trim();
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
                // Wraps in full in every language, never "…" (client, Nov 14).
                helperMaxLines: 8,
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
            ),
                  ]),
                ),
              ),
          ],
        ),
        );
      },
    );
  }
}
