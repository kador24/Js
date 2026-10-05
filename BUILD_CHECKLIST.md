# Jamal Phone Manager — Final Build Checklist

## 1. قبل الرفع

- `pubspec.yaml` موجود.
- لا يوجد `pubspec.lock` قديم من Flutter 3.24.
- لا يوجد `google_fonts`.
- لا يوجد `await import(...)` في Dart.
- Kotlin = `2.2.20`.
- AGP = `8.11.1`.
- Gradle = `8.14.0`.
- Java/Kotlin target = 17.
- minSdk = 23.

## 2. GitHub Actions

Workflow:

```text
.github/workflows/build-apk.yml
```

المطلوب أن ينجح بالترتيب:

```text
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

ثم يظهر Artifact:

```text
jamal-phone-manager-apk
```

## 3. الوظائف الأساسية

### Products
- إضافة منتج.
- تعديل المنتج.
- تعطيل المنتج بدل الحذف الفعلي.
- باركود.
- صورة.
- تصنيف.
- سعر بيع وتكلفة.
- خصائص نصية.

### Inventory
- إنشاء المنتج برصيد افتتاحي يسجل `opening`.
- الشراء يسجل `in`.
- البيع يسجل `out`.
- الإرجاع يسجل `return`.
- التسوية اليدوية تسجل `adjust`.
- لا يوجد تعديل صامت للرصيد عند تعديل المنتج.

### Purchases
- متعددة المنتجات.
- تكلفة الوحدة محفوظة تاريخيًا في `purchase_items`.
- `cost_price` يتحدث بمتوسط مرجح عند دخول مخزون جديد.
- الدفع الجزئي/الآجل محفوظ.

### Sales
- متعددة المنتجات.
- خصم.
- تكلفة تاريخية لكل سطر.
- ربح محفوظ للفواتير المكتملة.
- نقدي / بطاقة / تحويل / آجل.
- دفعة أولى للبيع الآجل.
- تحصيل لاحق.
- إرجاع كامل مع رد الأموال وحركة المخزون.

### Finance
- رأس مال أولي.
- مساهمات.
- سحوبات لا تتجاوز السيولة.
- مصاريف active/voided.
- سيولة مشتقة من سجل المدفوعات والمصروفات والمشتريات ورأس المال.
- ذمم العملاء.
- قيمة المخزون.

### Backup
- AES-GCM-256.
- مفتاح 32-byte.
- مفتاح استعادة ظاهر للمستخدم ويمكن مشاركته.
- قاعدة البيانات + صور المنتجات.
- آخر 5 نسخ محلية.
- استعادة من `.jpm` أو قاعدة `.db` قديمة.

### Telegram
- Token وChat ID في Secure Storage.
- لا أسرار داخل المصدر.
- إنشاء نسخة محلية قبل الإرسال.
- تقرير دوري.
- طابور للمهام عند انقطاع الإنترنت.
- WorkManager للجدولة الأسبوعية/الشهرية.

## 4. اختبار سيناريو حقيقي

نفذ:

```text
Capital = 3,000,000
Buy 10 × 180,000
Sell 3 × 215,000
Return the sale
Add expense 10,000
Create a credit sale with partial payment
Collect the remaining amount
Create backup
Restore backup
```

تحقق من:

- المخزون.
- تكلفة المخزون.
- الربح.
- المصاريف.
- السيولة.
- الذمم.
- سجل حركة المخزون.
- الصور بعد الاستعادة.

## 5. التوقيع

Release الحالي للاختبار يستخدم debug signing.
قبل Google Play يجب إضافة keystore وRelease signing حقيقي.
