import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/print/print_service.dart';
import 'package:pdf/pdf.dart';
import 'package:inventory_app/core/qr/qr_payload.dart';
import 'package:inventory_app/core/share/share_origin.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';
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

  /// True while a background PDF rebuild is in flight (Print shows hourglass).
  bool _pdfBuilding = false;
  InventoryItem? _item;
  String? _payload;
  String _defaultSubtitle = '';

  /// Pre-built label PDF — Print only opens the sheet when this matches
  /// [_pdfCacheKey] so iOS never gets an empty/slow onLayout rebuild.
  Uint8List? _pdfBytes;
  String? _pdfCacheKey;
  Timer? _pdfDebounce;
  int _pdfGen = 0;

  /// Labels laid out on one printed page (remembered between sessions).
  int _perPage = 1;

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
    // Warm fonts immediately (also started from main.dart).
    unawaited(PrintService.preload());
    unawaited(_loadPerPage());
    _load();
  }

  Future<void> _loadPerPage() async {
    final n = await PrintService.lastQrLabelsPerPage();
    if (mounted && n != _perPage) setState(() => _perPage = n);
  }

  void _setPerPage(int n) {
    if (n == _perPage) return;
    AppHaptics.selection();
    setState(() => _perPage = n);
    unawaited(PrintService.saveQrLabelsPerPage(n));
  }

  void _onFieldsChanged() {
    if (!mounted) return;
    setState(() {}); // live preview
    _schedulePdfRebuild();
  }

  String get _companyName =>
      ref.read(shopSettingsProvider).valueOrNull?.companyName ?? '';

  String get _pdfKey =>
      '$_labelTitle\x1f$_labelSubtitle\x1f$_qrData\x1f${_companyName.trim()}';

  bool get _pdfReady =>
      _pdfBytes != null && _pdfBytes!.isNotEmpty && _pdfCacheKey == _pdfKey;

  void _schedulePdfRebuild() {
    _pdfDebounce?.cancel();
    _pdfDebounce = Timer(const Duration(milliseconds: 200), () {
      unawaited(_rebuildPdfCache());
    });
  }

  Future<void> _rebuildPdfCache() async {
    if (_payload == null || _item == null) return;
    final gen = ++_pdfGen;
    final key = _pdfKey;
    if (_pdfCacheKey == key && _pdfBytes != null && _pdfBytes!.isNotEmpty) {
      if (mounted && _pdfBuilding) setState(() => _pdfBuilding = false);
      return;
    }
    if (mounted) setState(() => _pdfBuilding = true);
    try {
      await PrintService.preload();
      final bytes = await PrintService.prepareQrLabelPrintPdf(
        title: _labelTitle,
        subtitle: _labelSubtitle,
        qrData: _qrData,
        companyName: _companyName,
      );
      if (!mounted || gen != _pdfGen) return;
      setState(() {
        _pdfBytes = bytes;
        _pdfCacheKey = key;
        _pdfBuilding = false;
      });
    } catch (e, st) {
      debugPrint('QR label PDF cache failed: $e\n$st');
      if (mounted && gen == _pdfGen) {
        setState(() {
          _pdfBuilding = false;
          _pdfBytes = null;
          _pdfCacheKey = null;
        });
      }
    }
  }

  Future<void> _load() async {
    final item = await ref
        .read(inventoryRepositoryProvider)
        .getItem(widget.itemId);
    if (item == null) {
      if (mounted) context.pop();
      return;
    }
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

    if (mounted) setState(() => _loading = false);
    // Build the print PDF now so the first tap is O(1).
    unawaited(_rebuildPdfCache());
  }

  @override
  void dispose() {
    _pdfDebounce?.cancel();
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

  Future<void> _persist() async {
    final item = _item;
    if (item == null) return;
    // Empty = "use the default", so defaults follow later title/price edits.
    final updated = item.copyWith(
      qrTitle: _labelTitle == item.title ? '' : _labelTitle,
      qrSubtitle: _labelSubtitle == _defaultSubtitle ? '' : _labelSubtitle,
      qrLink: _linkCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    await ref.read(inventoryItemsProvider.notifier).upsert(updated);
    _item = updated;
  }

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Never open the system sheet until bytes are ready — empty/slow
      // onLayout is what produced blank pages on the first few taps.
      if (!_pdfReady) {
        _pdfDebounce?.cancel();
        await _rebuildPdfCache();
      }
      final bytes = _pdfBytes;
      if (!mounted) return;
      if (bytes == null || bytes.length < 800 || !_pdfReady) {
        throw StateError('Label PDF not ready (${bytes?.length ?? 0} bytes)');
      }
      final ready = bytes;
      setState(() => _busy = false);
      // Persist in the background; don't delay the print window.
      unawaited(_persist());
      debugPrint('QR label print tap: ${ready.length} bytes, $_perPage/page');
      // Straight to the OS print dialog. PNG is rasterized before the sheet
      // opens; onLayout only wraps it (1 label, or a grid of [_perPage]).
      await PrintService.layoutQrLabelPdf(
        bytes: ready,
        title: _labelTitle,
        subtitle: _labelSubtitle,
        qrData: _qrData,
        companyName: _companyName,
        format: PrintService.qrLabelFormat,
        perPage: _perPage,
      );
    } catch (e, st) {
      debugPrint('Print label failed: $e\n$st');
      if (mounted) {
        setState(() => _busy = false);
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
      if (!mounted) return;
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
    // Back always works, even while a print job is still open.
    setState(() => _busy = true);
    try {
      await _persist();
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/inventory');
      }
    } catch (e) {
      debugPrint('Saving QR label failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(tProvider)('save_failed'))),
        );
      }
    }
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
                    child: QrImageView(
                      data: _qrData,
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
          _PagePreview(
            count: _perPage,
            company: company,
            title: _labelTitle,
            subtitle: _labelSubtitle,
            qrData: _qrData,
            caption: _perPage > 1
                ? t('labels_on_a4').replaceAll('{n}', '$_perPage')
                : null,
            picker: _PerPagePicker(
              value: _perPage,
              label: t('per_page'),
              menuTitle: t('labels_per_page'),
              enabled: !_busy,
              onChanged: _setPerPage,
            ),
            previewLabel: t('print_preview'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AccentButton(
                  label: t('print_label'),
                  icon: (_busy || (_pdfBuilding && !_pdfReady))
                      ? Icons.hourglass_top_rounded
                      : Icons.print_rounded,
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

/// On-screen page preview: a sheet of paper showing exactly [count] labels
/// in the same grid the print uses, with the labels-per-page dropdown on it.
class _PagePreview extends StatelessWidget {
  const _PagePreview({
    required this.count,
    required this.company,
    required this.title,
    required this.subtitle,
    required this.qrData,
    required this.picker,
    required this.previewLabel,
    this.caption,
  });

  final int count;
  final String company;
  final String title;
  final String subtitle;
  final String qrData;
  final Widget picker;
  final String previewLabel;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Same paper as the print: 1 label = full-bleed sticker page (A6 on
    // Android, the 70×100 mm sticker on iOS); more = A4, 8 mm margin, 4 mm gap.
    final single = count <= 1;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final sheet = single
        ? (ios ? PrintService.qrLabelFormat : PdfPageFormat.a6)
        : PdfPageFormat.a4;
    final margin = single ? 0.0 : 8 * PdfPageFormat.mm;
    final grid = PrintService.qrLabelGrid(
      count,
      sheet.width - margin * 2,
      sheet.height - margin * 2,
      gap: 4 * PdfPageFormat.mm,
    );
    final text = GoogleFonts.interTextTheme(Theme.of(context).textTheme);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.stroke),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                previewLabel,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              picker,
            ],
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              style: TextStyle(
                color: p.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: AspectRatio(
                aspectRatio: sheet.width / sheet.height,
                child: LayoutBuilder(
                  builder: (context, box) {
                    final scale = box.maxWidth / sheet.width;
                    final gap = 4 * PdfPageFormat.mm * scale;
                    final w = grid.labelW * scale;
                    final h = grid.labelH * scale;
                    final rows = <Widget>[];
                    var placed = 0;
                    for (var r = 0; r < grid.rows && placed < count; r++) {
                      final cells = <Widget>[];
                      for (var c = 0; c < grid.cols && placed < count; c++) {
                        if (c > 0) cells.add(SizedBox(width: gap));
                        cells.add(
                          _MiniLabel(
                            cutLine: !single,
                            width: w,
                            height: h,
                            text: text,
                            company: company,
                            title: title,
                            subtitle: subtitle,
                            qrData: qrData,
                          ),
                        );
                        placed++;
                      }
                      if (r > 0) rows.add(SizedBox(height: gap));
                      rows.add(
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: cells,
                        ),
                      );
                    }
                    return Container(
                      color: Colors.white,
                      padding: EdgeInsets.all(margin * scale),
                      child: Column(
                        mainAxisAlignment: single
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: rows,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One label on the page preview, scaled to the cell size. Text uses the
/// same point sizes as the printed label so the preview matches the print.
class _MiniLabel extends StatelessWidget {
  const _MiniLabel({
    this.cutLine = true,
    required this.width,
    required this.height,
    required this.text,
    required this.company,
    required this.title,
    required this.subtitle,
    required this.qrData,
  });

  final bool cutLine;
  final double width;
  final double height;
  final TextTheme text;
  final String company;
  final String title;
  final String subtitle;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    // Laid out once at the real label size (pt) and scaled as a picture, so
    // line breaks are identical to the print at every labels-per-page count.
    final fmt = PrintService.qrLabelFormat;
    final shownTitle = title.trim().isEmpty ? '—' : title.trim();
    TextStyle style(double size, FontWeight w) => text.bodyMedium!.copyWith(
      color: Colors.black,
      fontWeight: w,
      fontSize: size,
      height: 1.15,
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: cutLine
            ? Border.all(color: const Color(0xFFBDBDBD), width: 0.5)
            : null,
      ),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: fmt.width,
          height: fmt.height,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (company.trim().isNotEmpty) ...[
                  Text(
                    company.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: style(
                      PrintService.labelCompanyFit(company),
                      FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                QrImageView(
                  data: qrData,
                  size: PrintService.labelQrSize,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
                const SizedBox(height: 8),
                Text(
                  shownTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: style(
                    PrintService.labelTitleSize(shownTitle),
                    FontWeight.w700,
                  ),
                ),
                if (subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle.trim(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: style(
                      PrintService.labelSubtitleSize(subtitle),
                      FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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

/// "Labels per page" selector next to Print (same 52 px box as the round
/// actions). Opens a compact menu with the counts in
/// [PrintService.qrLabelsPerPageOptions].
class _PerPagePicker extends StatelessWidget {
  const _PerPagePicker({
    required this.value,
    required this.label,
    required this.menuTitle,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final String label;
  final String menuTitle;
  final bool enabled;
  final ValueChanged<int> onChanged;

  Future<void> _open(BuildContext context) async {
    final p = AppPalette.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    AppHaptics.light();
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final picked = await showMenu<int>(
      context: context,
      color: p.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: p.stroke),
      ),
      position: RelativeRect.fromLTRB(
        topLeft.dx,
        topLeft.dy,
        overlay.size.width - topLeft.dx - box.size.width,
        overlay.size.height - topLeft.dy,
      ),
      items: [
        PopupMenuItem<int>(
          enabled: false,
          height: 36,
          child: Text(
            menuTitle,
            style: TextStyle(
              color: p.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        for (final n in PrintService.qrLabelsPerPageOptions)
          PopupMenuItem<int>(
            value: n,
            height: 44,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  n == 1
                      ? Icons.crop_portrait_rounded
                      : Icons.grid_view_rounded,
                  size: 18,
                  color: p.textMuted,
                ),
                const SizedBox(width: 24),
                if (n == value)
                  Icon(Icons.check_rounded, size: 20, color: p.fabBorder),
              ],
            ),
          ),
      ],
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: '$menuTitle: $value',
      child: Pressable(
        onTap: enabled ? () => _open(context) : null,
        enabled: enabled,
        child: Container(
          width: 64,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.stroke),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$value',
                    style: TextStyle(
                      color: p.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      height: 1.1,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 20,
                    color: p.textSecondary,
                  ),
                ],
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
