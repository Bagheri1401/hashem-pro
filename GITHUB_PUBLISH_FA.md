# راهنمای انتشار Hashem Pro در GitHub

## روش بدون دستور (مرورگر)

1. وارد `https://github.com/new` شوید.
2. نام مخزن را `hashem-pro` انتخاب کنید.
3. بسته به نیاز، گزینه `Public` یا `Private` را انتخاب کنید؛ برای اشتراک عمومی، `Public`.
4. چون پروژه دارای `README.md` و `.gitignore` است، هنگام ایجاد مخزن گزینه افزودن README، `.gitignore` یا LICENSE را فعال نکنید.
5. مخزن را ایجاد کنید و به **Add file → Upload files** بروید.
6. **ZIP را به همان صورت آپلود نکنید**. آن را استخراج کرده، همه فایل‌ها و پوشه‌های داخل `Hashem_Pro_GitHub_Ready` (از جمله `.github` و `.gitignore`) را داخل صفحه آپلود بکشید.
7. روی `Commit changes` بزنید.
8. از قسمت Actions نتیجه اجرای تست‌ها را بررسی کنید.

اگر مرورگر گوشی فایل‌های مخفی با نام نقطه‌دار را انتخاب نمی‌کند، از رایانه یا روش Git استفاده کنید.

## روش Git CLI (روی رایانه/سیستمی با git)

ابتدا در GitHub مخزن خالی با همین نام بسازید. سپس در پوشه استخراج‌شده:

```bash
git init
git branch -M main
git add .
git commit -m "Initial public-ready MVP v0.1.0"
git remote add origin https://github.com/bagheri1401/hashem-pro.git
git push -u origin main
```

برای ورود به GitHub از راهکار معتبر Git Credential Manager، SSH یا GitHub CLI استفاده کنید؛ **رمز یا Personal Access Token را در فایل‌های پروژه نگذارید**.

## پیش از عمومی کردن مخزن

- کد را مرور کنید و مطمئن شوید هیچ کلید، توکن، IP خصوصی یا مشخصات مشتری داخل آن نیست.
- تست‌ها فقط بخش نرم‌افزاری را پوشش می‌دهند؛ پیش از استقرار واقعی، GRE و FRP را در شبکه آزمایشی بررسی کنید.
- درباره مجوز بازنشر کد تصمیم بگیرید. در حال حاضر LICENSE اضافه نشده است؛ اگر می‌خواهید دیگران حق استفاده، تغییر و توزیع کد را داشته باشند، یک مجوز مناسب (مثلاً MIT، Apache-2.0 یا GPLv3) به مخزن اضافه کنید.
- می‌توانید نسخه اول را با Tag `v0.1.0` و Release Note منتشر کنید.

## مشخصات آماده برای صفحه مخزن

- **Owner:** `bagheri1401`
- **Repository name:** `hashem-pro`
- **Description:** `Hashem Pro - Multi-node GRE + FRP tunnel manager with a Persian web dashboard`
- **Topics:** `gre`, `frp`, `tunnel`, `fastapi`, `networking`, `linux`, `persian`

> توجه: لینک `https://github.com/bagheri1401/hashem-pro` تنها پس از ساخت و انتشار مخزن قابل استفاده خواهد بود. نام کاربری GitHub شما با نام کاربری ورود به پنل فرق دارد؛ برای پنل در زمان نصب رمز جدا تعیین کنید.
