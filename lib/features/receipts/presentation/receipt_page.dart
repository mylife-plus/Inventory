import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/core/receipts/receipt_details_gate.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/contact_launch.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
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
import 'package:inventory_app/core/share/share_origin.dart';

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
      await shareWithOrigin(ShareParams(text: body), context);
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
                  // Only the contact options — no customer card here.
                  children: [
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
                          await shareWithOrigin(ShareParams(text: body), ctx);
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
                          await shareWithOrigin(ShareParams(text: body), ctx);
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

  /// Receipt Print: a small paper-size picker (A4 / 80 mm / 58 mm roll,
  /// last choice preselected) that goes straight into the OS print dialog.
  Future<void> _printReceipt(
    Sale sale,
    MoneyFormatter money,
    ShopSettings fallback,
  ) async {
    final t = ref.read(tProvider);
    final initial = await PrintService.lastReceiptPaper();
    if (!mounted) return;
    final paper = await _pickReceiptPaper(t, initial);
    if (paper == null || !mounted) return;
    unawaited(PrintService.saveReceiptPaper(paper));
    final shop = ref.read(shopSettingsProvider).valueOrNull ?? fallback;
    try {
      // Built up front; onLayout only hands these bytes to the system.
      final pdf = await PrintService.buildReceiptPdf(
        shop: shop,
        sale: sale,
        money: money.format,
        format: PrintService.receiptFormatFor(paper),
        t: t.call,
      );
      await PrintService.layoutReceiptPdf(
        bytes: pdf.bytes,
        format: pdf.format,
        sale: sale,
      );
    } catch (e, st) {
      debugPrint('Print receipt failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t('print_failed')}: $e')),
      );
    }
  }

  Future<String?> _pickReceiptPaper(S t, String initial) {
    final options = [
      (
        id: PrintService.receiptPaperA4,
        label: t('paper_a4'),
        sub: t('paper_a4_sub'),
        icon: Icons.description_rounded,
      ),
      (
        id: PrintService.receiptPaperRoll80,
        label: t('paper_roll80'),
        sub: t('paper_roll80_sub'),
        icon: Icons.receipt_long_rounded,
      ),
      (
        id: PrintService.receiptPaperRoll58,
        label: t('paper_roll58'),
        sub: t('paper_roll58_sub'),
        icon: Icons.receipt_rounded,
      ),
    ];
    return showAppSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppSheetHeader(
                title: t('printer_paper_size'),
                subtitle: t('receipt_paper_sub'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    for (final o in options) ...[
                      _PaperOptionRow(
                        icon: o.icon,
                        label: o.label,
                        subtitle: o.sub,
                        selected: o.id == initial,
                        onTap: () => Navigator.of(ctx).pop(o.id),
                      ),
                      const SizedBox(height: 10),
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

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/inventory');
    }
  }

  Future<void> _changeCustomer(Sale sale) async {
    final changed =
        await context.push<bool>('/sell/customer?saleId=${sale.id}');
    if (changed != true || !mounted) return;
    final fresh = await ref.read(saleRepositoryProvider).get(sale.id);
    if (mounted && fresh != null) setState(() => _sale = fresh);
  }

  Widget _customerCard(Sale sale, MoneyFormatter money) {
    final t = ref.read(tProvider);
    final customers = ref.watch(customersProvider).valueOrNull ?? const [];
    final customer = sale.customerId == null
        ? null
        : customers.where((c) => c.id == sale.customerId).firstOrNull;
    if (customer == null) {
      final name = sale.customerName;
      return CustomerListCard(
        name: (name == null || name.isEmpty || name == 'Guest')
            ? t('guest')
            : name,
        money: money,
        naStats: true,
        onTap: () => _changeCustomer(sale),
      );
    }
    return SelectCustomerTile(
      key: ValueKey('receipt-cust-${customer.id}-${sale.total}'),
      customer: customer,
      money: money,
      // Client: contact icons here are informational only (no redirect).
      contactsInteractive: false,
      onTap: () => _changeCustomer(sale),
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
    // The editor takes the receipt's place in the history, so Cancel (a
    // plain pop) lands on the screen that opened the receipt — Items Sold
    // list, customer purchases — never back on this receipt.
    if (context.canPop()) {
      context.pushReplacement('/sell');
    } else {
      context.go('/sell');
    }
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
    final b = StringBuffer()..writeln(settings.companyName);
    final street = settings.street.replaceAll('\u001F', ' ').trim();
    final zipCity = '${settings.zip} ${settings.city}'.trim();
    if (street.isNotEmpty) b.writeln(street);
    if (zipCity.isNotEmpty) b.writeln(zipCity);
    if (settings.phone.trim().isNotEmpty) b.writeln(settings.phone);
    b
      ..writeln('------------------------------')
      ..writeln('${t('receipt')} ${sale.id.substring(0, 8).toUpperCase()}')
      ..writeln(sale.createdAt.toLocal().toString().split('.').first)
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
            onPressed: _leave,
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
                t('shop_details_needed'),
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

    // Receipt QR opens the shop's QR-Link; no link → no QR at all.
    final receiptQr = settings.receiptQrData;

    final zipCity = '${settings.zip} ${settings.city}'.trim();

    final receiptCard = Container(
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
      clipBehavior: Clip.antiAlias,
      // Long receipts scroll inside the card so the page always fits.
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
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
                if (settings.street.trim().isNotEmpty)
                  Text(settings.street.replaceAll('\u001F', ' '),
                      textAlign: TextAlign.center),
                if (zipCity.isNotEmpty)
                  Text(zipCity, textAlign: TextAlign.center),
                if (settings.phone.isNotEmpty)
                  Text(settings.phone, textAlign: TextAlign.center),
                const Divider(height: 22, color: Color(0xFFDDDDDD)),
                Text(
                  '${t('receipt')} ${sale.id.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  sale.createdAt.toLocal().toString().split('.').first,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF666666)),
                ),
                const Divider(height: 22, color: Color(0xFFDDDDDD)),
                ...sale.lines.map(
                  (l) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            // Same "5 x Cheese" wording as the printout.
                            '${formatQty(l.quantity)} x ${l.title}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                if (receiptQr != null) ...[
                  Center(
                    child: QrImageView(
                      data: receiptQr,
                      size: 140,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
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
    );

    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/inventory');
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          title: Text(t('send_receipt')),
          actions: [
            IconButton(
              tooltip: t('edit_item'),
              onPressed: () => _editSaleItems(sale),
              icon: Icon(Icons.edit_rounded, color: p.textSecondary),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Selected customer — tap to change.
                _customerCard(sale, money),
                const SizedBox(height: 12),
                Expanded(child: FadeSlide(child: receiptCard)),
                const SizedBox(height: 12),
                AccentButton(
                  label: t('print_receipt'),
                  icon: Icons.print_rounded,
                  onPressed: () => _withReceiptDetails(
                    () => _printReceipt(sale, money, settings),
                  ),
                ),
                const SizedBox(height: 8),
                AccentButton(
                  label: t('send_receipt'),
                  icon: Icons.ios_share_rounded,
                  color: p.cardElevated,
                  foreground: p.textPrimary,
                  onPressed: () =>
                      _withReceiptDetails(() => _sendReceipt(sale)),
                ),
                const SizedBox(height: 8),
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
          ),
        ),
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

enum _ReceiptYearSortKey { year, receipts }

const _kDefaultYearSort = SortState<_ReceiptYearSortKey>(_ReceiptYearSortKey.year);

class _ReceiptsYearsPageState extends ConsumerState<ReceiptsYearsPage> {
  bool _showSearch = false;
  final _search = TextEditingController();
  SortState<_ReceiptYearSortKey> _sort = _kDefaultYearSort;
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showSortSheet<_ReceiptYearSortKey>(
      context: context,
      options: [
        SortOption(
          key: _ReceiptYearSortKey.year,
          icon: Icons.schedule_rounded,
          label: t('sort_newest'),
          reversedLabel: t('sort_oldest'),
        ),
        SortOption(
          key: _ReceiptYearSortKey.receipts,
          icon: Icons.receipt_long_rounded,
          label: t('sort_most_receipts'),
          reversedLabel: t('sort_fewest_receipts'),
        ),
      ],
      current: _sort,
      defaultState: _kDefaultYearSort,
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final t = ref.read(tProvider);
    var from = _from;
    var to = _to;
    final applied = await showAppSheet<bool>(
      context: context,
      alignTop: true,
      heightFactor: 0.5,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModal) {
          Future<void> pick(bool isFrom) async {
            final d = await pickFilterDate(context, isFrom ? from : to);
            if (d == null) return;
            setModal(() => isFrom ? from = d : to = d);
          }

          return AppFilterSheet(
            onReset: () {
              from = null;
              to = null;
              Navigator.pop(ctx, true);
            },
            onApply: () => Navigator.pop(ctx, true),
            child: Row(
              children: [
                Expanded(
                  child: AppFilterDateField(
                    placeholder: t('from_date'),
                    value: from,
                    onTap: () => pick(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppFilterDateField(
                    placeholder: t('to_date'),
                    value: to,
                    onTap: () => pick(false),
                  ),
                ),
              ],
            ),
          );
        },
      ),
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
      context: context,
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
    int cmp(MapEntry<int, List<Sale>> a, MapEntry<int, List<Sale>> b) {
      if (_sort.key == _ReceiptYearSortKey.receipts) {
        final c = b.value.length.compareTo(a.value.length);
        if (c != 0) return c;
      }
      return b.key.compareTo(a.key);
    }

    entries.sort((a, b) => _sort.reversed ? cmp(b, a) : cmp(a, b));
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
                  sortActive: _sort != _kDefaultYearSort,
                  filterActive: _from != null || _to != null,
                  searchActive:
                      _showSearch || _search.text.trim().isNotEmpty,
                ),
              ),
              if (_showSearch)
                AppSearchField(
                  controller: _search,
                  hintText: t('search'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  onChanged: (_) => setState(() {}),
                  onDismiss: () {
                    if (mounted) setState(() => _showSearch = false);
                  },
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
      context: context,
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
                              // 'Guest' is the stored sentinel; show it in
                              // the app language.
                              (sale.customerName == null ||
                                      sale.customerName!.trim().isEmpty ||
                                      sale.customerName == 'Guest')
                                  ? t('guest')
                                  : sale.customerName!,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: p.textPrimary,
                              ),
                            ),
                            Text(
                              formatDateTimeShort(sale.createdAt, t.code),
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

/// One paper size in the receipt print picker. Tap = print on that paper.
class _PaperOptionRow extends StatelessWidget {
  const _PaperOptionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? p.fabBorder.withValues(alpha: 0.18)
                    : p.cardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? p.fabBorder : p.textMuted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: p.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.print_rounded, size: 22, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}
