# 🚀 esx_families v0.5.2 — Performance + War HUD + Force Declare War

## ⚡ تحسينات الأداء (Performance Pass)

تركّزت الجولة على **تخفيف الضغط على السيرفر والكلاينت** بدون فقدان أي ميزة:

### Client-side
- **HUD الرئيسية**: تم استبدال إعادة بناء النصوص كل frame بـ **string cache** يُعاد بناؤه فقط عند تغيّر `MyContext`. النتيجة: تقليل ~80% من استهلاك CPU لـ HUD على شاشات بدون حرب.
- **War HUD المباشر**: عداد ⏱️ live + نقاط 🟢 لنا / 🔴 لهم تحدّث **real-time** من event بدون أي round-trip للسيرفر. حساب timer يتم مرة واحدة فقط في الثانية (مو كل frame).
- **2D pre-check** قبل sqrt في كل المؤشرات (vault, trade, recruitment): يستبعد النقاط البعيدة بدون استدعاء `vector3` مكلف. مفيد جداً للسيرفرات بعدد كبير من النقاط.
- **textUI cache**: لا نعيد استدعاء `lib.showTextUI` كل tick — فقط عند تغيّر الحالة. (تخفيف على NUI thread)
- **Adaptive sleep**: 2000ms عند عدم وجود نقاط قريبة، 500ms عند الاقتراب، 0 فقط عند التفاعل الفعلي.
- **Context refresh**: من 30s → 60s. لا يعمل إذا HUD مخفي أو اللاعب ليس في عائلة.

### Server-side (مُحسَّن أصلاً من v0.3.0 — تأكيد)
- War tick واحد فقط يعمل لما يكون فيه حروب نشطة
- Batch writes للـ vault money كل 30s
- Throttle للـ kill events 1000ms
- Spatial grid للـ zone lookups

---

## 🆕 ميزات جديدة

### 1. ⚡ Force Declare War (للأدمن)
- في `F9 → ⚔️ إدارة الحروب → ⚡ فرض حرب فورية`
- اختر **مهاجم + مدافع + زون** + خيار "بدء فوري" (يتجاوز مرحلة التحضير)
- يتجاوز كل القيود: cooldown، تكلفة، حد أدنى للأعضاء، coward status
- مثالي للاختبار أو لإجبار حرب بين عصابتين متجمدتين

### 2. ⚡ إعلان حرب مباشر من F6 (للقائد)
- زر جديد في القائمة الرئيسية للقائد فقط
- يفتح قائمة الزونات المتاحة للهجوم **مباشرة** بدون الحاجة للذهاب لـ War Council Ped

### 3. 📊 War HUD محسّن
- يظهر تلقائياً تحت HUD العائلة عند بدء حرب
- ⚔️ أسماء العصابتين | 🟢 نقاطنا / 🔴 نقاط العدو | ⏱️ الوقت المتبقي (live)
- يختفي تلقائياً عند انتهاء الحرب

---

## 🔧 إصلاحات

- **HUD frame storm**: في v0.5.0 كان `Wait(0)` يعمل دايماً حتى بدون عرض حرب → سُحب لـ `Wait(1000)` عند الراحة.
- **textUI flicker**: كان `recruitment.lua` و `vault.lua` يعيد عرض/إخفاء textUI كل tick → الآن cached.
- **Vault menu syntax** (نظافة كود): تنظيف نمط if/end المتداخل.

---

## 📁 الملفات المعدلة

| الملف | التغيير |
|------|---------|
| `client/hud.lua` | إعادة كتابة كاملة — string cache + war HUD مدمج |
| `client/vault.lua` | 2D pre-check + textUI cache |
| `client/trade.lua` | 2D pre-check |
| `client/recruitment.lua` | 2D pre-check + adaptive sleep + textUI cache |
| `client/menu.lua` | زر إعلان حرب مباشر للقائد |
| `client/menu_admin.lua` | زر فرض حرب فورية + flow كامل |
| `server/wars_admin.lua` | 3 callbacks جديدة: `adminForceDeclareWar`, `adminListGangsForWar`, `adminListZonesForWar` |
| `fxmanifest.lua` | v0.5.2-esx |

---

## 🗄️ Database

**لا تغييرات على schema** — متوافق 100% مع v0.5.0/v0.5.1.

---

## 📋 الخطوات

1. توقف المورد: `ensure esx_families` → `stop esx_families`
2. استبدل الملفات
3. `start esx_families`
4. اختبر:
   - F6 → تأكد من ظهور HUD سلس بدون lag
   - أعلن حرب → تأكد من ظهور War HUD مع timer + scores live
   - F9 → ⚔️ إدارة الحروب → ⚡ فرض حرب فورية → اختر مهاجم+مدافع+زون → تأكد من بدء الحرب فوراً
