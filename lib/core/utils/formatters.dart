import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const uuid = Uuid();

String newId() => uuid.v4();

class MoneyFormatter {
  MoneyFormatter({
    required this.symbol,
    String decimalSeparator = ',',
  }) : decimalSeparator =
            (decimalSeparator == '.' || decimalSeparator == ',')
                ? decimalSeparator
                : ',';

  final String symbol;
  final String decimalSeparator;

  /// Group digits with `.` (EU) or `,` (US) — never spaces.
  String _groupThousands(String digits) {
    final negative = digits.startsWith('-');
    final raw = negative ? digits.substring(1) : digits;
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final fromEnd = raw.length - i;
      if (i > 0 && fromEnd % 3 == 0) {
        buf.write(decimalSeparator == ',' ? '.' : ',');
      }
      buf.write(raw[i]);
    }
    return negative ? '-$buf' : buf.toString();
  }

  /// Amount only (no currency symbol), e.g. `12,50` or `1.476,00`.
  String formatAmount(num value, {int decimals = 2}) {
    final fixed = value.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final whole = _groupThousands(parts[0]);
    if (decimals == 0) return whole;
    return '$whole$decimalSeparator${parts[1]}';
  }

  String format(num value, {int decimals = 2}) {
    final amount = formatAmount(value, decimals: decimals);
    if (symbol.trim().isEmpty) return amount;
    return '$amount $symbol';
  }
}

String formatQty(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Prices are VAT-inclusive (receipt shows “VAT x% included”).
class VatBreakdown {
  const VatBreakdown({
    required this.gross,
    required this.net,
    required this.vat,
    required this.rate,
  });

  final double gross;
  final double net;
  final double vat;
  final double rate;

  factory VatBreakdown.inclusive({
    required double gross,
    required double rate,
  }) {
    if (rate <= 0 || gross <= 0) {
      return VatBreakdown(gross: gross, net: gross, vat: 0, rate: rate);
    }
    final vat = gross * rate / (100 + rate);
    return VatBreakdown(
      gross: gross,
      net: gross - vat,
      vat: vat,
      rate: rate,
    );
  }
}


/// Day + short month + year in the app language, e.g. "08. Oct. 2026" /
/// "08. Okt. 2026". The locale's own dot after the month is stripped first so
/// it is never doubled.
String formatDateShort(DateTime d, String locale) {
  final local = d.toLocal();
  final m = DateFormat.MMM(locale).format(local).replaceAll('.', '');
  return '${local.day.toString().padLeft(2, '0')}. $m. ${local.year}';
}

/// [formatDateShort] plus the time in the locale's clock style,
/// e.g. "08. Oct. 2026, 4:07 PM" / "08. Okt. 2026, 16:07".
String formatDateTimeShort(DateTime d, String locale) =>
    '${formatDateShort(d, locale)}, ${DateFormat.jm(locale).format(d.toLocal())}';
