import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:jamal_phone_manager/database/database_helper.dart';
import 'package:jamal_phone_manager/models/expense.dart';
import 'package:jamal_phone_manager/models/product.dart';
import 'package:jamal_phone_manager/repositories/store_repository.dart';
import 'package:jamal_phone_manager/services/backup_service.dart';
import 'package:jamal_phone_manager/services/expense_service.dart';
import 'package:jamal_phone_manager/services/financial_service.dart';
import 'package:jamal_phone_manager/services/product_service.dart';
import 'package:jamal_phone_manager/services/purchase_service.dart';
import 'package:jamal_phone_manager/services/sale_service.dart';
import 'package:jamal_phone_manager/services/settings_service.dart';
import 'package:jamal_phone_manager/utils/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late DatabaseHelper database;
  late StoreRepository repository;
  late ProductService products;
  late PurchaseService purchases;
  late SaleService sales;
  late FinancialService finance;
  late ExpenseService expenses;
  late SettingsService settings;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jpm_test_');
    final dbPath = '${tempDir.path}/jamal_phone.db';
    database = DatabaseHelper.forTesting(factory: databaseFactoryFfi, databasePath: dbPath);
    repository = StoreRepository(database: database);
    products = ProductService(repository: repository);
    purchases = PurchaseService(repository: repository);
    sales = SaleService(repository: repository);
    finance = FinancialService(repository: repository);
    expenses = ExpenseService(repository: repository);
    settings = SettingsService(repository: repository);
    await database.database;
  });

  tearDown(() async {
    await database.close();
    await tempDir.delete(recursive: true);
  });

  Future<Product> createProduct({String name = 'Phone A', double cost = 0, double sell = 215000, int stock = 0}) async {
    final now = DateTime.now().toIso8601String();
    final id = await products.insert(Product(
      name: name,
      sellPrice: sell,
      costPrice: cost,
      stock: stock,
      createdAt: now,
      updatedAt: now,
    ));
    return (await products.getById(id))!;
  }

  test('purchase + weighted average + stock movements', () async {
    final product = await createProduct();
    final accessory = await createProduct(name: 'Accessory A', cost: 5000, sell: 8000);
    final firstPurchaseId = await purchases.createPurchase(
      items: [
        {'productId': product.id, 'quantity': 10, 'unitCost': 180000},
        {'productId': accessory.id, 'quantity': 4, 'unitCost': 5000},
      ],
      paymentMethod: 'cash',
    );
    await purchases.createPurchase(
      items: [
        {'productId': product.id, 'quantity': 10, 'unitCost': 220000},
      ],
      paymentMethod: 'credit',
      paidAmount: 0,
      dueDate: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    );
    final updated = await products.getById(product.id!);
    final purchaseItems = await (await repository.db).query('purchase_items', where: 'purchase_id = ?', whereArgs: [firstPurchaseId]);
    expect(purchaseItems, hasLength(2));
    expect(updated!.stock, 20);
    expect(updated.costPrice, Money.round(200000));
    expect(await products.auditStockIntegrity(productId: product.id), isTrue);
    final db = await repository.db;
    final movementCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stock_movements WHERE product_id = ?', [product.id]));
    expect(movementCount, 2);
  });

  test('sale preserves historical cost and full return restores inventory/refunds', () async {
    await settings.setInitialCapital(3000000);
    final product = await createProduct(cost: 180000, sell: 215000, stock: 10);
    final saleId = await sales.createSale(
      items: [
        {'productId': product.id, 'unitPrice': 215000, 'quantity': 3},
      ],
      paymentMethod: 'cash',
    );
    final sale = await sales.getById(saleId);
    expect(sale!.items.single.unitCost, 180000);
    expect(sale.profit, 105000);
    await sales.returnSale(saleId);
    final returned = await sales.getById(saleId);
    expect(returned!.isReturned, isTrue);
    expect(returned.paidAmount, 0);
    expect(returned.remainingAmount, 0);
    expect((await products.getById(product.id!))!.stock, 10);
    expect((await finance.getSummary())['sales'], 0);
    expect((await finance.getSummary())['grossProfit'], 0);
    expect((await finance.getSummary())['cashBalance'], 3000000);
    final refundLedger = await (await repository.db).query('payment_ledger', where: "entry_type = 'sale_refund'");
    expect(refundLedger, hasLength(1));
    expect(refundLedger.single['payment_method'], 'cash');
  });

  test('full credit return refunds each original payment method', () async {
    final product = await createProduct(cost: 100000, sell: 150000, stock: 2);
    final saleId = await sales.createSale(
      items: [{'productId': product.id, 'unitPrice': 150000, 'quantity': 1}],
      paymentMethod: 'credit',
      initialPayment: 50000,
      initialPaymentMethod: 'card',
      dueDate: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    );
    await sales.recordReceivablePayment(saleId, 100000, paymentMethod: 'transfer');
    await sales.returnSale(saleId);
    final db = await repository.db;
    final refunds = await db.query('payment_ledger', where: "reference_id = ? AND entry_type = 'sale_refund'", whereArgs: [saleId], orderBy: 'id');
    expect(refunds, hasLength(2));
    expect(refunds[0]['payment_method'], 'card');
    expect(refunds[0]['amount'], 50000);
    expect(refunds[1]['payment_method'], 'transfer');
    expect(refunds[1]['amount'], 100000);
  });

  test('discount reduces historical gross profit', () async {
    final product = await createProduct(cost: 100000, sell: 150000, stock: 1);
    final saleId = await sales.createSale(
      items: [{'productId': product.id, 'unitPrice': 150000, 'quantity': 1}],
      discount: 10000,
      paymentMethod: 'cash',
    );
    final sale = await sales.getById(saleId);
    expect(sale!.total, 140000);
    expect(sale.profit, 40000);
    expect(sale.items.single.profit, 40000);
  });

  test('credit sale + partial payment + later collection', () async {
    final product = await createProduct(cost: 180000, sell: 100000, stock: 10);
    final saleId = await sales.createSale(
      items: [
        {'productId': product.id, 'unitPrice': 100000, 'quantity': 1},
      ],
      paymentMethod: 'credit',
      initialPayment: 40000,
      initialPaymentNote: 'دفعة أولى',
      dueDate: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    );
    expect((await sales.getById(saleId))!.remainingAmount, 60000);
    await sales.recordReceivablePayment(saleId, 60000, paymentMethod: 'transfer', note: 'تحصيل لاحق');
    final sale = await sales.getById(saleId);
    expect(sale!.remainingAmount, 0);
    expect(sale.paidAmount, 100000);
    final db = await repository.db;
    expect((await db.query('payment_ledger', where: "reference_id = ? AND entry_type = 'sale_payment'", whereArgs: [saleId])).single['payment_method'], 'cash');
    expect((await db.query('payment_ledger', where: "reference_id = ? AND entry_type = 'customer_collection'", whereArgs: [saleId])).single['payment_method'], 'transfer');
    expect((await sales.getReceivables()), isEmpty);
    final notes = await db.rawQuery("SELECT note FROM receivable_payments WHERE sale_id = ? ORDER BY id", [saleId]);
    expect(notes.map((e) => e['note']).join('|'), contains('دفعة أولى'));
    expect(notes.map((e) => e['note']).join('|'), contains('تحصيل لاحق'));
  });

  test('initial capital correction preserves the immutable ledger', () async {
    await settings.setInitialCapital(3000000);
    await settings.setInitialCapital(3250000);
    final summary = await finance.getSummary();
    expect(summary['initialCapital'], 3250000);
    expect(summary['cashBalance'], 3250000);
    final db = await repository.db;
    final rows = await db.query('payment_ledger', orderBy: 'id ASC');
    expect(rows.where((row) => row['entry_type'] == 'initial_capital'), hasLength(1));
    expect(rows.where((row) => row['entry_type'] == 'initial_capital_adjustment'), hasLength(1));
  });

  test('expense + capital use the financial ledger', () async {
    final summaryBefore = await finance.getSummary();
    expect(summaryBefore['cashBalance'], 0);
    await settings.setInitialCapital(3000000);
    await expenses.insert(Expense(
      title: 'نقل',
      amount: 10000,
      expenseDate: DateTime.now().toIso8601String(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    await finance.addCapitalTransaction(type: 'contribution', amount: 100000, description: 'إضافة');
    await finance.addCapitalTransaction(type: 'withdrawal', amount: 50000, description: 'سحب');
    final summary = await finance.getSummary();
    expect(summary['cashBalance'], 3040000);
    expect(summary['capitalIn'], 100000);
    expect(summary['capitalOut'], 50000);
    expect(summary['expenses'], 10000);
  });

  test('supplier payable and partial/later supplier payment', () async {
    final product = await createProduct();
    final db = await repository.db;
    final supplierId = await db.insert('suppliers', {
      'name': 'Supplier A',
      'created_at': DateTime.now().toIso8601String(),
    });
    final purchaseId = await purchases.createPurchase(
      supplierId: supplierId,
      items: [
        {'productId': product.id, 'quantity': 2, 'unitCost': 50000},
      ],
      paymentMethod: 'credit',
      paidAmount: 0,
      dueDate: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    );
    expect((await purchases.getPayables())['payable'], 100000);
    await purchases.recordSupplierPayment(purchaseId, 40000, paymentMethod: 'cash', note: 'دفعة أولى');
    expect((await purchases.getPayables())['payable'], 60000);
    await purchases.recordSupplierPayment(purchaseId, 60000, paymentMethod: 'transfer', note: 'تسوية نهائية');
    expect((await purchases.getPayables())['payable'], 0);
    final ledger = await db.query('payment_ledger', where: "entry_type = 'supplier_payment'", orderBy: 'id');
    expect(ledger.length, 2);
  });

  test('migrates a legacy v7 database without losing data', () async {
    final legacyPath = '${tempDir.path}/legacy_v7.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      legacyPath,
      version: 7,
      options: OpenDatabaseOptions(onCreate: (db, version) async {
        await db.execute('CREATE TABLE categories (id INTEGER PRIMARY KEY AUTOINCREMENT, name_ar TEXT NOT NULL, name_en TEXT, icon TEXT, color TEXT, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category_id INTEGER, brand TEXT, barcode TEXT UNIQUE, sell_price REAL NOT NULL DEFAULT 0, cost_price REAL NOT NULL DEFAULT 0, stock INTEGER NOT NULL DEFAULT 0, min_stock INTEGER NOT NULL DEFAULT 5, warranty TEXT, description TEXT, image_path TEXT, attributes TEXT, is_active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT, notes TEXT, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, supplier_id INTEGER, invoice_number TEXT, total_amount REAL NOT NULL DEFAULT 0, payment_method TEXT NOT NULL DEFAULT \'cash\', paid_amount REAL NOT NULL DEFAULT 0, due_date TEXT, notes TEXT, purchase_date TEXT NOT NULL, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE purchase_items (id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER NOT NULL, product_id INTEGER NOT NULL, quantity INTEGER NOT NULL, unit_cost REAL NOT NULL, total_cost REAL NOT NULL)');
        await db.execute('CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_number TEXT UNIQUE, customer_name TEXT, customer_phone TEXT, subtotal REAL NOT NULL DEFAULT 0, discount REAL NOT NULL DEFAULT 0, total REAL NOT NULL DEFAULT 0, profit REAL NOT NULL DEFAULT 0, payment_method TEXT NOT NULL DEFAULT \'cash\', paid_amount REAL NOT NULL DEFAULT 0, due_date TEXT, notes TEXT, sale_date TEXT NOT NULL, created_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'completed\')');
        await db.execute('CREATE TABLE sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, product_name TEXT NOT NULL, quantity INTEGER NOT NULL, unit_price REAL NOT NULL, unit_cost REAL NOT NULL, total_price REAL NOT NULL, profit REAL NOT NULL)');
        await db.execute('CREATE TABLE stock_movements (id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER NOT NULL, type TEXT NOT NULL, quantity INTEGER NOT NULL, previous_stock INTEGER NOT NULL, new_stock INTEGER NOT NULL, reference_type TEXT, reference_id INTEGER, notes TEXT, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, category TEXT, notes TEXT, expense_date TEXT NOT NULL, created_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT \'active\')');
        await db.execute('CREATE TABLE capital_transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, amount REAL NOT NULL, description TEXT, transaction_date TEXT NOT NULL, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE receivable_payments (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, amount REAL NOT NULL, payment_type TEXT NOT NULL DEFAULT \'collection\', payment_date TEXT NOT NULL, note TEXT, created_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('CREATE TABLE pending_telegram (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL, retries INTEGER NOT NULL DEFAULT 0)');
        final now = DateTime.now().toIso8601String();
        await db.insert('settings', {'key': 'store_name', 'value': 'Jamal Phone'});
        await db.insert('settings', {'key': 'currency', 'value': 'دج'});
        await db.insert('settings', {'key': 'initial_capital', 'value': '3000000'});
        await db.insert('suppliers', {'name': 'Legacy Supplier', 'created_at': now});
        await db.insert('products', {'name': 'Legacy Phone', 'sell_price': 200000, 'cost_price': 150000, 'stock': 5, 'created_at': now, 'updated_at': now});
        await db.insert('purchases', {'supplier_id': 1, 'invoice_number': 'P-LEG-001', 'total_amount': 500000, 'payment_method': 'cash', 'paid_amount': 200000, 'purchase_date': now, 'created_at': now});
        final saleId = await db.insert('sales', {'invoice_number': 'LEG-001', 'total': 200000, 'profit': 50000, 'payment_method': 'cash', 'paid_amount': 200000, 'sale_date': now, 'created_at': now, 'status': 'completed'});
        await db.insert('receivable_payments', {'sale_id': saleId, 'amount': 200000, 'payment_type': 'collection', 'payment_date': now, 'note': 'legacy cash', 'created_at': now});
        await db.insert('expenses', {'title': 'legacy expense', 'amount': 10000, 'expense_date': now, 'created_at': now, 'status': 'active'});
        await db.insert('capital_transactions', {'type': 'contribution', 'amount': 50000, 'description': 'legacy', 'transaction_date': now, 'created_at': now});
      }),
    );
    await legacy.close();

    final migrated = DatabaseHelper.forTesting(factory: databaseFactoryFfi, databasePath: legacyPath);
    final db = await migrated.database;
    final versionRows = await db.rawQuery('PRAGMA user_version');
    expect((versionRows.first.values.first as num).toInt(), 10);
    final product = (await db.query('products', where: 'name = ?', whereArgs: ['Legacy Phone'])).single;
    expect(product['stock'], 5);
    expect((await db.query('stock_movements', where: 'product_id = ?', whereArgs: [product['id']])).single['reason_code'], 'legacy_reconciliation');
    expect((await db.query('payment_ledger', where: "entry_type = 'sale_payment'")).length, 1);
    expect((await db.query('payment_ledger', where: "entry_type = 'expense'")).length, 1);
    expect((await db.query('payment_ledger', where: "entry_type = 'capital_in'")).length, 1);
    expect((await db.query('payment_ledger', where: "entry_type = 'supplier_payment'")).length, 1);
    expect((await db.query('supplier_payments')).length, 1);
    expect((await db.query('settings', where: 'key = ?', whereArgs: ['store_name'])).single['value'], 'Jamal Phone');
    await migrated.close();
  });

  test('financial and stock ledgers are immutable and stock movement matches product balance', () async {
    final product = await createProduct(cost: 10000, sell: 15000, stock: 2);
    final db = await repository.db;
    await products.adjustStock(product.id!, 1, 'in', notes: 'اختبار');
    final movement = (await db.query('stock_movements', orderBy: 'id DESC', limit: 1)).single;
    await expectLater(
      db.update('stock_movements', {'new_stock': 999}, where: 'id = ?', whereArgs: [movement['id']]),
      throwsA(isA<DatabaseException>()),
    );

    await settings.setInitialCapital(100000);
    await expenses.insert(Expense(
      title: 'اختبار',
      amount: 1000,
      expenseDate: DateTime.now().toIso8601String(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    final ledger = (await db.query('payment_ledger', where: "entry_type = 'expense'", limit: 1)).single;
    await expectLater(
      db.delete('payment_ledger', where: 'id = ?', whereArgs: [ledger['id']]),
      throwsA(isA<DatabaseException>()),
    );
    expect(await products.auditStockIntegrity(productId: product.id), isTrue);
  });

  test('requested functional scenario and encrypted backup/restore with images', () async {
    await settings.setInitialCapital(3000000);
    final imageDir = Directory('${tempDir.path}/product_images');
    final backupDir = Directory('${tempDir.path}/backups');
    await imageDir.create(recursive: true);
    await backupDir.create(recursive: true);
    final imageFile = File('${imageDir.path}/phone.txt');
    final imageBytes = List<int>.generate(32, (i) => i);
    await imageFile.writeAsBytes(imageBytes);

    final product = await createProduct(cost: 0, sell: 215000);
    final db = await repository.db;
    await db.update('products', {'image_path': imageFile.path}, where: 'id = ?', whereArgs: [product.id]);
    await purchases.createPurchase(
      items: [{'productId': product.id, 'quantity': 10, 'unitCost': 180000}],
      paymentMethod: 'cash',
    );
    final firstSale = await sales.createSale(
      items: [{'productId': product.id, 'unitPrice': 215000, 'quantity': 3}],
      paymentMethod: 'cash',
    );
    await sales.returnSale(firstSale);
    await expenses.insert(Expense(
      title: 'مصروف', amount: 10000,
      expenseDate: DateTime.now().toIso8601String(),
      createdAt: DateTime.now().toIso8601String(),
    ));
    final creditSale = await sales.createSale(
      items: [{'productId': product.id, 'unitPrice': 100000, 'quantity': 1}],
      paymentMethod: 'credit',
      initialPayment: 40000,
      dueDate: DateTime.now().add(const Duration(days: 30)).toIso8601String(),
    );
    await sales.recordReceivablePayment(creditSale, 60000, note: 'تحصيل لاحق');
    final scenarioSummary = await finance.getSummary();
    expect(scenarioSummary['grossProfit'], -80000);
    expect(scenarioSummary['netProfit'], -90000);
    expect(scenarioSummary['cashBalance'], 1290000);
    expect(scenarioSummary['receivables'], 0);
    expect(scenarioSummary['supplierPayables'], 0);
    expect(scenarioSummary['inventoryValue'], 1620000);
    expect(scenarioSummary['currentCapital'], 2910000);
    final movementRows = await db.rawQuery(
      'SELECT COUNT(*) AS count, COALESCE(SUM(delta_quantity),0) AS delta FROM stock_movements WHERE product_id = ?',
      [product.id],
    );
    expect((movementRows.first['count'] as num).toInt(), 4);
    expect((movementRows.first['delta'] as num).toInt(), 9);

    final key = List<int>.generate(32, (i) => 255 - i);
    final backup = BackupService(
      database: database,
      backupDirectory: backupDir,
      productImagesDirectory: imageDir,
      testMasterKey: key,
    );
    final backupPath = await backup.createBackup();
    expect(File(backupPath).existsSync(), isTrue);
    expect(await File(backupPath).readAsString(), isNot(contains('JPM-DATA-2')));
    expect(await backup.listBackups(), hasLength(1));

    final dbAfterBackup = await repository.db;
    final staleImage = File('${imageDir.path}/stale.txt');
    await staleImage.writeAsString('stale');
    await dbAfterBackup.update('products', {'image_path': null, 'stock': 0}, where: 'id = ?', whereArgs: [product.id]);
    await database.close();
    await backup.restoreBackup(backupPath, recoveryKey: await backup.getRecoveryKey());
    await database.database;
    final restoredProduct = await products.getById(product.id!);
    expect(restoredProduct!.stock, 9);
    expect((await finance.getSummary())['cashBalance'], 1290000);
    expect((await finance.getSummary())['receivables'], 0);
    expect((await finance.getSummary())['supplierPayables'], 0);
    expect(await File(restoredProduct.imagePath!).readAsBytes(), imageBytes);
    expect(await staleImage.exists(), isFalse);
    expect(await products.auditStockIntegrity(productId: product.id), isTrue);
  });
}
