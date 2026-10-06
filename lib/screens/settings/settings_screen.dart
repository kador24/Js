import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/category.dart';
import '../../models/expense.dart';
import '../../providers/app_provider.dart';
import '../../theme/app_theme.dart';
import '../inventory/stock_movements_screen.dart';
import '../reports/reports_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _editText(String title, String current, Future<void> Function(String) save) async {
    final ctrl = TextEditingController(text: current);
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextField(controller: ctrl, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ'))]));
    ctrl.dispose();
    if (value != null && value.trim().isNotEmpty) await save(value.trim());
  }

  Future<void> _editNumber(String title, double current, Future<void> Function(double) save) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true)), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('حفظ'))]));
    ctrl.dispose();
    final number = value == null ? null : double.tryParse(value.replaceAll(',', ''));
    if (number != null && number >= 0) {
      try {
        await save(number);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _manageCategories() async {
    while (mounted) {
      final list = await context.read<AppProvider>().categoriesService.getAll();
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: Column(children: [ListTile(title: const Text('التصنيفات', style: TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(onPressed: () => Navigator.pop(ctx, 'add'), icon: const Icon(Icons.add))), Expanded(child: ListView.builder(itemCount: list.length, itemBuilder: (_, i) => ListTile(leading: const Icon(Icons.category), title: Text(list[i].nameAr))))])));
      if (action != 'add') return;
      final ctrl = TextEditingController();
      final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('تصنيف جديد'), content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'الاسم')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('إضافة'))]));
      ctrl.dispose();
      if (name != null && name.trim().isNotEmpty) {
        await context.read<AppProvider>().categoriesService.insert(Category(nameAr: name.trim(), createdAt: DateTime.now().toIso8601String()));
        await context.read<AppProvider>().loadCategories();
      }
    }
  }

  Future<void> _addExpense() async {
    final title = TextEditingController();
    final amount = TextEditingController();
    final category = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('مصروف جديد'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')), const SizedBox(height: 10), TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')), const SizedBox(height: 10), TextField(controller: category, decoration: const InputDecoration(labelText: 'التصنيف (اختياري)'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))]));
    final parsed = double.tryParse(amount.text.replaceAll(',', ''));
    if (ok == true && title.text.trim().isNotEmpty && parsed != null && parsed > 0) {
      final now = DateTime.now().toIso8601String();
      await context.read<AppProvider>().expensesService.insert(Expense(title: title.text.trim(), amount: parsed, category: category.text.trim().isEmpty ? null : category.text.trim(), expenseDate: now, createdAt: now));
      await context.read<AppProvider>().refreshDashboard();
    }
    title.dispose(); amount.dispose(); category.dispose();
  }

  Future<void> _listExpenses() async {
    final list = await context.read<AppProvider>().expensesService.getAll();
    if (!mounted) return;
    await showModalBottomSheet(context: context, builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .7, child: Column(children: [const Padding(padding: EdgeInsets.all(16), child: Text('المصاريف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))), Expanded(child: list.isEmpty ? const Center(child: Text('لا توجد مصاريف')) : ListView.builder(itemCount: list.length, itemBuilder: (_, i) => ListTile(title: Text(list[i].title), subtitle: Text(list[i].expenseDate.substring(0, 10)), trailing: Text('${list[i].amount.toStringAsFixed(0)} دج', style: const TextStyle(color: AppTheme.dangerColor, fontWeight: FontWeight.bold)))))])));
  }

  Future<void> _capitalTransaction() async {
    String type = 'contribution';
    final amount = TextEditingController();
    final description = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => AlertDialog(title: const Text('حركة رأس المال'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: type, items: const [DropdownMenuItem(value: 'contribution', child: Text('إضافة رأس مال')), DropdownMenuItem(value: 'withdrawal', child: Text('سحب من رأس المال'))], onChanged: (v) => setModal(() => type = v ?? 'contribution')), const SizedBox(height: 10), TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'المبلغ')), const SizedBox(height: 10), TextField(controller: description, decoration: const InputDecoration(labelText: 'الوصف'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))])));
    final parsed = double.tryParse(amount.text.replaceAll(',', ''));
    if (ok == true && parsed != null && parsed > 0) {
      try { await context.read<AppProvider>().financialService.addCapitalTransaction(type: type, amount: parsed, description: description.text.trim().isEmpty ? null : description.text.trim()); await context.read<AppProvider>().refreshDashboard(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    }
    amount.dispose(); description.dispose();
  }

  Future<void> _telegramSettings() async {
    final state = await context.read<AppProvider>().telegramService.getCredentialsState();
    final token = TextEditingController(text: state['token']);
    final chat = TextEditingController(text: state['chatId']);
    final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('إعدادات تيليجرام'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'Bot Token')), const SizedBox(height: 10), TextField(controller: chat, decoration: const InputDecoration(labelText: 'Chat ID')), const SizedBox(height: 8), const Text('يحفظ التوكن في Android Secure Storage وليس داخل قاعدة البيانات.', style: TextStyle(fontSize: 12))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))]));
    if (save == true) {
      try { await context.read<AppProvider>().telegramService.saveCredentials(token: token.text, chatId: chat.text); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات تيليجرام بأمان'), backgroundColor: Colors.green)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
    }
    token.dispose(); chat.dispose();
  }

  Future<void> _createBackup() async {
    try { final path = await context.read<AppProvider>().backupService.createBackup(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نسخة مشفرة: ${path.split('/').last}'), backgroundColor: Colors.green)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  Future<void> _restoreBackup() async {
    final files = await context.read<AppProvider>().backupService.listBackups();
    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(context: context, builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .65, child: ListView(padding: const EdgeInsets.all(8), children: [for (final file in files) ListTile(leading: const Icon(Icons.backup), title: Text(file.path.split('/').last), onTap: () => Navigator.pop(ctx, file.path))])));
    if (selected == null) return;
    final key = selected.toLowerCase().endsWith('.jpm') ? await _askRecoveryKey() : null;
    if (selected.toLowerCase().endsWith('.jpm') && key == null) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('استعادة البيانات'), content: const Text('ستستبدل البيانات الحالية. أنشئ نسخة حالية أولًا. متابعة؟'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة'))]));
    if (ok != true) return;
    try { await context.read<AppProvider>().backupService.restoreBackup(selected, recoveryKey: key); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الاستعادة. أغلق التطبيق وافتحه من جديد.'), backgroundColor: Colors.green)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  Future<void> _restoreExternal() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any, withData: false);
    final path = result?.files.single.path;
    if (path == null) return;
    final key = path.toLowerCase().endsWith('.jpm') ? await _askRecoveryKey() : null;
    if (path.toLowerCase().endsWith('.jpm') && key == null) return;
    try { await context.read<AppProvider>().backupService.restoreBackup(path, recoveryKey: key); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت الاستعادة. أعد تشغيل التطبيق.'), backgroundColor: Colors.green)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red)); }
  }

  Future<String?> _askRecoveryKey() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('مفتاح الاستعادة'), content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'الصق مفتاح الاستعادة هنا')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('متابعة'))]));
    ctrl.dispose();
    return value?.trim().isEmpty == true ? null : value?.trim();
  }

  Future<void> _showRecoveryKey() async {
    final key = await context.read<AppProvider>().backupService.getRecoveryKey();
    if (!mounted) return;
    await showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('مفتاح استعادة النسخ'), content: SelectableText(key), actions: [TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: key)); Navigator.pop(ctx); }, child: const Text('نسخ')), FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق'))]));
  }

  Future<void> _sendNow() async {
    try { await context.read<AppProvider>().telegramService.sendScheduledBackup(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال النسخة والتقرير'), backgroundColor: Colors.green)); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('المزيد والإعدادات')),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        _header('الحساب والمظهر'),
        ListTile(leading: const Icon(Icons.store), title: const Text('اسم المتجر'), subtitle: Text(app.storeName), onTap: () => _editText('اسم المتجر', app.storeName, (v) => app.updateSetting('store_name', v))),
        ListTile(leading: const Icon(Icons.currency_exchange), title: const Text('العملة'), subtitle: Text(app.currency), onTap: () => _editText('العملة', app.currency, (v) => app.updateSetting('currency', v))),
        ListTile(leading: const Icon(Icons.brightness_6), title: const Text('المظهر'), trailing: DropdownButton<ThemeMode>(value: app.themeMode, items: const [DropdownMenuItem(value: ThemeMode.system, child: Text('تلقائي')), DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')), DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن'))], onChanged: (v) { if (v != null) app.setThemeMode(v); })),
        ListTile(leading: const Icon(Icons.account_balance_wallet), title: const Text('رأس المال الأولي'), subtitle: Text(app.formatMoney(app.initialCapital)), onTap: () => _editNumber('رأس المال الأولي', app.initialCapital, app.setInitialCapital)),
        ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('حركة رأس المال'), onTap: _capitalTransaction),
        _header('المخزون والتقارير'),
        ListTile(leading: const Icon(Icons.category), title: const Text('إدارة التصنيفات'), onTap: _manageCategories),
        ListTile(leading: const Icon(Icons.swap_vert), title: const Text('سجل حركة المخزون'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockMovementsScreen()))),
        ListTile(leading: const Icon(Icons.analytics), title: const Text('التقارير'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()))),
        _header('المصاريف'),
        ListTile(leading: const Icon(Icons.add_card), title: const Text('إضافة مصروف'), onTap: _addExpense),
        ListTile(leading: const Icon(Icons.receipt_long), title: const Text('عرض المصاريف'), onTap: _listExpenses),
        _header('النسخ الاحتياطي'),
        SwitchListTile(title: const Text('نسخ احتياطي تلقائي'), subtitle: const Text('تنفيذ في الخلفية عند توفر الإنترنت'), value: _autoBackup(context), onChanged: (v) => app.updateSetting('auto_backup_enabled', v.toString())),
        ListTile(title: const Text('الدورية'), subtitle: Text(_frequencyLabel(context)), leading: const Icon(Icons.schedule), onTap: () async { final value = await showDialog<String>(context: context, builder: (ctx) => SimpleDialog(title: const Text('دورية النسخ'), children: [SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'weekly'), child: const Text('أسبوعية')), SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'monthly'), child: const Text('شهرية'))])); if (value != null) await app.updateSetting('backup_frequency', value); }),
        ListTile(leading: const Icon(Icons.backup), title: const Text('إنشاء نسخة مشفرة الآن'), onTap: _createBackup),
        ListTile(leading: const Icon(Icons.restore), title: const Text('استعادة من النسخ المحلية'), onTap: _restoreBackup),
        ListTile(leading: const Icon(Icons.file_open), title: const Text('استعادة ملف .jpm خارجي'), onTap: _restoreExternal),
        ListTile(leading: const Icon(Icons.key), title: const Text('عرض مفتاح الاستعادة'), subtitle: const Text('احتفظ به خارج الهاتف'), onTap: _showRecoveryKey),
        ListTile(leading: const Icon(Icons.share), title: const Text('مشاركة مفتاح الاستعادة'), onTap: context.read<AppProvider>().backupService.shareRecoveryKey),
        _header('Telegram'),
        ListTile(leading: const Icon(Icons.telegram), title: const Text('إعداد Bot Token و Chat ID'), onTap: _telegramSettings),
        ListTile(leading: const Icon(Icons.send), title: const Text('إرسال نسخة + تقرير الآن'), onTap: _sendNow),
        const SizedBox(height: 16),
        Center(child: Text('Jamal Phone Manager • 1.1.1', style: TextStyle(color: Colors.grey[600], fontSize: 12))),
      ]),
    );
  }

  bool _autoBackup(BuildContext context) => context.watch<AppProvider>().autoBackupEnabled;
  String _frequencyLabel(BuildContext context) => context.watch<AppProvider>().backupFrequency == 'monthly' ? 'شهرية' : 'أسبوعية';
  Widget _header(String text) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(text, style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)));
}
