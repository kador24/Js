import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../database/database_helper.dart';

class BackupService {
  BackupService({
    DatabaseHelper? database,
    FlutterSecureStorage? secureStorage,
    Directory? backupDirectory,
    Directory? productImagesDirectory,
    List<int>? testMasterKey,
  })  : _db = database ?? DatabaseHelper.instance,
        _secure = secureStorage ?? const FlutterSecureStorage(),
        _backupDirectoryOverride = backupDirectory,
        _productImagesDirectoryOverride = productImagesDirectory,
        _testMasterKey = testMasterKey;

  static const _keyName = 'jamal_backup_master_key_v1';
  static const _format = 'JPM-ENCRYPTED-1';
  static const _dataFormat = 'JPM-DATA-2';
  static const _version = 2;
  final AesGcm _aes = AesGcm.with256bits();

  final DatabaseHelper _db;
  final FlutterSecureStorage _secure;
  final Directory? _backupDirectoryOverride;
  final Directory? _productImagesDirectoryOverride;
  final List<int>? _testMasterKey;

  Future<List<int>> _getOrCreateKey() async {
    if (_testMasterKey != null) return List<int>.unmodifiable(_testMasterKey!);
    final saved = await _secure.read(key: _keyName);
    if (saved != null && saved.isNotEmpty) {
      try {
        final decoded = base64Url.decode(saved);
        if (decoded.length == 32) return decoded;
      } catch (_) {
        // Generate a fresh key only when the secure entry is invalid.
      }
    }
    final secret = await _aes.newSecretKey();
    final bytes = await secret.extractBytes();
    await _secure.write(key: _keyName, value: base64UrlEncode(bytes));
    return bytes;
  }

  Future<String> getRecoveryKey() async =>
      base64UrlEncode(await _getOrCreateKey());

  Future<void> importRecoveryKey(String key) async {
    try {
      final bytes = base64Url.decode(key.trim());
      if (bytes.length != 32) throw const FormatException();
      await _secure.write(key: _keyName, value: base64UrlEncode(bytes));
    } catch (_) {
      throw Exception('مفتاح الاستعادة غير صحيح');
    }
  }

