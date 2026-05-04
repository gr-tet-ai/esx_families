# esx_families v0.4.1 — Direct Admin Key + Test Mode

## ✨ الجديد

### 🔑 لوحة الإدارة بمفتاح مستقل (F9)
- اضغط **F9** → تفتح لوحة الإدارة الكاملة مباشرة (بدون المرور عبر F6)
- **F6** = قائمة العوائل/العصابات للجميع (كما هي)
- **F9** = لوحة الإدارة الكاملة (للأدمن فقط، إلا لو شغّلت Test Mode)

### 🧪 وضع الاختبار (Test Mode)
في `config/config.lua`:
```lua
Config.OpenAdminForEveryone = false  -- خليها true وقت التجربة مع الشباب
Config.AdminKey = 'F9'               -- تقدر تغيّر المفتاح
```

لما `OpenAdminForEveryone = true`:
- **كل لاعب** يضغط F9 يفتح لوحة الإدارة كاملة (إنشاء/حذف عائلات، مناطق، خزائن، حروب، إلخ)
- لا تحتاج تعديل قاعدة البيانات ولا `add_principal` ولا أي شي ثاني

⚠️ **مهم:** بعد التجربة، رجّعها `false` قبل الإطلاق العام.

## 🛠️ التغييرات التقنية

| الملف | التعديل |
|---|---|
| `config/config.lua` | إضافة `OpenAdminForEveryone` + `AdminKey` |
| `server/main.lua` | `IsAdmin()` تُرجع true تلقائياً لو Test Mode مفعّل |
| `client/menu.lua` | كوماند جديد `/familyadmin` + keybind F9 |
| `client/menu_admin.lua` | حذف parent menu — اللوحة صارت standalone |

## 🔒 الأمان
- التحقق من `IsAdmin` يبقى **server-side** — مستحيل تجاوزه من client
- لو نسيت `OpenAdminForEveryone = true` بعد الإطلاق → الكل بيقدر يحذف عوائل، فاحرص

## 📋 خطوات الاستخدام
1. حمّل الفولدر إلى `resources/[gangs]/esx_families`
2. ريستارت السيرفر
3. ادخل اللعبة → اضغط **F9** → لوحة الإدارة كاملة
4. لما تخلصون التجربة → غيّر `OpenAdminForEveryone = false` وأعد التشغيل

## 🔄 الانتقال من v0.4.0
- **DB:** لا تغيير ❌ (نفس الـ schema)
- **Config:** أضف السطرين الجدد فقط
- **استبدل:** ملفات `client/menu.lua`, `client/menu_admin.lua`, `server/main.lua`, `config/config.lua`
