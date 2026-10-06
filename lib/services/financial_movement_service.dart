import 'package:sqflite/sqflite.dart';

import '../utils/money.dart';

class FinancialMovementService {
  const FinancialMovementService._();

  static Future<void> record(
    DatabaseExecutor executor, {
    required String direction,
    required num amount,
    required String method,
    required String movementType,
    required String sourceType,
    required int sourceId,
    required String createdAt,
    String? referenceType,
    int? referenceId,
    String? note,
  }) async {
    final normalizedAmount = normalizeMoney(amount);
    if (direction != 'in' && direction != 'out') {
      throw ArgumentError.value(direction, 'direction');
    }
    if (normalizedAmount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Amount must be greater than zero',
      );
    }
    await executor.insert('financial_movements', {
      'direction': direction,
      'amount': normalizedAmount,
      'method': method,
      'movement_type': movementType,
      'reference_type': referenceType,
      'reference_id': referenceId,
      'source_type': sourceType,
      'source_id': sourceId,
      'note': note,
      'created_at': createdAt,
    });
  }
}
