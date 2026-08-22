# مجموعة النعماني — نظام ERP يعمل دون إنترنت

نظام إدارة مبسّط واحترافي لمنتجات **مجموعة النعماني** (مبيدات، أسمدة، مغذيات نباتية، مستلزمات زراعية).

المالك: أحمد نعمان الجعبيري

**حماية البيانات وسلامتها هي الأولوية الأولى.**

## المتطلبات

- Flutter `3.47.0` أو أحدث
- Dart `3.13.0` أو أحدث
- Google Chrome
- Docker Desktop فقط عند تشغيل PostgreSQL والخادم

## تشغيل Flutter Web

من مجلد المشروع الرئيسي، افتح PowerShell ونفّذ:

```powershell
flutter clean
flutter pub get
dart run build_runner build
flutter run -d chrome
```

قاعدة البيانات المحلية تعمل على الويب عبر Drift وSQLite WASM. الملفات المطلوبة موجودة مسبقاً:

```text
web/sqlite3.wasm
web/drift_worker.js
```

لا تحذف هذه الملفات. بيانات العمل تُخزن بصورة دائمة داخل قاعدة المتصفح، وليس في متغيرات مؤقتة أو `localStorage`.

إذا لم يظهر Chrome ضمن الأجهزة:

```powershell
flutter devices
flutter config --enable-web
flutter run -d chrome
```

## تشغيل PostgreSQL والخادم

انسخ `.env.example` إلى `.env` واضبط القيم، ثم شغّل PostgreSQL والخادم:

```powershell
docker compose up -d postgres server
```

ثم شغّل Flutter Web من مجلد المشروع في نافذة ثالثة:

```powershell
flutter run -d chrome
```

يعمل التطبيق محلياً دون الخادم بعد إنشاء البيانات المحلية. الخادم مطلوب للمصادقة المركزية والمزامنة والنسخ إلى Google Sheets. في الإنتاج اجعل `ALLOW_SEED=false` واستخدم `JWT_SECRET` عشوائياً بطول 32 حرفاً على الأقل. إنشاء مدير الخادم الأول لا يحدث إلا عند ضبط `BOOTSTRAP_ADMIN_USERNAME` و`BOOTSTRAP_ADMIN_PASSWORD` صراحة.

## إعداد Google Sheets

1. أنشئ Service Account في Google Cloud وفعّل Google Sheets API.
2. شارك ملف **Live Backup** وملف **Full Backup** مع بريد حساب الخدمة بصلاحية Editor.
3. اضبط `GOOGLE_SERVICE_ACCOUNT_JSON` و`GOOGLE_LIVE_SPREADSHEET_ID` و`GOOGLE_FULL_SPREADSHEET_ID`. يجب أن يكون المعرّفان مختلفين.
4. افتح «النسخ الاحتياطي والمزامنة» داخل النظام. تظهر الحالة `غير مهيأ` عند نقص الإعداد، ويظهر آخر خطأ Google الفعلي دون كشف الأسرار.

يحفظ الخادم كل عملية مقبولة أولاً في PostgreSQL ثم يضع نسخة Google في `backup_outbox`. فشل Google لا يلغي العملية ولا يفقدها؛ يعاد إرسالها يدوياً أو كل 15 دقيقة. النسخة الكاملة تقرأ Snapshot من PostgreSQL ولا تستخدم بيانات المتصفح مباشرة.

## بناء نسخة الويب للإنتاج

```powershell
flutter clean
flutter pub get
dart run build_runner build
flutter build web --release --no-wasm-dry-run
```

توجد ملفات الإنتاج في:

```text
build/web/
```

يجب تقديم المجلد بواسطة خادم HTTP/HTTPS. لا تفتح `index.html` مباشرة كملف.

## الدخول التجريبي

يُنشأ فقط عندما تكون قاعدة البيانات فارغة و`allow_seed` مفعّلاً:

```text
اسم المستخدم: admin
كلمة المرور: ChangeMe!Admin1
```

غيّر كلمة المرور وأوقف البيانات التجريبية قبل الإنتاج.

هذا الحساب محلي للتطوير. لتسجيل الدخول المركزي يجب تشغيل الخادم مع بيانات bootstrap المطابقة أو إنشاء المستخدم من شاشة الإدارة أثناء الاتصال.

## حل مشاكل Flutter Web

```powershell
flutter clean
Remove-Item -Recurse -Force .dart_tool, build -ErrorAction SilentlyContinue
flutter pub get
dart run build_runner build
flutter run -d chrome
```

لا تمسح بيانات موقع التطبيق من إعدادات Chrome في بيئة الإنتاج؛ حذف بيانات الموقع يحذف قاعدة البيانات المحلية لذلك الجهاز.

## التشخيص والتحقق

```powershell
flutter analyze
flutter test
flutter build web --release
cd server
dart analyze
dart test --concurrency=1
```

اختبارات الخادم تحتاج PostgreSQL باسم `al_nomani_test` على `localhost:5432` وبيانات `postgres/postgres`. CI ينشئ هذه القاعدة تلقائياً. عند فشل المزامنة افحص بالترتيب: صلاحية الجلسة، وصول `/health`، العمليات المعلقة، `backup_outbox`، ثم مشاركة ملف Google مع حساب الخدمة.

للمزيد:

- `docs/ARCHITECTURE.md`
- `docs/SECURITY.md`
- `docs/DEPLOYMENT.md`
