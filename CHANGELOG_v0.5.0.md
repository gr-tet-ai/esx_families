# 🔥 esx_families v0.5.0 — "الإصلاحات الجبارة"

## ⚠️ ترقية إلزامية من v0.4.x

```sql
SOURCE sql/upgrade_v0.4.x_to_v0.5.0.sql;
```

ثم `restart esx_families`.

---

## ✅ الإصلاحات الحرجة

### 1. القائد يطلع له "لست في عائلة" — مُصلَح ✓
- **Auto-heal**: لو القائد ما أُضيف لـ `family_members` لأي سبب، `getMyContext` يضيفه تلقائياً عند أول F6.
- **CitizenID Normalization**: `ESXBridge.NormalizeCitizenId()` يقبل `license:xxx` أو نص خام.
- **CitizenExists check**: قبل تعيين قائد، نتحقق من وجوده في DB (يمنع typos).
- **Event `youJoinedGang`**: القائد المُعيَّن أونلاين يستلم إشعار فوري + يُحدَّث context الكلاينت.

### 2. نقطة المبايعة (trade) منسوبة لعائلة — مُصلَح ✓
- `adminCreateTradePoint` يقبل الآن `gangId` صريح (dropdown في F9).
- لو ما حُدد، يُربط تلقائياً بأقرب زون.

### 3. دائرة الخزنة لا تظهر — مُصلَح ✓
- Marker كُبِّر: type=1 cylinder بدل 27 + size 1.6×1.6×1.0 (كان 1.0×1.0×0.5).
- لون ذهبي ساطع a=180.
- **Blip جديد** على الخريطة بلون العائلة (sprite 500).
- مسافة التفاعل 1.5 → 2.0م.

### 4. الحرب لا تتفعل — مُصلَح ✓
- جذرها كان نفس مشكلة "لست في عائلة" (`GetPlayerGang` يرجع nil) → حُلّت بـ auto-heal.

### 5. إضافة عضو لا يتفعل — مُصلَح ✓
- `inviteMember` ينظف عضوية سابقة + ينبه المدعو فوراً.

---

## 🆕 الميزات الجديدة

### A) نقاط المبايعة الفعلية (Recruitment Points)
نظام انضمام احترافي بدون citizenid يدوي:
- **القائد** من F6 → "📍 نقاط المبايعة" → "إنشاء هنا" → ينشئ NPC في موقعه.
- **الأدمن** من F9 يقدر ينشئ لأي عائلة (سيُضاف في v0.5.1).
- اللاعب يقترب من الـ NPC → [E] → نافذة "هل تريد الانضمام؟" → يُرسل طلب.
- القائد/أصحاب `can_invite` يستلمون إشعار + قائمة "🤝 طلبات الانضمام" في F6.
- قبول/رفض بزر واحد. جدول `family_join_requests` يحفظ التاريخ.

### B) HUD حالة العائلة
- يسار الشاشة: شعار العائلة، رتبتك، عدد الأعضاء، الزونات، رصيد الخزنة، حالة الحرب.
- يتحدث تلقائياً كل 30 ثانية.
- تشغيل/إيقاف بأمر `/familyhud`.

### C) Hybrid blips للأعضاء فقط
- Blip 🤝 برتقالي يظهر فقط للأعضاء/الأدمن (مو لكل اللاعبين).
- NPC مرئي للجميع (organic discovery).

### D) فصل F6/F9 صريح
- F6 = القائد فقط. غيره يستلم نص توجيهي للبحث عن نقطة مبايعة.
- F9 = أدمن فقط. زر إضافي في F6 للأدمن لفتح F9.

---

## 📁 الملفات الجديدة

```
sql/upgrade_v0.4.x_to_v0.5.0.sql
server/recruitment.lua          (300+ سطر)
client/recruitment.lua          (160+ سطر)
client/menu_recruitment.lua     (95+ سطر)
client/hud.lua                  (90+ سطر)
```

## 🔧 ملفات معدّلة

```
server/esx_bridge.lua    + NormalizeCitizenId, CitizenExists, GetSourceByCitizenId
server/callbacks.lua     + auto-heal, leader notification, validation
server/ranks.lua         + invite normalization + notify
server/trade.lua         + gangId optional parameter
client/main.lua          + RefreshMyContext, youJoinedGang handler
client/vault.lua         + Blip + cleanup
client/menu.lua          + Recruitment options + F6/F9 separation
config/config.lua        + larger vault marker
fxmanifest.lua           + 5 ملفات جديدة
```

---

## 🧪 خطوات الاختبار السريع

1. شغّل migration: `SOURCE sql/upgrade_v0.4.x_to_v0.5.0.sql;`
2. `restart esx_families`
3. F9 → Manage Gangs → Create → اكتب license كامل (مع `license:`)
4. القائد لو أونلاين يستلم إشعار فوري ويفتح F6 ✓
5. F6 → 📍 نقاط المبايعة → إنشاء هنا → جرب NPC + [E] من حساب آخر
6. F6 → 🤝 طلبات الانضمام → اقبل
7. شوف الـ HUD يسار الشاشة + Blip الخزنة ذهبي

---

## 🎯 الأرقام
- 80% → **~95%** اكتمال
- 32 → **45 integrity check**
- 5 ملفات جديدة + 9 معدّلة
- ~1500 سطر إضافة/تعديل

## 🔮 v0.6.0 القادمة
- NUI كامل بـ Vue 3 (HTML/CSS احترافي)
- F9 admin recruitment management
- خريطة عائلات تفاعلية
- ميزات HUD متقدمة
