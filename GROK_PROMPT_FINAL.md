# Grok AI — Jamal Phone Manager Final Audit & Repair

المشروع موجود في هذا المستودع:

https://github.com/kador24/Js

وسأعطيك أيضًا ZIP للمشروع المعدّل. اعتبر ZIP هو المصدر العملي الذي يجب فحصه وتعديله، والـGitHub هو مرجع المستودع.

أريد منك التعامل مع المشروع كمهندس Flutter/Android محترف، وليس ككاتب تقرير فقط.

## الهدف

تحويل Jamal Phone Manager إلى تطبيق Android كامل وموثوق لإدارة متجر متعدد المنتجات: هواتف + إكسسوارات + شواحن + كابلات + حافظات + سماعات + منتجات أخرى.

التطبيق Offline-first. SQLite هي مصدر البيانات الأساسي. الإنترنت يستخدم فقط للميزات الاختيارية مثل Telegram والبحث الخارجي عن الباركود.

## قاعدة مهمة جدًا

اقرأ المستودع والـZIP فعليًا.
لا تعتمد على README وحده.
لا تفترض وجود كود غير موجود.
لا تخمّن سبب خطأ لم تختبره.

قبل أي تغيير:
1. افحص بنية المشروع كاملة.
2. افحص كل ملفات `lib/`.
3. افحص كل ملفات `android/`.
4. افحص `pubspec.yaml` وملفات CI.
5. شغّل الأدوات فعليًا إذا كانت البيئة متاحة.

## بيئة البناء المستهدفة

- Flutter 3.47.6
- Dart 3.13+
- Java 17
- Android Gradle Plugin 8.11.1
- Gradle 8.14.0
- Kotlin 2.2.20
- Android minSdk 23

لا ترفع AGP إلى 9 أو Kotlin إلى نسخة أحدث فقط لأن هناك تحذيرًا. لا تغير نسخ Android/Flutter إلا إذا كان الاختبار الفعلي يثبت أن التغيير ضروري.

لا تستخدم:

`--android-skip-build-dependency-validation`

كحل لإخفاء مشكلة توافق حقيقية.

## حالة الإصلاحات التي تم تطبيقها مسبقًا

تم معالجة مشاكل كانت مؤكدة من CI:

- `intl` متوافق مع Flutter 3.47.
- AGP القديم تم رفعه إلى 8.11.1.
- Gradle wrapper إلى 8.14.0.
- Kotlin إلى 2.2.20.
- إزالة `google_fonts` القديم الذي كان يسبب خطأ constant evaluation.
- إزالة كود Dart غير صالح من نوع `await import(...)`.
- ضبط Java/Kotlin target على 17.
- minSdk = 23 بسبب secure storage.
- إزالة `pubspec.lock` القديم لأنه كان مولدًا من بيئة Flutter قديمة.

لا تعكس هذه الإصلاحات بدون سبب.

## Architecture المطلوبة

### المنتجات

يجب أن يدعم المنتج:

- الاسم
- التصنيف
- الماركة
- Barcode
- سعر البيع
- تكلفة الشراء
- المخزون
- حد المخزون
- الضمان
- الوصف
- الصورة
- خصائص إضافية

لا تجعل النظام خاصًا بالهواتف فقط.

## Categories

يمكن للمستخدم إضافة تصنيفات من داخل التطبيق بدون تعديل الكود.

## Inventory

المخزون يجب أن يكون قابلًا للتدقيق.

كل تغيير يجب أن يسجل في `stock_movements`، مثل:

- opening
- in
- out
- return
- adjust

لا يوجد تعديل صامت لكمية المنتج من شاشة تعديل المنتج.

## Purchases

شراء متعدد المنتجات.

عند شراء منتج جديد يجب تحديث `cost_price` بطريقة Weighted Average:

newCost = ((oldStock * oldCost) + (newQty * newUnitCost)) / newStock

ويجب الحفاظ على تكلفة كل عملية شراء في `purchase_items`.

## Sales

البيع متعدد المنتجات.

يجب حفظ `unit_cost` التاريخية داخل `sale_items` لحظة البيع حتى لا يتغير الربح التاريخي إذا تغيرت تكلفة المنتج مستقبلًا.

طرق الدفع:

- cash
- card
- transfer
- credit

يجب دعم:

- discount
- customer name
- customer phone
- due date
- partial payment
- later collection

## Profit

ربح السطر:

(unit_price - historical_unit_cost) * quantity

والخصم يخفض ربح الفاتورة.

## Returns

المرتجع الكامل:

- لا يحذف الفاتورة.
- يغير حالة الفاتورة إلى returned.
- يعيد الكمية للمخزون.
- يسجل stock movement من نوع return.
- إذا كان العميل قد دفع، يسجل refund في سجل الدفعات.
- لا تدخل الفاتورة المرتجعة في مبيعات الفترة أو الأرباح أو الذمم.

## Receivables

البيع الآجل يجب أن يدعم:

- دفعة أولى.
- باقي المبلغ.
- تحصيل لاحق.
- سجل كامل للدفعات.

يجب ألا تعتمد المحاسبة فقط على رقم mutable داخل الفاتورة إذا كان بالإمكان الاعتماد على payment ledger.

## Capital

- Initial capital
- Contributions
- Withdrawals

يمنع سحب مبلغ أكبر من السيولة الحالية.

لا تسمح بتغيير initial capital بعد وجود معاملات مالية، بل استخدم capital transactions.

