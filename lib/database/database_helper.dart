import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();

  DatabaseHelper._init({DatabaseFactory? factory, String? databasePath})
      : _factory = factory ?? databaseFactory,
        _databasePathOverride = databasePath;

  factory DatabaseHelper.forTesting({
    required DatabaseFactory factory,
    required String databasePath,
  }) =>
      DatabaseHelper._init(factory: factory, databasePath: databasePath);

  final DatabaseFactory _factory;
  final String? _databasePathOverride;
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jamal_phone.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final path = _databasePathOverride ??
        join(await _factory.getDatabasesPath(), fileName);
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 10,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
      ),
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_ar TEXT NOT NULL,
        name_en TEXT,
        icon TEXT,
        color TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category_id INTEGER,
        brand TEXT,
        barcode TEXT UNIQUE,
        sell_price REAL NOT NULL DEFAULT 0,
        cost_price REAL NOT NULL DEFAULT 0,
        stock INTEGER NOT NULL DEFAULT 0,
        min_stock INTEGER NOT NULL DEFAULT 5,
        warranty TEXT,
        description TEXT,
        image_path TEXT,
        attributes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        invoice_number TEXT,
        total_amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        paid_amount REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        notes TEXT,
        purchase_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_cost REAL NOT NULL,
        total_cost REAL NOT NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT UNIQUE,
        customer_name TEXT,
        customer_phone TEXT,
        subtotal REAL NOT NULL DEFAULT 0,
        discount REAL NOT NULL DEFAULT 0,
        total REAL NOT NULL DEFAULT 0,
        profit REAL NOT NULL DEFAULT 0,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        paid_amount REAL NOT NULL DEFAULT 0,
        due_date TEXT,
        notes TEXT,
        sale_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed'
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        unit_cost REAL NOT NULL,
        total_price REAL NOT NULL,
        profit REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        previous_stock INTEGER NOT NULL,
        new_stock INTEGER NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        notes TEXT,
        created_at TEXT NOT NULL,
        delta_quantity INTEGER,
        reason_code TEXT,
        FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT,
        notes TEXT,
        expense_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');

    await db.execute('''
      CREATE TABLE capital_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT,
        transaction_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE receivable_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        payment_type TEXT NOT NULL DEFAULT 'collection',
        payment_date TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pending_telegram (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await _createModernFinanceTables(db);
    await _createIndexes(db);
    await _createModernFinanceIndexes(db);
    await _createIntegrityTriggers(db);
    await _seed(db);
  }

  Future<void> _createModernFinanceTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS supplier_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        supplier_id INTEGER,
        purchase_id INTEGER,
        amount REAL NOT NULL CHECK(amount > 0),
        payment_method TEXT NOT NULL DEFAULT 'cash',
        payment_date TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE SET NULL,
        FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_ledger (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        direction TEXT NOT NULL CHECK(direction IN ('in', 'out')),
        entry_type TEXT NOT NULL,
        amount REAL NOT NULL CHECK(amount > 0),
        payment_method TEXT NOT NULL DEFAULT 'cash',
        source_table TEXT NOT NULL,
        source_id INTEGER NOT NULL,
        reference_type TEXT,
        reference_id INTEGER,
        note TEXT,
        transaction_date TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seed(Database db) async {
    final now = DateTime.now().toIso8601String();
    const categories = [
      ['هواتف', 'Phones', 'phone_android'],
      ['إكسسوارات', 'Accessories', 'headphones'],
      ['شواحن وكابلات', 'Chargers & Cables', 'cable'],
      ['حافظات', 'Cases', 'phone_iphone'],
      ['سماعات', 'Audio', 'headphones'],
      ['أخرى', 'Other', 'category'],
    ];
    for (var i = 0; i < categories.length; i++) {
      await db.insert('categories', {
        'name_ar': categories[i][0],
        'name_en': categories[i][1],
        'icon': categories[i][2],
        'created_at': now,
      });
    }

    const defaults = <String, String>{
      'store_name': 'Jamal Phone',
      'currency': 'دج',
      'theme_mode': 'system',
      'low_stock_threshold': '5',
      'backup_frequency': 'weekly',
      'auto_backup_enabled': 'true',
      'initial_capital': '0',
      'last_backup_at': '',
      'last_backup_status': '',
    };
    for (final entry in defaults.entries) {
      await db.insert('settings', {'key': entry.key, 'value': entry.value});
    }
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_product_date ON stock_movements(product_id, created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_movements_reference ON stock_movements(reference_type, reference_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date_status ON sales(sale_date, status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer_phone ON sales(customer_phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_supplier_date ON purchases(supplier_id, purchase_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receivable_payments_sale ON receivable_payments(sale_id, payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receivable_payments_date_type ON receivable_payments(payment_date, payment_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_date_status ON expenses(expense_date, status)');
  }

  Future<void> _createModernFinanceIndexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_supplier_payments_purchase ON supplier_payments(purchase_id, payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_supplier_payments_supplier ON supplier_payments(supplier_id, payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payment_ledger_date ON payment_ledger(transaction_date, direction)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_payment_ledger_type ON payment_ledger(entry_type, transaction_date)');
    // A ledger row is uniquely identified by its source record. Clean up any
    // duplicate rows left by a pre-v10 database before enforcing that rule.
    await db.execute('''
      DELETE FROM payment_ledger
      WHERE id NOT IN (
        SELECT MIN(id)
        FROM payment_ledger
        GROUP BY source_table, source_id
      )
    ''');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_ledger_source ON payment_ledger(source_table, source_id)');
  }

  Future<void> _createIntegrityTriggers(Database db) async {
    final triggerSql = <String>[
      '''
      CREATE TRIGGER IF NOT EXISTS trg_products_stock_nonnegative_insert
      BEFORE INSERT ON products
      WHEN NEW.stock < 0
      BEGIN
        SELECT RAISE(ABORT, 'المخزون لا يمكن أن يكون سالبًا');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_products_stock_nonnegative_update
      BEFORE UPDATE OF stock ON products
      WHEN NEW.stock < 0
      BEGIN
        SELECT RAISE(ABORT, 'المخزون لا يمكن أن يكون سالبًا');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_stock_movements_consistency
      BEFORE INSERT ON stock_movements
      WHEN NEW.quantity <= 0
        OR NEW.previous_stock < 0
        OR NEW.new_stock < 0
        OR NEW.delta_quantity IS NULL
        OR NEW.delta_quantity = 0
        OR NEW.previous_stock + NEW.delta_quantity <> NEW.new_stock
        OR (SELECT stock FROM products WHERE id = NEW.product_id) <> NEW.new_stock
      BEGIN
        SELECT RAISE(ABORT, 'حركة المخزون غير متسقة مع رصيد المنتج');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_stock_movements_immutable_update
      BEFORE UPDATE ON stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'سجل حركات المخزون غير قابل للتعديل');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_stock_movements_immutable_delete
      BEFORE DELETE ON stock_movements
      BEGIN
        SELECT RAISE(ABORT, 'سجل حركات المخزون غير قابل للحذف');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_payment_ledger_immutable_update
      BEFORE UPDATE ON payment_ledger
      BEGIN
        SELECT RAISE(ABORT, 'سجل المدفوعات غير قابل للتعديل');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_payment_ledger_immutable_delete
      BEFORE DELETE ON payment_ledger
      BEGIN
        SELECT RAISE(ABORT, 'سجل المدفوعات غير قابل للحذف');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_payments_immutable_update
      BEFORE UPDATE ON supplier_payments
      BEGIN
        SELECT RAISE(ABORT, 'سجل دفعات الموردين غير قابل للتعديل');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_supplier_payments_immutable_delete
      BEFORE DELETE ON supplier_payments
      BEGIN
        SELECT RAISE(ABORT, 'سجل دفعات الموردين غير قابل للحذف');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_receivable_payments_immutable_update
      BEFORE UPDATE ON receivable_payments
      BEGIN
        SELECT RAISE(ABORT, 'سجل تحصيلات العملاء غير قابل للتعديل');
      END
      ''',
      '''
      CREATE TRIGGER IF NOT EXISTS trg_receivable_payments_immutable_delete
      BEFORE DELETE ON receivable_payments
      BEGIN
        SELECT RAISE(ABORT, 'سجل تحصيلات العملاء غير قابل للحذف');
      END
      ''',
    ];
    for (final sql in triggerSql) {
      await db.execute(sql);
    }
  }

  Future<bool> _hasColumn(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2 && !(await _hasColumn(db, 'sales', 'status'))) {
      await db.execute("ALTER TABLE sales ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'");
    }

    if (oldVersion < 3) {
      if (!(await _hasColumn(db, 'purchases', 'payment_method'))) {
        await db.execute("ALTER TABLE purchases ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'");
      }
      if (!(await _hasColumn(db, 'sales', 'paid_amount'))) {
        await db.execute('ALTER TABLE sales ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
      }
      if (!(await _hasColumn(db, 'sales', 'due_date'))) {
        await db.execute('ALTER TABLE sales ADD COLUMN due_date TEXT');
      }
      await db.execute('''
        CREATE TABLE IF NOT EXISTS receivable_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          sale_id INTEGER NOT NULL,
          amount REAL NOT NULL,
          payment_date TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
        )
      ''');
      await db.execute("UPDATE sales SET paid_amount = total WHERE payment_method != 'credit' AND paid_amount = 0");
    }

    if (oldVersion < 4) {
      await db.insert('settings', {'key': 'backup_frequency', 'value': 'weekly'}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('settings', {'key': 'auto_backup_enabled', 'value': 'true'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 5) {
      if (!(await _hasColumn(db, 'purchases', 'paid_amount'))) {
        await db.execute('ALTER TABLE purchases ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
      }
      if (!(await _hasColumn(db, 'purchases', 'due_date'))) {
        await db.execute('ALTER TABLE purchases ADD COLUMN due_date TEXT');
      }
    }

    if (oldVersion < 6) {
      await _createIndexes(db);
      await db.insert('settings', {'key': 'last_backup_at', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('settings', {'key': 'last_backup_status', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    if (oldVersion < 7) {
      if (!(await _hasColumn(db, 'expenses', 'status'))) {
        await db.execute("ALTER TABLE expenses ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
      }
      if (!(await _hasColumn(db, 'receivable_payments', 'payment_type'))) {
        await db.execute("ALTER TABLE receivable_payments ADD COLUMN payment_type TEXT NOT NULL DEFAULT 'collection'");
      }
      await db.execute('''
        INSERT INTO receivable_payments (sale_id, amount, payment_type, payment_date, note, created_at)
        SELECT s.id, s.paid_amount, 'collection', s.sale_date, 'ترحيل تلقائي من نسخة قاعدة بيانات قديمة', s.sale_date
        FROM sales s
        WHERE s.status = 'completed'
          AND s.paid_amount > 0
          AND NOT EXISTS (SELECT 1 FROM receivable_payments rp WHERE rp.sale_id = s.id)
      ''');
    }

    if (oldVersion < 8) {
      if (!(await _hasColumn(db, 'stock_movements', 'delta_quantity'))) {
        await db.execute('ALTER TABLE stock_movements ADD COLUMN delta_quantity INTEGER');
      }
      if (!(await _hasColumn(db, 'stock_movements', 'reason_code'))) {
        await db.execute('ALTER TABLE stock_movements ADD COLUMN reason_code TEXT');
      }
      await db.execute('''
        UPDATE stock_movements
        SET delta_quantity = CASE
          WHEN type IN ('in', 'return', 'opening') THEN ABS(quantity)
          WHEN type = 'out' THEN -ABS(quantity)
          WHEN type = 'adjust' THEN new_stock - previous_stock
          ELSE new_stock - previous_stock
        END
        WHERE delta_quantity IS NULL
      ''');
      final legacyProducts = await db.rawQuery('''
        SELECT p.id, p.stock
        FROM products p
        WHERE p.stock > 0
          AND NOT EXISTS (SELECT 1 FROM stock_movements sm WHERE sm.product_id = p.id)
      ''');
      final migratedAt = DateTime.now().toIso8601String();
      for (final row in legacyProducts) {
        final stock = (row['stock'] as num?)?.toInt() ?? 0;
        if (stock <= 0) continue;
        await db.insert('stock_movements', {
          'product_id': row['id'],
          'type': 'opening',
          'quantity': stock,
          'previous_stock': 0,
          'new_stock': stock,
          'reference_type': 'migration',
          'reference_id': null,
          'notes': 'تسوية رصيد قديم أثناء ترقية قاعدة البيانات',
          'created_at': migratedAt,
          'delta_quantity': stock,
          'reason_code': 'legacy_reconciliation',
        });
      }
    }

    if (oldVersion < 9) {
      await _createModernFinanceTables(db);
    }
    await _createModernFinanceIndexes(db);

    if (oldVersion < 10) {
      // Backfill the unified payment ledger from all legacy money movements.
      final receivableRows = await db.query('receivable_payments');
      for (final row in receivableRows) {
        final id = row['id'] as int;
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        final type = row['payment_type'] as String? ?? 'collection';
        final refund = type == 'refund';
        await db.insert(
          'payment_ledger',
          {
            'direction': refund ? 'out' : 'in',
            'entry_type': refund ? 'sale_refund' : 'sale_payment',
            'amount': amount,
            'payment_method': 'cash',
            'source_table': 'receivable_payments',
            'source_id': id,
            'reference_type': 'sale',
            'reference_id': row['sale_id'],
            'note': row['note'],
            'transaction_date': row['payment_date'],
            'created_at': row['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final purchases = await db.query('purchases');
      for (final row in purchases) {
        final id = row['id'] as int;
        final amount = (row['paid_amount'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        final exists = await db.query(
          'supplier_payments',
          columns: ['id'],
          where: 'purchase_id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (exists.isNotEmpty) continue;
        final paymentId = await db.insert('supplier_payments', {
          'supplier_id': row['supplier_id'],
          'purchase_id': id,
          'amount': amount,
          'payment_method': row['payment_method'] ?? 'cash',
          'payment_date': row['purchase_date'],
          'note': 'ترحيل دفعة شراء قديمة',
          'created_at': row['created_at'],
        });
        await db.insert(
          'payment_ledger',
          {
            'direction': 'out',
            'entry_type': 'supplier_payment',
            'amount': amount,
            'payment_method': row['payment_method'] ?? 'cash',
            'source_table': 'supplier_payments',
            'source_id': paymentId,
            'reference_type': 'purchase',
            'reference_id': id,
            'note': 'ترحيل دفعة شراء قديمة',
            'transaction_date': row['purchase_date'],
            'created_at': row['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final expenses = await db.query('expenses', where: "status = 'active'");
      for (final row in expenses) {
        final id = row['id'] as int;
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        await db.insert(
          'payment_ledger',
          {
            'direction': 'out',
            'entry_type': 'expense',
            'amount': amount,
            'payment_method': 'cash',
            'source_table': 'expenses',
            'source_id': id,
            'reference_type': 'expense',
            'reference_id': id,
            'note': row['notes'],
            'transaction_date': row['expense_date'],
            'created_at': row['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final capitalRows = await db.query('capital_transactions');
      for (final row in capitalRows) {
        final id = row['id'] as int;
        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
        if (amount <= 0) continue;
        final contribution = row['type'] == 'contribution';
        await db.insert(
          'payment_ledger',
          {
            'direction': contribution ? 'in' : 'out',
            'entry_type': contribution ? 'capital_in' : 'capital_out',
            'amount': amount,
            'payment_method': 'cash',
            'source_table': 'capital_transactions',
            'source_id': id,
            'reference_type': 'capital',
            'reference_id': id,
            'note': row['description'],
            'transaction_date': row['transaction_date'],
            'created_at': row['created_at'],
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      final initialRows = await db.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['initial_capital'],
        limit: 1,
      );
      final initial = initialRows.isEmpty
          ? 0.0
          : double.tryParse(initialRows.first['value'] as String? ?? '') ?? 0;
      if (initial > 0) {
        await db.insert(
          'payment_ledger',
          {
            'direction': 'in',
            'entry_type': 'initial_capital',
            'amount': initial,
            'payment_method': 'cash',
            'source_table': 'settings_initial_capital',
            'source_id': 1,
            'reference_type': 'settings',
            'reference_id': null,
            'note': 'رأس المال الأولي',
            'transaction_date': DateTime.now().toIso8601String(),
            'created_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    await _createIndexes(db);
    await _createModernFinanceIndexes(db);
    await _createIntegrityTriggers(db);
  }

  Future<String> getDatabasePath() async {
    if (_databasePathOverride != null) return _databasePathOverride!;
    return join(await _factory.getDatabasesPath(), 'jamal_phone.db');
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final db = await database;
    return db.transaction(action);
  }

  Future<bool> validateDatabaseFile(String path) async {
    final db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: true,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
          await database.execute('PRAGMA busy_timeout = 5000');
        },
      ),
    );
    try {
      final result = await db.rawQuery('PRAGMA quick_check');
      final value = result.isEmpty ? null : result.first.values.first;
      return value == 'ok';
    } finally {
      await db.close();
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }

  Future<void> deleteDatabase() async {
    final path = await getDatabasePath();
    await _factory.deleteDatabase(path);
    _database = null;
  }
}
