import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import 'backup_service.dart';
import 'report_service.dart';
import 'settings_service.dart';

class TelegramService {
  static const _tokenKey = 'jamal_telegram_bot_token';
  static const _chatKey = 'jamal_telegram_chat_id';
  final SettingsService _settings = SettingsService();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final BackupService _backup = BackupService();
  final ReportService _reports = ReportService();

  Future<bool> hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<bool> hasCredentials() async {
    final token = await _secure.read(key: _tokenKey);
    final chat = await _secure.read(key: _chatKey);
    return token != null && token.isNotEmpty && chat != null && chat.isNotEmpty;
  }

  Future<void> migrateLegacyCredentials() async {
    final token = await _secure.read(key: _tokenKey);
    final chat = await _secure.read(key: _chatKey);
    if (token != null && chat != null && token.isNotEmpty && chat.isNotEmpty) return;
    final legacyToken = await _settings.get('telegram_bot_token');
    final legacyChat = await _settings.get('telegram_chat_id');
    if (legacyToken != null && legacyToken.isNotEmpty) await _secure.write(key: _tokenKey, value: legacyToken);
    if (legacyChat != null && legacyChat.isNotEmpty) await _secure.write(key: _chatKey, value: legacyChat);
    if ((legacyToken ?? '').isNotEmpty || (legacyChat ?? '').isNotEmpty) {
      await _settings.set('telegram_bot_token', '');
      await _settings.set('telegram_chat_id', '');
    }
  }

  Future<Map<String, String>> getCredentialsState() async {
    final token = await _secure.read(key: _tokenKey);
    final chat = await _secure.read(key: _chatKey);
    return {'token': token ?? '', 'chatId': chat ?? ''};
  }

  Future<void> saveCredentials({required String token, required String chatId}) async {
    final cleanToken = token.trim();
    final cleanChat = chatId.trim();
    if (cleanToken.isEmpty || cleanChat.isEmpty) throw Exception('أدخل Bot Token و Chat ID');
    await _secure.write(key: _tokenKey, value: cleanToken);
    await _secure.write(key: _chatKey, value: cleanChat);
    await _settings.set('telegram_bot_token', '');
    await _settings.set('telegram_chat_id', '');
  }

  Future<String> _token() async => (await _secure.read(key: _tokenKey)) ?? '';
  Future<String> _chatId() async => (await _secure.read(key: _chatKey)) ?? '';

  Future<void> sendMessage(String text, {bool queueIfOffline = true}) async {
    final token = await _token();
    final chatId = await _chatId();
    if (token.isEmpty || chatId.isEmpty) throw Exception('إعدادات تيليجرام غير مكتملة');
    if (!await hasInternet()) {
      if (queueIfOffline) await _queueTask('message', text);
      throw Exception('لا يوجد اتصال بالإنترنت؛ تم حفظ المهمة للمحاولة لاحقًا');
    }
    try {
      final response = await http.post(
        Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
        body: {'chat_id': chatId, 'text': text},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        if (queueIfOffline && response.statusCode >= 500) {
          await _queueTask('message', text);
        }
        throw Exception('فشل إرسال الرسالة: ${response.body}');
      }
    } on SocketException {
      if (queueIfOffline) await _queueTask('message', text);
      rethrow;
    } on TimeoutException {
      if (queueIfOffline) await _queueTask('message', text);
      throw Exception('انتهت مهلة إرسال الرسالة؛ تم حفظ المهمة للمحاولة لاحقًا');
    }
  }

