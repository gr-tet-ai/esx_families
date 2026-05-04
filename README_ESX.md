# esx_families v0.3.0 (ESX Edition)

> **نسخة ESX من `qbx_families`** — محوّلة بالكامل عبر طبقة Bridge متينة.

---

## ✅ نتائج المراجعة الفنية

| الفحص | النتيجة |
|---|---|
| استدعاءات Qbox مباشرة | ✅ 0 (كلها عبر bridge) |
| Client side dependencies على framework | ✅ 0 (يستخدم events فقط) |
| ox_lib usage (callbacks/notify) | ✅ 171 موضع — يعمل مع ESX بدون تعديل |
| ox_inventory usage | ✅ يعمل مع ESX بنفس الـ API |
| Bridge يدعم ESX Legacy + ESX 1.x | ✅ نعم (يحاول الطريقتين) |
| `removeMoney` يرجع boolean صحيح | ✅ مُصلَح (pcall + manual check) |
| Lazy money read (لا snapshot قديم) | ✅ metatable يقرأ live |
| طول identifier في DB | ✅ VARCHAR(60) — يكفي لـ license:hex |

---

## 📦 ما هذا؟

سكربت **Family/Gang Turf System** كامل لسيرفرات ESX:
- إدارة العصابات والرتب (مستقلة عن ESX jobs)
- زونات/مناطق نفوذ مع حماية وضرائب
- نظام خزنة (Vault) موحّد مع حدود سحب يومية
- نظام تجارة (Trade Points) مع ضرائب على الممنوعات
- نظام حرب (Wars) كامل بـ score + timer + War Council + Test Mode
- Stash موحّد لكل عصابة (ox_inventory)
- لوحة Admin شاملة

---

## 🔧 التركيب (5 دقائق)

### 1. التبعيات (يجب أن تكون مثبتة قبل):
- `es_extended` — ESX Legacy 1.10+ موصى به (يدعم ESX 1.x القديم أيضاً)
- `ox_lib`
- `ox_inventory`
- `oxmysql`

### 2. ضع المجلد في:
```
resources/[local]/esx_families/
```

### 3. شغّل الـ SQL في phpMyAdmin:
- **تثبيت جديد:** استورد `sql/install_full.sql`
- **ترقية من v0.2.0 Qbox:** استورد `sql/upgrade_v0.2.0_to_v0.3.0.sql`

### 4. أضف في `server.cfg` (بهذا الترتيب):
```cfg
ensure oxmysql
ensure ox_lib
ensure ox_inventory
ensure es_extended
ensure esx_families
```

### 5. عدّل `config/config.lua`:
```lua
Config.AdminGroups = { 'admin', 'superadmin' }   -- ESX groups (تأكد من groups سيرفرك)
Config.AdminCitizenIds = { 'char1:abc123...' }   -- اختياري: ESX identifiers محددة
```

### 6. Restart السيرفر، وراقب الـ console:
```
[esx_families] ESX Bridge loaded ✓ (ESX object: true)
```

لو ظهر `ESX object: false` أو رسالة `ERROR`، تأكد إن `es_extended` يبدأ **قبل** `esx_families` في server.cfg.

---

## 🛡️ كيف يعمل الـ Bridge (تقني)

### الفلسفة
بدلاً من إعادة كتابة 4,000+ سطر، أضفنا ملف bridge واحد (`server/esx_bridge.lua`) يلتقط `xPlayer` من ESX ويلفّه في object بنفس شكل Qbox `PlayerData`.

### المتانة
الـ bridge يعالج 5 مشاكل ESX المعروفة:

1. **`removeMoney` لا يرجع boolean** — نستخدم `pcall` + فحص رصيد يدوي قبل الخصم
2. **Money snapshot قديم** — `PlayerData.money.cash` تُقرأ live عبر metatable (مو snapshot)
3. **ESX Legacy vs 1.x** — يجرب `getSharedObject()` أولاً، ثم `TriggerEvent` كـ fallback
4. **Reason parameter اختياري** — بعض إصدارات ESX ترفض الـ reason، نحاول مرتين
5. **Identifier length** — DB يدعم 60 حرف (يكفي لـ `license:hex` 48 + هامش)

