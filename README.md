<div dir="rtl" align="right">

<h1 align="center">☁️ بهینه‌ساز سرور ایران — ابر باران</h1>

<p align="center">
<b>ABR BARAN · Iran Server Optimizer</b><br>
اسکریپت متن‌باز و امن برای راه‌اندازی و بهینه‌سازی سرور لینوکس (اوبونتو، دبیان، راکی، آلما) در ایران:<br>
<b>تنظیم DNS ایرانی · میرور ایرانی apt و yum · نصب Docker · فعال‌سازی BBR · امنیت SSH، فایروال و Fail2ban · آپدیت امن</b>
</p>

<p align="center">
<a href="https://github.com/MrAbediii/abrbaran-iran-server-optimizer/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/MrAbediii/abrbaran-iran-server-optimizer/actions/workflows/ci.yml/badge.svg"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue.svg"></a>
<img alt="Shell: bash" src="https://img.shields.io/badge/shell-bash-4EAA25.svg">
<img alt="Ubuntu · Debian · Rocky · Alma · Fedora" src="https://img.shields.io/badge/Ubuntu%20·%20Debian%20·%20Rocky%20·%20Alma%20·%20Fedora-supported-informational.svg">
<a href="https://abrbaranidc.ir"><img alt="ABR BARAN IDC" src="https://img.shields.io/badge/by-ABR%20BARAN%20IDC-0ea5e9.svg"></a>
</p>

<p align="center"><a href="README.en.md">English README</a> · <a href="https://abrbaranidc.ir">abrbaranidc.ir</a></p>

---

## خلاصه در یک نگاه

با **یک دستور**، سرور لینوکس شما در ایران آماده‌ی کار می‌شود: سریع‌ترین **میرور ایرانی اوبونتو و دبیان** انتخاب می‌شود، **DNS** درست تنظیم می‌شود، **Docker** از میرور سالم نصب می‌شود، **BBR** و تنظیمات کرنل اعمال می‌شود و امنیت پایه برقرار می‌گردد. هر تغییر **اندازه‌گیری، تایید و در صورت لزوم برگردانده** می‌شود.

```bash
curl -fsSL https://raw.githubusercontent.com/MrAbediii/abrbaran-iran-server-optimizer/main/abrbaran-optimizer.sh -o abrbaran-optimizer.sh \
  && sudo bash abrbaran-optimizer.sh
```

## این پروژه چه مشکل‌هایی را حل می‌کند؟

اگر روی سرور ایران با این مشکلات روبه‌رو شده‌اید، این ابزار برای شماست:

| مشکل رایج | راه‌حل در این پروژه |
|---|---|
| `apt update` کند است یا خطای `Temporary failure resolving` / `Failed to fetch` می‌دهد | تست موازیِ حدود ۹۰ میرور ایرانی و خارجی، انتخاب بر اساس **سرعت واقعی دانلود** و **failover خودکار** |
| `download.docker.com` یا `docker pull` از ایران باز نمی‌شود | نصب Docker از **میرورهای سالم** با راستی‌آزمایی کلید GPG و تنظیم **میرور رجیستری Docker Hub** |
| DNS سرور کند است یا صفحه‌ی مسدودسازی (`10.10.34.x`) برمی‌گرداند | تست ۲۵ DNS ایرانی و خارجی (شکن، الکترو، بگذر، رادار، Cloudflare، Google، Quad9، …) و حذف پاسخ‌های جعلی |
| دسترسی به GitHub قطع یا کند است | بررسی ۴ دامنه‌ی GitHub و مقایسه‌ی قبل و بعد از تغییر DNS |
| اوبونتو ۲۶.۰۴ یا دبیان ۱۳ میرور سازگار ندارد | تشخیص خودکار suite و مسیر مخزن، پشتیبانی از `deb822 (.sources)` |
| نگرانی از خراب شدن سرور با اسکریپت‌های «بهینه‌ساز» | پشتیبان خودکار، `--dry-run`، تایید هر مرحله و `--restore` |

## نصب و اجرا

