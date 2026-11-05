#!/usr/bin/env bash
# تست‌های واحد (بدون نیاز به root و بدون اینترنت) — اجرا:  bash tests/run.sh
# تمام وابستگی‌های شبکه/سیستم با stub جایگزین می‌شوند.
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/abrbaran-optimizer.sh"
PASS=0; FAIL=0
t_ok()   { PASS=$((PASS + 1)); printf '  \033[32m✔\033[0m %s\n' "$1"; }
t_fail() { FAIL=$((FAIL + 1)); printf '  \033[31m✘\033[0m %s\n      %s\n' "$1" "${2:-}"; }
assert_contains() { case "$2" in *"$3"*) t_ok "$1" ;; *) t_fail "$1" "انتظار می‌رفت شامل «$3» باشد؛ خروجی: ${2:0:200}" ;; esac; }
assert_not_contains() { case "$2" in *"$3"*) t_fail "$1" "نباید شامل «$3» باشد" ;; *) t_ok "$1" ;; esac; }
assert_eq() { if [ "$2" = "$3" ]; then t_ok "$1"; else t_fail "$1" "انتظار «$3» ولی «$2»"; fi; }

echo "== CLI"
assert_contains "--version" "$(bash "$SCRIPT" --version)" "abrbaran-optimizer"
assert_contains "--help" "$(bash "$SCRIPT" --help)" "--only"
bash "$SCRIPT" --bogus >/dev/null 2>&1; assert_eq "گزینه‌ی ناشناخته → کد خروج 1" "$?" "1"
bash "$SCRIPT" --only nothing >/dev/null 2>&1; assert_eq "--only با نام نامعتبر → کد خروج 1" "$?" "1"

# بقیه‌ی تست‌ها اسکریپت را source می‌کنند (main اجرا نمی‌شود)
# shellcheck disable=SC1090
source "$SCRIPT"
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
PLAIN=true; IS_TTY=false; setup_ui; exec 3>&1
LOGFILE=$TMPD/log; : > "$LOGFILE"; BK=$TMPD/bk; ORIG=$TMPD/orig; mkdir -p "$BK"
write_awk_programs

echo "== ماژول‌ها"
ONLY_LIST=""; SKIP_LIST="update"
mod_on dns && t_ok "mod_on: dns فعال" || t_fail "mod_on dns"
mod_on update && t_fail "mod_on: update باید رد شود" || t_ok "mod_on: update رد شد"
ONLY_LIST="dns,docker"; SKIP_LIST=""
mod_on repo && t_fail "mod_on: --only باید repo را حذف کند" || t_ok "mod_on: --only فقط موارد خواسته شده"
ONLY_LIST=""

echo "== بازنویسی مخزن apt"
RE=$(apt_static_regex ubuntu)
cat > "$TMPD/ubuntu.sources" <<'X'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu/
Suites: resolute resolute-updates resolute-backports
Components: main restricted universe multiverse

