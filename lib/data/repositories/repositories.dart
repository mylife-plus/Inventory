import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventory_app/core/utils/formatters.dart';
import 'package:inventory_app/data/db/app_database.dart';
import 'package:inventory_app/domain/models/models.dart';
import 'package:sqflite/sqflite.dart';

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final shopRepositoryProvider = Provider<ShopRepository>((ref) {
  return ShopRepository(ref.watch(databaseProvider));
});

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(ref.watch(databaseProvider));
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  return CustomerRepository(ref.watch(databaseProvider));
});

final saleRepositoryProvider = Provider<SaleRepository>((ref) {
  return SaleRepository(ref.watch(databaseProvider));
});

final shopSettingsProvider =
    AsyncNotifierProvider<ShopSettingsNotifier, ShopSettings>(
  ShopSettingsNotifier.new,
);

class ShopSettingsNotifier extends AsyncNotifier<ShopSettings> {
  @override
  Future<ShopSettings> build() => ref.read(shopRepositoryProvider).get();

  Future<void> save(ShopSettings settings) async {
    await ref.read(shopRepositoryProvider).save(settings);
    state = AsyncData(settings);
  }
}

final categoriesProvider =
    AsyncNotifierProvider<CategoriesNotifier, List<Category>>(
  CategoriesNotifier.new,
);

class CategoriesNotifier extends AsyncNotifier<List<Category>> {
  @override
  Future<List<Category>> build() =>
      ref.read(inventoryRepositoryProvider).listCategories();

  Future<Category> getOrCreate(String name) async {
    final cat = await ref.read(inventoryRepositoryProvider).getOrCreateCategory(name);
    state = AsyncData(await ref.read(inventoryRepositoryProvider).listCategories());
    return cat;
  }
}

final inventoryItemsProvider =
    AsyncNotifierProvider<InventoryItemsNotifier, List<InventoryItem>>(
  InventoryItemsNotifier.new,
);

class InventoryItemsNotifier extends AsyncNotifier<List<InventoryItem>> {
  @override
  Future<List<InventoryItem>> build() =>
      ref.read(inventoryRepositoryProvider).listItems();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(inventoryRepositoryProvider).listItems());
  }

  Future<void> upsert(InventoryItem item) async {
    await ref.read(inventoryRepositoryProvider).upsertItem(item);
    await refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(inventoryRepositoryProvider).deleteItem(id);
    await refresh();
  }
}

final customersProvider =
    AsyncNotifierProvider<CustomersNotifier, List<Customer>>(
  CustomersNotifier.new,
);

class CustomersNotifier extends AsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() =>
      ref.read(customerRepositoryProvider).list();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(customerRepositoryProvider).list());
  }

  Future<void> upsert(Customer customer) async {
    await ref.read(customerRepositoryProvider).upsert(customer);
    await refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(customerRepositoryProvider).delete(id);
    await refresh();
  }
}

final salesProvider = AsyncNotifierProvider<SalesNotifier, List<Sale>>(
  SalesNotifier.new,
);

class SalesNotifier extends AsyncNotifier<List<Sale>> {
  @override
  Future<List<Sale>> build() => ref.read(saleRepositoryProvider).list();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(saleRepositoryProvider).list());
  }

  Future<Sale> completeSale({
    required List<SaleLine> lines,
    Customer? customer,
  }) async {
    final sale = await ref.read(saleRepositoryProvider).createSale(
          lines: lines,
          customer: customer,
        );
    await ref.read(inventoryItemsProvider.notifier).refresh();
    await refresh();
    // Customer purchase counts / spend update on next stats load.
    ref.invalidate(customersProvider);
    return sale;
  }

  Future<Sale> updateSaleLines({
    required String saleId,
    required List<SaleLine> lines,
  }) async {
    final sale = await ref.read(saleRepositoryProvider).updateSaleLines(
          saleId: saleId,
          lines: lines,
        );
    await ref.read(inventoryItemsProvider.notifier).refresh();
    await refresh();
    ref.invalidate(customersProvider);
    return sale;
  }

  Future<void> updateSaleCustomer(String saleId, Customer? customer) async {
    await ref.read(saleRepositoryProvider).updateSaleCustomer(saleId, customer);
    await refresh();
    ref.invalidate(customersProvider);
  }

  /// Items that just went below alert threshold (for UI snackbars).
  Future<List<InventoryItem>> lowStockAfterSale(List<SaleLine> lines) async {
    final low = <InventoryItem>[];
    for (final line in lines) {
      final item =
          await ref.read(inventoryRepositoryProvider).getItem(line.itemId);
      if (item != null &&
          item.alertEnabled &&
          item.amount <= item.alertAmount) {
        low.add(item);
      }
    }
    return low;
  }
}

