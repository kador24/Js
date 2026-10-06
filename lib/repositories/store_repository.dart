import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

class StoreRepository {
  StoreRepository({DatabaseHelper? database})
      : _database = database ?? DatabaseHelper.instance;

  final DatabaseHelper _database;

  Future<Database> get db => _database.database;

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) =>
      _database.transaction(action);

  Future<String> getDatabasePath() => _database.getDatabasePath();

  Future<void> close() => _database.close();
}
