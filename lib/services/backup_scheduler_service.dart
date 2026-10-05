import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';
import 'settings_service.dart';
import 'telegram_service.dart';

const _taskName = 'jamal_phone_periodic_backup';
const _uniqueName = 'jamal_phone_periodic_backup_unique';

@pragma('vm:entry-point')
void jamalBackgroundTaskDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final settings = SettingsService();
      final enabled = (await settings.get('auto_backup_enabled')) != 'false';
      if (!enabled) return true;
      final telegram = TelegramService();
      await telegram.processPending();
      await telegram.sendScheduledBackup();
      return true;
    } catch (_) {
      return false;
    }
  });
}

class BackupSchedulerService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(jamalBackgroundTaskDispatcher, isInDebugMode: false);
    _initialized = true;
  }

  static Future<void> schedule({required bool enabled, required String frequency}) async {
    await initialize();
    await Workmanager().cancelByUniqueName(_uniqueName);
    if (!enabled) return;
    final duration = frequency == 'monthly' ? const Duration(days: 30) : const Duration(days: 7);
    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: duration,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      constraints: const Constraints(networkType: NetworkType.connected),
    );
  }
}
