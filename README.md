<div dir="rtl" align="right">

<h1 align="center">☁️ بهینه‌ساز سرور ایران — ابر باران</h1>

<p align="center">
<b>ABR BARAN · Iran Server Optimizer</b><br>
یک اسکریپت هوشمند، امن و زیبا برای آماده‌سازی سرور لینوکس در ایران:<br>
DNS · میرور بسته‌ها · Docker · BBR · کرنل · امنیت · آپدیت — همه با تایید واقعی و بازگردانی کامل.
</p>

<p align="center">
<a href="https://github.com/aliabedi94/abrbaran-iran-server-optimizer/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/aliabedi94/abrbaran-iran-server-optimizer/actions/workflows/ci.yml/badge.svg"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
<img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
<img alt="Ubuntu · Debian · RHEL family" src="https://img.shields.io/badge/Ubuntu%20·%20Debian%20·%20Rocky%20·%20Alma%20·%20Fedora-supported-informational.svg">
</p>

<p align="center"><a href="README.en.md">English README</a></p>

---

## چرا این پروژه؟

روی سرورهای ایران، `apt update` کند یا ناموفق می‌شود، `docker pull` و `download.docker.com` در دسترس نیستند، DNS پیش‌فرض داده‌ی غلط یا صفحه‌ی مسدودسازی می‌دهد و GitHub گاهی باز نمی‌شود. اسکریپت‌های عمومی «بهینه‌ساز لینوکس» این‌ها را نمی‌شناسند و بیشتر تنظیمات را **کورکورانه** اعمال می‌کنند.

این پروژه برعکس کار می‌کند: **اول اندازه می‌گیرد، بعد تصمیم می‌گیرد، بعد تایید می‌کند، و اگر خراب شد برمی‌گرداند.**

## نصب و اجرا

```bash
curl -fsSL https://raw.githubusercontent.com/aliabedi94/abrbaran-iran-server-optimizer/main/abrbaran-optimizer.sh -o abrbaran-optimizer.sh \
  && sudo bash abrbaran-optimizer.sh
```

اگر دسترسی به GitHub محدود است، همین فایل از سرور ابر باران هم قابل دریافت است:

```bash
curl -fsSL https://abrbaranidc.ir/Download/abrbaran-optimizer.sh -o abrbaran-optimizer.sh && sudo bash abrbaran-optimizer.sh
```

> بهتر است قبل از اجرا فایل را بخوانید؛ اسکریپت متن‌باز و تنها یک فایل bash است.

بدون هیچ گزینه‌ای در ترمینال، **منوی تعاملی** باز می‌شود:

```
  1  بهینه‌سازی کامل و هوشمند  (پیشنهادی)
  2  انتخاب دستی مرحله‌ها
  3  فقط نصب Docker + میرور رجیستری
  4  فقط DNS
  5  فقط مخزن/میرور بسته‌ها
  6  گزارش وضعیت سرور (فقط خواندنی)
  7  بازگردانی تنظیمات اولیه
```

### اجرای غیرتعاملی (اتوماسیون)

```bash
sudo bash abrbaran-optimizer.sh -y                       # همه‌ی مراحل کم‌ریسک، بدون پرسش
sudo bash abrbaran-optimizer.sh -y --docker              # + نصب Docker و میرور رجیستری
sudo bash abrbaran-optimizer.sh -y --docker --fail2ban   # + Fail2ban برای SSH
sudo bash abrbaran-optimizer.sh --only dns,repo          # فقط DNS و میرور بسته‌ها
sudo bash abrbaran-optimizer.sh --only docker --docker   # فقط Docker
sudo bash abrbaran-optimizer.sh --dry-run                # فقط تست و گزارش؛ هیچ تغییری اعمال نمی‌شود
sudo bash abrbaran-optimizer.sh --status                 # گزارش وضعیت سرور
sudo bash abrbaran-optimizer.sh --restore                # بازگردانی همه‌ی تنظیمات
```

## چه کارهایی انجام می‌دهد؟