  Future<Directory> _backupDirectory() async {
    if (_backupDirectoryOverride != null) {
      final dir = _backupDirectoryOverride!;
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(p.join(dir.path, 'backups'));
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    return backupDir;
  }

  Future<Directory> _productImagesDirectory() async {
    if (_productImagesDirectoryOverride != null) {
      final dir = _productImagesDirectoryOverride!;
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final dir = await getApplicationDocumentsDirectory();
    final imageDir = Directory(p.join(dir.path, 'product_images'));
    if (!await imageDir.exists()) await imageDir.create(recursive: true);
    return imageDir;
  }

  Future<List<Map<String, String>>> _collectProductImages() async {
    final dir = await _productImagesDirectory();
    final result = <Map<String, String>>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final bytes = await entity.readAsBytes();
      result.add({
        'path': entity.path,
        'fileName': p.basename(entity.path),
        'data': base64UrlEncode(bytes),
      });
    }
    return result;
  }

  Future<String> createBackup() async {
    final dbPath = await _db.getDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('قاعدة البيانات غير موجودة');
    }

    final db = await _db.database;
    try {
      await db.execute('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {
      // Native SQLite may not use WAL; closing is still sufficient.
    }
    await _db.close();

    final dbBytes = await dbFile.readAsBytes();
    final images = await _collectProductImages();
    final clearPayload = utf8.encode(jsonEncode({
      'format': _dataFormat,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'database': base64UrlEncode(dbBytes),
      'images': images,
    }));

    final compressed = gzip.encode(clearPayload);
    final keyBytes = await _getOrCreateKey();
    final secretBox = await _aes.encrypt(
      compressed,
      secretKey: SecretKey(keyBytes),
    );
    final envelope = <String, dynamic>{
      'format': _format,
      'version': _version,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'data': base64UrlEncode(secretBox.concatenation()),
    };

    final dir = await _backupDirectory();
    final nowUtc = DateTime.now().toUtc();
    final stamp = '${nowUtc.year.toString().padLeft(4, '0')}${nowUtc.month.toString().padLeft(2, '0')}${nowUtc.day.toString().padLeft(2, '0')}_${nowUtc.hour.toString().padLeft(2, '0')}${nowUtc.minute.toString().padLeft(2, '0')}${nowUtc.second.toString().padLeft(2, '0')}${nowUtc.millisecond.toString().padLeft(3, '0')}';
    final path = p.join(dir.path, 'jamal_phone_backup_$stamp.jpm');
    await File(path).writeAsString(jsonEncode(envelope), flush: true);

    final files = (await dir
            .list()
            .where((entity) => entity is File && entity.path.toLowerCase().endsWith('.jpm'))
            .toList())
        .whereType<File>()
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (var i = 5; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
    return path;
  }

  Future<List<File>> listBackups() async {
    final dir = await _backupDirectory();
    final files = (await dir
            .list()
            .where((entity) => entity is File &&
                (entity.path.toLowerCase().endsWith('.jpm') ||
                    entity.path.toLowerCase().endsWith('.db')))
            .toList())
        .whereType<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<Map<String, dynamic>> _decryptEnvelope(
    File source,
    String? recoveryKey,
  ) async {
    final envelope = jsonDecode(await source.readAsString());
    if (envelope is! Map || envelope['format'] != _format) {
      throw Exception('صيغة النسخة المشفرة غير مدعومة');
    }
    final encoded = envelope['data'] as String?;
    if (encoded == null || encoded.isEmpty) throw Exception('بيانات النسخة ناقصة');

    final keyBytes = recoveryKey == null || recoveryKey.trim().isEmpty
        ? await _getOrCreateKey()
        : _decodeKey(recoveryKey);
    final box = SecretBox.fromConcatenation(
      base64Url.decode(encoded),
      nonceLength: _aes.nonceLength,
      macLength: _aes.macAlgorithm.macLength,
    );
    final decrypted = await _aes.decrypt(box, secretKey: SecretKey(keyBytes));
    final version = (envelope['version'] as num?)?.toInt() ?? 1;

    if (version == 1) {
      return {'databaseBytes': decrypted, 'images': <dynamic>[]};
    }
    if (version != 2) throw Exception('إصدار النسخة غير مدعوم');

    final package = jsonDecode(utf8.decode(gzip.decode(decrypted)));
    if (package is! Map || package['format'] != _dataFormat) {
      throw Exception('بيانات النسخة غير صالحة');
    }
    final encodedDb = package['database'] as String?;
    if (encodedDb == null || encodedDb.isEmpty) {
      throw Exception('قاعدة البيانات غير موجودة داخل النسخة');
    }
    return {
      'databaseBytes': base64Url.decode(encodedDb),
      'images': package['images'] is List ? package['images'] as List : <dynamic>[],
    };
  }

  List<int> _decodeKey(String value) {
    try {
      final bytes = base64Url.decode(value.trim());
      if (bytes.length != 32) throw const FormatException();
      return bytes;
    } catch (_) {
      throw Exception('مفتاح الاستعادة غير صحيح');
    }
  }

  Future<void> _restoreImages(List<dynamic> entries) async {
    final dir = await _productImagesDirectory();
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final pathMap = <String, String>{};
    for (final raw in entries) {
      if (raw is! Map) continue;
      final oldPath = raw['path']?.toString() ?? '';
      final fileName = p.basename(raw['fileName']?.toString() ?? '');
      final encoded = raw['data']?.toString() ?? '';
      if (fileName.isEmpty || encoded.isEmpty) continue;
      try {
        final newPath = p.join(dir.path, fileName);
        await File(newPath).writeAsBytes(base64Url.decode(encoded), flush: true);
        if (oldPath.isNotEmpty) pathMap[oldPath] = newPath;
      } catch (_) {}
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      if (pathMap.isEmpty) {
        await txn.update(
          'products',
          {'image_path': null},
          where: 'image_path LIKE ?',
          whereArgs: [p.join(dir.path, '%')],
        );
        return;
      }
      for (final entry in pathMap.entries) {
        await txn.update(
          'products',
          {'image_path': entry.value},
          where: 'image_path = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  Future<void> restoreBackup(String backupPath, {String? recoveryKey}) async {
    final source = File(backupPath);
    if (!await source.exists()) throw Exception('ملف النسخة الاحتياطية غير موجود');
    final dbPath = await _db.getDatabasePath();
    final tempPath = '$dbPath.restore_tmp';
    List<dynamic> images = const [];
    try {
      late List<int> clear;
      if (backupPath.toLowerCase().endsWith('.jpm')) {
        final package = await _decryptEnvelope(source, recoveryKey);
        clear = package['databaseBytes'] as List<int>;
        images = package['images'] as List<dynamic>? ?? const [];
      } else if (backupPath.toLowerCase().endsWith('.db')) {
        clear = await source.readAsBytes();
      } else {
        throw Exception('صيغة النسخة غير مدعومة');
      }

      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(clear, flush: true);
      final valid = await _db.validateDatabaseFile(tempPath);
      if (!valid) throw Exception('قاعدة البيانات داخل النسخة غير صالحة');
      await _db.close();
      for (final sidecar in <String>['$dbPath-wal', '$dbPath-shm']) {
        final file = File(sidecar);
        if (await file.exists()) {
          try {
            await file.delete();
          } catch (_) {}
        }
      }
      await tempFile.copy(dbPath);
      if (backupPath.toLowerCase().endsWith('.jpm')) {
        await _restoreImages(images);
      }
    } finally {
      final tmp = File(tempPath);
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> shareBackup(String path) async {
    await Share.shareXFiles(
      [XFile(path)],
      text: 'نسخة احتياطية مشفرة - Jamal Phone Manager',
    );
  }

  Future<void> shareRecoveryKey() async {
    await Share.share(
      await getRecoveryKey(),
      subject: 'مفتاح استعادة Jamal Phone Manager',
    );
  }
}