```bash
curl -fsSL https://raw.githubusercontent.com/MrAbediii/abrbaran-iran-server-optimizer/main/abrbaran-optimizer.sh -o abrbaran-optimizer.sh \
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
| **DNS** | تست ۲۵ سرور DNS ایرانی و خارجی | پاسخ‌های جعلی/صفحه‌ی مسدودسازی شناسایی و حذف می‌شود؛ تایید نهایی با resolve واقعی؛ در صورت شکست، برگشت خودکار |
| **مخزن / میرور** | تست موازیِ حدود ۹۰ میرور Ubuntu/Debian/RPM (ایرانی + جهانی) | سرعت واقعی دانلود ۳ ایرانی + ۳ خارجی اندازه‌گیری می‌شود؛ مسیر مخزن خودکار کشف می‌شود؛ **failover**: اگر وسط `apt update/upgrade` میرور خراب شد، به بهترین میرور بعدی (نه قبلی!) می‌رود |
| **Docker** | نصب Docker Engine + Compose و تنظیم میرور رجیستری Docker Hub | **اثر انگشت کلید GPG** با کلید رسمی مقایسه می‌شود؛ `daemon.json` ادغام می‌شود نه بازنویسی؛ لاگ‌چرخانی پیش‌فرض؛ تایید با یک `docker pull` واقعی |
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

## میرورها و DNS های پشتیبانی‌شده

- **میرور ایرانی:** آروان‌کلود (ArvanCloud)، ایران‌سرور، پیشگامان، سینداد، مبین‌هاست، دانشگاه صنعتی اصفهان، شاتل، پردیسکو، ۰-۱ کلود، آبرها، پارس‌دو، افرانت و …
- **میرور جهانی:** Ubuntu/Debian رسمی، kernel.org، FAU، LeaseWeb، Init7، AARNet، Hetzner، OVH، Yandex، Tsinghua، USTC، Aliyun و …
- **DNS ایرانی:** شکن، الکترو، بگذر، رادار، ۴۰۳، وانیلا، DNSPro، پیشگامان، شاتل، آسیاتک، مخابرات و …
- **DNS جهانی:** Cloudflare، Google، Quad9، OpenDNS، ControlD، DNS.SB، Yandex، Level3، Verisign و …
- **رجیستری Docker:** آروان‌کلود، ایران‌سرور، HaioCloud، docker.ir، HamDocker، mirror.gcr.io و …

هر مورد در لحظه‌ی اجرا تست می‌شود و موارد ناسالم خودکار کنار می‌روند.

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

**بهترین میرور اوبونتو در ایران کدام است؟** بسته به دیتاسنتر و اپراتور شما فرق می‌کند؛ برای همین این ابزار روی خود سرور شما سرعت واقعی را اندازه می‌گیرد و بهترین را انتخاب می‌کند.

**چطور Docker را روی سرور ایران نصب کنم؟** `sudo bash abrbaran-optimizer.sh --only docker --docker` را اجرا کنید؛ از میرور سالم نصب می‌شود و میرور رجیستری هم تنظیم می‌گردد.

**آیا امن است؟** همه‌ی تغییرات پشتیبان‌گیری و تایید می‌شوند و `--dry-run` اجازه می‌دهد پیش از اجرا ببینید چه می‌شود. با این حال هیچ ابزاری ریسک صفر ندارد؛ روی سرور حیاتی ابتدا snapshot بگیرید.

**چرا PasswordAuthentication را غیرفعال نمی‌کنید؟** چون اگر هنوز کلید SSH نگذاشته باشید قفل می‌شوید. اسکریپت فقط هشدار و راهنما می‌دهد.

**چرا XanMod/BBRv3 ندارید؟** تعویض کرنل روی بسیاری از VPSها بوت را خراب می‌کند و بازگردانی‌اش آسان نیست. BBR استاندارد کرنل با اندازه‌گیری فعال می‌شود.

**روی OpenVZ/LXC چطور؟** پارامترهای کرنل قابل‌تغییر نیستند و اسکریپت آن‌ها را رد می‌کند؛ بقیه‌ی مراحل کار می‌کند.

## مشارکت و امنیت

- مشارکت: درخواست ادغام (Pull Request) و گزارش مشکل (Issue) خوش‌آمد است؛ [راهنمای مشارکت](https://github.com/MrAbediii/abrbaran-iran-server-optimizer/blob/main/CONTRIBUTING.md)
- امنیت: برای گزارش آسیب‌پذیری [سیاست امنیتی](https://github.com/MrAbediii/abrbaran-iran-server-optimizer/blob/main/SECURITY.md) را ببینید
- حمایت: اگر پروژه به کارتان آمد، به آن ستاره ⭐ بدهید

## مجوز

استفاده‌ی آزاد، شخصی و تجاری با مجوز [MIT](LICENSE).

<p align="center">ساخته‌شده با ❤️ توسط <a href="https://abrbaranidc.ir">ابر باران (ABR BARAN IDC)</a><br>
<sub>کلیدواژه‌ها: بهینه ساز سرور ایران · میرور اوبونتو ایران · میرور دبیان ایران · تغییر DNS سرور · نصب داکر در ایران · فعال سازی BBR · آپدیت اوبونتو ایران · ابر باران</sub></p>

</div>
