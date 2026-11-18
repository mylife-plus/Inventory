import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/l10n/app_prefs.dart';
import 'package:inventory_app/core/theme/app_theme.dart';
import 'package:inventory_app/core/utils/date_bounds.dart';
import 'package:inventory_app/shared/widgets/app_sheets.dart';
import 'package:inventory_app/shared/widgets/app_widgets.dart';

/// Opens the From or To calendar bounded by [bounds] (first → last record
/// day, To ≥ From + 1 day) and returns the new pair, or null on cancel.
Future<({DateTime? from, DateTime? to})?> pickBoundedRangeDay(
  BuildContext context, {
  required DateBounds bounds,
  required bool isFrom,
  required DateTime? from,
  required DateTime? to,
}) async {
  if (isFrom) {
    final r = bounds.fromRange();
    final d = await pickFilterDate(
      context,
      from ?? bounds.first,
      firstDate: r.min,
      lastDate: r.max,
    );
    if (d == null) return null;
    final f = dayOf(d);
    return (from: f, to: bounds.fixTo(f, to));
  }
  final r = bounds.toRange(from);
  final d = await pickFilterDate(
    context,
    to ?? bounds.last,
    firstDate: r.min,
    lastDate: r.max,
  );
  if (d == null) return null;
  return (from: from, to: dayOf(d));
}

/// From / To fields (same look as every filter) with bounded calendars.
class BoundedDateRangeFields extends ConsumerWidget {
  const BoundedDateRangeFields({
    super.key,
    required this.bounds,
    required this.from,
    required this.to,
    required this.onChanged,
    this.enabled = true,
  });

  final DateBounds bounds;
  final DateTime? from;
  final DateTime? to;
  final void Function(DateTime? from, DateTime? to) onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    Future<void> pick(bool isFrom) async {
      if (!enabled) return;
      final r = await pickBoundedRangeDay(
        context,
        bounds: bounds,
        isFrom: isFrom,
        from: from,
        to: to,
      );
      if (r != null) onChanged(r.from, r.to);
    }

    return Row(
      children: [
        Expanded(
          child: AppFilterDateField(
            key: const ValueKey('range_from'),
            placeholder: t('from_date'),
            value: from,
            onTap: () => pick(true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppFilterDateField(
            key: const ValueKey('range_to'),
            placeholder: t('to_date'),
            value: to,
            onTap: () => pick(false),
          ),
        ),
      ],
    );
  }
}

/// Export pop-up: From / To (default: everything = first → last record),
/// Export button with a loading wheel while the file is written. Returns
/// the written file (caller shares it) or null when cancelled / failed.
Future<File?> showCsvExportSheet({
  required BuildContext context,
  required String title,
  required DateBounds bounds,
  required Future<File> Function(DateTime from, DateTime to) build,
}) {
  return showAppSheet<File>(
    context: context,
    builder: (_) => _CsvExportSheet(title: title, bounds: bounds, build: build),
  );
}

class _CsvExportSheet extends ConsumerStatefulWidget {
  const _CsvExportSheet({
    required this.title,
    required this.bounds,
    required this.build,
  });

  final String title;
  final DateBounds bounds;
  final Future<File> Function(DateTime from, DateTime to) build;

  @override
  ConsumerState<_CsvExportSheet> createState() => _CsvExportSheetState();
}

class _CsvExportSheetState extends ConsumerState<_CsvExportSheet> {
  late DateTime _from = widget.bounds.first;
  late DateTime _to = widget.bounds.last;
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    final t = ref.read(tProvider);
    try {
      // Keep the wheel visible for a moment even for tiny files.
      final results = await Future.wait<Object?>([
        widget.build(_from, _to),
        Future<void>.delayed(const Duration(milliseconds: 450)),
      ]);
      if (!mounted) return;
      Navigator.of(context).pop(results.first as File);
    } catch (e) {
      debugPrint('CSV export failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      showTopNotice(context, t('export_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final t = ref.watch(tProvider);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSheetHeader(title: widget.title),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: BoundedDateRangeFields(
                bounds: widget.bounds,
                from: _from,
                to: _to,
                enabled: !_busy,
                onChanged: (f, to) => setState(() {
                  _from = f ?? widget.bounds.first;
                  _to = to ?? widget.bounds.last;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Text(
                widget.bounds.coversAll(_from, _to)
                    ? t('export_range_all')
                    : t('export_range_hint'),
                key: const ValueKey('export_range_note'),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _busy
                  ? Container(
                      key: const ValueKey('export_loading'),
                      width: double.infinity,
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.fab,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : AccentButton(
                      key: const ValueKey('export_csv_button'),
                      label: t('export_csv'),
                      icon: Icons.ios_share_rounded,
                      onPressed: _export,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
