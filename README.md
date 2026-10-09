# Hashem Pro | GRE + FRP Tunnel Manager · نسخه 0.1 (MVP)

> **وضعیت: آزمایشی / Experimental** — پنل برای استفاده در محیط تست ارائه شده است، نه استقرار عمومی بدون ممیزی امنیتی. تست عملکرد واقعی بین سرورهای ایران و خارج هنوز لازم است.
> راهنمای انتشار در GitHub: [GITHUB_PUBLISH_FA.md](GITHUB_PUBLISH_FA.md) | [Security](SECURITY.md) | [Changelog](CHANGELOG.md)


**Hashem Pro** پنل مدیریت خصوصی برای یک سرور **ایران** (نقطه اتصال کاربران) و چندین سرور **خارج**، همراه با:

- GRE مستقل برای هر خارج: `gf1`, `gf2`, ... و subnet اختصاصی `10.233.N.0/30`.
- FRPS جداگانه روی ایران و FRPC روی خارج؛ اتصال کنترل FRP از طریق **IP خصوصی GRE** انجام می‌شود.
- پورت TCP/UDP هر سرویس روی **IP عمومی ایران** باز می‌شود، و به `127.0.0.1:PORT` روی خارج متصل می‌شود.
- پنل وب فارسی RTL: افزودن/حذف سرور، افزودن/حذف فوروارد، اعمال، Start/Stop، وضعیت، Ping و لاگ FRPS.
- SSH فقط با کلید و **تأیید کلید میزبان**، توکن جداگانه برای هر FRP، TLS اجباری FRP، بدون تغییر default route.
- نگهداری سیستم با systemd و پایگاه SQLite؛ دسترسی پنل فقط روی localhost.

## مشخصات پروژه

- نام پروژه: **Hashem Pro**
- صاحب مخزن: **bagheri1401**
- نام پیشنهادی مخزن: **hashem-pro**
- مسیر پیشنهادی پس از انتشار: `https://github.com/bagheri1401/hashem-pro`
- شناسه‌های فنی سرویس (`grefrp-*`) برای سازگاری با نصب‌کننده عمداً تغییر نکرده‌اند.

## معماری دقیق

```
Client A -> IRAN_PUBLIC_IP:15001 -> frps(gf1) -- GRE gf1 --> frpc(gf1) -> 127.0.0.1:8080 (FOREIGN A)
Client B -> IRAN_PUBLIC_IP:15002 -> frps(gf2) -- GRE gf2 --> frpc(gf2) -> 127.0.0.1:8081 (FOREIGN B)
                               |-- پنل: 127.0.0.1:8765 فقط مدیریت --|
```

> نکته اساسی: FRP از TCP/UDP پشتیبانی می‌کند، اما **بسته‌های خام GRE را به‌صورت مستقیم حمل نمی‌کند**. GRE لایه ۳ شبکه را می‌سازد و FRP از آن به‌عنوان مسیر خصوصی استفاده می‌کند. GRE (protocol number 47) باید بین IPهای عمومی دو سرور در دیتاسنترها و فایروال‌ها مجاز باشد. GRE رمزنگاری ندارد؛ اتصال بین FRPS و FRPC با TLS اجباری محافظت می‌شود، اما جایگزین VPN با محرمانگی سرتاسری تضمین‌شده نیست. برای محرمانگی داده کاربران، سرویس مقصد باید TLS/رمزنگاری مناسب خود را نیز داشته باشد.

## الزامات

1. Ubuntu 22.04/24.04 یا Debian 12/13 با systemd در دو سمت، دسترسی SSH به روت سرور خارج با کلید.
2. IPv4 عمومی با دسترسی طرفین؛ پشتیبانی GRE پروتکل 47 در هر دو مسیر و فایروال دیتاسنتر.
3. دسترسی دانلود GitHub و بسته‌های apt/pip در زمان نصب، پردازنده x86_64 یا ARM64.
4. آگاه بودن از تداخل آدرس‌های `10.233.0.0/16` با شبکه خود، از هر دو طرف. اگر تداخل دارید پیش از نصب subnet را در `grefrp/core.py` اصلاح کنید.
5. قبل از اجرا، بکاپ و snapshot از هر دو سرور بگیرید و نخست در محیط تست آزمایش کنید.

