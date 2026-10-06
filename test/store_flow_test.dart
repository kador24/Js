import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jamal_phone_manager/database/database_helper.dart';
import 'package:jamal_phone_manager/models/expense.dart';
import 'package:jamal_phone_manager/models/product.dart';
import 'package:jamal_phone_manager/services/backup_service.dart';
import 'package:jamal_phone_manager/services/expense_service.dart';
import 'package:jamal_phone_manager/services/financial_service.dart';
import 'package:jamal_phone_manager/services/product_service.dart';
import 'package:jamal_phone_manager/services/purchase_service.dart';
import 'package:jamal_phone_manager/services/sale_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemoryBackupKeyStore implements BackupKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'store ledgers, complete return, partial supplier payment, and encrypted image restore',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final helper = DatabaseHelper.instance;
      await helper.close();
      await helper.deleteDatabase();
      final database = await helper.database;
      await database.update(
        'settings',
        {'value': '3000000'},
        where: 'key = ?',
        whereArgs: ['initial_capital'],
      );

      final documents = await Directory.systemTemp.createTemp(
        'jamal_phone_manager_test_',
      );
      final imageDirectory = Directory('${documents.path}/product_images')
        ..createSync(recursive: true);
      final image = File('${imageDirectory.path}/phone.png')
        ..writeAsBytesSync([1, 2, 3, 4]);
      final backupKeys = _MemoryBackupKeyStore();
      final backupService = BackupService(
        databaseHelper: helper,
        keyStore: backupKeys,
        documentsDirectory: () async => documents,
      );

      try {
        final now = DateTime.now().toIso8601String();
        final products = ProductService();
        final purchases = PurchaseService();
        final sales = SaleService();
        final finances = FinancialService();
        final expenses = ExpenseService();
        final phoneId = await products.insert(
          Product(
            name: 'Phone',
            sellPrice: 215000,
            costPrice: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final phone = await products.getById(phoneId);
        expect(phone, isNotNull);
        await products.update(phone!.copyWith(imagePath: image.path));

        await finances.addCapitalTransaction(
          type: 'contribution',
          amount: 1000,
          description: 'Capital ledger test',
        );
        await finances.addCapitalTransaction(
          type: 'withdrawal',
          amount: 1000,
          description: 'Capital reversal test',
        );

        final purchaseId = await purchases.createPurchase(
          supplierName: 'Main supplier',
          paymentMethod: 'cash',
          items: [
            {'productId': phoneId, 'quantity': 10, 'unitCost': 180000},
          ],
        );
        final purchase = await purchases.getById(purchaseId);
        expect(purchase!.totalAmount, 180000);
        expect(purchase.items.single.quantity, 10);
        expect((await products.getById(phoneId))!.costPrice, 180000);

        final cashSaleId = await sales.createSale(
          items: [
            {'productId': phoneId, 'quantity': 3, 'unitPrice': 215000},
          ],
          paymentMethod: 'cash',
          paymentNote: 'Counter payment note',
        );
        final cashSale = await sales.getById(cashSaleId);
        expect(cashSale!.items.single.unitCost, 180000);
        expect(cashSale.items.single.profit, 105000);
        expect((await products.getById(phoneId))!.stock, 7);

        await sales.returnSale(cashSaleId);
        expect((await sales.getById(cashSaleId))!.isReturned, isTrue);
        expect((await products.getById(phoneId))!.stock, 10);
        final refundRows = await database.query(
          'receivable_payments',
          where: "sale_id = ? AND payment_type = 'refund'",
          whereArgs: [cashSaleId],
        );
        expect(refundRows.single['amount'], 645000);
        expect((await sales.getTodayStats())['sales'], 0);

        await expenses.insert(
          Expense(
            title: 'Shop expense',
            amount: 10000,
            category: 'operating',
            notes: 'Functional scenario expense',
            expenseDate: now,
            createdAt: now,
          ),
        );
        final creditSaleId = await sales.createSale(
          items: [
            {'productId': phoneId, 'quantity': 1, 'unitPrice': 100000},
          ],
          paymentMethod: 'credit',
          initialPayment: 40000,
          dueDate: DateTime.now()
              .add(const Duration(days: 30))
              .toIso8601String(),
          paymentNote: '40,000 paid now',
        );
        final initialPaymentRows = await sales.getReceivablePayments(
          creditSaleId,
        );
        expect(initialPaymentRows.single['note'], '40,000 paid now');
        expect((await sales.getById(creditSaleId))!.paidAmount, 40000);
        expect((await finances.getSummary())['receivables'], 60000);
        expect((await products.getById(phoneId))!.stock, 9);
        await sales.recordReceivablePayment(
          creditSaleId,
          60000,
          paymentMethod: 'transfer',
          note: '60,000 collected later',
        );
        expect((await sales.getById(creditSaleId))!.remainingAmount, 0);

        final accessoryId = await products.insert(
          Product(
            name: 'Accessory',
            sellPrice: 20,
            costPrice: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final payablePurchaseId = await purchases.createPurchase(
          supplierName: 'Partial payment supplier',
          paymentMethod: 'credit',
          paidAmount: 0,
          dueDate: DateTime.now()
              .add(const Duration(days: 30))
              .toIso8601String(),
          items: [
            {'productId': accessoryId, 'quantity': 2, 'unitCost': 10},
          ],
        );
        await purchases.recordSupplierPayment(
          payablePurchaseId,
          5,
          paymentMethod: 'card',
          note: 'First supplier installment',
        );
        expect(
          (await purchases.getById(payablePurchaseId))!.remainingAmount,
          15,
        );
        expect((await finances.getSummary())['supplierPayables'], 15);
        final supplierPayments = await purchases.getPayments(payablePurchaseId);
        expect(supplierPayments.single['note'], 'First supplier installment');
        await purchases.recordSupplierPayment(
          payablePurchaseId,
          15,
          paymentMethod: 'transfer',
          note: 'Final supplier installment',
        );
        expect(
          (await purchases.getById(payablePurchaseId))!.remainingAmount,
          0,
        );
        await expectLater(
          products.setStock(phoneId, -1, notes: 'Invalid negative count'),
          throwsException,
        );
        expect((await products.getById(phoneId))!.stock, 9);

        final movements = await database.query('stock_movements');
        expect(movements.length, 5);
        final financialMovements = await database.query('financial_movements');
        expect(financialMovements.length, greaterThanOrEqualTo(9));

        final rangeStart = DateTime.now().subtract(const Duration(days: 2));
        final rangeEnd = DateTime.now().add(const Duration(days: 2));
        final summary = await finances.getSummary(
          from: rangeStart,
          to: rangeEnd,
        );
        expect(summary['initialCapital'], 3000000);
        expect(summary['cashBalance'], 1289980);
        expect(summary['sales'], 100000);
        expect(summary['grossProfit'], -80000);
        expect(summary['expenses'], 10000);
        expect(summary['netProfit'], -90000);
        expect(summary['receivables'], 0);
        expect(summary['supplierPayables'], 0);
        expect(summary['inventoryValue'], 1620020);

        final backupPath = await backupService.createBackup();
        expect(await File(backupPath).exists(), isTrue);
        await image.writeAsBytes([9, 9, 9]);
        await products.setStock(phoneId, 99, notes: 'Post-backup mutation');
        await backupService.restoreBackup(backupPath);

        final restoredPhone = await products.getById(phoneId);
        expect(restoredPhone!.stock, 9);
        expect(restoredPhone.imagePath, isNotNull);
        expect(await File(restoredPhone.imagePath!).readAsBytes(), [
          1,
          2,
          3,
          4,
        ]);
        final restoredSummary = await finances.getSummary(
          from: rangeStart,
          to: rangeEnd,
        );
        expect(restoredSummary['cashBalance'], 1289980);
        expect(restoredSummary['receivables'], 0);
        expect(restoredSummary['supplierPayables'], 0);
        expect((await helper.database).isOpen, isTrue);

        final averageCostProductId = await products.insert(
          Product(
            name: 'Weighted average test',
            sellPrice: 300,
            costPrice: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final secondProductId = await products.insert(
          Product(
            name: 'Second line test',
            sellPrice: 60,
            costPrice: 0,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final multiLinePurchaseId = await purchases.createPurchase(
          paymentMethod: 'cash',
          items: [
            {'productId': averageCostProductId, 'quantity': 1, 'unitCost': 100},
            {'productId': averageCostProductId, 'quantity': 1, 'unitCost': 200},
            {'productId': secondProductId, 'quantity': 1, 'unitCost': 50},
          ],
        );
        expect((await products.getById(averageCostProductId))!.costPrice, 150);
        expect((await purchases.getById(multiLinePurchaseId))!.items.length, 3);
      } finally {
        await helper.close();
        await documents.delete(recursive: true);
        await helper.deleteDatabase();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