| مرحله | کار | نکته‌ی هوشمند |
|---|---|---|
| **DNS** | تست ۲۵ سرور DNS ایرانی و خارجی (Shecan، Electro، Begzar، RadarGame، 403، Cloudflare، Google، Quad9، ControlD، …) | پاسخ‌های جعلی/صفحه‌ی مسدودسازی (`10.10.34.x`) شناسایی و حذف می‌شود؛ تایید نهایی با resolve واقعی؛ در صورت شکست، برگشت خودکار |
| **مخزن / میرور** | تست موازیِ ~۹۰ میرور Ubuntu/Debian/RPM (ایرانی + جهانی) | سرعت واقعی دانلود ۳ ایرانی + ۳ خارجی اندازه‌گیری می‌شود؛ مسیر درست میرورهایی که مسیرشان را نمی‌دانیم خودکار کشف می‌شود؛ **failover**: اگر وسط `apt update/upgrade` میرور خراب شد، به بهترین میرور بعدی (نه قبلی!) می‌رود |
| **Docker** | نصب Docker Engine + Compose از میرورهای سالم و تنظیم میرور رجیستری Docker Hub | `download.docker.com` از ایران بسته است؛ **اثر انگشت کلید GPG** با کلید رسمی مقایسه می‌شود (میرور نمی‌تواند بسته‌ی دستکاری‌شده بدهد)؛ `daemon.json` ادغام می‌شود نه بازنویسی؛ لاگ‌چرخانی پیش‌فرض اضافه می‌شود؛ با یک `docker pull` واقعی تایید می‌شود |
| **BBR** | فعال‌سازی BBR | سرعت شبکه قبل و بعد اندازه‌گیری می‌شود؛ اگر بدتر شد، خودکار برمی‌گردد |
| **sysctl** | ۱۵+ پارامتر شبکه/کرنل متناسب با رم | فقط مقدارهایی که واقعاً باید تغییر کنند؛ مقدار قبلی نمایش داده می‌شود |
| **ابزارها** | git، htop، tmux، jq، ncdu، rsync، … | فقط بسته‌های موجود و نصب‌نشده |
| **منابع سیستم** | سوآپ (در صورت نبودن)، سقف فایل‌های باز، محدودسازی لاگ journald، TRIM، رفع خطای `unable to resolve host` | روی کانتینر/btrfs/zfs و دیسک کم، سوآپ ساخته نمی‌شود |
| **SSH** | `ClientAlive`، `LoginGraceTime`، `MaxAuthTries` | با `sshd -t` اعتبارسنجی؛ **رمز/root را عمداً دست نمی‌زند** تا قفل نشوید؛ فقط هشدار می‌دهد |
| **فایروال UFW** *(اختیاری)* | deny ورودی، آزاد خروجی | پورت SSH و پورت‌های در حال استفاده باز می‌مانند؛ SSH با rate-limit؛ **تایید ۴۵ ثانیه‌ای ضد قفل‌شدن** |
| **Fail2ban** *(اختیاری)* | محافظت از SSH | IP فعلی شما مستثنی می‌شود |
| **GitHub** | بررسی دسترسی به ۴ دامنه‌ی GitHub | مقایسه‌ی قبل/بعد از تغییر DNS |
| **زمان** | منطقه‌ی زمانی تهران + NTP | — |
| **آپدیت** | آپدیت/آپگرید با نوار پیشرفت | تشخیص نیاز به ریبوت؛ ریبوت فقط با ۶۰ ثانیه تاخیر و تایید |

## تفاوت با پروژه‌های مشابه

بر اساس README پروژه‌های عمومی مشابه در زمان نگارش:

| قابلیت | این پروژه | Linux-Optimizer | VPS-Optimizer-2 | iran-docker |
|---|:-:|:-:|:-:|:-:|
| میرور ایرانی بسته‌ها با تست سرعت و failover | ✅ | ❌ | ❌ | ❌ |
| DNS ایرانی + خارجی با تشخیص پاسخ جعلی | ✅ | ❌ (فقط Cloudflare) | ❌ | ✅ (چند مورد) |
| نصب Docker از میرور + راستی‌آزمایی کلید | ✅ | ❌ | ❌ | ✅ |
| میرور رجیستری Docker با تست زنده | ✅ | ❌ | ❌ | ✅ |
| BBR با اندازه‌گیری قبل/بعد و بازگشت | ✅ | ❌ | ❌ | ❌ |
| بازگردانی کامل (`--restore`) و پشتیبان خودکار | ✅ | بخشی | ❌ | بخشی |
| حالت `--dry-run` | ✅ | ❌ | ❌ | ❌ |
| UFW با محافظ ضد قفل‌شدن | ✅ | ❌ | ❌ | ❌ |
| منوی تعاملی + CLI غیرتعاملی | ✅ | منو | منو | منو |
| تست خودکار و CI | ✅ | ❌ | ❌ | ❌ |
| نصب کرنل XanMod | ❌ (عمداً؛ ریسک بوت) | ✅ | ✅ | ❌ |

