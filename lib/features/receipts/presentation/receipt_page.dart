import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/receipts/receipt_details_gate.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/contact_launch.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/export/csv_export.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/sell/presentation/sell_page.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class ReceiptPage extends ConsumerStatefulWidget {
  const ReceiptPage({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<ReceiptPage> createState() => _ReceiptPageState();
}

class _ReceiptPageState extends ConsumerState<ReceiptPage> {
  Sale? _sale;
  bool _loading = true;
  /// False until shop receipt details exist — never show QR before that.
  bool _detailsReady = false;
  bool _promptingDetails = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final fromList = (ref.read(salesProvider).valueOrNull ?? [])
        .where((s) => s.id == widget.saleId)
        .firstOrNull;
    final sale =
        fromList ?? await ref.read(saleRepositoryProvider).get(widget.saleId);

    if (!mounted) return;

    var settings = ref.read(shopSettingsProvider).valueOrNull;
    var ready = settings?.hasReceiptDetails ?? false;

    // Collect details BEFORE any receipt / QR UI.
    if (!ready && !_promptingDetails) {
      _promptingDetails = true;
      if (mounted) {
        setState(() {
          _sale = sale;
          _loading = true;
          _detailsReady = false;
        });
      }
      try {
        ready = await ensureShopReceiptDetails(context, ref);
      } finally {
        _promptingDetails = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _sale = sale;
      _detailsReady = ready;
      _loading = false;
    });
  }

  Future<void> _retryDetails() async {
    if (_promptingDetails) return;
    setState(() {
      _loading = true;
      _promptingDetails = true;
    });
    final ready = await ensureShopReceiptDetails(context, ref);
    if (!mounted) return;
    setState(() {
      _detailsReady = ready;
      _loading = false;
      _promptingDetails = false;
    });
  }

  Future<void> _withReceiptDetails(Future<void> Function() action) async {
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    if (settings != null && !settings.hasReceiptDetails) {
      await _retryDetails();
      final again = ref.read(shopSettingsProvider).valueOrNull;
      if (again == null || !again.hasReceiptDetails) return;
    }
    await action();
  }

  Future<void> _sendReceipt(Sale sale) async {
    final t = ref.read(tProvider);
    final p = AppPalette.of(context);
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    if (settings == null) return;
    final money = MoneyFormatter(
      symbol: settings.currencySymbol,
      decimalSeparator: settings.decimalSeparator,
    );
    final body = _buildReceiptText(
      sale: sale,
      settings: settings,
      money: money,
    );

    Customer? customer;
    final customerId = sale.customerId;
    if (customerId != null && customerId.isNotEmpty) {
      final customers = ref.read(customersProvider).valueOrNull ?? const [];
      try {
        customer = customers.firstWhere((c) => c.id == customerId);
      } catch (_) {
        customer =
            await ref.read(customerRepositoryProvider).get(customerId);
      }
    }

    final contacts = customer?.allContacts ?? const <CustomerContact>[];
    if (contacts.isEmpty) {
      await SharePlus.instance.share(ShareParams(text: body));
      return;
    }

    if (!mounted) return;
    await showAppSheet<void>(
      context: context,
      heightFactor: 0.62,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(title: t('send_receipt')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  children: [
                    if (customer != null) ...[
                      CustomerListCard(
                        name: customer.displayName,
                        money: money,
                        photoPath: customer.photoPath,
                        contacts: contacts,
                        onContactTap: (contact) async {
                          Navigator.pop(ctx);
                          await launchContactWithMessage(
                            contact,
                            body,
                            subject: t('receipt'),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (contacts.isEmpty)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: p.stroke),
                        ),
                        leading: Icon(Icons.ios_share_rounded, color: p.neon),
                        title: Text(
                          t('share'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await SharePlus.instance
                              .share(ShareParams(text: body));
                        },
                      )
                    else ...[
                      for (final contact in contacts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: p.stroke),
                            ),
                            leading: AppIcon(contact.iconAsset, size: 28),
                            title: Text(
                              contact.display,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            onTap: () async {
                              Navigator.pop(ctx);
                              await launchContactWithMessage(
                                contact,
                                body,
                                subject: t('receipt'),
                              );
                            },
                          ),
                        ),
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: p.stroke),
                        ),
                        leading: Icon(Icons.ios_share_rounded, color: p.neon),
                        title: Text(
                          t('share'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: p.textPrimary,
                          ),
                        ),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await SharePlus.instance
                              .share(ShareParams(text: body));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _editSaleItems(Sale sale) async {
    // Prefill sell cart with this receipt's lines and open the sell items page.
    ref.read(cartProvider.notifier).replaceAll(sale.lines);
    ref.read(editingSaleIdProvider.notifier).state = sale.id;
    ref.read(editingSaleLinesProvider.notifier).state =
        List<SaleLine>.from(sale.lines);
    ref.read(sellCustomerProvider.notifier).state = null;
    if (!mounted) return;
    context.go('/sell');
  }

  String _buildReceiptText({
    required Sale sale,
    required ShopSettings settings,
    required MoneyFormatter money,
  }) {
    final t = ref.read(tProvider);
    final vat = VatBreakdown.inclusive(
      gross: sale.total,
      rate: settings.vatRate,
    );
    final b = StringBuffer()
      ..writeln(settings.companyName)
      ..writeln(settings.street.replaceAll('\u001F', ' '))
      ..writeln('${settings.zip} ${settings.city}'.trim())
      ..writeln(settings.phone)
      ..writeln('------------------------------')
      ..writeln('${t('receipt')} ${sale.id.substring(0, 8).toUpperCase()}')
      ..writeln(sale.createdAt.toLocal())
      ..writeln('------------------------------');
    for (final line in sale.lines) {
      b.writeln(
        '${formatQty(line.quantity)} x ${line.title}  ${money.format(line.lineTotal)}',
      );
    }
    b.writeln('------------------------------');
    if (vat.rate > 0) {
      b
        ..writeln('${t('subtotal')}  ${money.format(vat.net)}')
        ..writeln(
          '${t('vat')} ${formatQty(vat.rate)}%  ${money.format(vat.vat)}',
        );
    }
    b.writeln('${t('total')}  ${money.format(sale.total)}');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );

    if (_loading || settings == null || _promptingDetails) {
      return Scaffold(
        appBar: AppBar(title: Text(t('receipt'))),
        body: const AppLoader(),
      );
    }

    if (!_detailsReady) {
      return Scaffold(
        appBar: AppBar(
          title: Text(t('receipt_details')),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/inventory');
              }
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_rounded, size: 48, color: p.fabBorder),
              const SizedBox(height: 16),
              Text(
                t('receipt_details'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your shop details before showing the receipt.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 24),
              AccentButton(
                label: t('continue_btn'),
                onPressed: _retryDetails,
              ),
            ],
          ),
        ),
      );
    }

    final sale = _sale;
    if (sale == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('receipt'))),
        body: EmptyState(
          icon: Icons.receipt_long_rounded,
          title: t('no_receipts'),
          subtitle: t('no_receipts_sub'),
        ),
      );
    }

    final receiptQr = QrPayload.encodeReceipt(sale.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(t('send_receipt')),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/inventory');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: t('edit_item'),
            onPressed: () => _editSaleItems(sale),
            icon: Icon(Icons.edit_rounded, color: p.textSecondary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          FadeSlide(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Color(0xFF111111),
                  fontSize: 14,
                  height: 1.35,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      settings.companyName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    if (settings.street.isNotEmpty)
                      Text(settings.street.replaceAll('\u001F', ' '),
                          textAlign: TextAlign.center),
                    Text(
                      '${settings.zip} ${settings.city}'.trim(),
                      textAlign: TextAlign.center,
                    ),
                    if (settings.phone.isNotEmpty)
                      Text(settings.phone, textAlign: TextAlign.center),
                    const Divider(height: 22, color: Color(0xFFDDDDDD)),
                    Text(
                      '${t('receipt')} ${sale.id.substring(0, 8).toUpperCase()}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      sale.createdAt.toLocal().toString().split('.').first,
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF666666)),
                    ),
                    const Divider(height: 22, color: Color(0xFFDDDDDD)),
                    ...sale.lines.map(
                      (l) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${formatQty(l.quantity)}  ${l.title}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(money.format(l.lineTotal)),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 22, color: Color(0xFFDDDDDD)),
                    Builder(
                      builder: (_) {
                        final vat = VatBreakdown.inclusive(
                          gross: sale.total,
                          rate: settings.vatRate,
                        );
                        return Column(
                          children: [
                            if (vat.rate > 0) ...[
                              Row(
                                children: [
                                  Expanded(child: Text(t('subtotal'))),
                                  Text(money.format(vat.net)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${t('vat')} ${formatQty(vat.rate)}%',
                                    ),
                                  ),
                                  Text(money.format(vat.vat)),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    t('total').toUpperCase(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                Text(
                                  money.format(sale.total),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                    color: Color(0xFF1FA800),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: QrImageView(
                        data: receiptQr,
                        size: 140,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t('thank_you'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          AccentButton(
            label: t('print_receipt'),
            icon: Icons.print_rounded,
            onPressed: () => _withReceiptDetails(
              () => PrintService.pickFormatAndPrintReceipt(
                context: context,
                shop: ref.read(shopSettingsProvider).valueOrNull ?? settings,
                sale: sale,
                money: money.format,
              ),
            ),
          ),
          const SizedBox(height: 10),
          AccentButton(
            label: t('send_receipt'),
            icon: Icons.ios_share_rounded,
            color: p.cardElevated,
            foreground: p.textPrimary,
            onPressed: () => _withReceiptDetails(() => _sendReceipt(sale)),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => context.go('/inventory'),
            style: OutlinedButton.styleFrom(
              foregroundColor: p.textPrimary,
              side: BorderSide(color: p.stroke),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(t('done')),
          ),
        ],
      ),
    );
  }
}

/// Year list matching client Settings → Receipts design.
class ReceiptsYearsPage extends ConsumerStatefulWidget {
  const ReceiptsYearsPage({super.key});

  @override
  ConsumerState<ReceiptsYearsPage> createState() => _ReceiptsYearsPageState();
}

enum _ReceiptYearSort { newest, oldest, mostReceipts }

class _ReceiptsYearsPageState extends ConsumerState<ReceiptsYearsPage> {
  bool _showSearch = false;
  final _search = TextEditingController();
  _ReceiptYearSort _sort = _ReceiptYearSort.newest;
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showAppSheet<_ReceiptYearSort>(
      context: context,
      heightFactor: 0.42,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(title: t('sort')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    AppRadioRow<_ReceiptYearSort>(
                      label: t('sort_newest'),
                      icon: Icons.schedule_rounded,
                      value: _ReceiptYearSort.newest,
                      groupValue: _sort,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    ),
                    const SizedBox(height: 8),
                    AppRadioRow<_ReceiptYearSort>(
                      label: t('sort_oldest'),
                      icon: Icons.history_rounded,
                      value: _ReceiptYearSort.oldest,
                      groupValue: _sort,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    ),
                    const SizedBox(height: 8),
                    AppRadioRow<_ReceiptYearSort>(
                      label: t('sort_most_receipts'),
                      icon: Icons.receipt_long_rounded,
                      value: _ReceiptYearSort.mostReceipts,
                      groupValue: _sort,
                      onChanged: (v) => Navigator.pop(ctx, v),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final t = ref.read(tProvider);
    var from = _from;
    var to = _to;
    final applied = await showAppSheet<bool>(
      context: context,
      heightFactor: 0.48,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setModal) {
            Future<void> pickFrom() async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: from ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setModal(() => from = d);
            }

            Future<void> pickTo() async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: to ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) setModal(() => to = d);
            }

            String fmt(DateTime? v, String placeholder) {
              if (v == null) return placeholder;
              return '${v.day.toString().padLeft(2, '0')}.'
                  '${v.month.toString().padLeft(2, '0')}.'
                  '${v.year}';
            }

            Widget dateField({
              required DateTime? value,
              required String placeholder,
              required VoidCallback onTap,
            }) {
              return Pressable(
                onTap: onTap,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: p.cardElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.stroke),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          fmt(value, placeholder),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color:
                                value == null ? p.textMuted : p.textPrimary,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_rounded,
                          size: 22, color: p.textMuted),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                AppSheetHeader(title: t('filter')),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    children: [
                      dateField(
                        value: from,
                        placeholder: t('from_date'),
                        onTap: pickFrom,
                      ),
                      const SizedBox(height: 12),
                      dateField(
                        value: to,
                        placeholder: t('to_date'),
                        onTap: pickTo,
                      ),
                    ],
                  ),
                ),
                AppSheetActions(
                  onReset: () => setModal(() {
                    from = null;
                    to = null;
                  }),
                  onApply: () => Navigator.pop(ctx, true),
                ),
              ],
            );
          },
        );
      },
    );
    if (applied == true && mounted) {
      setState(() {
        _from = from;
        _to = to;
      });
    }
  }

  Future<void> _exportReceipts(List<Sale> sales) async {
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    await CsvExportService().exportReceipts(
      sales: sales,
      currency: settings?.currencySymbol ?? '€',
      companyName: settings?.companyName,
      from: _from,
      to: _to,
    );
  }

  List<Sale> _filteredSales(List<Sale> list) {
    return list.where((s) {
      final d = s.createdAt;
      if (_from != null) {
        final start = DateTime(_from!.year, _from!.month, _from!.day);
        if (d.isBefore(start)) return false;
      }
      if (_to != null) {
        final end =
            DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59, 999);
        if (d.isAfter(end)) return false;
      }
      return true;
    }).toList();
  }

  List<MapEntry<int, List<Sale>>> _yearEntries(List<Sale> list) {
    final byYear = <int, List<Sale>>{};
    for (final s in list) {
      byYear.putIfAbsent(s.createdAt.year, () => []).add(s);
    }
    var entries = byYear.entries.toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      entries = entries
          .where(
            (e) =>
                '${e.key}'.contains(q) ||
                '${e.value.length}'.contains(q),
          )
          .toList();
    }
    switch (_sort) {
      case _ReceiptYearSort.newest:
        entries.sort((a, b) => b.key.compareTo(a.key));
      case _ReceiptYearSort.oldest:
        entries.sort((a, b) => a.key.compareTo(b.key));
      case _ReceiptYearSort.mostReceipts:
        entries.sort((a, b) => b.value.length.compareTo(a.value.length));
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final sales = ref.watch(salesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded, size: 18, color: p.textPrimary),
            const SizedBox(width: 8),
            Text(t('receipts')),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t('export_csv'),
            onPressed: () {
              final list = sales.valueOrNull;
              if (list == null || list.isEmpty) return;
              _exportReceipts(_filteredSales(list));
            },
            icon: Icon(
              Icons.file_download_outlined,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
      body: sales.when(
        loading: () => const AppLoader(),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final filtered = _filteredSales(list);
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_rounded,
              title: t('no_receipts'),
              subtitle: t('no_receipts_sub'),
            );
          }

          final years = _yearEntries(filtered);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: ListActionIconsRow(
                  onSort: _showSortSheet,
                  onFilter: _showFilterSheet,
                  onSearch: () => setState(() => _showSearch = !_showSearch),
                ),
              ),
              if (_showSearch)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: t('search'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                    ),
                  ),
                ),
              Expanded(
                child: years.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_rounded,
                        title: t('no_receipts'),
                        subtitle: t('no_receipts_sub'),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          FadeSlide(
                            child: AppCard(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: [
                                  for (var i = 0; i < years.length; i++) ...[
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => context.push(
                                          '/receipts/year/${years[i].key}',
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 16,
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                '${years[i].key}',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 17,
                                                  color: p.textPrimary,
                                                ),
                                              ),
                                              const Spacer(),
                                              Icon(
                                                Icons.receipt_long_rounded,
                                                size: 18,
                                                color: p.textSecondary,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                t('year_receipts').replaceAll(
                                                  '{count}',
                                                  '${years[i].value.length}',
                                                ),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: p.textPrimary
                                                      .withValues(alpha: 0.85),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Icon(
                                                Icons.chevron_right_rounded,
                                                color: p.textPrimary
                                                    .withValues(alpha: 0.55),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (i < years.length - 1)
                                      Divider(
                                        height: 1,
                                        indent: 16,
                                        endIndent: 16,
                                        color: p.stroke,
                                      ),
                                  ],
                                ],
                              ),
                            ),
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
}

class ReceiptsYearPage extends ConsumerWidget {
  const ReceiptsYearPage({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final sales = ref.watch(salesProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );

    Future<void> exportYear(List<Sale> yearSales) async {
      await CsvExportService().exportReceipts(
        sales: yearSales,
        currency: settings?.currencySymbol ?? '€',
        companyName: settings?.companyName,
        from: DateTime(year, 1, 1),
        to: DateTime(year, 12, 31, 23, 59, 59),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$year'),
        actions: [
          IconButton(
            tooltip: t('export_csv'),
            onPressed: () {
              final list = sales.valueOrNull;
              if (list == null) return;
              final yearSales =
                  list.where((s) => s.createdAt.year == year).toList();
              if (yearSales.isEmpty) return;
              exportYear(yearSales);
            },
            icon: Icon(
              Icons.file_download_outlined,
              color: p.textPrimary,
            ),
          ),
        ],
      ),
      body: sales.when(
        loading: () => const AppLoader(),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          final yearSales =
              list.where((s) => s.createdAt.year == year).toList();
          if (yearSales.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_rounded,
              title: t('no_receipts'),
              subtitle: t('no_receipts_sub'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: yearSales.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final sale = yearSales[i];
              return FadeSlide(
                delay: Duration(milliseconds: 30 * i),
                child: AppCard(
                  onTap: () => context.push('/sell/receipt/${sale.id}'),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded, color: p.neon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale.customerName ?? t('guest'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                            Text(
                              sale.createdAt
                                  .toLocal()
                                  .toString()
                                  .split('.')
                                  .first,
                              style: TextStyle(
                                color: p.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MoneyText(
                        money.format(sale.total),
                        weight: FontWeight.w800,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
