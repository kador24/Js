import '../models/category.dart';
import '../repositories/store_repository.dart';

class CategoryService {
  CategoryService({StoreRepository? repository}) : _repo = repository ?? StoreRepository();

  final StoreRepository _repo;

  Future<List<Category>> getAll() async {
    final db = await _repo.db;
    final result = await db.query('categories', orderBy: 'name_ar ASC');
    return result.map(Category.fromMap).toList();
  }

  Future<int> insert(Category category) async {
    final db = await _repo.db;
    return db.insert('categories', category.toMap()..remove('id'));
  }

  Future<int> update(Category category) async {
    final db = await _repo.db;
    return db.update('categories', category.toMap()..remove('id'), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<int> delete(int id) async {
    final db = await _repo.db;
    return db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
