import 'dart:convert';

import 'package:equatable/equatable.dart';

class ShopSettings extends Equatable {
  const ShopSettings({
    required this.companyName,
    this.street = '',
    this.zip = '',
    this.city = '',
    this.phone = '',
    this.vatRate = 0,
    this.currencySymbol = '€',
    this.decimalSeparator = ',',
    this.setupComplete = false,
  });

  final String companyName;
  final String street;
  final String zip;
  final String city;
  final String phone;
  final double vatRate;
  final String currencySymbol;
  final String decimalSeparator;
  final bool setupComplete;

  /// True when shop header details are ready for receipts.
  /// All visible receipt fields must be filled on first setup.
  bool get hasReceiptDetails =>
      setupComplete &&
      companyName.trim().isNotEmpty &&
      street.trim().isNotEmpty &&
      zip.trim().isNotEmpty &&
      city.trim().isNotEmpty &&
      phone.trim().isNotEmpty;

  ShopSettings copyWith({
    String? companyName,
    String? street,
    String? zip,
    String? city,
    String? phone,
    double? vatRate,
    String? currencySymbol,
    String? decimalSeparator,
    bool? setupComplete,
  }) {
    return ShopSettings(
      companyName: companyName ?? this.companyName,
      street: street ?? this.street,
      zip: zip ?? this.zip,
      city: city ?? this.city,
      phone: phone ?? this.phone,
      vatRate: vatRate ?? this.vatRate,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      decimalSeparator: decimalSeparator ?? this.decimalSeparator,
      setupComplete: setupComplete ?? this.setupComplete,
    );
  }

  Map<String, Object?> toMap() => {
        'company_name': companyName,
        'cashier': '',
        'manager': '',
        'street': street,
        'zip': zip,
        'city': city,
        'phone': phone,
        'vat_rate': vatRate,
        'currency_symbol': currencySymbol,
        'decimal_separator': decimalSeparator,
        'setup_complete': setupComplete ? 1 : 0,
      };

  factory ShopSettings.fromMap(Map<String, Object?> map) {
    return ShopSettings(
      companyName: (map['company_name'] as String?) ?? '',
      street: (map['street'] as String?) ?? '',
      zip: (map['zip'] as String?) ?? '',
      city: (map['city'] as String?) ?? '',
      phone: (map['phone'] as String?) ?? '',
      vatRate: (map['vat_rate'] as num?)?.toDouble() ?? 0,
      currencySymbol: (map['currency_symbol'] as String?) ?? '€',
      decimalSeparator: (map['decimal_separator'] as String?) == '.' ? '.' : ',',
      setupComplete: (map['setup_complete'] as int?) == 1,
    );
  }

  @override
  List<Object?> get props => [
        companyName,
        street,
        zip,
        city,
        phone,
        vatRate,
        currencySymbol,
        decimalSeparator,
        setupComplete,
      ];
}

