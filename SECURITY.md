# Security Policy

## گزارش آسیب‌پذیری / Reporting a vulnerability

لطفاً آسیب‌پذیری‌ها را **به‌صورت عمومی در Issue** گزارش نکنید. از بخش *Security → Report a vulnerability* همین مخزن (GitHub private advisory) استفاده کنید، یا از طریق وب‌سایت <https://abrbaranidc.ir> تماس بگیرید.

Please do not open public issues for vulnerabilities. Use *Security → Report a vulnerability* (private advisory) on this repository or contact us via <https://abrbaranidc.ir>.

## نکات امنیتی طراحی
- اسکریپت از اینترنت کد اجرا نمی‌کند؛ فقط فایل‌های داده (مثل Packages، Release) را برای تست می‌خواند. باینری Speedtest مستقیماً از سرور رسمی Ookla دریافت می‌شود.
- کلید GPG مخزن Docker با اثر انگشت رسمی `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` مقایسه می‌شود.
- تغییرات SSH فقط با drop-in و پس از `sshd -t` اعمال می‌شود و احراز هویت را سخت‌تر یا نرم‌تر نمی‌کند.
