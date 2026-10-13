import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:inventory_app/features/inventory/presentation/qr_print_preview_page.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Default label subtitle: "price per unit", or just the price without a unit.
String defaultQrSubtitleFor({
  required double price,
  required String? unit,
  required MoneyFormatter money,
  required String perWord,
}) {
  final priceText = money.format(price);
  final u = unit?.trim() ?? '';
  return u.isEmpty ? priceText : '$priceText $perWord $u';
}

class QrLabelPage extends ConsumerStatefulWidget {
  const QrLabelPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<QrLabelPage> createState() => _QrLabelPageState();
}

class _QrLabelPageState extends ConsumerState<QrLabelPage> {
  bool _loading = true;
  bool _busy = false;

  InventoryItem? _item;
  String? _payload;
  String _defaultSubtitle = '';

  /// Renders the label image (what the print preview + print use) in the
  /// background once typing pauses, so Print → preview is instant.
  Timer? _warmTimer;

  /// QR widget rebuilt only when its data changes (not on every keystroke).
  String? _qrKey;
  Widget? _qrWidget;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _linkCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _subtitleCtrl = TextEditingController();
    _linkCtrl = TextEditingController();
    _titleCtrl.addListener(_onFieldsChanged);
    _subtitleCtrl.addListener(_onFieldsChanged);
    _linkCtrl.addListener(_onFieldsChanged);
    // Item from the in-memory list → first frame already shows the label
    // (no loader flash); falls back to the DB.
    final cached = ref
        .read(inventoryItemsProvider)
        .valueOrNull
        ?.where((i) => i.id == widget.itemId)
        .firstOrNull;
    if (cached != null) {
      _apply(cached);
    } else {
      _load();
    }
  }

  void _onFieldsChanged() {
    if (!mounted || _loading) return;
    setState(() {}); // live preview
    _scheduleWarm(const Duration(milliseconds: 600));
  }

  void _scheduleWarm(Duration after) {
    _warmTimer?.cancel();
    _warmTimer = Timer(after, () {
      if (!mounted || _payload == null) return;
      unawaited(
        PrintService.rasterQrLabelPng(
          title: _labelTitle,
          subtitle: _labelSubtitle,
          qrData: _qrData,
          companyName: _companyName,
        ).then<void>(
          (_) {},
          onError: (Object e) {
            debugPrint('QR label warm failed: $e');
          },
        ),
      );
    });
  }

  String get _companyName =>
      ref.read(shopSettingsProvider).valueOrNull?.companyName ?? '';

  Future<void> _load() async {
    final item = await ref
        .read(inventoryRepositoryProvider)
        .getItem(widget.itemId);
    if (item == null) {
      if (mounted) context.pop();
      return;
    }
    if (!mounted) return;
    setState(() => _apply(item));
  }

  void _apply(InventoryItem item) {
    final settings = ref.read(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );

    _item = item;
    _payload = QrPayload.encodeItem(
      id: item.id,
      title: item.title,
      price: item.price,
      unit: item.unit,
    );

    final defaultSubtitle = defaultQrSubtitleFor(
      price: item.price,
      unit: item.unit,
      money: money,
      perWord: ref.read(tProvider)('per'),
    );
    _defaultSubtitle = defaultSubtitle;
    final legacyDefaults = {
      item.defaultQrSubtitle,
      money.format(item.price),
      if ((item.unit ?? '').isNotEmpty)
        '${money.format(item.price)} / ${item.unit}',
    };

    _titleCtrl.text = (item.qrTitle != null && item.qrTitle!.trim().isNotEmpty)
        ? item.qrTitle!
        : item.title;
    // Saved subtitles that were just an old auto default get the current
    // default (so a price change shows on the label).
    final saved = item.qrSubtitle?.trim() ?? '';
    _subtitleCtrl.text = (saved.isEmpty || legacyDefaults.contains(saved))
        ? defaultSubtitle
        : saved;
    _linkCtrl.text = item.qrLink ?? '';

    _loading = false;
    // After the page has slid in (never during the open animation).
    _scheduleWarm(const Duration(milliseconds: 450));
  }

  @override
  void dispose() {
    _warmTimer?.cancel();
    _titleCtrl.removeListener(_onFieldsChanged);
    _subtitleCtrl.removeListener(_onFieldsChanged);
    _linkCtrl.removeListener(_onFieldsChanged);
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _linkCtrl.dispose();
    super.dispose();
  }

  String get _labelTitle {
    final v = _titleCtrl.text.trim();
    return v.isEmpty ? (_item?.title ?? '') : v;
  }

  String get _labelSubtitle => _subtitleCtrl.text.trim();

  String? get _labelLink {
    final v = _linkCtrl.text.trim();
    return v.isEmpty ? null : v;
  }

  /// With a link: link + `#inv=<id>` (phone camera opens the URL, the
  /// in-app scanner still finds the item). Without: the JSON item payload.
  String get _qrData => QrPayload.labelData(
    itemId: widget.itemId,
    payload: _payload ?? '',
    link: _labelLink,
  );

  /// Saves the label texts — only when they changed (an unchanged label
  /// never rewrites the item / reloads the inventory list). Not awaited by
  /// Back / Print, so leaving the page is instant.
  Future<void> _persist() async {
    final item = _item;
    if (item == null) return;
    // Empty = "use the default", so defaults follow later title/price edits.
    final qrTitle = _labelTitle == item.title ? '' : _labelTitle;
    final qrSubtitle = _labelSubtitle == _defaultSubtitle ? '' : _labelSubtitle;
    final qrLink = _linkCtrl.text.trim();
    if ((item.qrTitle ?? '') == qrTitle &&
        (item.qrSubtitle ?? '') == qrSubtitle &&
        (item.qrLink ?? '') == qrLink) {
      return;
    }
    final updated = item.copyWith(
      qrTitle: qrTitle,
      qrSubtitle: qrSubtitle,
      qrLink: qrLink,
      updatedAt: DateTime.now(),
    );
    _item = updated;
    await ref.read(inventoryItemsProvider.notifier).upsert(updated);
  }

  /// Print → print preview pop-up (labels per page + Print there,
  /// which opens the system print window). The label PDF keeps warming in
  /// the background, so the preview's Print is instant.
  Future<void> _print() async {
    if (_busy || _payload == null) return;
    try {
      unawaited(_persist());
      FocusScope.of(context).unfocus();
      await QrPrintPreviewPage.show(
        context,
        QrPrintArgs(
          title: _labelTitle,
          subtitle: _labelSubtitle,
          qrData: _qrData,
          company: _companyName,
        ),
      );
    } catch (e, st) {
      debugPrint('Open print preview failed: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.read(tProvider)('print_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    if (_busy) return;
    final payload = _payload;
    if (payload == null) return;
    setState(() => _busy = true);
    try {
      await _persist();
      if (!mounted || !buttonContext.mounted) return;
      final company =
          ref.read(shopSettingsProvider).valueOrNull?.companyName.trim() ?? '';
      final buffer = StringBuffer();
      if (company.isNotEmpty) buffer.writeln(company);
      buffer
        ..writeln(_labelTitle)
        ..writeln(_labelSubtitle);
      final link = _labelLink;
      if (link != null) buffer.writeln(link);
      buffer.writeln(payload);
      setState(() => _busy = false);
      await shareWithOrigin(
        ShareParams(text: buffer.toString()),
        buttonContext,
      );
    } catch (e, st) {
      debugPrint('Share label failed: $e\n$st');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.read(tProvider)('share_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _copy() async {
    final payload = _payload;
    if (payload == null) return;
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ref.read(tProvider)('qr_copied'))));
  }

  Future<void> _done() async {
    // Leave at once; the (rare) save finishes in the background.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final failed = ref.read(tProvider)('save_failed');
    unawaited(
      _persist().catchError((Object e) {
        debugPrint('Saving QR label failed: $e');
        messenger?.showSnackBar(SnackBar(content: Text(failed)));
      }),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/inventory');
    }
  }

  Widget _qr() {
    final data = _qrData;
    if (_qrKey == data && _qrWidget != null) return _qrWidget!;
    _qrKey = data;
    return _qrWidget = RepaintBoundary(
      child: QrImageView(
        data: data,
        size: 150,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF001830),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF001830),
        ),
        errorCorrectionLevel: QrErrorCorrectLevel.M,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final company = (settings?.companyName.trim().isNotEmpty == true)
        ? settings!.companyName.trim()
        : t('company_name');

    if (_loading || _item == null || _payload == null) {
      return const Scaffold(body: AppLoader());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('qr_label')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _done,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          FadeSlide(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    p.cardElevated,
                    p.card,
                    p.fabBorder.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(color: p.stroke),
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                children: [
                  Text(
                    company,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.fabBorder,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _qr(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _labelTitle,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 24,
                      height: 1.15,
                      color: p.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (_labelSubtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      _labelSubtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.neon,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                  // Link is never shown on the label — only encoded in the QR.
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(labelText: t('title')),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _subtitleCtrl,
            decoration: InputDecoration(labelText: t('subtitle')),
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _linkCtrl,
            decoration: InputDecoration(
              labelText: t('link'),
              hintText: 'https://…',
              helperText: t('qr_link_helper'),
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 14),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  label: t('print_label'),
                  icon: Icons.print_rounded,
                  onPressed: _busy ? null : _print,
                ),
              ),
              const SizedBox(width: 10),
              Builder(
                builder: (btnCtx) => _RoundAction(
                  icon: Icons.ios_share_rounded,
                  onTap: _busy ? null : () => _share(btnCtx),
                ),
              ),
              const SizedBox(width: 8),
              _RoundAction(
                icon: Icons.copy_rounded,
                onTap: _busy ? null : _copy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Pressable(
      onTap: onTap,
      enabled: onTap != null,
      child: Container(
        width: 52,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.stroke),
        ),
        child: Icon(icon, color: p.textPrimary, size: 22),
      ),
    );
  }
}
