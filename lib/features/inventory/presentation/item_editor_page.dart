import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/core/notifications/in_app_notifications.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';

class ItemEditorPage extends ConsumerStatefulWidget {
  const ItemEditorPage({super.key, this.itemId});

  final String? itemId;

  @override
  ConsumerState<ItemEditorPage> createState() => _ItemEditorPageState();
}

class _ItemEditorPageState extends ConsumerState<ItemEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _category = TextEditingController();
  final _categoryFocus = FocusNode();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _amount = TextEditingController();
  final _unit = TextEditingController();
  final _alertAmount = TextEditingController();
  bool _alertEnabled = false;
  String? _photoPath;
  String? _resolvedPhoto;
  String? _existingId;
  String? _qrTitle;
  String? _qrSubtitle;
  String? _qrLink;
  DateTime? _createdAt;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryFocus.addListener(_onCategoryFocus);
    _load();
  }

  void _onCategoryFocus() {
    if (!_categoryFocus.hasFocus) return;
    // Retrigger optionsBuilder so existing inventory categories appear on focus.
    final text = _category.text;
    _category.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _load() async {
    if (widget.itemId == null) {
      setState(() => _loading = false);
      return;
    }
    final item =
        await ref.read(inventoryRepositoryProvider).getItem(widget.itemId!);
    if (item != null) {
      _existingId = item.id;
      _createdAt = item.createdAt;
      _category.text = item.categoryName ?? '';
      _title.text = item.title;
      _price.text = item.price.toStringAsFixed(2);
      _amount.text = formatQty(item.amount);
      _unit.text = item.unit ?? '';
      _alertEnabled = item.alertEnabled;
      _alertAmount.text = formatQty(item.alertAmount);
      _photoPath = item.photoPath;
      _qrTitle = item.qrTitle;
      _qrSubtitle = item.qrSubtitle;
      _qrLink = item.qrLink;
      _resolvedPhoto = await LocalImageStore.resolve(item.photoPath);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _categoryFocus.removeListener(_onCategoryFocus);
    _category.dispose();
    _categoryFocus.dispose();
    _title.dispose();
    _price.dispose();
    _amount.dispose();
    _unit.dispose();
    _alertAmount.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_camera_rounded, color: p.fabBorder),
                title: Text(ref.read(tProvider)('take_photo')),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: p.fabBorder),
                title: Text(ref.read(tProvider)('choose_gallery')),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (file == null) return;

    final relative = await LocalImageStore.savePicked(
      file,
      itemId: _existingId,
    );
    final resolved = await LocalImageStore.resolve(relative);
    if (!mounted) return;
    setState(() {
      _photoPath = relative;
      _resolvedPhoto = resolved;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    String? categoryId;
    if (_category.text.trim().isNotEmpty) {
      final cat = await ref
          .read(categoriesProvider.notifier)
          .getOrCreate(_category.text.trim());
      categoryId = cat.id;
    }

    final settings = ref.read(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    final now = DateTime.now();
    final id = _existingId ?? newId();
    final price = double.parse(_price.text.replaceAll(',', '.'));
    final title = _title.text.trim();
    final unit = _unit.text.trim().isEmpty ? null : _unit.text.trim();
    // QR label fields may have been edited on the label screen meanwhile —
    // use the latest saved values. Auto-generated defaults are stored as ''
    // so the label always shows the current title / "price per unit".
    final latest = _existingId == null
        ? null
        : await ref.read(inventoryRepositoryProvider).getItem(_existingId!);
    final per = ref.read(tProvider)('per');
    String keepCustom(String? saved, Set<String> defaults) {
      final v = saved?.trim() ?? '';
      return (v.isEmpty || defaults.contains(v)) ? '' : v;
    }

    final subtitleDefaults = <String>{
      for (final it in [?latest]) ...{
        it.defaultQrSubtitle,
        money.format(it.price),
        if ((it.unit ?? '').isNotEmpty) ...{
          '${money.format(it.price)} / ${it.unit}',
          '${money.format(it.price)} $per ${it.unit}',
        },
      },
    };
    final qrTitle =
        keepCustom(latest?.qrTitle ?? _qrTitle, {title, ?latest?.title});
    final qrSubtitle =
        keepCustom(latest?.qrSubtitle ?? _qrSubtitle, subtitleDefaults);

    final item = InventoryItem(
      id: id,
      title: title,
      price: price,
      amount: double.parse(_amount.text.replaceAll(',', '.')),
      categoryId: categoryId,
      categoryName:
          _category.text.trim().isEmpty ? null : _category.text.trim(),
      unit: unit,
      photoPath: _photoPath,
      alertEnabled: _alertEnabled,
      alertAmount:
          double.tryParse(_alertAmount.text.replaceAll(',', '.').trim()) ??
              (_alertEnabled ? 1 : 0),
      qrTitle: qrTitle,
      qrSubtitle: qrSubtitle,
      qrLink: latest?.qrLink ?? _qrLink,
      createdAt: _createdAt ?? now,
      updatedAt: now,
    );

    await ref.read(inventoryItemsProvider.notifier).upsert(item);
    if (!mounted) return;
    final shouldAlert = item.isLowStock;
    setState(() {
      _saving = false;
      _existingId = id;
    });
    context.go('/inventory');
    if (shouldAlert) {
      notifyLowStockItems(ref, [item]);
    }
  }

  Future<void> _delete() async {
    if (_existingId == null) return;
    final ok = await showAppConfirmDialog(
      context: context,
      title: ref.read(tProvider)('delete_item'),
      message: ref.read(tProvider)('cannot_undo'),
      cancelLabel: ref.read(tProvider)('cancel'),
      confirmLabel: ref.read(tProvider)('delete'),
      destructive: true,
    );
    if (!ok) return;
    await LocalImageStore.delete(_photoPath);
    await ref.read(inventoryItemsProvider.notifier).delete(_existingId!);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final p = AppPalette.of(context);
    // Only suggest categories already used on inventory items.
    final inventoryCategories = (ref.watch(inventoryItemsProvider).valueOrNull ?? [])
        .map((e) => e.categoryName?.trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final currency =
        ref.watch(shopSettingsProvider).valueOrNull?.currencySymbol ?? '€';

    if (_loading) {
      return const Scaffold(
        body: AppLoader(),
      );
    }

    const fieldGap = 14.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existingId == null ? t('new_item') : t('edit_item')),
      ),
      bottomNavigationBar: ConfirmCancelBar(
        onCancel: () => context.pop(),
        onConfirm: _saving ? () {} : _save,
        onDelete: _existingId == null ? null : _delete,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Container(
                  width: 120,
                  height: 120,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.cardElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: p.stroke),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    image: _resolvedPhoto == null
                        ? null
                        : DecorationImage(
                            image: FileImage(File(_resolvedPhoto!)),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: _resolvedPhoto == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo_rounded,
                                color: p.fabBorder),
                            const SizedBox(height: 6),
                            Text(t('photo'),
                                style: TextStyle(color: p.textMuted)),
                          ],
                        )
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.black54,
                            child: Text(
                              t('change_photo'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                return RawAutocomplete<String>(
                  textEditingController: _category,
                  focusNode: _categoryFocus,
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    if (inventoryCategories.isEmpty) {
                      return const Iterable<String>.empty();
                    }
                    if (q.isEmpty) return inventoryCategories;
                    return inventoryCategories
                        .where((n) => n.toLowerCase().contains(q));
                  },
                  onSelected: (v) {
                    _category
                      ..text = v
                      ..selection =
                          TextSelection.collapsed(offset: v.length);
                  },
                  fieldViewBuilder: (context, controller, focus, onSubmit) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focus,
                      onFieldSubmitted: (_) => onSubmit(),
                      textCapitalization: TextCapitalization.words,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: t('category'),
                        hintText: t('search_or_create'),
                        suffixIcon: Icon(
                          Icons.arrow_drop_down_rounded,
                          color: p.textSecondary,
                        ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    final opts = options.toList();
                    if (opts.isEmpty) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 8,
                        color: p.cardElevated,
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 180),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: opts.length,
                              itemBuilder: (_, i) {
                                final name = opts[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      color: p.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onTap: () => onSelected(name),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: fieldGap),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(labelText: t('title')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? t('required') : null,
            ),
            const SizedBox(height: fieldGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration: InputDecoration(
                      labelText: t('price'),
                      suffixIcon: Pressable(
                        onTap: () => pickAndSaveCurrency(context, ref),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            widthFactor: 1,
                            child: Text(
                              currency,
                              style: TextStyle(
                                color: p.neon,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    style: TextStyle(
                      color: p.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (n == null) return t('enter_price');
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    decoration: InputDecoration(labelText: t('amount')),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (n == null) return t('required');
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: fieldGap),
            TextFormField(
              controller: _unit,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: '${t('unit')} (${t('optional')})',
              ),
            ),
            const SizedBox(height: fieldGap),
            AppCard(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      t('quantity_alert'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      t('notify_below_level'),
                      style: TextStyle(fontSize: 12.5, color: p.textMuted),
                    ),
                    value: _alertEnabled,
                    onChanged: (v) => setState(() {
                      _alertEnabled = v;
                      // Activating starts at 1 unless a level is already set.
                      final current = double.tryParse(
                        _alertAmount.text.replaceAll(',', '.').trim(),
                      );
                      if (v && (current == null || current <= 0)) {
                        _alertAmount.text = '1';
                      }
                    }),
                    secondary: Icon(Icons.notifications_active_rounded,
                        color: p.neon),
                  ),
                  if (_alertEnabled)
                    // Rebuild only the field when the unit changes so the
                    // suffix always shows the item's current unit.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _unit,
                      builder: (context, unitValue, _) {
                        final unit = unitValue.text.trim();
                        return TextFormField(
                          controller: _alertAmount,
                          decoration: InputDecoration(
                            labelText: t('amount'),
                            suffixText: unit.isEmpty ? null : unit,
                            suffixStyle: TextStyle(
                              color: p.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          textInputAction: TextInputAction.done,
                        );
                      },
                    ),
                ],
              ),
            ),
            if (_existingId != null) ...[
              const SizedBox(height: fieldGap),
              AppCard(
                onTap: () => context.push('/inventory/qr/$_existingId'),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: p.fabBorder.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: p.fabBorder,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('qr_label'),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: p.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t('print_label'),
                            style: TextStyle(
                              fontSize: 13,
                              color: p.textMuted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: p.textMuted,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
