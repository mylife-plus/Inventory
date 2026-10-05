class AppCurrency {
  const AppCurrency({
    required this.code,
    required this.name,
    required this.symbol,
  });

  final String code;
  final String name;
  final String symbol;

  /// What we store in shop settings (shown next to amounts).
  String get display => symbol.isNotEmpty ? symbol : code;
}

/// Major currencies first — TND / regional at the end (not on top).
const kCurrencies = <AppCurrency>[
  AppCurrency(code: 'EUR', name: 'Euro', symbol: '€'),
  AppCurrency(code: 'USD', name: 'US Dollar', symbol: '\$'),
  AppCurrency(code: 'GBP', name: 'British Pound', symbol: '£'),
  AppCurrency(code: 'CHF', name: 'Swiss Franc', symbol: 'CHF'),
  AppCurrency(code: 'CAD', name: 'Canadian Dollar', symbol: 'CA\$'),
  AppCurrency(code: 'AUD', name: 'Australian Dollar', symbol: 'A\$'),
  AppCurrency(code: 'JPY', name: 'Japanese Yen', symbol: '¥'),
  AppCurrency(code: 'CNY', name: 'Chinese Yuan', symbol: 'CN¥'),
  AppCurrency(code: 'SEK', name: 'Swedish Krona', symbol: 'SEK'),
  AppCurrency(code: 'NOK', name: 'Norwegian Krone', symbol: 'NOK'),
  AppCurrency(code: 'DKK', name: 'Danish Krone', symbol: 'DKK'),
  AppCurrency(code: 'PLN', name: 'Polish Zloty', symbol: 'zł'),
  AppCurrency(code: 'CZK', name: 'Czech Koruna', symbol: 'Kč'),
  AppCurrency(code: 'RON', name: 'Romanian Leu', symbol: 'RON'),
  AppCurrency(code: 'HUF', name: 'Hungarian Forint', symbol: 'Ft'),
  AppCurrency(code: 'TRY', name: 'Turkish Lira', symbol: '₺'),
  AppCurrency(code: 'BRL', name: 'Brazilian Real', symbol: 'R\$'),
  AppCurrency(code: 'INR', name: 'Indian Rupee', symbol: '₹'),
  AppCurrency(code: 'SAR', name: 'Saudi Riyal', symbol: 'SAR'),
  AppCurrency(code: 'AED', name: 'UAE Dirham', symbol: 'AED'),
  AppCurrency(code: 'MAD', name: 'Moroccan Dirham', symbol: 'MAD'),
  AppCurrency(code: 'DZD', name: 'Algerian Dinar', symbol: 'DZD'),
  AppCurrency(code: 'EGP', name: 'Egyptian Pound', symbol: 'EGP'),
  AppCurrency(code: 'PKR', name: 'Pakistani Rupee', symbol: 'PKR'),
  AppCurrency(code: 'TND', name: 'Tunisian Dinar', symbol: 'TND'),
];

AppCurrency? findCurrency(String codeOrSymbol) {
  final q = codeOrSymbol.trim().toLowerCase();
  for (final c in kCurrencies) {
    if (c.code.toLowerCase() == q ||
        c.symbol.toLowerCase() == q ||
        c.display.toLowerCase() == q) {
      return c;
    }
  }
  return null;
}
