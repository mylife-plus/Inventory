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

  /// Name in the app language, English as the fallback.
  String nameFor(String locale) => _kCurrencyNames[locale]?[code] ?? name;
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

/// Currency names in the app languages (English is [AppCurrency.name]).
const _kCurrencyNames = <String, Map<String, String>>{
  'de': {
    'EUR': 'Euro',
    'USD': 'US-Dollar',
    'GBP': 'Britisches Pfund',
    'CHF': 'Schweizer Franken',
    'CAD': 'Kanadischer Dollar',
    'AUD': 'Australischer Dollar',
    'JPY': 'Japanischer Yen',
    'CNY': 'Chinesischer Yuan',
    'SEK': 'Schwedische Krone',
    'NOK': 'Norwegische Krone',
    'DKK': 'Dänische Krone',
    'PLN': 'Polnischer Złoty',
    'CZK': 'Tschechische Krone',
    'RON': 'Rumänischer Leu',
    'HUF': 'Ungarischer Forint',
    'TRY': 'Türkische Lira',
    'BRL': 'Brasilianischer Real',
    'INR': 'Indische Rupie',
    'SAR': 'Saudi-Riyal',
    'AED': 'VAE-Dirham',
    'MAD': 'Marokkanischer Dirham',
    'DZD': 'Algerischer Dinar',
    'EGP': 'Ägyptisches Pfund',
    'PKR': 'Pakistanische Rupie',
    'TND': 'Tunesischer Dinar',
  },
  'es': {
    'EUR': 'Euro',
    'USD': 'Dólar estadounidense',
    'GBP': 'Libra esterlina',
    'CHF': 'Franco suizo',
    'CAD': 'Dólar canadiense',
    'AUD': 'Dólar australiano',
    'JPY': 'Yen japonés',
    'CNY': 'Yuan chino',
    'SEK': 'Corona sueca',
    'NOK': 'Corona noruega',
    'DKK': 'Corona danesa',
    'PLN': 'Esloti polaco',
    'CZK': 'Corona checa',
    'RON': 'Leu rumano',
    'HUF': 'Forinto húngaro',
    'TRY': 'Lira turca',
    'BRL': 'Real brasileño',
    'INR': 'Rupia india',
    'SAR': 'Riyal saudí',
    'AED': 'Dírham de los EAU',
    'MAD': 'Dírham marroquí',
    'DZD': 'Dinar argelino',
    'EGP': 'Libra egipcia',
    'PKR': 'Rupia pakistaní',
    'TND': 'Dinar tunecino',
  },
  'fr': {
    'EUR': 'Euro',
    'USD': 'Dollar américain',
    'GBP': 'Livre sterling',
    'CHF': 'Franc suisse',
    'CAD': 'Dollar canadien',
    'AUD': 'Dollar australien',
    'JPY': 'Yen japonais',
    'CNY': 'Yuan chinois',
    'SEK': 'Couronne suédoise',
    'NOK': 'Couronne norvégienne',
    'DKK': 'Couronne danoise',
    'PLN': 'Zloty polonais',
    'CZK': 'Couronne tchèque',
    'RON': 'Leu roumain',
    'HUF': 'Forint hongrois',
    'TRY': 'Livre turque',
    'BRL': 'Réal brésilien',
    'INR': 'Roupie indienne',
    'SAR': 'Riyal saoudien',
    'AED': 'Dirham des EAU',
    'MAD': 'Dirham marocain',
    'DZD': 'Dinar algérien',
    'EGP': 'Livre égyptienne',
    'PKR': 'Roupie pakistanaise',
    'TND': 'Dinar tunisien',
  },
  'pt': {
    'EUR': 'Euro',
    'USD': 'Dólar americano',
    'GBP': 'Libra esterlina',
    'CHF': 'Franco suíço',
    'CAD': 'Dólar canadiano',
    'AUD': 'Dólar australiano',
    'JPY': 'Iene japonês',
    'CNY': 'Yuan chinês',
    'SEK': 'Coroa sueca',
    'NOK': 'Coroa norueguesa',
    'DKK': 'Coroa dinamarquesa',
    'PLN': 'Zlóti polaco',
    'CZK': 'Coroa checa',
    'RON': 'Leu romeno',
    'HUF': 'Florim húngaro',
    'TRY': 'Lira turca',
    'BRL': 'Real brasileiro',
    'INR': 'Rupia indiana',
    'SAR': 'Rial saudita',
    'AED': 'Dirham dos EAU',
    'MAD': 'Dirham marroquino',
    'DZD': 'Dinar argelino',
    'EGP': 'Libra egípcia',
    'PKR': 'Rupia paquistanesa',
    'TND': 'Dinar tunisino',
  },
};
