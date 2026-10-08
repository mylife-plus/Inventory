import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:inventory_app/core/l10n/s.dart';
import 'package:inventory_app/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    for (final code in S.supported.keys) {
      await initializeDateFormatting(code);
    }
  });

  final d = DateTime(2026, 10, 8, 16, 7, 35);

  test('receipt list dates are friendly and localized', () {
    expect(formatDateShort(d, 'en'), '08. Oct. 2026');
    expect(formatDateShort(d, 'de'), '08. Okt. 2026');
    expect(formatDateTimeShort(d, 'de'), '08. Okt. 2026, 16:07');
    expect(formatDateTimeShort(d, 'en'), contains('4:07'));
  });

  test('no doubled dots or raw ISO stamps in any language', () {
    for (final code in S.supported.keys) {
      final s = formatDateTimeShort(d, code);
      expect(s.contains('..'), isFalse, reason: '$code: $s');
      expect(s.contains('2026-10-08'), isFalse, reason: '$code: $s');
    }
  });

  test('turnover range chips are translated and short in every language', () {
    for (final code in S.supported.keys) {
      final t = S(code);
      for (final k in [
        'range_2w',
        'range_1m',
        'range_3m',
        'range_6m',
        'range_1y',
        'range_2y',
        'range_all',
      ]) {
        final v = t(k);
        expect(v, isNot(k), reason: '$code missing $k');
        expect(v.length, lessThanOrEqualTo(4), reason: '$code $k = $v');
      }
    }
  });

  test('every key added in this round exists in every language', () {
    const keys = [
      'walk_in_customer',
      'street',
      'house_nr',
      'zip',
      'city',
      'phone_number',
      'vat_rate',
      'receipt_info_hint',
      'change_photo',
      'save_failed',
      'enter_price',
      'unlock_reason',
      'enable_lock_reason',
      'backup_share_text',
      'csv_turnover_export',
      'csv_receipts_export',
      'csv_sale_details',
      'csv_all_time',
      'csv_to',
      'close',
    ];
    for (final code in S.supported.keys) {
      final t = S(code);
      for (final k in keys) {
        expect(t(k), isNot(k), reason: '$code missing $k');
      }
    }
  });

  test('time uses plain spaces so the PDF font can draw it', () {
    for (final code in S.supported.keys) {
      final s = formatDateTimeShort(d, code);
      expect(s.contains('\u202F'), isFalse, reason: code);
      expect(s.contains('\u00A0'), isFalse, reason: code);
    }
  });
}