Types: deb
URIs: http://security.ubuntu.com/ubuntu/
Suites: resolute-security
Components: main restricted universe multiverse
X
APT_FILES=("$TMPD/ubuntu.sources")
OLD=$(discover_old_uris resolute)
out=$(NEWBASE=http://m.example/ubuntu SECSUITE=resolute-security REPLSEC=0 STATICRE="$RE" OLDURIS="$OLD" awk -f "$TMPD/deb822.awk" "$TMPD/ubuntu.sources")
assert_contains "deb822: مخزن اصلی به میرور رفت" "$out" "URIs: http://m.example/ubuntu"
assert_contains "deb822: security رسمی حفظ شد" "$out" "URIs: http://security.ubuntu.com/ubuntu/"
cat > "$TMPD/one.sources" <<'X'
Types: deb
URIs: http://archive.ubuntu.com/ubuntu
Suites: resolute resolute-updates resolute-security
Components: main
X
out=$(NEWBASE=http://m.example/ubuntu SECSUITE=resolute-security REPLSEC=0 STATICRE="$RE" OLDURIS="$(APT_FILES=("$TMPD/one.sources"); discover_old_uris resolute)" awk -f "$TMPD/deb822.awk" "$TMPD/one.sources")
assert_contains "deb822: stanza مخلوط split شد (security رسمی)" "$out" "Suites: resolute-security"
assert_contains "deb822: بخش غیرامنیتی روی میرور" "$out" "URIs: http://m.example/ubuntu"
cat > "$TMPD/sources.list" <<'X'
deb http://us-east-1.ec2.archive.ubuntu.com/ubuntu/ noble main
deb http://security.ubuntu.com/ubuntu noble-security main
deb https://ppa.launchpadcontent.net/foo/ppa/ubuntu noble main
X
out=$(NEWBASE=http://m.example/ubuntu SECSUITE=noble-security REPLSEC=0 STATICRE="$RE" OLDURIS="$(APT_FILES=("$TMPD/sources.list"); discover_old_uris noble)" awk -f "$TMPD/classic.awk" "$TMPD/sources.list")
assert_contains "classic: مخزن cloud به میرور رفت" "$out" "deb http://m.example/ubuntu noble main"
assert_contains "classic: PPA دست‌نخورده" "$out" "ppa.launchpadcontent.net/foo/ppa/ubuntu"

echo "== failover مخزن (بدون شبکه)"
export APT_ETC=$TMPD/etc-apt; mkdir -p "$APT_ETC/sources.list.d"
cp "$TMPD/ubuntu.sources" "$APT_ETC/sources.list.d/ubuntu.sources"
cp "$TMPD/ubuntu.sources" "$TMPD/pristine"
collect_apt_files; apt_backup
P_FAMILY=ubuntu; P_SUITE=resolute; SEC_OFFICIAL_OK=true; APT_NEED_UPDATES=true
APT_CAND=("Bad|IR|http://bad.example/ubuntu|50|9000|1" "Good|INT|http://good.example/ubuntu|90|5000|1")
apt_run() { local t=$1; shift; [ "$1" = update ] || return 0
  if grep -q 'bad.example' "$APT_ETC/sources.list.d/ubuntu.sources"; then echo "Err:1 http://bad.example/ubuntu InRelease"; return 100; fi
  echo "Hit:1 http://good.example/ubuntu InRelease"; return 0; }
APT_CUR_IDX=-1; apt_failover_next >/dev/null 2>&1; rc=$?
assert_eq "failover: از Bad به Good رفت" "$APT_BEST_NAME" "Good"
assert_eq "failover: کد بازگشت 0" "$rc" "0"
apt_run() { echo "Err:1 http://x/ubuntu InRelease"; return 100; }
APT_CUR_IDX=-1; apt_failover_next >/dev/null 2>&1; rc=$?
assert_eq "failover: وقتی همه خراب‌اند rc=1" "$rc" "1"
cmp -s "$APT_ETC/sources.list.d/ubuntu.sources" "$TMPD/pristine" && t_ok "failover: فایل‌های اصلی دقیقاً بازگردانده شد" || t_fail "pristine restore"
unset APT_ETC

echo "== تشخیص خودکار مسیر میرور"
P_FAMILY=ubuntu; P_ARCH=amd64; P_SUITE=resolute
curl() { case "$*" in *"https://mirror.shatel.ir/"*) echo 200 ;; *) echo 000 ;; esac; }
dist_probe() { case "$1" in https://mirror.shatel.ir/repo/Ubuntu) echo 0.1 ;; *) return 1 ;; esac; }
assert_eq "مسیر /repo/Ubuntu پیدا شد" "$(resolve_auto_base https://mirror.shatel.ir)" "https://mirror.shatel.ir/repo/Ubuntu"
resolve_auto_base http://unreachable.example >/dev/null && t_fail "میزبان غیرقابل‌دسترس باید رد شود" || t_ok "میزبان غیرقابل‌دسترس رد شد"
unset -f curl dist_probe

echo "== Docker"
DOCKER_FLAVOR=ubuntu; DOCKER_CODENAMES=(resolute noble jammy); PKG_MGR=apt
curl() { case "$*" in
  *mirrors.aliyun.com/docker-ce/linux/ubuntu/dists/resolute/Release*) echo "404 0.100" ;;
  *mirrors.aliyun.com/docker-ce/linux/ubuntu/dists/noble/Release*) echo "200 0.200" ;;
  *download.docker.com*) echo "403 0.2" ;;
  *arvancloud*"/manifests/"*) echo "200 0.050" ;;
  *arvancloud*"/v2/"*) echo 200 ;;
  *) echo "000 0" ;; esac; }
assert_eq "codename fallback: resolute → noble" "$(docker_probe_item 'Aliyun|https://mirrors.aliyun.com/docker-ce')" "OK|200|Aliyun|https://mirrors.aliyun.com/docker-ce|noble"
assert_contains "docker.com مسدود → FAIL" "$(docker_probe_item 'Official|https://download.docker.com')" "FAIL|Official"
assert_contains "رجیستری سالم OK" "$(docker_registry_probe_item 'Arvan|https://docker.arvancloud.ir')" "OK|50|Arvan"
assert_contains "رجیستری مرده FAIL" "$(docker_registry_probe_item 'Dead|https://dead.example')" "FAIL|Dead"
unset -f curl
if command -v python3 >/dev/null 2>&1; then
  DOCKER_DAEMON_JSON=$TMPD/daemon.json
  echo '{"data-root":"/srv/docker","log-opts":{"max-size":"50m"}}' > "$DOCKER_DAEMON_JSON"
  docker_write_daemon_json https://a.example https://b.example
  merged=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["data-root"], d["log-opts"]["max-size"], d["log-opts"]["max-file"], len(d["registry-mirrors"]))' "$DOCKER_DAEMON_JSON")
  assert_eq "daemon.json: کلیدهای قبلی حفظ و میرور اضافه شد" "$merged" "/srv/docker 50m 3 2"
  echo '{bad json' > "$DOCKER_DAEMON_JSON"
  docker_write_daemon_json https://a.example; rc=$?
  assert_eq "daemon.json نامعتبر → دست‌نخورده و rc≠0" "$([ $rc -ne 0 ] && grep -q 'bad json' "$DOCKER_DAEMON_JSON" && echo yes)" "yes"
fi

echo "== DNS"
out=$(print_dns_table "$(printf 'iran|Shecan|1.1.1.1|3|2\nforeign|Cloudflare|1.1.1.1|1|2\niran|Dead|2.2.2.2|9999|0\n')")
assert_contains "جدول DNS: کندترین پایین‌تر" "$out" "Cloudflare"
assert_contains "جدول DNS: ناسالم‌ها جمع‌بندی" "$out" "Dead"

echo
if [ "$FAIL" -eq 0 ]; then printf '\033[32mهمه‌ی %d تست موفق بود.\033[0m\n' "$PASS"; exit 0
else printf '\033[31m%d تست ناموفق · %d موفق\033[0m\n' "$FAIL" "$PASS"; exit 1; fi
