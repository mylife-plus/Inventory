import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/media/local_image_store.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/features/customers/presentation/customer_list_tools.dart';
import 'package:inventory_app/shared/widgets/app_loader.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:inventory_app/shared/widgets/app_icon.dart';
import 'package:inventory_app/shared/widgets/local_photo.dart';
import 'package:inventory_app/core/utils/app_haptics.dart';

enum _SocialKind {
  whatsapp,
  facebook,
  instagram,
  linkedin,
  telegram,
}

extension on _SocialKind {
  String get l10nKey => switch (this) {
        _SocialKind.whatsapp => 'whatsapp',
        _SocialKind.facebook => 'facebook',
        _SocialKind.instagram => 'instagram',
        _SocialKind.linkedin => 'linkedin',
        _SocialKind.telegram => 'telegram',
      };

  String get asset => switch (this) {
        _SocialKind.whatsapp => AppAssets.whatsapp,
        _SocialKind.facebook => AppAssets.facebook,
        _SocialKind.instagram => AppAssets.instagram,
        _SocialKind.linkedin => AppAssets.linkedin,
        _SocialKind.telegram => AppAssets.telegram,
      };

  TextInputType get keyboardType => switch (this) {
        _SocialKind.whatsapp => TextInputType.phone,
        _ => TextInputType.url,
      };
}

Widget _fieldIcon(String asset, {double size = 22}) {
  return Padding(
    padding: const EdgeInsets.all(10),
    child: AppIcon(asset, size: size),
  );
}