  Future<void> sendDocument(String filePath, {String? caption, bool queueIfOffline = true}) async {
    final token = await _token();
    final chatId = await _chatId();
    if (token.isEmpty || chatId.isEmpty) throw Exception('إعدادات تيليجرام غير مكتملة');
    final file = File(filePath);
    if (!await file.exists()) throw Exception('ملف النسخة غير موجود');
    if (!await hasInternet()) {
      if (queueIfOffline) await _queueTask('document', jsonEncode({'path': filePath, 'caption': caption}));
      throw Exception('لا يوجد اتصال بالإنترنت؛ تم حفظ المهمة للمحاولة لاحقًا');
    }
    try {
      final request = http.MultipartRequest('POST', Uri.parse('https://api.telegram.org/bot$token/sendDocument'));
      request.fields['chat_id'] = chatId;
      if (caption != null && caption.isNotEmpty) request.fields['caption'] = caption;
      request.files.add(await http.MultipartFile.fromPath('document', filePath));
      final response = await request.send().timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        if (queueIfOffline && response.statusCode >= 500) {
          await _queueTask('document', jsonEncode({'path': filePath, 'caption': caption}));
        }
        throw Exception('فشل إرسال الملف: $body');
      }
    } on SocketException {
      if (queueIfOffline) {
        await _queueTask('document', jsonEncode({'path': filePath, 'caption': caption}));
      }
      rethrow;
    } on TimeoutException {
      if (queueIfOffline) {
        await _queueTask('document', jsonEncode({'path': filePath, 'caption': caption}));
      }
      throw Exception('انتهت مهلة إرسال الملف؛ تم حفظ المهمة للمحاولة لاحقًا');
    }
  }

  Future<void> sendScheduledBackup() async {
    await migrateLegacyCredentials();

    // A scheduled backup is useful even before Telegram is configured.
    // Always create the encrypted local backup first, then optionally send it.
    final backupPath = await _backup.createBackup();
    final frequency = await _settings.get('backup_frequency') ?? 'weekly';
    final days = frequency == 'monthly' ? 30 : 7;
    final report = await _reports.buildTextReport(days: days);

    if (!await hasCredentials()) {
      await _settings.set('last_backup_at', DateTime.now().toIso8601String());
      await _settings.set('last_backup_status', 'local_only');
      return;
    }

    try {
      await sendDocument(backupPath, queueIfOffline: true);
      await sendMessage(report, queueIfOffline: true);
      await _settings.set('last_backup_at', DateTime.now().toIso8601String());
      await _settings.set('last_backup_status', 'sent');
    } catch (_) {
      await _settings.set('last_backup_at', DateTime.now().toIso8601String());
      await _settings.set('last_backup_status', 'local_only');
      rethrow;
    }
  }

  Future<void> sendBackupWithReport() => sendScheduledBackup();

  Future<void> _queueTask(String type, String payload) async {
    final db = await _db.database;
    await db.insert('pending_telegram', {
      'type': type,
      'payload': payload,
      'created_at': DateTime.now().toIso8601String(),
      'retries': 0,
    });
  }

  Future<void> processPending() async {
    if (!await hasInternet() || !await hasCredentials()) return;
    final db = await _db.database;
    final tasks = await db.query('pending_telegram', orderBy: 'created_at ASC');
    for (final task in tasks) {
      final id = task['id'] as int;
      final retries = (task['retries'] as num?)?.toInt() ?? 0;
      try {
        final type = task['type'];
        if (type == 'message') {
          await sendMessage(task['payload'] as String, queueIfOffline: false);
        } else if (type == 'document') {
          final data = jsonDecode(task['payload'] as String) as Map;
          await sendDocument(data['path'] as String, caption: data['caption'] as String?, queueIfOffline: false);
        }
        await db.delete('pending_telegram', where: 'id = ?', whereArgs: [id]);
      } catch (_) {
        final next = retries + 1;
        if (next >= 8) {
          await db.delete('pending_telegram', where: 'id = ?', whereArgs: [id]);
        } else {
          final path = task['type'] == 'document'
              ? (() {
                  try {
                    final data = jsonDecode(task['payload'] as String) as Map;
                    return data['path']?.toString();
                  } catch (_) {
                    return null;
                  }
                })()
              : null;
          if (path != null && !await File(path).exists()) {
            await db.delete('pending_telegram', where: 'id = ?', whereArgs: [id]);
          } else {
            await db.update('pending_telegram', {'retries': next}, where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    }
  }
}