## نصب آسان Hashem Pro (ایران / خارج)

روی **سرور ایران** به‌عنوان root یا کاربر دارای sudo اجرا کنید. ابتدا فایل نصب دریافت می‌شود و سپس به‌صورت تعاملی نام کاربری و رمز مدیر پنل پرسیده می‌شود:

```bash
curl -fsSL https://raw.githubusercontent.com/Bagheri1401/hashem-pro/main/install.sh -o /tmp/hashem-pro-install.sh && sudo bash /tmp/hashem-pro-install.sh --iran
```

روی **هر سرور خارج** دستور زیر را اجرا کنید. پس از نصب FRP و ملزومات، می‌توانید کلید عمومی SSH تولیدشده در سرور ایران را وارد کنید:

```bash
curl -fsSL https://raw.githubusercontent.com/Bagheri1401/hashem-pro/main/install.sh -o /tmp/hashem-pro-install.sh && sudo bash /tmp/hashem-pro-install.sh --foreign
```

برای نمایش منوی انتخاب ایران/خارج در پوشه سورس: `sudo bash install.sh`.

**مهم:** اسکریپت با دسترسی root اجرا می‌شود؛ قبل از اجرای عمومی، سورس را مرور کنید. دانلود و اجرای اسکریپت نیازمند دسترسی اینترنت، `apt` و GitHub است؛ رمز مدیر به صورت تعاملی دریافت می‌شود و نصب‌کننده بر اساس تنظیمات موجود، رمز قبلی را حذف نمی‌کند. پنل تنها روی `127.0.0.1:8765` فعال می‌شود؛ با SSH port forwarding دسترسی بگیرید. سرور خارج همچنان به تأیید اثرانگشت کلید SSH (known_hosts) و مجاز بودن GRE شماره 47 نیاز دارد.

## نصب پنل روی سرور ایران

فایل ZIP را در ایران extract کنید و در ریشه پوشه آن:

```bash
sudo bash scripts/install-panel.sh
```

نصب‌کننده FRP **نسخه 0.71.0** را با SHA-256 ثابت و بررسی‌شده دانلود می‌کند، رابط وب را ایجاد می‌کند و نام کاربری و رمز مدیر را می‌پرسد (حداقل ۱۲ کاراکتر). رمز به‌صورت PBKDF2 ذخیره می‌شود. سرویس:

```bash
sudo systemctl status grefrp-panel
sudo journalctl -u grefrp-panel -n 50 --no-pager
```

پنل تنها روی `127.0.0.1:8765` گوش می‌دهد. برای باز کردن آن از رایانه خود:

```bash
ssh -N -L 8765:127.0.0.1:8765 root@IRAN_PUBLIC_IP
```

سپس در مرورگر رایانه `http://127.0.0.1:8765` را باز کنید. برای دسترسی مدیریتی عمومی، Reverse Proxy با HTTPS و کنترل IP و احراز هویت چندعاملی لازم است؛ **این نسخه را روی 0.0.0.0 در اینترنت باز نکنید**.

## آماده‌سازی سرور خارج (برای هر کشور)

روی سرور خارجی، پیش‌نیاز و FRP را نصب کنید. فایل `scripts/install-frp.sh` را با `scp` به سرور خارج منتقل کنید:

```bash
scp scripts/install-frp.sh root@FOREIGN_PUBLIC_IP:/root/install-frp.sh
ssh root@FOREIGN_PUBLIC_IP 'bash /root/install-frp.sh'
```

**نکته امنیتی:** برای دسترسی خودکار پنل، کلید عمومی سرور ایران باید در `~root/.ssh/authorized_keys` سرور خارج قرار گیرد (فقط کلید عمومی، نه خصوصی):

