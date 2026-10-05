import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/data/repositories/repositories.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';
import 'package:inventory_app/shared/widgets/currency_picker.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _company;
  late final TextEditingController _street;
  late final TextEditingController _zip;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _vat;
  late final TextEditingController _currency;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _company = TextEditingController();
    _street = TextEditingController();
    _zip = TextEditingController();
    _city = TextEditingController();
    _phone = TextEditingController();
    _vat = TextEditingController(text: '19');
    _currency = TextEditingController(text: '€');
  }

  @override
  void dispose() {
    _company.dispose();
    _street.dispose();
    _zip.dispose();
    _city.dispose();
    _phone.dispose();
    _vat.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final settings = ShopSettings(
        companyName: _company.text.trim(),
        street: _street.text.trim(),
        zip: _zip.text.trim(),
        city: _city.text.trim(),
        phone: _phone.text.trim(),
        vatRate: double.tryParse(_vat.text.replaceAll(',', '.')) ?? 0,
        currencySymbol:
            _currency.text.trim().isEmpty ? '€' : _currency.text.trim(),
        setupComplete: true,
      );
      await ref.read(shopSettingsProvider.notifier).save(settings);
      if (!mounted) return;
      context.go('/inventory');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(tProvider)('backup_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              Text(
                ref.watch(tProvider)('app_name'),
                style: TextStyle(
                  color: p.fabBorder,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set up your shop details for receipts',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: p.textSecondary,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 28),
              SectionHeader(title: ref.watch(tProvider)('receipt_details')),
              const SizedBox(height: 12),
              TextFormField(
                controller: _company,
                decoration:
                    const InputDecoration(labelText: 'Company / shop name'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? ref.watch(tProvider)('required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _street,
                decoration: const InputDecoration(labelText: 'Street'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _zip,
                      decoration: const InputDecoration(labelText: 'ZIP'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _vat,
                      decoration:
                          const InputDecoration(labelText: 'VAT tax rate %'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await showCurrencyPicker(
                          context,
                          current: _currency.text,
                        );
                        if (picked != null && picked.isNotEmpty) {
                          setState(() => _currency.text = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _currency.text,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(Icons.expand_more_rounded,
                                color: p.textMuted),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              AccentButton(
                label: _saving
                    ? '…'
                    : ref.watch(tProvider)('continue_btn'),
                onPressed: _saving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