## Expenses

المصروفات يجب أن تستخدم soft delete/void بحيث لا يختفي الأثر التاريخي.

## Cash / Liquidity

تحقق من أن السيولة لا تعني المبيعات الإجمالية فقط.

يجب احتساب التدفق النقدي من المدفوعات الفعلية، المشتريات المدفوعة، المصاريف، ورأس المال، والاستردادات.

## Dashboard / Reports

يجب أن تعرض على الأقل:

- مبيعات اليوم
- ربح اليوم
- السيولة الحالية
- الذمم
- رأس المال الحالي
- قيمة المخزون
- منخفض المخزون
- الأكثر مبيعًا
- مخطط المبيعات

التقارير يجب أن تستخدم نفس مصدر البيانات الموجود في SQLite، وليس أرقامًا مكررة في أماكن منفصلة.

## Barcode

الماسح بالكاميرا.

الإدخال اليدوي.

البحث داخل منتجات المتجر.

البحث الخارجي اختياري، ولا تفترض أن Barcode الهاتف سيعطي مواصفات كاملة للهاتف.

إذا كانت خدمة البحث الخارجي غير مناسبة لفئة المنتجات العامة، اجعلها helper اختياريًا ولا تجعلها dependency أساسية للبيع.

## Images

صورة المنتج يجب تخزن داخل مساحة التطبيق، لا تعتمد على مسار خارجي مؤقت.

النسخة الاحتياطية يجب أن تشمل:

- SQLite
- صور المنتجات

## Backup

يجب أن تكون النسخة المحلية مشفرة.

التصميم الحالي يستخدم AES-GCM 256-bit.

يجب أن يظل مفتاح الاستعادة منفصلًا وآمنًا.

يجب:

- إنشاء نسخة محلية.
- الاحتفاظ بآخر 5 نسخ.
- استعادة النسخة.
- استعادة صور المنتجات.
- دعم recovery key.
- عدم وضع المفتاح داخل GitHub.

## Telegram

Bot Token وChat ID لا يوضعان داخل source code.

يجب تخزينهما في Android Secure Storage.

عند تشغيل backup مجدول:

1. ينشئ نسخة محلية مشفرة أولًا.
2. ينشئ التقرير.
3. إذا توفر الإنترنت وcredentials صالحة يرسل النسخة إلى Telegram.
4. عند فشل الشبكة يبقى backup محليًا.
5. الرسائل/المهام المؤجلة يمكن أن تنتقل إلى queue لإعادة المحاولة.

## Background scheduling

استخدم WorkManager للجدولة الأسبوعية/الشهرية.

لا تدّع أن الجدولة الدقيقة بالدقيقة مضمونة على Android؛ النظام يدير التنفيذ حسب سياسات الطاقة والشبكة.

## Security

افحص عدم وجود:

- Telegram tokens داخل source.
- أسرار داخل GitHub workflow.
- بيانات مالية داخل storefront/public files.
- backup غير مشفر بدون سبب.

## RTL / UI

التطبيق عربي RTL.

يجب الحفاظ على:

- Material 3
- light/dark mode
- حالات loading
- empty states
- رسائل أخطاء واضحة
- أزرار سريعة
- تصميم مناسب للهاتف

## CI/CD

نفّذ فعليًا:

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

إذا ظهر خطأ:

1. سجل الخطأ الحقيقي.
2. أصلح root cause.
3. أعد التشغيل.
4. لا تتجاوز الفحص فقط.

## Functional test

اختبر هذا السيناريو فعليًا بالـSQLite أو باختبارات Dart حيث يمكن:

```text
Initial capital = 3,000,000

Buy:
10 × 180,000

Sell:
3 × 215,000

Return the sale completely

Add expense:
10,000

Create credit sale:
Total 100,000
Paid now 40,000
Remaining 60,000

Collect later:
60,000

Create encrypted backup

Restore backup
```

تحقق من:

- stock movements
- current stock
- historical cost
- profit
- expense
- cash
- receivable
- return/refund
- backup
- restored database
- restored product images

## Regression rules

لا تحذف feature موجودة بدون سبب.
لا تعيد تسمية database tables الموجودة بدون migration.
لا تغير أسماء settings keys بدون migration.
لا تكسر البيانات القديمة.
أي database schema change يحتاج migration واضحة.

## Code quality

ابحث عن:

- imports غير مستخدمة
- variables غير مستخدمة
- methods غير موجودة
- null safety errors
- invalid async/await
- context usage after await
- broken provider access
- transaction consistency problems
- silent exception swallowing
- dead code
- malformed generated code

## Final delivery

لا أريد تقريرًا فقط.

أريد منك:

1. تعديل الملفات الفعلية.
2. تشغيل format/analyze/test/build.
3. إصلاح كل P0/P1.
4. إبقاء المشروع قابلًا للبناء بدون flags تتجاوز التحقق.
5. إعطائي في النهاية:
   - build result
   - test result
   - الملفات التي تغيرت
   - أهم الإصلاحات
   - أي شيء بقي P2/P3
   - اسم APK الناتج ومكانه

إذا كنت غير قادر على تشغيل جزء من toolchain، صرّح بذلك بوضوح ولا تدّعي نجاحه.

الهدف النهائي: نسخة Jamal Phone Manager مستقرة، قابلة للبناء، وقابلة للاستخدام الفعلي في متجر، وليس مجرد مشروع يمر من `flutter build` مع تعطيل الفحوصات.
