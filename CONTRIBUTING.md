# Contributing / راهنمای مشارکت

سپاس که می‌خواهید کمک کنید! Thanks for helping.

## افزودن DNS یا میرور
1. لیست مناسب را در `abrbaran-optimizer.sh` پیدا کنید: `DNS_IRAN`، `DNS_FOREIGN`، `UBUNTU_MIRRORS`، `DEBIAN_MIRRORS`، `RPM_HOSTS`، `DOCKER_CE_BASES`، `DOCKER_REGISTRIES`.
2. فرمت `نام|ناحیه|آدرس` را رعایت کنید (ناحیه: `IR` یا `INT`). اگر مسیر دقیق مخزن را نمی‌دانید، آدرس را با `@` تمام کنید (`https://mirror.example.ir@`) تا مسیر خودکار کشف شود.
3. با `curl -I <url>/dists/<codename>/InRelease` (یا `/v2/` برای رجیستری) از یک سرور ایرانی درستی را بسنجید.
4. فقط سرویس‌های عمومی و قانونی؛ DNS تبلیغاتی/فیلترشده برای سرور مناسب نیست.

## تغییر کد
- فقط `bash` (سازگار با 4.2+)، بدون آرایه‌های انجمنی (`declare -A`)، بدون وابستگی جدید اجباری.
- هر تغییر روی سرور باید: **پشتیبان‌گیری → اعمال → تایید → بازگردانی در صورت شکست** داشته باشد، و در `--restore` و `--dry-run` هم رفتار درست داشته باشد.
- قبل از PR:
  ```bash
  bash -n abrbaran-optimizer.sh
  bash tests/run.sh
  shellcheck -S error abrbaran-optimizer.sh   # در صورت نصب بودن
  ```
- برای هر قابلیت جدید در `tests/run.sh` تست اضافه کنید (شبکه و دستورهای سیستمی را stub کنید).
- `CHANGELOG.md` را به‌روز کنید.