> این جدول خلاصه‌ی برداشت ما از README آن پروژه‌هاست و ممکن است تغییر کرده باشد. اگر اشتباهی دیدید، Issue باز کنید.

## سیستم‌عامل‌های پشتیبانی‌شده

- **Ubuntu** 20.04 تا 26.04 (از جمله `deb822 .sources`) و مشتقات؛ **Debian** 11 تا 13
- **RHEL family:** Rocky، AlmaLinux، CentOS Stream، Fedora، Oracle Linux (dnf/yum)
- بخش‌های DNS، sysctl، BBR، زمان و آپدیت روی openSUSE، Alpine و Arch هم تا حد امکان کار می‌کند.

## ایمنی و بازگردانی

- قبل از هر تغییر، پشتیبان در `/var/backups/abrbaran-optimizer/<زمان>` و یک نسخه‌ی «اولیه» (فقط اولین اجرا) ذخیره می‌شود.
- هر تغییر حساس **تایید می‌شود** (resolve واقعی، `apt update` واقعی، `sshd -t`، `docker info`) و در صورت شکست، همان‌جا برگردانده می‌شود.
- با `Ctrl+C` هم تغییرات نیمه‌کاره برگردانده می‌شود.
- موارد حساس (Docker، فایروال، Fail2ban، ریبوت) هرگز بدون پرسش یا گزینه‌ی صریح فعال نمی‌شوند؛ `-y` فقط برای کارهای کم‌ریسک است.
- لاگ کامل هر اجرا: `/root/abrbaran-optimizer-<زمان>.log`
- بازگردانی: `sudo bash abrbaran-optimizer.sh --restore`
  (بسته‌های نصب‌شده، Docker، swapfile و UFW عمداً حذف نمی‌شوند.)

## افزودن DNS یا میرور

لیست‌ها بالای هر بخش در فایل اسکریپت‌اند (`DNS_IRAN`، `UBUNTU_MIRRORS`، `DEBIAN_MIRRORS`، `RPM_HOSTS`، `DOCKER_CE_BASES`، `DOCKER_REGISTRIES`). هر مورد در زمان اجرا تست می‌شود و ناسالم‌ها خودکار کنار می‌روند، پس افزودن یک مورد بی‌خطر است. آدرسی که به `@` ختم شود فقط «ریشه‌ی سایت» است و مسیر درست مخزن خودکار کشف می‌شود. با [قالب Issue افزودن میرور](.github/ISSUE_TEMPLATE/mirror_request.md) یا Pull Request مشارکت کنید؛ راهنما در [CONTRIBUTING.md](CONTRIBUTING.md).

## سوالات متداول

**آیا امن است؟** همه‌ی تغییرات پشتیبان‌گیری و تایید می‌شوند و `--dry-run` اجازه می‌دهد پیش از اجرا ببینید چه می‌شود. با این حال هیچ ابزاری ریسک صفر ندارد؛ روی سرور حیاتی ابتدا snapshot بگیرید.

**چرا PasswordAuthentication را غیرفعال نمی‌کنید؟** چون اگر هنوز کلید SSH نگذاشته باشید قفل می‌شوید. اسکریپت فقط هشدار و راهنما می‌دهد.

**چرا XanMod/BBRv3 ندارید؟** تعویض کرنل روی بسیاری از VPSها بوت را خراب می‌کند و بازگردانی‌اش آسان نیست. BBR استاندارد کرنل با اندازه‌گیری فعال می‌شود.

**روی OpenVZ/LXC چطور؟** پارامترهای کرنل قابل‌تغییر نیستند و اسکریپت آن‌ها را رد می‌کند؛ بقیه‌ی مراحل کار می‌کند.

## مشارکت و امنیت

Pull Request و Issue خوش‌آمد است؛ [CONTRIBUTING.md](CONTRIBUTING.md). گزارش آسیب‌پذیری: [SECURITY.md](SECURITY.md).

## مجوز

[MIT](LICENSE) — استفاده‌ی آزاد، شخصی و تجاری.

<p align="center">ساخته‌شده با ❤️ توسط <a href="https://abrbaranidc.ir">ابر باران (ABR BARAN IDC)</a></p>

</div>
