import 'package:flutter/material.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../repositories/store_repository.dart';
import '../services/backup_scheduler_service.dart';
import '../services/backup_service.dart';
import '../services/category_service.dart';
import '../services/expense_service.dart';
import '../services/financial_service.dart';
import '../services/product_service.dart';
import '../services/purchase_service.dart';
import '../services/report_service.dart';
import '../services/sale_service.dart';
import '../services/settings_service.dart';
import '../services/supplier_service.dart';
import '../services/telegram_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider() {
    _settings = SettingsService(repository: _repository);
    _products = ProductService(repository: _repository);
    _sales = SaleService(repository: _repository);
    _purchases = PurchaseService(repository: _repository);
    _suppliers = SupplierService(repository: _repository);
    _categories = CategoryService(repository: _repository);
    _financial = FinancialService(repository: _repository);
    _reports = ReportService(repository: _repository);
    _expenses = ExpenseService(repository: _repository);
    _backup = BackupService();
    _telegram = TelegramService();
  }

  final StoreRepository _repository = StoreRepository();
  late final SettingsService _settings;
  late final ProductService _products;
  late final SaleService _sales;
  late final PurchaseService _purchases;
  late final SupplierService _suppliers;
  late final CategoryService _categories;
  late final FinancialService _financial;
  late final ReportService _reports;
  late final ExpenseService _expenses;
  late final BackupService _backup;
  late final TelegramService _telegram;

  ThemeMode _themeMode = ThemeMode.system;
  String _currency = 'دج';
  String _storeName = 'Jamal Phone';
  bool _loading = false;
  String? _error;

  List<Product> products = [];
  List<Category> categories = [];
  List<Sale> recentSales = [];
  Map<String, double> todayStats = {'sales': 0, 'profit': 0, 'count': 0};
  Map<String, double> financialSummary = {};
  double inventoryValue = 0;
  List<Product> lowStockProducts = [];
  List<Map<String, dynamic>> topSelling = [];
  List<Map<String, dynamic>> salesChart = [];

  ThemeMode get themeMode => _themeMode;
  String get currency => _currency;
  String get storeName => _storeName;
  bool get loading => _loading;
  String? get error => _error;
  double get initialCapital => financialSummary['initialCapital'] ?? 0;
  double get currentCapital => financialSummary['currentCapital'] ?? 0;
  double get cashBalance => financialSummary['cashBalance'] ?? 0;
  double get receivables => financialSummary['receivables'] ?? 0;
  double get supplierPayables => financialSummary['supplierPayables'] ?? 0;
  double get netProfit => financialSummary['netProfit'] ?? 0;
  bool get autoBackupEnabled => _autoBackupEnabled;
  String get backupFrequency => _backupFrequency;
  ProductService get productsService => _products;
  SaleService get salesService => _sales;
  PurchaseService get purchasesService => _purchases;
  SupplierService get suppliersService => _suppliers;
  CategoryService get categoriesService => _categories;
  FinancialService get financialService => _financial;
  ReportService get reportsService => _reports;
  ExpenseService get expensesService => _expenses;
  BackupService get backupService => _backup;
  TelegramService get telegramService => _telegram;
  StoreRepository get repository => _repository;

  bool _autoBackupEnabled = true;
  String _backupFrequency = 'weekly';

  Future<void> init() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final settings = await _settings.getAll();
      _currency = settings['currency'] ?? 'دج';
      _storeName = settings['store_name'] ?? 'Jamal Phone';
      final theme = settings['theme_mode'] ?? 'system';
      _themeMode = theme == 'dark' ? ThemeMode.dark : theme == 'light' ? ThemeMode.light : ThemeMode.system;
      _autoBackupEnabled = settings['auto_backup_enabled'] != 'false';
      _backupFrequency = settings['backup_frequency'] ?? 'weekly';
      await _telegram.migrateLegacyCredentials();
      await refreshDashboard();
      await _applyBackupSchedule(settings);
      await _telegram.processPending();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _applyBackupSchedule(Map<String, String>? values) async {
    final settings = values ?? await _settings.getAll();
    await BackupSchedulerService.schedule(
      enabled: settings['auto_backup_enabled'] != 'false',
      frequency: settings['backup_frequency'] ?? 'weekly',
    );
  }

  Future<void> refreshDashboard() async {
    todayStats = await _sales.getTodayStats();
    financialSummary = await _financial.getSummary();
    inventoryValue = await _products.getInventoryValue();
    lowStockProducts = await _products.getLowStock();
    topSelling = await _products.getTopSelling();
    salesChart = await _sales.getSalesChart();
    recentSales = await _sales.getAll();
    if (recentSales.length > 10) recentSales = recentSales.sublist(0, 10);
    notifyListeners();
  }

  Future<void> loadProducts({String? search, int? categoryId}) async {
    products = await _products.getAll(search: search, categoryId: categoryId);
    notifyListeners();
  }

  Future<void> loadCategories() async {
    categories = await _categories.getAll();
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final value = mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system';
    await _settings.set('theme_mode', value);
    notifyListeners();
  }

  Future<void> updateSetting(String key, String value) async {
    await _settings.set(key, value);
    if (key == 'store_name') _storeName = value;
    if (key == 'currency') _currency = value;
    if (key == 'backup_frequency') _backupFrequency = value;
    if (key == 'auto_backup_enabled') _autoBackupEnabled = value != 'false';
    if (key == 'backup_frequency' || key == 'auto_backup_enabled') {
      await _applyBackupSchedule(null);
    }
    notifyListeners();
  }

  Future<void> setInitialCapital(double value) async {
    if (value < 0) throw Exception('رأس المال لا يمكن أن يكون سالبًا');
    await _settings.setInitialCapital(value);
    await refreshDashboard();
  }

  Future<void> addCapital({required String type, required double amount, String? description}) async {
    await _financial.addCapitalTransaction(type: type, amount: amount, description: description);
    await refreshDashboard();
  }

  String formatMoney(double amount) => '${amount.toStringAsFixed(0)} $_currency';
}
