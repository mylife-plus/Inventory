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
