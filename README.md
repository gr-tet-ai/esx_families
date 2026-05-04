# 🏛️ qbx_families - نظام العصابات والزونات

> **النسخة:** 0.1.1 (Phase 1 + F6 Menu)
> **التوافق:** Qbox Framework + ox_lib + ox_inventory + oxmysql

---

## 🎮 الزر السريع: **F6**

اضغط **F6** داخل اللعبة → القائمة الرئيسية تفتح فيها:
- 🏦 خزنة عصابتك (للأعضاء/القائد)
- 👑 لوحة الآدمن الكاملة (إذا كنت آدمن)

> 💡 لتغيير الزر: اللعبة → Settings → Key Bindings → FiveM → "فتح قائمة العوائل"

---

## ✨ الميزات في هذه النسخة

- ✅ **قائمة F6 رئيسية** بـ ox_lib (تشتغل بدون أوامر)
- ✅ نظام إنشاء العصابات (بإدارة الآدمن)
- ✅ تحديد الزونات على الخريطة بـ Blip ملون + شعاع
- ✅ إشعار دخول/خروج تلقائي للزون + HUD
- ✅ خزنة Standalone للعصابة (إيداع/سحب فلوس)
- ✅ نظام مفاتيح: القائد + 2 أعضاء = 3 أشخاص يفتحون
- ✅ خصم نسبة حماية تلقائي على بيع المواد غير القانونية
- ✅ سجل عمليات كامل

---

## 📦 خطوات التركيب

### 1️⃣ نسخ السكربت
```
[server-root]/resources/[qbx_custom]/qbx_families/
```

### 2️⃣ تشغيل قاعدة البيانات
شغّل `qbx_families/sql/install.sql` في HeidiSQL أو phpMyAdmin.

### 3️⃣ server.cfg
```cfg
ensure ox_lib
ensure oxmysql
ensure ox_inventory
ensure qbx_core
ensure qbx_families   👈
```

### 4️⃣ إعادة تشغيل
```
restart qbx_families
```

---

## 🧪 سيناريو الاختبار (5 دقائق)

1. ادخل اللعبة كآدمن
2. **اضغط F6** → القائمة تفتح
3. اختر **"إنشاء عصابة جديدة"** → عبّي الحقول
4. اختر **"إنشاء زون عند موقعي"** → اختر العصابة + الشعاع + الحماية
5. على الخريطة: بليب ملون + دائرة ✅
6. تحرك خارج المنطقة وارجع لها → إشعار "⚠️ منطقة عصابة" ✅
7. اختر **"إنشاء خزنة عند موقعي"** (داخل بيت القائد)
8. اضغط F6 مرة ثانية (لو أنت القائد) → **"فتح خزنة عصابتي"** → القائمة الكاملة ✅

---

## 🎮 الأوامر (متاحة كبديل عن F6)

| الأمر | الوصف |
|------|-------|
| `/familymenu` | فتح القائمة الرئيسية (نفس F6) |
| `/creategang <name> <label> <leader_cid> [color]` | إنشاء عصابة |
| `/createzone <gang_id> <name> <radius> <protection%>` | إنشاء زون |
| `/createvault <gang_id>` | إنشاء خزنة |
| `/deletezone <zone_id>` | حذف زون |
| `/listgangs` | عرض العصابات |

---

## 🔌 ربط نظام الحماية

```lua
-- في سكربت التداول الخاص بك (Server-side)
local finalPrice, taxTaken, zone = exports.qbx_families:ApplyProtectionTax(
    sellerSrc, buyerSrc, itemName, itemCount, totalPrice
)
```

---

## ⚙️ إعدادات مهمة (config/config.lua)

```lua
Config.AdminGroups = { 'admin', 'god' }
Config.MaxVaultKeys = 2
Config.IllegalItems = { 'weed', 'cocaine', 'meth', ... }
```

---

## 🔜 المراحل القادمة

| Phase | المحتوى |
|-------|---------|
| Phase 2 | إضافة الأسلحة/المواد للخزنة (ox_inventory stash) |
| Phase 3 | واجهة NUI تفاعلية بـ React |
| Phase 4 | نظام الرتب والصلاحيات الكامل |
| Phase 5 | حروب العصابات + التحالفات |
| Phase 6 | وضع الشركات + الرواتب |

---

**صنع بمحبة ❤️ لـ Family Server**
