import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('jamal_phone.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);
    return openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
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

    await _createIndexes(db);
    await _seed(db);
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_date_status ON sales(sale_date, status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer_phone ON sales(customer_phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receivable_payments_sale ON receivable_payments(sale_id, payment_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_receivable_payments_date_type ON receivable_payments(payment_date, payment_type)');
    await db.execute("CREATE INDEX IF NOT EXISTS idx_expenses_date_status ON expenses(expense_date, status)");
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    Future<bool> hasColumn(String table, String column) async {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows.any((row) => row['name'] == column);
    }

    if (oldVersion < 2 && !(await hasColumn('sales', 'status'))) {
      await db.execute("ALTER TABLE sales ADD COLUMN status TEXT NOT NULL DEFAULT 'completed'");
    }
    if (oldVersion < 3) {
      if (!(await hasColumn('purchases', 'payment_method'))) {
        await db.execute("ALTER TABLE purchases ADD COLUMN payment_method TEXT NOT NULL DEFAULT 'cash'");
      }
      if (!(await hasColumn('sales', 'paid_amount'))) {
        await db.execute("ALTER TABLE sales ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0");
      }
      if (!(await hasColumn('sales', 'due_date'))) {
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
      if (!(await hasColumn('purchases', 'paid_amount'))) {
        await db.execute("ALTER TABLE purchases ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0");
      }
      if (!(await hasColumn('purchases', 'due_date'))) {
        await db.execute('ALTER TABLE purchases ADD COLUMN due_date TEXT');
      }
    }
    if (oldVersion < 6) {
      await _createIndexes(db);
      await db.insert('settings', {'key': 'last_backup_at', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('settings', {'key': 'last_backup_status', 'value': ''}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    if (oldVersion < 7) {
      if (!(await hasColumn('expenses', 'status'))) {
        await db.execute("ALTER TABLE expenses ADD COLUMN status TEXT NOT NULL DEFAULT 'active'");
      }
      if (!(await hasColumn('receivable_payments', 'payment_type'))) {
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
      await _createIndexes(db);
    }
  }

  Future<String> getDatabasePath() async {
    final dbPath = await getDatabasesPath();
    return join(dbPath, 'jamal_phone.db');
  }

  Future<void> close() async {
    final db = _database;
    if (db == null) return;
    await db.close();
    _database = null;
  }

  Future<void> deleteDatabase() async {
    final path = await getDatabasePath();
    await databaseFactory.deleteDatabase(path);
    _database = null;
  }
}
