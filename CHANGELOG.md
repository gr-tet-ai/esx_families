# Changelog

## v0.4.0-esx — Full UI Edition (2026-05-02)

### 🎉 إعادة بناء كاملة لتجربة المستخدم

كل التحكم بالنظام الآن من **قائمة F6 واحدة موحّدة** — لا حاجة لأوامر شات.
الأوامر القديمة (`/creategang`, `/createzone`, ...) لا تزال تعمل كـ backup للأدمن.

### ✨ القائمة الرئيسية (F6)

#### للجميع
- 🌐 **العائلات في السيرفر** — قائمة بكل العوائل + عدد الأعضاء/المناطق + حالة الحرب
- 📜 **الحروب الجارية** — متابعة لايف لكل الحروب النشطة

#### لأعضاء العائلة
- 📊 **نظرة عامة** — معلومات العائلة، الخزنة، المناطق
- 👥 **الأعضاء** — عرض / دعوة / طرد / ترقية (حسب الصلاحيات)
- 🎖️ **الرتب والصلاحيات** (للقائد) — إنشاء/تعديل/حذف رتب بـ 7 صلاحيات + حد سحب يومي
- 🗺️ **مناطقي** — قائمة المناطق + تحديد على الخريطة
- 🏦 **الخزنة** — فتح/إيداع/سحب/مفاتيح/سجل
- ⚔️ **الحروب** — وصول مباشر لـ War Council
- 🚪 **مغادرة العائلة** (لغير القائد)

#### للأدمن — لوحة إدارة شاملة
- 🏛️ **العائلات** — إنشاء/تغيير قائد/حذف
- 🗺️ **المناطق** — إنشاء عند الموقع/عرض/حذف/تحديد على الخريطة
- 🏦 **الخزائن** — إنشاء/حذف
- 💲 **نقاط البيع** — إنشاء/عرض/حذف
- ⚔️ **إدارة الحروب** — إنهاء قسري/إلغاء واسترجاع/Test Mode
- 📍 **War Council** — تحديد إحداثيات Ped مجلس الحرب

### 🛠️ ملفات جديدة
- `client/menu_members.lua` — إدارة الأعضاء كاملة
- `client/menu_ranks.lua` — إدارة الرتب الديناميكية
- `client/menu_admin.lua` — لوحة إدارة احترافية متفرعة

### 🛠️ ملفات معدّلة
- `client/menu.lua` — إعادة كتابة كاملة (ox_lib context menus بدلاً من NUI مخصصة)
- `server/callbacks.lua` — موسّع بـ:
  - `getMyContext` (استدعاء واحد لكل بيانات القائمة الرئيسية — أداء)
  - `getGangDetails`, `getAllZonesAdmin`, `listGangsPublic`, `listActiveWars`
  - `adminChangeLeader`, `leaveGang`, `getVaultLogs`
- `server/wars_admin.lua` — net events جديدة:
  - `adminEndWar`, `adminRefundWar`, `adminToggleTestMode`, `adminSetWarCouncil`
- `client/wars.lua` — إضافة `OpenWarsMenuFromF6()` كـ alias
- `fxmanifest.lua` — تسجيل الملفات الجديدة + version 0.4.0

### 🔒 الأمان (660° clean)
- كل callback يفحص الصلاحيات داخلياً (IsAdmin / isLeader / HasRankPermission)
- لا اعتماد على client للتحقق — أي تخمين/تخريب من العميل يُرفض
- منع حذف عائلة/زون/خزنة في حرب نشطة (atomic safety)
- منع طرد القائد أو ترقية لرتبة Boss من القائمة
- alertDialog confirmation لكل عملية تخريب (حذف، طرد، تغيير قيادة)
- تنظيف الكاش الكامل عند حذف عائلة (members + ranks + zones + vault)
- إعادة بناء spatial grid عند إنشاء/حذف زون

### 🔄 Backward compatibility
- كل الأوامر القديمة تعمل
- كل الـ callbacks v0.3.0 تعمل (لم نحذف شيء، فقط أضفنا)
- DB schema بدون تغيير

---

## v0.3.0-esx — Wars + Unified Stash + Admin Config (2026-04)
- نظام الحروب الكامل (score+timer, snapshot, War Council, Test Mode)
- 32 integrity check لمنع الثغرات
- Unified gang stash (ox_inventory)
- Admin config dynamic (بدون restart)
- ESX bridge layer

## v0.2.0
- Ranks system (7 perms + daily withdraw limit)
- Members management
- Vault key system
- 21 ثغرة مكتشفة → دمج إصلاحاتها في v0.3.0

## v0.1.x
- Gangs, Zones, Vaults, Trade points (Qbox أصلي)