### APIs المُجسّرة
| الكود يستدعي | الـ bridge يحوّل إلى |
|---|---|
| `ESXBridge.GetPlayer(src)` | `ESX.GetPlayerFromId(src)` |
| `ESXBridge.GetPlayerByCitizenId(id)` | `ESX.GetPlayerFromIdentifier(id)` |
| `player.PlayerData.citizenid` | `xPlayer.identifier` |
| `player.PlayerData.money.cash` | `xPlayer.getMoney()` (live) |
| `player.PlayerData.money.bank` | `xPlayer.getAccount('bank').money` (live) |
| `player.PlayerData.group` | `xPlayer.getGroup()` |
| `player.PlayerData.source` | `xPlayer.source` |
| `player.Functions.RemoveMoney('cash', n, r)` | check + `xPlayer.removeMoney(n, r)` → boolean |
| `player.Functions.AddMoney('cash', n, r)` | `xPlayer.addMoney(n, r)` → boolean |

> **ملاحظة:** ESX `identifier` (مثل `char1:steam:abc...` أو `license:hex`) يُستخدم كـ `citizenid` في كل جداول DB. لا migration بيانات مطلوب.

---

## ⚠️ أمور مهمة قبل التشغيل

### 1. لو تستخدم `esx_multicharacter`
الـ identifier راح يكون `char1:steam:hex` بدل `steam:hex`. هذا طبيعي والـ bridge يدعمه.

### 2. Gang system مستقل
السكربت لا يستخدم ESX jobs/society. عنده جداول `family_gangs` و `family_members` خاصة. أنشئ العصابات عبر:
```
/creategang <name> <label> <leader_identifier> [blip_color]
```
حيث `<leader_identifier>` = ESX identifier للقائد (مثل `char1:steam:abc...`).

### 3. الـ Event names
الـ events الداخلية لا تزال تستخدم prefix `qbx_families:` (مثل `qbx_families:client:syncZones`). هذا مجرد namespace ولا يؤثر على الوظيفة، **لكن**: لا تركّب `qbx_families` و `esx_families` في نفس السيرفر — سيتعارضان.

### 4. Admin groups
تأكد من `Config.AdminGroups` يطابق groups سيرفر ESX:
- ESX Legacy: عادة `admin`, `superadmin`, `mod`
- ESX 1.x: قد تكون `god`, `admin`

---

## 🧪 خطة اختبار موصى بها (15 دقيقة)

بعد التشغيل، اختبر بالترتيب:

| # | الاختبار | الكوماند | يختبر |
|---|---|---|---|
| 1 | Bridge يعمل | راقب console عند الـ restart | ESX object loaded |
| 2 | Admin check | `/families` (آدمن) | `getGroup()` |
| 3 | إنشاء عصابة | `/creategang test "Test" YOUR_ID 1` | DB writes |
| 4 | إنشاء خزنة | عبر لوحة الآدمن | Vault cache |
| 5 | إيداع كاش | افتح خزنة وأودع | `RemoveMoney` returns true ✓ |
| 6 | سحب كاش | اسحب من الخزنة | `AddMoney` + rollback logic |
| 7 | بيع illegal item | داخل zone عصابة | `ApplyProtectionTax` |
| 8 | بدء حرب | `/startwar` (آدمن) | `GetPlayerByCitizenId` |

لو شي ما اشتغل، شغّل `restart esx_families` وابعتلي رسالة الـ ERROR من console.

---

## 📊 تفاصيل التحويل

| ملف | تغيير |
|---|---|
| `fxmanifest.lua` | name → esx_families، dep → es_extended |
| `server/esx_bridge.lua` | **جديد** — bridge متين (~210 سطر) |
| `server/main.lua` | 2x استبدال GetPlayer |
| `server/vault.lua` | 2x استبدال GetPlayer |
| `server/protection.lua` | 1x استبدال GetPlayer |
| `server/wars.lua` | 3x استبدال GetPlayerByCitizenId |
| `sql/*.sql` | VARCHAR(50) → VARCHAR(60) لـ identifiers |
| **باقي الملفات (24 ملف)** | **بدون أي تعديل** ✅ |

---

## 🔄 الترقية المستقبلية

أي تحديث جديد لـ qbx_families (v0.4.0+) يمكن دمجه بسهولة:
1. انسخ الملفات الجديدة
2. أعد تطبيق 8 الاستبدالات (script سهل: `sed -i 's/exports\.qbx_core:GetPlayer(/ESXBridge.GetPlayer(/g; s/exports\.qbx_core:GetPlayerByCitizenId(/ESXBridge.GetPlayerByCitizenId(/g'`)
3. احتفظ بـ `esx_bridge.lua` كما هو

---

## 📞 دعم

نفس الميزات والوظائف 100% — راجع `CHANGELOG.md` لتفاصيل v0.3.0 الكاملة.