```bash
# On Iran: public key for the remote nodes:
sudo cat /etc/grefrp/id_ed25519.pub
```

روی خارج (در نشست کنسول/SSH مطمئن) کلید چاپ‌شده را در `~root/.ssh/authorized_keys` قرار دهید. بهتر است `PermitRootLogin prohibit-password` و `PasswordAuthentication no` را تنها **بعد از تأیید اتصال با کلید** فعال کنید تا دسترسی خودتان قطع نشود.

سپس برای جلوگیری از حمله man-in-the-middle، fingerprint کلید SSH هر سرور را از **کنسول مورد اعتماد** دریافت و با `ssh-keyscan` مقایسه کنید:

```bash
# On foreign, trusted provider console:
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub

# On Iran (change IP and port):
ssh-keyscan -p 22 FOREIGN_PUBLIC_IP > /tmp/foreign_ssh_hostkey
ssh-keygen -lf /tmp/foreign_ssh_hostkey
# فقط پس از مقایسه اثرانگشت‌ها:
sudo sh -c 'cat /tmp/foreign_ssh_hostkey >> /etc/grefrp/known_hosts'
sudo chmod 600 /etc/grefrp/known_hosts
```

کنترل اتصال **از ایران**:

```bash
sudo ssh -F /dev/null -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/etc/grefrp/known_hosts \
  -i /etc/grefrp/id_ed25519 root@FOREIGN_PUBLIC_IP 'id -u'
```

خروجی باید `0` باشد. برای SSH روی پورت غیر 22، همان پورت را در `ssh-keyscan`, `ssh -p`, و فرم پنل ثبت کنید.

## کار با پنل

1. وارد شوید و IP عمومی ایران، IP عمومی خارج، نام، پورت SSH و MTU را ثبت کنید.
2. در صفحه سرور خارج، یک پورت مانند `15001/TCP` روی ایران را به `8080/TCP` روی خارج وصل کنید. باید **در خارج سرویسی واقعاً روی `127.0.0.1:8080` گوش بدهد**.
3. «اعمال تنظیمات» را انتخاب کنید. پنل در خارج FRPC و GRE و در ایران FRPS و GRE را ایجاد و با systemd فعال می‌کند.
4. «بررسی وضعیت» را بزنید: `grefrp-gre-*`، `grefrp-frps-*` و `remote_frpc` باید `active` باشند و `ping_remote_GRE` باید `ok` شود.
5. فقط پورت‌های ورودی مورد نیاز سرویس خود را در فایروال ایران و پنل دیتاسنتر باز کنید. **به‌صورت جداگانه** پروتکل GRE (شماره 47) باید بین سرورها اجازه عبور داشته باشد.
6. برای هر سرور دیگر مراحل را تکرار کنید. برای تغییر/حذف پورت، بعد از ویرایش «اعمال تنظیمات» را دوباره بزنید.

### نمونه بررسی عیب‌یابی

```bash
# Iran
ip -d tunnel show
ip addr show gf1
ping -c 3 10.233.1.2
systemctl status grefrp-gre-gf1 grefrp-frps-gf1
journalctl -u grefrp-frps-gf1 -n 70 --no-pager

# Foreign
ip addr show gf1
ping -c 3 10.233.1.1
systemctl status grefrp-gre-gf1 grefrp-frpc-gf1
journalctl -u grefrp-frpc-gf1 -n 70 --no-pager

# Check actual client service on foreign
ss -lntup | grep ':8080'
```

**پورت مدیریت FRP** برای هر سرور (`7200+ID`) فقط روی IP داخلی GRE سمت ایران bind می‌شود؛ لازم نیست آن را روی Public IP ایران باز کنید. پورت‌های منتشرشده، مانند `15001`, روی IP ایران گوش می‌دهند و باید با firewall به مراجعان مجاز محدود شوند.

## امنیت و محدودیت‌های نسخه 0.1