class ShopRepository {
  ShopRepository(this._db);
  final AppDatabase _db;

  Future<ShopSettings> get() async {
    final db = await _db.database;
    final rows = await db.query('shop_settings', where: 'id = 1');
    return ShopSettings.fromMap(rows.first);
  }

  Future<void> save(ShopSettings settings) async {
    final db = await _db.database;
    await db.update('shop_settings', settings.toMap(), where: 'id = 1');
  }
}

class InventoryRepository {
  InventoryRepository(this._db);
  final AppDatabase _db;

  Future<List<Category>> listCategories() async {
    final db = await _db.database;
    final rows = await db.query('categories', orderBy: 'name COLLATE NOCASE');
    return rows.map(Category.fromMap).toList();
  }

  Future<Category> getOrCreateCategory(String name) async {
    final trimmed = name.trim();
    final db = await _db.database;
    final existing = await db.query(
      'categories',
      where: 'LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return Category.fromMap(existing.first);
    final cat = Category(id: newId(), name: trimmed);
    await db.insert('categories', cat.toMap());
    return cat;
  }

  Future<List<InventoryItem>> listItems({String? query, String? categoryId}) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];
    if (query != null && query.trim().isNotEmpty) {
      where.add('i.title LIKE ?');
      args.add('%${query.trim()}%');
    }
    if (categoryId != null) {
      where.add('i.category_id = ?');
      args.add(categoryId);
    }
    final sql = '''
      SELECT i.*, c.name AS category_name
      FROM inventory_items i
      LEFT JOIN categories c ON c.id = i.category_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY i.updated_at DESC
    ''';
    final rows = await db.rawQuery(sql, args);
    return rows.map(InventoryItem.fromMap).toList();
  }

  Future<InventoryItem?> getItem(String id) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT i.*, c.name AS category_name
      FROM inventory_items i
      LEFT JOIN categories c ON c.id = i.category_id
      WHERE i.id = ?
      LIMIT 1
    ''', [id]);
    if (rows.isEmpty) return null;
    return InventoryItem.fromMap(rows.first);
  }

  Future<void> upsertItem(InventoryItem item) async {
    final db = await _db.database;
    await db.insert(
      'inventory_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteItem(String id) async {
    final db = await _db.database;
    await db.delete('inventory_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustStock(String itemId, double delta) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE inventory_items SET amount = MAX(0, amount + ?), updated_at = ? WHERE id = ?',
      [delta, DateTime.now().toIso8601String(), itemId],
    );
  }
}

class CustomerRepository {
  CustomerRepository(this._db);
  final AppDatabase _db;

  Future<List<Customer>> list() async {
    final db = await _db.database;
    final rows = await db.query('customers', orderBy: 'name COLLATE NOCASE');
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> get(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<void> upsert(Customer customer) async {
    final db = await _db.database;
    // Must UPDATE, not INSERT OR REPLACE: REPLACE deletes the row first, and
    // sales.customer_id is ON DELETE SET NULL — that wiped purchase history.
    final updated = await db.update(
      'customers',
      customer.toMap(),
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    if (updated == 0) {
      await db.insert('customers', customer.toMap());
    } else {
      // Keep sale labels in sync after rename.
      await db.update(
        'sales',
        {'customer_name': customer.displayName},
        where: 'customer_id = ?',
        whereArgs: [customer.id],
      );
    }
    // Re-link sales orphaned by older REPLACE upserts (same display name).
    await db.rawUpdate('''
      UPDATE sales
      SET customer_id = ?
      WHERE customer_id IS NULL
        AND customer_name = ?
        AND customer_name != 'Guest'
    ''', [customer.id, customer.displayName]);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<CustomerStats> stats(String customerId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS c, COALESCE(SUM(total), 0) AS s
      FROM sales WHERE customer_id = ?
    ''', [customerId]);
    return CustomerStats(
      purchaseCount: (rows.first['c'] as int?) ?? 0,
      totalSpent: (rows.first['s'] as num?)?.toDouble() ?? 0,
    );
  }
}