/// Material phone icon — cleaner than the brand SVG in form fields.
Widget _phoneFieldIcon({double size = 22}) {
  return Padding(
    padding: const EdgeInsets.all(10),
    child: Icon(Icons.phone_rounded, size: size, color: const Color(0xFF34C759)),
  );
}

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  final _search = TextEditingController();
  bool _showSearch = false;
  SortState<CustomerSortKey> _sort = kDefaultCustomerSort;
  CustomerFilter _filter = const CustomerFilter();
  Map<String, CustomerStats> _stats = {};
  String _statsKey = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadStats(List<Customer> list) async {
    final repo = ref.read(customerRepositoryProvider);
    final next = <String, CustomerStats>{};
    for (final c in list) {
      next[c.id] = await repo.stats(c.id);
    }
    if (!mounted) return;
    setState(() => _stats = next);
  }

  void _dismissSearch() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_showSearch) return;
    // Defer hide so a concurrent list-card tap still receives onTap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSearch) return;
      setState(() => _showSearch = false);
    });
  }

  Future<void> _showSortSheet() async {
    final picked = await showSortSheet<CustomerSortKey>(
      context: context,
      options: customerSortOptions(ref.read(tProvider)),
      current: _sort,
      defaultState: kDefaultCustomerSort,
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _showFilterSheet() async {
    final picked = await showCustomerFilterSheet(
      context,
      t: ref.read(tProvider),
      current: _filter,
      customFieldLabels: customFieldLabels(
        ref.read(customersProvider).valueOrNull ?? const [],
      ),
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final t = ref.watch(tProvider);
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    // Purchases / spend change after every sale or receipt edit.
    ref.listen(salesProvider, (_, _) {
      final list = ref.read(customersProvider).valueOrNull;
      if (list != null) _loadStats(list);
    });

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: _dismissSearch,
        child: Column(
          children: [
            ClientHeader(
              section: 1,
              title: t('customers'),
              titleAsset: AppAssets.customer,
              onSearch: () => setState(() => _showSearch = !_showSearch),
              onFilter: _showFilterSheet,
              onMenu: _showSortSheet,
              sortActive: _sort != kDefaultCustomerSort,
              filterActive: _filter.isActive,
              searchActive: _showSearch || _search.text.trim().isNotEmpty,
              trailing: Pressable(
                onTap: () => context.push('/customers/new'),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(
                    Icons.add_rounded,
                    size: 28,
                    color: AppPalette.of(context).textSecondary,
                  ),
                ),
              ),
            ),
            if (_showSearch)
              AppSearchField(
                controller: _search,
                hintText: t('search'),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                onChanged: (_) => setState(() {}),
                onDismiss: () {
                  if (mounted) setState(() => _showSearch = false);
                },
              ),
            Expanded(
              child: customers.when(
                loading: () => const AppLoader(),
                error: (e, _) => Center(child: Text('$e')),
                data: (list) {
                  // Keep stats warm for sort / filter / cards.
                  final key = list.map((c) => c.id).join(',');
                  if (key != _statsKey) {
                    _statsKey = key;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _loadStats(list);
                    });
                  }
                  final q = _search.text.trim().toLowerCase();
                  final filtered = sortCustomers(
                    list
                        .where((c) =>
                            _filter.matches(c, _stats[c.id]) &&
                            customerMatchesQuery(c, q))
                        .toList(),
                    _sort,
                    _stats,
                  );
                  if (filtered.isEmpty) {
                    return EmptyState(
                      icon: Icons.people_outline,
                      title: t('no_customers'),
                      subtitle: t('add_first_customer'),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => FadeSlide(
                      child: CustomerListCard(
                        name: filtered[i].displayName,
                        money: money,
                        stats: _stats[filtered[i].id],
                        photoPath: filtered[i].photoPath,
                        contacts: filtered[i].allContacts,
                        onTap: () =>
                            context.push('/customers/${filtered[i].id}'),
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

class CustomerEditorPage extends ConsumerStatefulWidget {
  const CustomerEditorPage({super.key, this.customerId});

  final String? customerId;

  @override
  ConsumerState<CustomerEditorPage> createState() => _CustomerEditorPageState();
}

class _CustomFieldEntry {
  _CustomFieldEntry({required this.label, String value = ''})
      : controller = TextEditingController(text: value);

  String label;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

class _CustomerEditorPageState extends ConsumerState<CustomerEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _whatsapp = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _linkedin = TextEditingController();
  final _telegram = TextEditingController();
  final _notes = TextEditingController();
  String? _id;
  DateTime? _createdAt;
  String? _photoPath;
  String? _resolvedPhoto;
  bool _loading = true;
  /// Socials the user chose to show (dropdown add).
  final Set<_SocialKind> _visibleSocials = {};
  /// Separate from socials — user-defined label/value pairs.
  final List<_CustomFieldEntry> _customFields = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.customerId == null) {
      setState(() => _loading = false);
      return;
    }
    final c =
        await ref.read(customerRepositoryProvider).get(widget.customerId!);
    if (c != null) {
      _id = c.id;
      _createdAt = c.createdAt;
      _name.text = c.name;
      _lastName.text = c.lastName ?? '';
      _phone.text = c.phone ?? '';
      _email.text = c.email ?? '';
      _whatsapp.text = c.whatsapp ?? '';
      _facebook.text = c.facebook ?? '';
      _instagram.text = c.instagram ?? '';
      _linkedin.text = c.linkedin ?? '';
      _telegram.text = c.telegram ?? '';
      _notes.text = c.notes ?? '';
      _photoPath = c.photoPath;
      _resolvedPhoto = await LocalImageStore.resolve(c.photoPath);
      if (_whatsapp.text.isNotEmpty) {
        _visibleSocials.add(_SocialKind.whatsapp);
      }
      if (_facebook.text.isNotEmpty) {
        _visibleSocials.add(_SocialKind.facebook);
      }
      if (_instagram.text.isNotEmpty) {
        _visibleSocials.add(_SocialKind.instagram);
      }
      if (_linkedin.text.isNotEmpty) {
        _visibleSocials.add(_SocialKind.linkedin);
      }
      if (_telegram.text.isNotEmpty) {
        _visibleSocials.add(_SocialKind.telegram);
      }
      for (final f in c.customFields) {
        _customFields.add(_CustomFieldEntry(label: f.label, value: f.value));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _whatsapp.dispose();
    _facebook.dispose();
    _instagram.dispose();
    _linkedin.dispose();
    _telegram.dispose();
    _notes.dispose();
    for (final f in _customFields) {
      f.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _pickOrClearPhoto() async {
    final t = ref.read(tProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final p = AppPalette.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.photo_camera_rounded, color: p.fabBorder),
                title: Text(t('take_photo')),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: Icon(Icons.photo_library_rounded, color: p.fabBorder),
                title: Text(t('choose_gallery')),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (_photoPath != null)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: p.danger),
                  title: Text(t('delete')),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (action == null) return;

    if (action == 'remove') {
      await LocalImageStore.delete(_photoPath);
      if (!mounted) return;
      setState(() {
        _photoPath = null;
        _resolvedPhoto = null;
      });
      return;
    }

    final source =
        action == 'camera' ? ImageSource.camera : ImageSource.gallery;
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (file == null) return;

    final id = _id ?? newId();
    _id ??= id;
    final relative = await LocalImageStore.savePicked(file, itemId: id);
    final resolved = await LocalImageStore.resolve(relative);
    if (!mounted) return;
    setState(() {
      _photoPath = relative;
      _resolvedPhoto = resolved;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final custom = <CustomerCustomField>[
      for (final f in _customFields)
        if (f.label.trim().isNotEmpty)
          CustomerCustomField(
            label: f.label.trim(),
            value: f.controller.text.trim(),
          ),
    ];
    final customer = Customer(
      id: widget.customerId ?? _id ?? newId(),
      name: _name.text.trim(),
      lastName: _opt(_lastName),
      phone: _opt(_phone),
      email: _opt(_email),
      whatsapp: _opt(_whatsapp),
      facebook: _opt(_facebook),
      instagram: _opt(_instagram),
      linkedin: _opt(_linkedin),
      telegram: _opt(_telegram),
      notes: _opt(_notes),
      customFields: custom,
      photoPath: _photoPath,
      createdAt: _createdAt ?? DateTime.now(),
    );
    await ref.read(customersProvider.notifier).upsert(customer);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final id = widget.customerId ?? _id;
    if (id == null) return;
    final t = ref.read(tProvider);
    final ok = await showAppConfirmDialog(
      context: context,
      title: t('delete_customer'),
      message: t('cannot_undo'),
      cancelLabel: t('cancel'),
      confirmLabel: t('delete'),
      destructive: true,
    );
    if (!ok) return;
    await LocalImageStore.delete(_photoPath);
    await ref.read(customersProvider.notifier).delete(id);
    if (!mounted) return;
    context.go('/customers');
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    if (_loading) {
      return const Scaffold(body: AppLoader());
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.customerId == null ? t('new_customer') : t('edit_customer'),
        ),
      ),
      bottomNavigationBar: ConfirmCancelBar(
        onCancel: () => context.pop(),
        onConfirm: _save,
        onDelete: widget.customerId == null ? null : _delete,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickOrClearPhoto,
                child: Container(
                  width: 128,
                  height: 128,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: p.cardElevated,
                    borderRadius: BorderRadius.circular(22),
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
                            Text(
                              t('photo'),
                              style: TextStyle(color: p.textMuted),
                            ),
                          ],
                        )
                      : Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            color: Colors.black54,
                            child: Text(
                              t('edit'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
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
            const SizedBox(height: 22),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t('first_name'),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? t('required') : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: t('last_name'),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              decoration: InputDecoration(
                labelText: t('phone'),
                prefixIcon: _phoneFieldIcon(),
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              decoration: InputDecoration(
                labelText: t('email'),
                prefixIcon: _fieldIcon(AppAssets.email),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
            ),
            const SizedBox(height: 14),
            ..._visibleSocials.map((kind) {
              final ctrl = switch (kind) {
                _SocialKind.whatsapp => _whatsapp,
                _SocialKind.facebook => _facebook,
                _SocialKind.instagram => _instagram,
                _SocialKind.linkedin => _linkedin,
                _SocialKind.telegram => _telegram,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: TextFormField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: t(kind.l10nKey),
                    hintText: kind == _SocialKind.whatsapp
                        ? t('whatsapp_hint')
                        : t('social_hint'),
                    prefixIcon: _fieldIcon(kind.asset),
                    suffixIcon: IconButton(
                      tooltip: t('delete'),
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        ctrl.clear();
                        _visibleSocials.remove(kind);
                      }),
                    ),
                  ),
                  keyboardType: kind.keyboardType,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              );
            }),
            if (_visibleSocials.length < _SocialKind.values.length) ...[
              Builder(
                builder: (btnCtx) {
                  return TextFormField(
                    readOnly: true,
                    canRequestFocus: false,
                    enableInteractiveSelection: false,
                    onTap: () => _pickSocial(btnCtx, t, p),
                    decoration: InputDecoration(
                      hintText: t('add_social'),
                      suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
            ],
            for (final entry in List<_CustomFieldEntry>.from(_customFields)) ...[
              TextFormField(
                controller: entry.controller,
                decoration: InputDecoration(
                  labelText: entry.label,
                  // Label always on top (no icon), value typed inside.
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: t('field_value'),
                  suffixIcon: IconButton(
                    tooltip: t('delete'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      setState(() => _customFields.remove(entry));
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => entry.dispose());
                    },
                  ),
                ),
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 14),
            ],
            // Same field style / height as "Add social" above.
            TextFormField(
              readOnly: true,
              canRequestFocus: false,
              enableInteractiveSelection: false,
              onTap: () => _showAddCustomFieldSheet(context, t, p),
              decoration: InputDecoration(
                hintText: t('add_field'),
                suffixIcon: const Icon(Icons.add_rounded, size: 26),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notes,
              decoration: InputDecoration(
                labelText: t('notes'),
                hintText: t('notes_hint'),
                prefixIcon: _fieldIcon(AppAssets.notes),
              ),
              minLines: 1,
              maxLines: null,
              textAlignVertical: TextAlignVertical.center,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickSocial(
    BuildContext btnCtx,
    String Function(String) t,
    AppPalette p,
  ) async {
    final remaining =
        _SocialKind.values.where((k) => !_visibleSocials.contains(k)).toList();
    if (remaining.isEmpty) return;

    final box = btnCtx.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(btnCtx).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final width = box.size.width;
    final topLeft = box.localToGlobal(Offset(0, box.size.height), ancestor: overlay);
    final bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    final picked = await showMenu<_SocialKind>(
      context: btnCtx,
      position: position,
      color: p.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.stroke),
      ),
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      items: [
        for (final kind in remaining)
          PopupMenuItem(
            value: kind,
            child: Row(
              children: [
                AppIcon(kind.asset, size: 22),
                const SizedBox(width: 12),
                Text(
                  t(kind.l10nKey),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _visibleSocials.add(picked));
  }

  Future<void> _showAddCustomFieldSheet(
    BuildContext context,
    String Function(String) t,
    AppPalette p,
  ) async {
    final label = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.cardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _AddCustomFieldSheetBody(t: t, palette: p),
    );
    if (label == null || label.isEmpty || !mounted) return;
    setState(() => _customFields.add(_CustomFieldEntry(label: label)));
  }
}

class _AddCustomFieldSheetBody extends StatefulWidget {
  const _AddCustomFieldSheetBody({required this.t, required this.palette});

  final String Function(String) t;
  final AppPalette palette;

  @override
  State<_AddCustomFieldSheetBody> createState() =>
      _AddCustomFieldSheetBodyState();
}

class _AddCustomFieldSheetBodyState extends State<_AddCustomFieldSheetBody> {
  late final TextEditingController _labelCtrl = TextEditingController();

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _labelCtrl.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final t = widget.t;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: SingleChildScrollView(
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
              t('add_field'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: p.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _labelCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: t('field_name'),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: Text(t('add_field')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptValueSheet extends StatefulWidget {
  const _PromptValueSheet({
    required this.title,
    required this.label,
    required this.keyboardType,
    required this.confirmLabel,
    required this.handleColor,
    required this.titleColor,
  });

  final String title;
  final String label;
  final TextInputType keyboardType;
  final String confirmLabel;
  final Color handleColor;
  final Color titleColor;

  @override
  State<_PromptValueSheet> createState() => _PromptValueSheetState();
}

class _PromptValueSheetState extends State<_PromptValueSheet> {
  late final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _ctrl.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: widget.handleColor,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: widget.titleColor,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: widget.keyboardType,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: widget.label),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              child: Text(widget.confirmLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerDetailPage extends ConsumerStatefulWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  bool _showSearch = false;
  final _search = TextEditingController();
  SortState<_PurchaseSortKey> _sort = _kDefaultPurchaseSort;
  DateTime? _from;
  DateTime? _to;
  Customer? _customer;
  bool _loadingCustomer = true;

  @override
  void initState() {
    super.initState();
    _reloadCustomer();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reloadCustomer() async {
    final c =
        await ref.read(customerRepositoryProvider).get(widget.customerId);
    if (!mounted) return;
    setState(() {
      _customer = c;
      _loadingCustomer = false;
    });
  }

  Future<void> _launchUri(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launch(String? value, {required String scheme}) async {
    if (value == null || value.isEmpty) return;
    final uri = Uri.parse('$scheme${Uri.encodeComponent(value)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String? _socialUrl(String? raw, {required String host, required String pathPrefix}) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    final handle = v.replaceFirst(RegExp(r'^@'), '');
    return 'https://$host$pathPrefix$handle';
  }

  List<_SocialKind> _missingSocials(Customer c) {
    return [
      if (c.whatsapp?.trim().isEmpty != false) _SocialKind.whatsapp,
      if (c.facebook?.trim().isEmpty != false) _SocialKind.facebook,
      if (c.instagram?.trim().isEmpty != false) _SocialKind.instagram,
      if (c.linkedin?.trim().isEmpty != false) _SocialKind.linkedin,
      if (c.telegram?.trim().isEmpty != false) _SocialKind.telegram,
    ];
  }

  Future<void> _showAddOnProfile(Customer c) async {
    final t = ref.read(tProvider);
    final p = AppPalette.of(context);
    final missing = _missingSocials(c);
    final needPhone = c.phone?.trim().isEmpty != false;
    final needEmail = c.email?.trim().isEmpty != false;

    final choice = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: p.cardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      t('add_field'),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                ),
                if (needPhone)
                  ListTile(
                    leading: const Icon(
                      Icons.phone_rounded,
                      size: 26,
                      color: Color(0xFF34C759),
                    ),
                    title: Text(
                      t('phone'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'phone'),
                  ),
                if (needEmail)
                  ListTile(
                    leading: AppIcon(AppAssets.email, size: 26),
                    title: Text(
                      t('email'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'email'),
                  ),
                for (final kind in missing)
                  ListTile(
                    leading: AppIcon(kind.asset, size: 26),
                    title: Text(
                      t(kind.l10nKey),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, kind),
                  ),
                ListTile(
                  leading: Icon(Icons.add_rounded, color: p.textPrimary),
                  title: Text(
                    t('add_field'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'custom'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null || !mounted) return;

    if (choice == 'phone') {
      final v = await _promptValue(
        title: t('phone'),
        label: t('phone'),
        keyboardType: TextInputType.phone,
      );
      if (v == null || v.trim().isEmpty || !mounted) return;
      await ref.read(customersProvider.notifier).upsert(
            c.copyWith(phone: v.trim()),
          );
      await _reloadCustomer();
    } else if (choice == 'email') {
      final v = await _promptValue(
        title: t('email'),
        label: t('email'),
        keyboardType: TextInputType.emailAddress,
      );
      if (v == null || v.trim().isEmpty || !mounted) return;
      await ref.read(customersProvider.notifier).upsert(
            c.copyWith(email: v.trim()),
          );
      await _reloadCustomer();
    } else if (choice is _SocialKind) {
      await _addSocialValue(c, choice);
    } else if (choice == 'custom') {
      await _addCustomField(c);
    }
  }

  Future<String?> _promptValue({
    required String title,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final t = ref.read(tProvider);
    final p = AppPalette.of(context);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.cardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _PromptValueSheet(
        title: title,
        label: label,
        keyboardType: keyboardType,
        confirmLabel: t('add_field'),
        handleColor: p.stroke,
        titleColor: p.textPrimary,
      ),
    );
  }

  Future<void> _addSocialValue(Customer c, _SocialKind kind) async {
    final t = ref.read(tProvider);
    final value = await _promptValue(
      title: t(kind.l10nKey),
      label: kind == _SocialKind.whatsapp ? t('whatsapp_hint') : t('social_hint'),
      keyboardType: kind.keyboardType,
    );
    if (value == null || value.isEmpty || !mounted) return;

    final updated = switch (kind) {
      _SocialKind.whatsapp => c.copyWith(whatsapp: value),
      _SocialKind.facebook => c.copyWith(facebook: value),
      _SocialKind.instagram => c.copyWith(instagram: value),
      _SocialKind.linkedin => c.copyWith(linkedin: value),
      _SocialKind.telegram => c.copyWith(telegram: value),
    };
    await ref.read(customersProvider.notifier).upsert(updated);
    await _reloadCustomer();
  }

  Future<void> _addCustomField(Customer c) async {
    final t = ref.read(tProvider);
    final label = await _promptValue(
      title: t('add_field'),
      label: t('field_name'),
    );
    if (label == null || label.isEmpty || !mounted) return;
    final value = await _promptValue(
      title: label,
      label: t('field_value'),
    );
    if (value == null || !mounted) return;

    final fields = [
      ...c.customFields,
      CustomerCustomField(label: label, value: value),
    ];
    await ref
        .read(customersProvider.notifier)
        .upsert(c.copyWith(customFields: fields));
    await _reloadCustomer();
  }

  Future<void> _showSortSheet() async {
    final t = ref.read(tProvider);
    final picked = await showSortSheet<_PurchaseSortKey>(
      context: context,
      options: [
        SortOption(
          key: _PurchaseSortKey.recent,
          icon: Icons.schedule_rounded,
          label: t('sort_most_recent'),
          reversedLabel: t('sort_oldest'),
        ),
        SortOption(
          key: _PurchaseSortKey.amount,
          icon: Icons.payments_rounded,
          label: t('sort_highest_amount'),
          reversedLabel: t('sort_lowest_amount'),
        ),
      ],
      current: _sort,
      defaultState: _kDefaultPurchaseSort,
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

  @override
  Widget build(BuildContext context) {
    final customerId = widget.customerId;
    final t = ref.watch(tProvider);
    if (_loadingCustomer) {
      return const Scaffold(body: AppLoader());
    }
    final c = _customer;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.person_off_rounded,
          title: t('no_customers'),
          subtitle: t('add_first_customer'),
        ),
      );
    }

    final salesFuture =
        ref.read(saleRepositoryProvider).listForCustomer(customerId);
    final statsFuture =
        ref.read(customerRepositoryProvider).stats(customerId);
    final settings = ref.watch(shopSettingsProvider).valueOrNull;
    final money = MoneyFormatter(
      symbol: settings?.currencySymbol ?? '€',
      decimalSeparator: settings?.decimalSeparator ?? ',',
    );
    final p = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            icon: const AppIcon(AppAssets.edit, size: 26),
            onPressed: () async {
              await context.push('/customers/edit/$customerId');
              await _reloadCustomer();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 128,
                height: 128,
                child: LocalPhoto(
                  path: c.photoPath,
                  fit: BoxFit.cover,
                  placeholderIcon: Icons.person_rounded,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            c.displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 22,
              color: p.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          FutureBuilder<CustomerStats>(
            future: statsFuture,
            builder: (context, s) {
              final stats = s.data;
              return Column(
                children: [
                  Text.rich(
                    textAlign: TextAlign.center,
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${stats?.purchaseCount ?? 0}',
                          style: TextStyle(
                            color: p.neon,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' ${t((stats?.purchaseCount ?? 0) == 1 ? 'purchase' : 'purchases')}',
                          style: TextStyle(
                            color: p.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money.format(stats?.totalSpent ?? 0),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.neon,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (c.phone != null && c.phone!.trim().isNotEmpty) ...[
            _ContactRow(
              icon: Icons.phone_rounded,
              iconColor: const Color(0xFF34C759),
              value: c.phone!,
              onTap: () => _launchUri('tel:${c.phone!.trim()}'),
            ),
            const SizedBox(height: 10),
          ],
          if (c.email != null && c.email!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.email,
              value: c.email!,
              onTap: () => _launchUri('mailto:${c.email!.trim()}'),
            ),
            const SizedBox(height: 10),
          ],
          if (c.notes != null && c.notes!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.notes,
              value: c.notes!,
              maxLines: 8,
            ),
            const SizedBox(height: 10),
          ],
          if (c.whatsapp != null && c.whatsapp!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.whatsapp,
              value: c.whatsapp!,
              onTap: () => _launch(
                c.whatsapp!.replaceAll(RegExp(r'[^\d+]'), ''),
                scheme: 'https://wa.me/',
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (c.facebook != null && c.facebook!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.facebook,
              value: c.facebook!,
              onTap: () {
                final url = _socialUrl(
                  c.facebook,
                  host: 'facebook.com',
                  pathPrefix: '/',
                );
                if (url != null) _launchUri(url);
              },
            ),
            const SizedBox(height: 10),
          ],
          if (c.instagram != null && c.instagram!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.instagram,
              value: c.instagram!,
              onTap: () {
                final url = _socialUrl(
                  c.instagram,
                  host: 'instagram.com',
                  pathPrefix: '/',
                );
                if (url != null) _launchUri(url);
              },
            ),
            const SizedBox(height: 10),
          ],
          if (c.linkedin != null && c.linkedin!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.linkedin,
              value: c.linkedin!,
              onTap: () {
                final url = _socialUrl(
                  c.linkedin,
                  host: 'linkedin.com',
                  pathPrefix: '/in/',
                );
                if (url != null) _launchUri(url);
              },
            ),
            const SizedBox(height: 10),
          ],
          if (c.telegram != null && c.telegram!.trim().isNotEmpty) ...[
            _ContactRow(
              asset: AppAssets.telegram,
              value: c.telegram!,
              onTap: () {
                final url = _socialUrl(
                  c.telegram,
                  host: 't.me',
                  pathPrefix: '/',
                );
                if (url != null) _launchUri(url);
              },
            ),
            const SizedBox(height: 10),
          ],
          // Empty custom fields are not shown on the profile.
          for (final f in c.customFields)
            if (f.label.trim().isNotEmpty && f.value.trim().isNotEmpty) ...[
              _CustomFieldRow(label: f.label, value: f.value),
              const SizedBox(height: 10),
            ],
          Pressable(
            onTap: () => _showAddOnProfile(c),
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: p.cardElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: p.stroke),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 26,
                color: p.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 22),
          ListActionIconsRow(
            onSort: _showSortSheet,
            onFilter: _showFilterSheet,
            onSearch: () => setState(() => _showSearch = !_showSearch),
            sortActive: _sort != _kDefaultPurchaseSort,
            filterActive: _from != null || _to != null,
            searchActive: _showSearch || _search.text.trim().isNotEmpty,
          ),
          if (_showSearch)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onTapOutside: (_) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _showSearch = false);
                  });
                },
                decoration: InputDecoration(
                  hintText: t('search_purchases'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (!_showSearch) return;
              FocusManager.instance.primaryFocus?.unfocus();
              setState(() => _showSearch = false);
            },
            child: _CustomerPurchases(
              salesFuture: salesFuture,
              money: money,
              sort: _sort,
              query: _search.text.trim().toLowerCase(),
              from: _from,
              to: _to,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.value,
    this.onTap,
    this.asset,
    this.icon,
    this.iconColor,
    this.maxLines = 1,
  });

  final String value;
  final VoidCallback? onTap;
  final String? asset;
  final IconData? icon;
  final Color? iconColor;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: value));
        AppHaptics.light();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ProviderScope.containerOf(context).read(tProvider)('copied'))),
          );
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: p.cardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.stroke),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, size: 26, color: iconColor ?? p.neon)
            else if (asset != null)
              AppIcon(asset!, size: 26)
            else
              Icon(Icons.link_rounded, size: 24, color: p.neon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: p.textPrimary,
                  height: maxLines > 1 ? 1.35 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom field on the profile: same input style as every text field in the
/// app — label on top (floating on the border), value inside, no icon.
class _CustomFieldRow extends StatelessWidget {
  const _CustomFieldRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return GestureDetector(
      onLongPress: () async {
        final text = value.trim().isEmpty ? label : value;
        await Clipboard.setData(ClipboardData(text: text));
        AppHaptics.light();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ProviderScope.containerOf(context).read(tProvider)('copied'))),
          );
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          contentPadding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        ),
        child: Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: p.textPrimary,
          ),
        ),
      ),
    );
  }
}

enum _PurchaseSortKey { recent, amount }

const _kDefaultPurchaseSort = SortState<_PurchaseSortKey>(_PurchaseSortKey.recent);

class _CustomerPurchases extends ConsumerWidget {
  const _CustomerPurchases({
    required this.salesFuture,
    required this.money,
    required this.sort,
    required this.query,
    this.from,
    this.to,
  });

  final Future<List<Sale>> salesFuture;
  final MoneyFormatter money;
  final SortState<_PurchaseSortKey> sort;
  final String query;
  final DateTime? from;
  final DateTime? to;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    final inventory = ref.watch(inventoryItemsProvider).valueOrNull ?? [];
    final photoById = {
      for (final i in inventory) i.id: i.photoPath,
    };

    return FutureBuilder<List<Sale>>(
      future: salesFuture,
      builder: (context, salesSnap) {
        final sales = [...(salesSnap.data ?? [])].where((s) {
          if (from != null) {
            final start = DateTime(from!.year, from!.month, from!.day);
            if (s.createdAt.isBefore(start)) return false;
          }
          if (to != null) {
            final end = DateTime(to!.year, to!.month, to!.day, 23, 59, 59);
            if (s.createdAt.isAfter(end)) return false;
          }
          return true;
        }).toList();
        if (salesSnap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: AppLoader(),
          );
        }
        if (sales.isEmpty) {
          return Text(
            t('no_purchases_yet'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          );
        }

        final oldestFirst =
            sort.key == _PurchaseSortKey.recent && sort.reversed;
        if (sort.key == _PurchaseSortKey.amount) {
          sales.sort((a, b) => sort.reversed
              ? a.total.compareTo(b.total)
              : b.total.compareTo(a.total));
        } else {
          sales.sort((a, b) => oldestFirst
              ? a.createdAt.compareTo(b.createdAt)
              : b.createdAt.compareTo(a.createdAt));
        }

        final entries = <({Sale sale, SaleLine line})>[];
        for (final sale in sales) {
          for (final line in sale.lines) {
            if (query.isNotEmpty &&
                !line.title.toLowerCase().contains(query)) {
              continue;
            }
            entries.add((sale: sale, line: line));
          }
        }
        if (entries.isEmpty) {
          return Text(
            t('no_matching_purchases'),
            textAlign: TextAlign.center,
            style: TextStyle(color: p.textSecondary),
          );
        }

        final byYear = <int, Map<int, List<({Sale sale, SaleLine line})>>>{};
        for (final e in entries) {
          final y = e.sale.createdAt.year;
          final m = e.sale.createdAt.month;
          byYear.putIfAbsent(y, () => {}).putIfAbsent(m, () => []).add(e);
        }
        final years = byYear.keys.toList()
          ..sort((a, b) => oldestFirst ? a.compareTo(b) : b.compareTo(a));
        final widgets = <Widget>[];
        for (final year in years) {
          final months = byYear[year]!;
          final yearTotal = months.values
              .expand((e) => e)
              .fold<double>(0, (s, e) => s + e.line.lineTotal);
          widgets.add(
            SectionHeader(
              title: '$year',
              trailing: Text(
                money.format(yearTotal),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: p.neon,
                ),
              ),
            ),
          );
          final monthKeys = months.keys.toList()
            ..sort((a, b) => oldestFirst ? a.compareTo(b) : b.compareTo(a));
          for (final month in monthKeys) {
            final list = months[month]!;
            final monthTotal =
                list.fold<double>(0, (s, e) => s + e.line.lineTotal);
            final monthName =
                DateFormat.MMMM(t.code).format(DateTime(year, month));
            widgets.add(
              SectionHeader(
                title: monthName,
                trailing: Text(
                  money.format(monthTotal),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: p.neon,
                  ),
                ),
              ),
            );
            // group lines by day for date labels
            final byDay = <String, List<({Sale sale, SaleLine line})>>{};
            for (final e in list) {
              final d = e.sale.createdAt;
              final key =
                  '${d.day.toString().padLeft(2, '0')}. ${DateFormat.MMM(t.code).format(d)} ${d.year}';
              byDay.putIfAbsent(key, () => []).add(e);
            }
            for (final dayEntry in byDay.entries) {
              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, top: 2),
                  child: Text(
                    dayEntry.key,
                    style: TextStyle(
                      color: p.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
              for (final e in dayEntry.value) {
                widgets.add(
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PurchaseLineCard(
                      sale: e.sale,
                      line: e.line,
                      photoPath: photoById[e.line.itemId],
                      money: money,
                    ),
                  ),
                );
              }
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widgets,
        );
      },
    );
  }
}

class _PurchaseLineCard extends ConsumerWidget {
  const _PurchaseLineCard({
    required this.sale,
    required this.line,
    required this.money,
    this.photoPath,
  });

  final Sale sale;
  final SaleLine line;
  final MoneyFormatter money;
  final String? photoPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = AppPalette.of(context);
    final badge = formatQty(line.quantity);
    final amountOnly = money.formatAmount(line.unitPrice).trim();

    return MediaListCard(
      onTap: () => context.push('/sell/receipt/${sale.id}'),
      thumb: CardThumb(
        path: photoPath ?? line.photoPath,
        badge: badge,
      ),
      child: Padding(
        // Same title-to-photo padding as the Inventory item card.
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    height: 1.2,
                    color: p.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                PriceUnitLine(
                  amount: amountOnly,
                  symbol: money.symbol,
                  unit: line.unit,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: CardTotalLine(value: money.format(line.lineTotal)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
