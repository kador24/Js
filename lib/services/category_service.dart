import '../database/database_helper.dart';
import '../models/category.dart';

class CategoryService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<Category>> getAll() async {
    final db = await _db.database;
    final result = await db.query('categories', orderBy: 'name_ar ASC');
    return result.map((e) => Category.fromMap(e)).toList();
  }

  Future<int> insert(Category category) async {
    final db = await _db.database;
    return await db.insert('categories', category.toMap()..remove('id'));
  }

  Future<int> update(Category category) async {
    final db = await _db.database;
    return await db.update('categories', category.toMap()..remove('id'), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