- این نسخه برای **اپراتور مورد اعتماد** و مدیریت سرورهای تحت مالکیت شماست؛ اجرای پنل با root به علت دستورات `ip`, `systemctl` و SSH روی مقصد انجام می‌شود و فقط به loopback دسترسی دارد. برای سرویس‌دهی سازمانی بهتر است daemon محدودالاختیار/SSH forced-command، احراز هویت MFA، ثبت لاگ حسابرسی و HA اضافه شود.
- این پنل **پنل کاربران V2Ray/Xray، ساخت کانفیگ مشتری، محاسبه حجم یا صدور اشتراک نیست**. کاربران همچنان به سرویس یا پورت روی سرور ایران متصل می‌شوند. حساب‌های کاربران را باید روی سرویس بالادستی مدیریت کرد.
- FRP با توکن مستقل برای هر خارج و TLS اجباری تنظیم شده؛ توکن در فایل TOML و SQLite محافظت‌شده با دسترسی روت ذخیره می‌شود. TLS پیش‌فرض FRP حتماً به معنی احراز هویت گواهی سرتاسری در برابر سرور جعلی نیست. در محیط حساس گواهی/CA معتبر و بررسی سرور را اضافه کنید.
- تغییرات اعمال‌شده به صورت restart هستند و می‌توانند اتصال‌های فعال همان node را قطع کنند؛ در زمان کم‌ترافیک اجرا کنید.
- بررسی وضعیت FRP و GRE **مستقل** است: `active` بودن systemd یا ping موفق، تضمین عملکرد واقعی سرویس کاربر نیست؛ با یک کلاینت واقعی هم تست کنید.
- مشکل GRE در دیتاسنترهای مسدودکننده پروتکل 47 با FRP حل نمی‌شود. در چنین شرایطی معماری جایگزین مانند WireGuard/UDP یا FRP مستقیم لازم است (در این نسخه تعبیه نشده).
- در این نسخه تداخل احتمالی پورت‌ها با سرویس‌های خارج از پنل باید توسط مدیر بررسی شود؛ ثبت پورت، از نظر سرویس‌های سیستم اسکن کامل انجام نمی‌دهد.
- برای تغییر IP عمومی، MTU و SSH باید فعلاً node را حذف و دوباره بسازید. حذف زمانی انجام می‌شود که سرور خارج با SSH در دسترس باشد.
- هیچ سیستم هوشمند load balancing، پایش مصرف کاربران یا failover خودکار در این MVP وجود ندارد.

## فایل‌ها

- `grefrp/core.py`: اعتبارسنجی، SQLite، اسکریپت‌های GRE، FRP TOML، systemd، SSH و اجرای عملیات.
- `grefrp/app.py`: برنامه FastAPI، نشست مدیر، CSRF و مسیرهای پنل.
- `templates/`, `static/`: ظاهر RTL فارسی و ریسپانسیو.
- `install.sh`: نصب یک‌دستوری با انتخاب حالت ایران یا خارج.
- `scripts/install-panel.sh`: نصب روی ایران.
- `scripts/install-frp.sh`: دانلود و تأیید SHA256 نسخه ثابت FRP در هر دو سمت.
- `tests/`: آزمون‌های پایه تولید تنظیمات و وب.

## منابع فنی

- https://github.com/fatedier/frp
- https://gofrp.org/en/docs/reference/server-configures/
- https://gofrp.org/en/docs/reference/client-configures/
- https://github.com/Azumi67/FRP_Reverse_Loadbalance
- https://github.com/Sir-Adnan/GRE-Tunnel-Manager

این پروژه کپی مخزن‌های بالا نیست؛ یک پیاده‌سازی مستقل MVP با مرور معماری آن‌هاست.

## وضعیت مجوز انتشار

این نسخه با انتخاب مجوز متن‌باز همراه نشده است. عمومی بودن مخزن به‌خودی‌خود به معنی اعطای مجوز استفاده، تغییر یا بازنشر نیست. صاحب پروژه باید پیش از توزیع متن‌باز یک فایل `LICENSE` مطابق ترجیح خود اضافه کند.
