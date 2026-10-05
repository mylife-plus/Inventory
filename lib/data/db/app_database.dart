import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'inventory_app.db');
    return openDatabase(
      path,
      version: 8,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE shop_settings (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            company_name TEXT NOT NULL DEFAULT '',
            cashier TEXT NOT NULL DEFAULT '',
            manager TEXT NOT NULL DEFAULT '',
            street TEXT NOT NULL DEFAULT '',
            zip TEXT NOT NULL DEFAULT '',
            city TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL DEFAULT '',
            vat_rate REAL NOT NULL DEFAULT 0,
            currency_symbol TEXT NOT NULL DEFAULT '€',
            decimal_separator TEXT NOT NULL DEFAULT ',',
            setup_complete INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.insert('shop_settings', {
          'id': 1,
          'currency_symbol': '€',
        });

        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE
          )
        ''');

        await db.execute('''
          CREATE TABLE inventory_items (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            price REAL NOT NULL,
            amount REAL NOT NULL,
            category_id TEXT,
            unit TEXT,
            photo_path TEXT,
            alert_enabled INTEGER NOT NULL DEFAULT 0,
            alert_amount REAL NOT NULL DEFAULT 0,
            qr_title TEXT,
            qr_subtitle TEXT,
            qr_link TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (category_id) REFERENCES categories(id)
              ON DELETE SET NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            last_name TEXT,
            short_name TEXT,
            phone TEXT,
            email TEXT,
            whatsapp TEXT,
            facebook TEXT,
            instagram TEXT,
            linkedin TEXT,
            telegram TEXT,
            notes TEXT,
            custom_fields TEXT,
            photo_path TEXT,
            created_at TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY,
            customer_id TEXT,
            customer_name TEXT,
            total REAL NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers(id)
              ON DELETE SET NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sale_lines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id TEXT NOT NULL,
            item_id TEXT NOT NULL,
            title TEXT NOT NULL,
            unit_price REAL NOT NULL,
            quantity REAL NOT NULL,
            unit TEXT,
            FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureCustomerColumns(db);
        if (oldVersion < 8) {
          // Old installs defaulted to TND; Euro is the first-launch default.
          await db.update(
            'shop_settings',
            {'currency_symbol': '€'},
            where: "currency_symbol = 'TND'",
          );
        }
      },
      onOpen: (db) async {
        // Repair schemas when version jumped without applying ALTERs.
        await _ensureCustomerColumns(db);
        await _relinkOrphanedSales(db);
      },
    );
  }

  /// Sales whose customer_id was cleared by INSERT OR REPLACE on customers.
  static Future<void> _relinkOrphanedSales(Database db) async {
    await db.execute('''
      UPDATE sales
      SET customer_id = (
        SELECT c.id FROM customers c
        WHERE TRIM(
          CASE
            WHEN c.short_name IS NOT NULL AND TRIM(c.short_name) != ''
              THEN c.short_name
            WHEN c.last_name IS NOT NULL AND TRIM(c.last_name) != ''
              THEN TRIM(c.name || ' ' || c.last_name)
            ELSE c.name
          END
        ) = sales.customer_name
        LIMIT 1
      )
      WHERE customer_id IS NULL
        AND customer_name IS NOT NULL
        AND TRIM(customer_name) != ''
        AND customer_name != 'Guest'
    ''');
  }

  /// Idempotent: add any missing customer columns (safe for old installs).
  static Future<void> _ensureCustomerColumns(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(customers)');
    final existing = <String>{
      for (final r in rows) (r['name'] as String?) ?? '',
    };
    const needed = <String>[
      'last_name',
      'short_name',
      'phone',
      'email',
      'whatsapp',
      'facebook',
      'instagram',
      'linkedin',
      'telegram',
      'notes',
      'custom_fields',
      'photo_path',
    ];
    for (final col in needed) {
      if (existing.contains(col)) continue;
      await db.execute('ALTER TABLE customers ADD COLUMN $col TEXT');
    }
  }
}