class Category extends Equatable {
  const Category({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toMap() => {'id': id, 'name': name};

  factory Category.fromMap(Map<String, Object?> map) => Category(
        id: map['id'] as String,
        name: map['name'] as String,
      );

  @override
  List<Object?> get props => [id, name];
}

class InventoryItem extends Equatable {
  const InventoryItem({
    required this.id,
    required this.title,
    required this.price,
    required this.amount,
    this.categoryId,
    this.categoryName,
    this.unit,
    this.photoPath,
    this.alertEnabled = false,
    this.alertAmount = 0,
    this.qrTitle,
    this.qrSubtitle,
    this.qrLink,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final double price;
  final double amount;
  final String? categoryId;
  final String? categoryName;
  final String? unit;
  final String? photoPath;
  final bool alertEnabled;
  final double alertAmount;
  final String? qrTitle;
  final String? qrSubtitle;
  final String? qrLink;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get displayUnit => (unit == null || unit!.isEmpty) ? '' : unit!;

  bool get isLowStock => alertEnabled && amount <= alertAmount;

  /// Thumb badge: stock quantity only (unit is shown on the price line).
  String get stockBadge {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String get defaultQrTitle => title;
  String get defaultQrSubtitle => price.toStringAsFixed(2);

  InventoryItem copyWith({
    String? id,
    String? title,
    double? price,
    double? amount,
    String? categoryId,
    String? categoryName,
    String? unit,
    String? photoPath,
    bool? alertEnabled,
    double? alertAmount,
    String? qrTitle,
    String? qrSubtitle,
    String? qrLink,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return InventoryItem(
      id: id ?? this.id,
      title: title ?? this.title,
      price: price ?? this.price,
      amount: amount ?? this.amount,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      unit: unit ?? this.unit,
      photoPath: photoPath ?? this.photoPath,
      alertEnabled: alertEnabled ?? this.alertEnabled,
      alertAmount: alertAmount ?? this.alertAmount,
      qrTitle: qrTitle ?? this.qrTitle,
      qrSubtitle: qrSubtitle ?? this.qrSubtitle,
      qrLink: qrLink ?? this.qrLink,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'price': price,
        'amount': amount,
        'category_id': categoryId,
        'unit': unit,
        'photo_path': photoPath,
        'alert_enabled': alertEnabled ? 1 : 0,
        'alert_amount': alertAmount,
        'qr_title': qrTitle,
        'qr_subtitle': qrSubtitle,
        'qr_link': qrLink,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<String, Object?> map) {
    return InventoryItem(
      id: map['id'] as String,
      title: map['title'] as String,
      price: (map['price'] as num).toDouble(),
      amount: (map['amount'] as num).toDouble(),
      categoryId: map['category_id'] as String?,
      categoryName: map['category_name'] as String?,
      unit: map['unit'] as String?,
      photoPath: map['photo_path'] as String?,
      alertEnabled: (map['alert_enabled'] as int?) == 1,
      alertAmount: (map['alert_amount'] as num?)?.toDouble() ?? 0,
      qrTitle: map['qr_title'] as String?,
      qrSubtitle: map['qr_subtitle'] as String?,
      qrLink: map['qr_link'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        price,
        amount,
        categoryId,
        categoryName,
        unit,
        photoPath,
        alertEnabled,
        alertAmount,
        qrTitle,
        qrSubtitle,
        qrLink,
        createdAt,
        updatedAt,
      ];
}

class Customer extends Equatable {
  const Customer({
    required this.id,
    required this.name,
    this.lastName,
    this.shortName,
    this.phone,
    this.email,
    this.whatsapp,
    this.facebook,
    this.instagram,
    this.linkedin,
    this.telegram,
    this.notes,
    this.customFields = const [],
    this.photoPath,
    required this.createdAt,
  });

  final String id;
  /// First / given name.
  final String name;
  final String? lastName;
  final String? shortName;
  final String? phone;
  final String? email;
  final String? whatsapp;
  final String? facebook;
  final String? instagram;
  final String? linkedin;
  final String? telegram;
  final String? notes;
  /// Extra user-defined label/value pairs (not socials).
  final List<CustomerCustomField> customFields;
  final String? photoPath;
  final DateTime createdAt;

  /// Prefer short name in lists when set; else "First Last".
  String get displayName {
    final s = shortName?.trim();
    if (s != null && s.isNotEmpty) return s;
    final last = lastName?.trim();
    if (last != null && last.isNotEmpty) {
      return '${name.trim()} $last'.trim();
    }
    return name;
  }

  /// Phone first, else first filled contact / social field.
  String? get contactLine => primaryContact?.display;

  /// Asset for [contactLine] (colorful brand icon).
  String get contactIconAsset =>
      primaryContact?.iconAsset ?? 'assets/images/icons/phone.svg';

  /// Every filled contact for icon rows (tap / long-press copy).
  List<CustomerContact> get allContacts {
    final out = <CustomerContact>[];
    void add(CustomerContact? c) {
      if (c != null) out.add(c);
    }

    final phone = this.phone?.trim();
    if (phone != null && phone.isNotEmpty) {
      add(CustomerContact.phone(phone));
    }
    final mail = email?.trim();
    if (mail != null && mail.isNotEmpty) {
      add(CustomerContact.email(mail));
    }
    final wa = whatsapp?.trim();
    if (wa != null && wa.isNotEmpty) {
      add(CustomerContact.whatsapp(wa));
    }
    final fb = facebook?.trim();
    if (fb != null && fb.isNotEmpty) {
      add(CustomerContact.social(
        fb,
        kind: CustomerContactKind.facebook,
        host: 'facebook.com',
        pathPrefix: '/',
        iconAsset: 'assets/images/icons/facebook.svg',
      ));
    }
    final ig = instagram?.trim();
    if (ig != null && ig.isNotEmpty) {
      add(CustomerContact.social(
        ig,
        kind: CustomerContactKind.instagram,
        host: 'instagram.com',
        pathPrefix: '/',
        iconAsset: 'assets/images/icons/instagram.svg',
      ));
    }
    final li = linkedin?.trim();
    if (li != null && li.isNotEmpty) {
      add(CustomerContact.social(
        li,
        kind: CustomerContactKind.linkedin,
        host: 'linkedin.com',
        pathPrefix: '/in/',
        iconAsset: 'assets/images/icons/linkedin.svg',
      ));
    }
    final tg = telegram?.trim();
    if (tg != null && tg.isNotEmpty) {
      add(CustomerContact.social(
        tg,
        kind: CustomerContactKind.telegram,
        host: 't.me',
        pathPrefix: '/',
        iconAsset: 'assets/images/icons/telegram.svg',
      ));
    }
    return out;
  }

  /// Best available contact for list subtitle + tap-to-open.
  CustomerContact? get primaryContact {
    final all = allContacts;
    return all.isEmpty ? null : all.first;
  }

  Customer copyWith({
    String? id,
    String? name,
    String? lastName,
    String? shortName,
    String? phone,
    String? email,
    String? whatsapp,
    String? facebook,
    String? instagram,
    String? linkedin,
    String? telegram,
    String? notes,
    List<CustomerCustomField>? customFields,
    String? photoPath,
    DateTime? createdAt,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      lastName: lastName ?? this.lastName,
      shortName: shortName ?? this.shortName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      whatsapp: whatsapp ?? this.whatsapp,
      facebook: facebook ?? this.facebook,
      instagram: instagram ?? this.instagram,
      linkedin: linkedin ?? this.linkedin,
      telegram: telegram ?? this.telegram,
      notes: notes ?? this.notes,
      customFields: customFields ?? this.customFields,
      photoPath: photoPath ?? this.photoPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'last_name': lastName,
        'short_name': shortName,
        'phone': phone,
        'email': email,
        'whatsapp': whatsapp,
        'facebook': facebook,
        'instagram': instagram,
        'linkedin': linkedin,
        'telegram': telegram,
        'notes': notes,
        'custom_fields': CustomerCustomField.encodeList(customFields),
        'photo_path': photoPath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: map['id'] as String,
        name: map['name'] as String,
        lastName: map['last_name'] as String?,
        shortName: map['short_name'] as String?,
        phone: map['phone'] as String?,
        email: map['email'] as String?,
        whatsapp: map['whatsapp'] as String?,
        facebook: map['facebook'] as String?,
        instagram: map['instagram'] as String?,
        linkedin: map['linkedin'] as String?,
        telegram: map['telegram'] as String?,
        notes: map['notes'] as String?,
        customFields:
            CustomerCustomField.decodeList(map['custom_fields'] as String?),
        photoPath: map['photo_path'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  @override
  List<Object?> get props => [
        id,
        name,
        lastName,
        shortName,
        phone,
        email,
        whatsapp,
        facebook,
        instagram,
        linkedin,
        telegram,
        notes,
        customFields,
        photoPath,
        createdAt,
      ];
}

class CustomerCustomField extends Equatable {
  const CustomerCustomField({required this.label, this.value = ''});

  final String label;
  final String value;

  CustomerCustomField copyWith({String? label, String? value}) =>
      CustomerCustomField(
        label: label ?? this.label,
        value: value ?? this.value,
      );

  Map<String, String> toJson() => {'label': label, 'value': value};

  factory CustomerCustomField.fromJson(Map<String, dynamic> json) =>
      CustomerCustomField(
        label: (json['label'] ?? '').toString(),
        value: (json['value'] ?? '').toString(),
      );

  static String? encodeList(List<CustomerCustomField> fields) {
    if (fields.isEmpty) return null;
    return jsonEncode(fields.map((e) => e.toJson()).toList());
  }

  static List<CustomerCustomField> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => CustomerCustomField.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.label.trim().isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  List<Object?> get props => [label, value];
}

enum CustomerContactKind {
  phone,
  email,
  whatsapp,
  facebook,
  instagram,
  linkedin,
  telegram,
}

class CustomerContact {
  const CustomerContact._({
    required this.kind,
    required this.raw,
    required this.display,
    required this.iconAsset,
    required this.uri,
  });

  final CustomerContactKind kind;
  final String raw;
  final String display;
  final String iconAsset;
  final Uri? uri;

  factory CustomerContact.phone(String value) => CustomerContact._(
        kind: CustomerContactKind.phone,
        raw: value,
        display: value,
        iconAsset: 'assets/images/icons/phone.svg',
        uri: Uri.parse('tel:${value.trim()}'),
      );

  factory CustomerContact.email(String value) => CustomerContact._(
        kind: CustomerContactKind.email,
        raw: value,
        display: value,
        iconAsset: 'assets/images/icons/email.svg',
        uri: Uri.parse('mailto:${value.trim()}'),
      );

  factory CustomerContact.whatsapp(String value) {
    final digits = value.replaceAll(RegExp(r'[^\d+]'), '');
    return CustomerContact._(
      kind: CustomerContactKind.whatsapp,
      raw: value,
      display: value,
      iconAsset: 'assets/images/icons/whatsapp.svg',
      uri: Uri.parse('https://wa.me/${Uri.encodeComponent(digits)}'),
    );
  }

  factory CustomerContact.social(
    String value, {
    required CustomerContactKind kind,
    required String host,
    required String pathPrefix,
    required String iconAsset,
  }) {
    final trimmed = value.trim();
    final display = _socialDisplay(trimmed);
    return CustomerContact._(
      kind: kind,
      raw: trimmed,
      display: display,
      iconAsset: iconAsset,
      uri: _socialUri(trimmed, host: host, pathPrefix: pathPrefix),
    );
  }

  static String _socialDisplay(String raw) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      try {
        final parts =
            Uri.parse(raw).path.split('/').where((e) => e.isNotEmpty).toList();
        if (parts.isNotEmpty) return '@${parts.last}';
      } catch (_) {}
    }
    return raw;
  }

  static Uri? _socialUri(
    String raw, {
    required String host,
    required String pathPrefix,
  }) {
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.tryParse(raw);
    }
    final handle = raw.replaceFirst(RegExp(r'^@'), '');
    return Uri.parse('https://$host$pathPrefix$handle');
  }
}

class CustomerStats extends Equatable {
  const CustomerStats({
    required this.purchaseCount,
    required this.totalSpent,
  });

  final int purchaseCount;
  final double totalSpent;

  @override
  List<Object?> get props => [purchaseCount, totalSpent];
}

class SaleLine extends Equatable {
  const SaleLine({
    required this.itemId,
    required this.title,
    required this.unitPrice,
    required this.quantity,
    this.unit,
    this.photoPath,
  });

  final String itemId;
  final String title;
  final double unitPrice;
  final double quantity;
  final String? unit;
  final String? photoPath;

  double get lineTotal => unitPrice * quantity;

  SaleLine copyWith({double? quantity, String? photoPath}) => SaleLine(
        itemId: itemId,
        title: title,
        unitPrice: unitPrice,
        quantity: quantity ?? this.quantity,
        unit: unit,
        photoPath: photoPath ?? this.photoPath,
      );

  @override
  List<Object?> get props =>
      [itemId, title, unitPrice, quantity, unit, photoPath];
}

class Sale extends Equatable {
  const Sale({
    required this.id,
    this.customerId,
    this.customerName,
    required this.total,
    required this.createdAt,
    required this.lines,
  });

  final String id;
  final String? customerId;
  final String? customerName;
  final double total;
  final DateTime createdAt;
  final List<SaleLine> lines;

  @override
  List<Object?> get props =>
      [id, customerId, customerName, total, createdAt, lines];
}