class SaleRepository {
  SaleRepository(this._db);
  final AppDatabase _db;

  Future<Sale?> get(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('sales', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final lines = await db.query(
      'sale_lines',
      where: 'sale_id = ?',
      whereArgs: [row['id']],
    );
    return Sale(
      id: row['id'] as String,
      customerId: row['customer_id'] as String?,
      customerName: row['customer_name'] as String?,
      total: (row['total'] as num).toDouble(),
      createdAt: DateTime.parse(row['created_at'] as String),
      lines: lines
          .map(
            (l) => SaleLine(
              itemId: l['item_id'] as String,
              title: l['title'] as String,
              unitPrice: (l['unit_price'] as num).toDouble(),
              quantity: (l['quantity'] as num).toDouble(),
              unit: l['unit'] as String?,
            ),
          )
          .toList(),
    );
  }

  Future<List<Sale>> list() async {
    final db = await _db.database;
    final sales = await db.query('sales', orderBy: 'created_at DESC');
    final result = <Sale>[];
    for (final row in sales) {
      final lines = await db.query(
        'sale_lines',
        where: 'sale_id = ?',
        whereArgs: [row['id']],
      );
      result.add(
        Sale(
          id: row['id'] as String,
          customerId: row['customer_id'] as String?,
          customerName: row['customer_name'] as String?,
          total: (row['total'] as num).toDouble(),
          createdAt: DateTime.parse(row['created_at'] as String),
          lines: lines
              .map(
                (l) => SaleLine(
                  itemId: l['item_id'] as String,
                  title: l['title'] as String,
                  unitPrice: (l['unit_price'] as num).toDouble(),
                  quantity: (l['quantity'] as num).toDouble(),
                  unit: l['unit'] as String?,
                ),
              )
              .toList(),
        ),
      );
    }
    return result;
  }

  Future<List<Sale>> listForCustomer(String customerId) async {
    final all = await list();
    return all.where((s) => s.customerId == customerId).toList();
  }

  Future<Sale> createSale({
    required List<SaleLine> lines,
    Customer? customer,
  }) async {
    if (lines.isEmpty) {
      throw StateError('Cannot complete a sale with no items');
    }
    final db = await _db.database;
    final id = newId();
    final total = lines.fold<double>(0, (sum, l) => sum + l.lineTotal);
    final now = DateTime.now();
    // Never persist guest sentinel as a real customer id.
    final customerId =
        (customer == null || customer.id == '__guest__') ? null : customer.id;
    final customerName = (customer == null || customer.id == '__guest__')
        ? 'Guest'
        : customer.displayName;

    await db.transaction((txn) async {
      for (final line in lines) {
        if (line.quantity <= 0) {
          throw StateError('Invalid quantity for ${line.title}');
        }
        final rows = await txn.query(
          'inventory_items',
          columns: ['amount', 'title'],
          where: 'id = ?',
          whereArgs: [line.itemId],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Item not found: ${line.title}');
        }
        final stock = (rows.first['amount'] as num).toDouble();
        if (stock + 1e-9 < line.quantity) {
          throw StateError(
            'Not enough stock for ${line.title} '
            '(need ${formatQty(line.quantity)}, have ${formatQty(stock)})',
          );
        }
      }

      await txn.insert('sales', {
        'id': id,
        'customer_id': customerId,
        'customer_name': customerName,
        'total': total,
        'created_at': now.toIso8601String(),
      });
      for (final line in lines) {
        await txn.insert('sale_lines', {
          'sale_id': id,
          'item_id': line.itemId,
          'title': line.title,
          'unit_price': line.unitPrice,
          'quantity': line.quantity,
          'unit': line.unit,
        });
        await txn.rawUpdate(
          'UPDATE inventory_items SET amount = MAX(0, amount - ?), updated_at = ? WHERE id = ?',
          [line.quantity, now.toIso8601String(), line.itemId],
        );
      }
    });

    return Sale(
      id: id,
      customerId: customerId,
      customerName: customerName,
      total: total,
      createdAt: now,
      lines: lines,
    );
  }

  /// Change who a receipt belongs to (`null` / guest sentinel = Guest).
  Future<void> updateSaleCustomer(String saleId, Customer? customer) async {
    final db = await _db.database;
    final isGuest = customer == null || customer.id == '__guest__';
    await db.update(
      'sales',
      {
        'customer_id': isGuest ? null : customer.id,
        'customer_name': isGuest ? 'Guest' : customer.displayName,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  /// Replace sale lines and adjust inventory (restock old, deduct new).
  Future<Sale> updateSaleLines({
    required String saleId,
    required List<SaleLine> lines,
  }) async {
    final existing = await get(saleId);
    if (existing == null) {
      throw StateError('Sale not found');
    }
    if (lines.isEmpty) {
      throw StateError('Sale must have at least one line');
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      for (final line in existing.lines) {
        await txn.rawUpdate(
          'UPDATE inventory_items SET amount = amount + ? WHERE id = ?',
          [line.quantity, line.itemId],
        );
      }

      for (final line in lines) {
        final rows = await txn.query(
          'inventory_items',
          columns: ['amount'],
          where: 'id = ?',
          whereArgs: [line.itemId],
        );
        if (rows.isEmpty) {
          throw StateError('Item missing: ${line.title}');
        }
        final stock = (rows.first['amount'] as num).toDouble();
        if (stock + 1e-9 < line.quantity) {
          throw StateError('Not enough stock for ${line.title}');
        }
        await txn.rawUpdate(
          'UPDATE inventory_items SET amount = amount - ? WHERE id = ?',
          [line.quantity, line.itemId],
        );
      }

      await txn.delete(
        'sale_lines',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      var total = 0.0;
      for (final line in lines) {
        total += line.lineTotal;
        await txn.insert('sale_lines', {
          'sale_id': saleId,
          'item_id': line.itemId,
          'title': line.title,
          'unit_price': line.unitPrice,
          'quantity': line.quantity,
          'unit': line.unit,
        });
      }

      await txn.update(
        'sales',
        {'total': total},
        where: 'id = ?',
        whereArgs: [saleId],
      );
    });

    final updated = await get(saleId);
    if (updated == null) {
      throw StateError('Sale missing after update');
    }
    return updated;
  }

  Future<List<Sale>> listInRange({DateTime? from, DateTime? to}) async {
    final all = await list();
    return all.where((s) {
      if (from != null && s.createdAt.isBefore(from)) return false;
      if (to != null && s.createdAt.isAfter(to)) return false;
      return true;
    }).toList();
  }

  /// Aggregated sold qty/revenue per item title in range.
  Future<List<SoldItemAgg>> soldItems({DateTime? from, DateTime? to}) async {
    final sales = await listInRange(from: from, to: to);
    final map = <String, SoldItemAgg>{};
    for (final sale in sales) {
      for (final line in sale.lines) {
        final prev = map[line.itemId];
        if (prev == null) {
          map[line.itemId] = SoldItemAgg(
            itemId: line.itemId,
            title: line.title,
            unit: line.unit,
            unitPrice: line.unitPrice,
            quantity: line.quantity,
            revenue: line.lineTotal,
          );
        } else {
          map[line.itemId] = SoldItemAgg(
            itemId: line.itemId,
            title: line.title,
            unit: line.unit,
            unitPrice: line.unitPrice,
            quantity: prev.quantity + line.quantity,
            revenue: prev.revenue + line.lineTotal,
          );
        }
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));
    return list;
  }
}

class SoldItemAgg {
  const SoldItemAgg({
    required this.itemId,
    required this.title,
    required this.quantity,
    required this.revenue,
    required this.unitPrice,
    this.unit,
  });

  final String itemId;
  final String title;
  final String? unit;
  final double unitPrice;
  final double quantity;
  final double revenue;
}

class DataRepository {
  DataRepository(this._db);
  final AppDatabase _db;

  Future<void> eraseAll() async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete('sale_lines');
      await txn.delete('sales');
      await txn.delete('inventory_items');
      await txn.delete('categories');
      await txn.delete('customers');
      await txn.update(
        'shop_settings',
        {
          'company_name': '',
          'cashier': '',
          'manager': '',
          'street': '',
          'zip': '',
          'city': '',
          'phone': '',
          'vat_rate': 0,
          'currency_symbol': '€',
          'decimal_separator': ',',
          'setup_complete': 0,
        },
        where: 'id = 1',
      );
    });
  }
}

final dataRepositoryProvider = Provider<DataRepository>((ref) {
  return DataRepository(ref.watch(databaseProvider));
});
