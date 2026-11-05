#!/usr/bin/env bash
#
# =============================================================================
#   ABR BARAN IDC . IR  —  Iran Server Optimizer  v4.0.0
#   بهینه‌ساز سرور ایران · ابر باران
#
#   DNS  ·  Repository (با failover چندمرحله‌ای)  ·  GitHub  ·  BBR  ·  Kernel
#   Docker  ·  Swap/Limits  ·  SSH/UFW/Fail2ban  ·  Speedtest  ·  NTP  ·  Update
#   Backup & Restore  ·  Status
#
#   License: MIT   ·   https://abrbaranidc.ir
# =============================================================================

SCRIPT_VERSION="4.0.0"
PROJECT_URL="https://github.com/aliabedi94/abrbaran-iran-server-optimizer"

usage() {
cat <<'EOF'
استفاده:
  sudo bash abrbaran-optimizer.sh [گزینه‌ها]
  (بدون گزینه و در ترمینال تعاملی، منوی اصلی نمایش داده می‌شود)

گزینه‌های عمومی:
  -y, --yes           پاسخ خودکار «بله» به سوالات کم‌ریسک (Speedtest، ابزارها، منطقه‌زمانی، آپدیت)
                      — ریبوت، Docker، فایروال و Fail2ban هرگز بدون گزینه‌ی صریح فعال نمی‌شوند
      --dry-run       فقط تست و گزارش؛ هیچ تغییری روی سرور اعمال نمی‌شود
      --restore       بازگردانی تنظیمات اولیه‌ی سرور (DNS، مخزن، sysctl، SSH، limits، Docker)
      --status        گزارش وضعیت سرور (فقط خواندنی)
      --plain         خروجی ساده بدون رنگ و نمادهای یونیکد
      --show-all      نمایش کامل جدول DNS و مخزن‌ها (پیش‌فرض: فقط برترین‌ها)
      --reboot-now    ریبوت امن خودکار در پایان، فقط اگر واقعاً لازم باشد
  -v, --version       نمایش نسخه
  -h, --help          نمایش همین راهنما

انتخاب مرحله‌ها:
      --only a,b,c    فقط این مرحله‌ها اجرا شوند
      --skip-<نام>    رد کردن یک مرحله (مثلاً --skip-update)
      نام مرحله‌ها:   dns repo github bbr tune tools system docker security speedtest time update

فعال‌سازی صریحِ قابلیت‌های حساس:
      --docker        نصب Docker + Compose و تنظیم میرور رجیستری بدون پرسش
      --firewall      فعال‌سازی فایروال UFW (SSH و پورت‌های در حال استفاده باز می‌مانند)
      --fail2ban      نصب و فعال‌سازی Fail2ban برای SSH

مثال‌ها:
  sudo bash abrbaran-optimizer.sh                         # منوی تعاملی
  sudo bash abrbaran-optimizer.sh -y --docker             # همه‌چیز + Docker، بدون پرسش
  sudo bash abrbaran-optimizer.sh --only docker --docker  # فقط Docker
  sudo bash abrbaran-optimizer.sh --only dns,repo         # فقط DNS و میرور
  sudo bash abrbaran-optimizer.sh -y --skip-update        # بدون آپدیت سیستم
EOF
}

ALL_MODS="dns repo github bbr tune tools system docker security speedtest time update"
ONLY_LIST=""
SKIP_LIST=""
AUTO_YES=false
FORCE_SKIP_SPEEDTEST=false
FORCE_SKIP_UPDATE=false
FORCE_REBOOT=false
SKIP_DNS=false
SKIP_REPO=false
SKIP_BBR=false
SKIP_TUNE=false
DRY_RUN=false
DO_RESTORE=false
PLAIN=false
SHOW_ALL=false
DO_STATUS=false
DO_DOCKER=false
DO_FIREWALL=false
DO_FAIL2BAN=false
BANNER_SHOWN=false
ARGC=0

has_word() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }

parse_args() {
  local m
  ARGC=$#
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes)          AUTO_YES=true ;;
      --skip-speedtest)  FORCE_SKIP_SPEEDTEST=true; SKIP_LIST+=",speedtest" ;;
      --skip-update)     FORCE_SKIP_UPDATE=true; SKIP_LIST+=",update" ;;
      --skip-*)
        m=${1#--skip-}
        if has_word "$(echo "$ALL_MODS" | tr ' ' ',')" "$m"; then SKIP_LIST+=",$m"
        else echo "مرحله‌ی ناشناخته: $m  (مرحله‌ها: $ALL_MODS)" >&2; exit 1; fi ;;
      --only=*)          set -- "--only" "${1#--only=}" "${@:2}"; continue ;;
      --only)            shift; ONLY_LIST="${1:-}"
        [ -z "$ONLY_LIST" ] && { echo "--only نیازمند فهرست مرحله‌هاست" >&2; exit 1; }
        for m in $(echo "$ONLY_LIST" | tr ',' ' '); do
          has_word "$(echo "$ALL_MODS" | tr ' ' ',')" "$m" || { echo "مرحله‌ی ناشناخته: $m  (مرحله‌ها: $ALL_MODS)" >&2; exit 1; }
        done ;;
      --docker)          DO_DOCKER=true ;;
      --firewall)        DO_FIREWALL=true ;;
      --fail2ban)        DO_FAIL2BAN=true ;;
      --reboot-now)      FORCE_REBOOT=true ;;
      --dry-run)         DRY_RUN=true ;;
      --restore)         DO_RESTORE=true ;;
      --status)          DO_STATUS=true ;;
      --plain)           PLAIN=true ;;
      --show-all)        SHOW_ALL=true ;;
      -v|--version)      echo "abrbaran-optimizer ${SCRIPT_VERSION}"; exit 0 ;;
      -h|--help)         usage; exit 0 ;;
      *) echo "گزینه‌ی ناشناخته: $1  (برای راهنما: --help)" >&2; exit 1 ;;
    esac
    shift
  done
  SKIP_LIST="${SKIP_LIST#,}"
}

set -o pipefail

# =============================================================================
#  رابط کاربری: رنگ، نماد، کادر، اسپینر، نوار پیشرفت
# =============================================================================
IS_TTY=false
[ -t 1 ] && IS_TTY=true
exec 3>&1   # خروجی اصلی ترمینال (برای اسپینر/نوار پیشرفت که نباید وارد لاگ شوند)

C_RESET=""; C_BOLD=""; C_DIM=""; C_ACC=""; C_OK=""; C_WARN=""; C_ERR=""; C_GRAY=""; C_GOLD=""; C_MAG=""
S_OK="+"; S_ERR="x"; S_WARN="!"; S_INFO="*"; S_STEP="#"; S_STAR="*"; S_ARROW=">"
B_FULL="#"; B_EMPTY="-"; HR_CH="="; SPIN_FRAMES=("-" "\\" "|" "/")
BOX_TL="+"; BOX_TR="+"; BOX_BL="+"; BOX_BR="+"; BOX_H="-"; BOX_V="|"

setup_ui() {
  local use_color=false use_uni=true n=8 e
  if [ "$IS_TTY" = true ] && [ -z "${NO_COLOR:-}" ] && [ "$PLAIN" != true ] && [ "${TERM:-dumb}" != "dumb" ]; then
    use_color=true
    n=$(tput colors 2>/dev/null || echo 8)
  fi
  [ "$PLAIN" = true ] && use_uni=false
  if [ "$use_color" = true ]; then
    e=$'\033['
    C_RESET="${e}0m"; C_BOLD="${e}1m"; C_DIM="${e}2m"
    if [ "${n:-8}" -ge 256 ] 2>/dev/null; then
      C_ACC="${e}38;5;81m";  C_OK="${e}38;5;78m";   C_WARN="${e}38;5;214m"
      C_ERR="${e}38;5;203m"; C_GRAY="${e}38;5;245m"; C_GOLD="${e}38;5;220m"; C_MAG="${e}38;5;177m"
    else
      C_ACC="${e}36m"; C_OK="${e}32m"; C_WARN="${e}33m"; C_ERR="${e}31m"
      C_GRAY="${e}90m"; C_GOLD="${e}33m"; C_MAG="${e}35m"
    fi
  fi
  if [ "$use_uni" = true ]; then
    S_OK="✔"; S_ERR="✘"; S_WARN="▲"; S_INFO="●"; S_STEP="◆"; S_STAR="★"; S_ARROW="❯"
    B_FULL="█"; B_EMPTY="░"; HR_CH="━"
    SPIN_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    BOX_TL="╭"; BOX_TR="╮"; BOX_BL="╰"; BOX_BR="╯"; BOX_H="─"; BOX_V="│"
  fi
}

rep() { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

# عرض نمایشی یک رشته (تعداد کاراکترها، مستقل از locale؛ بایت‌های ادامه‌ی UTF-8 حذف می‌شوند)
dispw() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | LC_ALL=C wc -c | tr -d ' '; }

info() { printf '  %s%s%s %s\n' "$C_ACC"  "$S_INFO" "$C_RESET" "$*"; }
ok()   { printf '  %s%s%s %s\n' "$C_OK"   "$S_OK"   "$C_RESET" "$*"; }
warn() { printf '  %s%s%s %s\n' "$C_WARN" "$S_WARN" "$C_RESET" "$*"; }
err()  { printf '  %s%s%s %s\n' "$C_ERR"  "$S_ERR"  "$C_RESET" "$*"; }
note() { printf '    %s%s%s\n' "$C_GRAY" "$*" "$C_RESET"; }
blank() { printf '\n'; }

STEP_NO=0
STEP_TOTAL=8
count_steps() {
  local n=1 m
  for m in dns repo github tools system docker security speedtest time update; do mod_on "$m" && n=$((n + 1)); done
  if mod_on bbr || mod_on tune; then n=$((n + 1)); fi
  STEP_TOTAL=$n
}
step() {
  STEP_NO=$((STEP_NO + 1))
  printf '\n%s%s%s\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"
  printf ' %s%s%s %s%d/%d%s  %s%s%s\n' "$C_GOLD" "$S_STEP" "$C_RESET" "$C_GRAY" "$STEP_NO" "$STEP_TOTAL" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
  printf '%s%s%s\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"
}

box_line() { # متن داخل کادر با پدینگ دقیق بر اساس عرض نمایشی
  local text="$1" style="${2:-}" w=58 tw pad
  tw=$(dispw "$text"); pad=$((w - tw)); [ "$pad" -lt 0 ] && pad=0
  printf '  %s%s%s%s%s%s%s%s\n' "$C_ACC" "$BOX_V" "$style" "$text" "$C_RESET" "$C_ACC" "$(rep ' ' "$pad")" "$BOX_V$C_RESET"
}

banner() {
  [ "$BANNER_SHOWN" = true ] && return 0
  BANNER_SHOWN=true
  local line; line=$(rep "$BOX_H" 58)
  printf '\n%s  %s%s%s%s\n' "$C_ACC" "$BOX_TL" "$line" "$BOX_TR" "$C_RESET"
  box_line ""
  box_line "      A B R   B A R A N   I D C . I R" "$C_BOLD"
  box_line "      Iran Server Optimizer  ·  v${SCRIPT_VERSION}" "$C_GRAY"
  box_line ""
  printf '%s  %s%s%s%s\n\n' "$C_ACC" "$BOX_BL" "$line" "$BOX_BR" "$C_RESET"
  printf '  %sبهینه‌ساز سرور ایران — DNS، میرور، Docker، شبکه، امنیت و آپدیت امن%s\n' "$C_GRAY" "$C_RESET"
  if [ "$DRY_RUN" = true ]; then
    printf '  %s%s حالت آزمایشی (dry-run): هیچ تغییری روی سرور اعمال نمی‌شود%s\n' "$C_WARN" "$S_WARN" "$C_RESET"
  fi
}

# یک خط «برچسب ······ مقدار» با نقطه‌چین هم‌تراز
kv() {
  local icon="$1" label="$2" value="$3" w pad
  w=$(dispw "$label"); pad=$((26 - w)); [ "$pad" -lt 2 ] && pad=2
  printf '  %s %s %s%s%s %s\n' "$icon" "$label" "$C_GRAY" "$(rep '·' "$pad")" "$C_RESET" "$value"
}

# نوار پیشرفت (فقط روی ترمینال، نه لاگ)
progress_bar() { # cur total label
  [ "$IS_TTY" = true ] || return 0
  local cur=$1 tot=$2 label=$3 wd=24 fill
  [ "$tot" -le 0 ] && return 0
  fill=$((cur * wd / tot))
  printf '\r\033[K  %s%s%s%s%s %s%d/%d%s  %s' "$C_ACC" "$(rep "$B_FULL" "$fill")" "$C_GRAY" "$(rep "$B_EMPTY" $((wd - fill)))" "$C_RESET" "$C_GRAY" "$cur" "$tot" "$C_RESET" "$label" >&3
}
progress_clear() { [ "$IS_TTY" = true ] && printf '\r\033[K' >&3; return 0; }

# اسپینر/نوار پیشرفت: اجرای یک دستور (یا تابع) در پس‌زمینه؛ خروجی در $SPIN_OUT
#   SPIN_PROGRESS_FN : تابعی که "cur|total|برچسب" برمی‌گرداند → نوار درصدی
#   SPIN_SUFFIX_FN   : تابعی که فقط یک برچسب کوتاه برمی‌گرداند → اسپینر ساده
# پس از پایان، یک خط ماندگار (✔/✘ + زمان) چاپ می‌شود تا در خروجی و لاگ بماند.
SPIN_OUT=""
SPIN_SUFFIX_FN=""
SPIN_PROGRESS_FN=""
SPIN_QUIET=false
with_spinner() {
  local msg="$1"; shift
  local pid i=0 start=$SECONDS rc suffix="" last=-100 prog cur tot pct fill bar="" el
  SPIN_OUT=$(mktemp "$TMPD/spin.XXXXXX")
  "$@" >"$SPIN_OUT" 2>&1 &
  pid=$!
  if [ "$IS_TTY" = true ]; then
    while kill -0 "$pid" 2>/dev/null; do
      if [ $((SECONDS - last)) -ge 1 ]; then
        last=$SECONDS; bar=""
        if [ -n "$SPIN_PROGRESS_FN" ]; then
          prog=$("$SPIN_PROGRESS_FN" "$SPIN_OUT" 2>/dev/null)
          IFS='|' read -r cur tot suffix <<<"$prog"
          if [ "${tot:-0}" -gt 0 ] 2>/dev/null; then
            [ "${cur:-0}" -gt "$tot" ] && cur=$tot
            pct=$((cur * 100 / tot)); fill=$((cur * 20 / tot))
            bar="  ${C_ACC}$(rep "$B_FULL" "$fill")${C_GRAY}$(rep "$B_EMPTY" $((20 - fill)))${C_RESET} ${C_BOLD}${pct}%${C_RESET}"
          fi
        elif [ -n "$SPIN_SUFFIX_FN" ]; then
          suffix=$("$SPIN_SUFFIX_FN" "$SPIN_OUT" 2>/dev/null)
        fi
      fi
      printf '\r\033[K  %s%s%s %s%s  %s%ds%s  %s%s%s' "$C_ACC" "${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}" "$C_RESET" "$msg" "$bar" "$C_GRAY" "$((SECONDS - start))" "$C_RESET" "$C_GRAY" "$suffix" "$C_RESET" >&3
      i=$((i + 1)); sleep 0.12
    done
    printf '\r\033[K' >&3
  else
    info "$msg ..."
  fi
  wait "$pid"; rc=$?
  el=$((SECONDS - start))
  if [ "$SPIN_QUIET" != true ]; then
    if [ "$rc" -eq 0 ]; then ok "$msg  ${C_GRAY}(${el}s)${C_RESET}"; else err "$msg  ${C_GRAY}(ناموفق · ${el}s)${C_RESET}"; fi
  fi
  return $rc
}

# =============================================================================
#  اجرای موازی (برای تست سریع DNS و مخزن‌ها) با نوار پیشرفت
# =============================================================================
count_done() { local c=0 f; for f in "$1"/*.done; do [ -e "$f" ] && c=$((c + 1)); done; echo "$c"; }

par_run() { # label maxjobs outdir func item...
  local label="$1" maxj="$2" dir="$3" fn="$4"; shift 4
  local total=$# started=0 done_n item pids=() pid
  rm -rf "$dir"; mkdir -p "$dir"
  for item in "$@"; do
    while :; do
      done_n=$(count_done "$dir")
      [ $((started - done_n)) -lt "$maxj" ] && break
      progress_bar "$done_n" "$total" "$label"; sleep 0.1
    done
    ( "$fn" "$item" >"$dir/$started.out" 2>/dev/null; : >"$dir/$started.done" ) &
    pids+=($!)
    started=$((started + 1))
  done
  while :; do
    done_n=$(count_done "$dir")
    progress_bar "$done_n" "$total" "$label"
    [ "$done_n" -ge "$total" ] && break
    sleep 0.1
  done
  # فقط منتظر کارهای خودِ par_run می‌مانیم (wait بدون آرگومان با process substitution لاگ گیر می‌کند)
  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
  progress_clear
}

par_collect() { # dir -> همه‌ی خروجی‌ها به ترتیب
  local dir="$1" f
  for f in $(ls -1 "$dir" 2>/dev/null | grep '\.out$' | sort -n); do cat "$dir/$f"; done
}

# =============================================================================
#  ابزارهای عمومی: پرسش، وضعیت‌ها، پشتیبان‌گیری
# =============================================================================
TMPD=""; LOGFILE=""; BACKUP_ROOT="/var/backups/abrbaran-optimizer"; BK=""; ORIG=""
SCRIPT_START_EPOCH=$(date +%s)

tty_usable() { ( : </dev/tty ) 2>/dev/null; }

# confirm "پرسش" force(yes|no|"") default(y|n)
confirm() {
  local prompt="$1" force="${2:-}" def="${3:-n}" hint ans
  case "$force" in yes) return 0 ;; no) return 1 ;; esac
  if [ "$def" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
  if ! tty_usable; then [ "$def" = "y" ] && [ "$AUTO_YES" = true ]; return; fi
  printf '\n  %s%s%s %s %s%s%s ' "$C_GOLD" "$S_ARROW" "$C_RESET" "$prompt" "$C_GRAY" "$hint" "$C_RESET" >/dev/tty
  read -r ans </dev/tty
  printf '  [پرسش] %s -> %s\n' "$prompt" "$ans" >> "$LOGFILE"
  [ -z "$ans" ] && { [ "$def" = "y" ]; return; }
  [[ "$ans" =~ ^([yY][eE][sS]|[yY]|بله|بلی)$ ]]
}

# set_st KEY kind text   (kind: ok | warn | err | skip)
set_st() { printf -v "ST_$1" '%s' "$2|$3"; }
get_st() { local v="ST_$1"; printf '%s' "${!v:-skip|انجام نشد}"; }

# bk_save SRC NAME : کپی در پشتیبان این اجرا و (اگر هنوز نیست) در پشتیبان «اولیه»
bk_save() {
  local src="$1" name="$2"
  [ -e "$src" ] || [ -L "$src" ] || return 0
  mkdir -p "$BK/$(dirname "$name")" 2>/dev/null
  cp -a "$src" "$BK/$name" 2>/dev/null
  if [ ! -e "$ORIG/$name" ] && [ ! -L "$ORIG/$name" ]; then
    mkdir -p "$ORIG/$(dirname "$name")" 2>/dev/null
    cp -a "$src" "$ORIG/$name" 2>/dev/null
  fi
}

url_host() { local u="${1#*://}"; printf '%s' "${u%%/*}"; }

ms_now() {
  local n; n=$(date +%s%N 2>/dev/null)
  case "$n" in *N|"") echo $(($(date +%s) * 1000)) ;; *) echo $((n / 1000000)) ;; esac
}

# =============================================================================
#  برنامه‌های awk (به‌جای sed پیچیده؛ سازگار با mawk/gawk/busybox)
# =============================================================================
write_awk_programs() {
cat > "$TMPD/deb822.awk" <<'AWK'
function norm(u) { sub(/\/+$/, "", u); return u }
function is_old(tok,   t, i) {
  t = norm(tok)
  for (i = 1; i <= no; i++) if (OLD[i] != "" && norm(OLD[i]) == t) return 1
  if (STATIC != "" && tok ~ STATIC) return 1
  return 0
}
function dump(arr, cnt,   i) { for (i = 1; i <= cnt; i++) print arr[i] }
function flush(   i, ui, si, ln, toks, nt, k, t, matched, newuris, sl, suites, ns, j, secs, oth, A, B) {
  if (n == 0) return
  ui = 0; si = 0
  for (i = 1; i <= n; i++) {
    if (L[i] ~ /^[ \t]*URIs:/) ui = i
    if (L[i] ~ /^[ \t]*Suites:/) si = i
  }
  if (ui == 0) { dump(L, n); n = 0; return }
  ln = L[ui]; sub(/^[ \t]*URIs:[ \t]*/, "", ln)
  nt = split(ln, toks, /[ \t]+/)
  matched = 0; newuris = ""
  for (k = 1; k <= nt; k++) {
    if (toks[k] == "") continue
    if (is_old(toks[k])) { matched = 1; t = NEWBASE } else t = toks[k]
    if (index(" " newuris " ", " " t " ") == 0) newuris = (newuris == "" ? t : newuris " " t)
  }
  if (!matched) { dump(L, n); n = 0; return }
  secs = ""; oth = ""
  if (si > 0 && REPLSEC == 0) {
    sl = L[si]; sub(/^[ \t]*Suites:[ \t]*/, "", sl)
    ns = split(sl, suites, /[ \t]+/)
    for (j = 1; j <= ns; j++) {
      if (suites[j] == "") continue
      if (suites[j] == SEC) secs = (secs == "" ? suites[j] : secs " " suites[j])
      else oth = (oth == "" ? suites[j] : oth " " suites[j])
    }
  }
  if (secs == "") {
    L[ui] = "URIs: " newuris; dump(L, n)
  } else if (oth == "") {
    dump(L, n)
  } else {
    for (i = 1; i <= n; i++) { A[i] = L[i]; B[i] = L[i] }
    A[ui] = "URIs: " newuris; A[si] = "Suites: " oth
    B[si] = "Suites: " secs
    dump(A, n); print ""; dump(B, n)
  }
  n = 0
}
BEGIN {
  NEWBASE = ENVIRON["NEWBASE"]; SEC = ENVIRON["SECSUITE"]; REPLSEC = ENVIRON["REPLSEC"] + 0
  STATIC = ENVIRON["STATICRE"]; no = split(ENVIRON["OLDURIS"], OLD, "\n"); n = 0
}
{ if ($0 ~ /^[ \t]*$/) { flush(); print } else { L[++n] = $0 } }
END { flush() }
AWK

cat > "$TMPD/classic.awk" <<'AWK'
function norm(u) { sub(/\/+$/, "", u); return u }
function is_old(tok,   t, i) {
  t = norm(tok)
  for (i = 1; i <= no; i++) if (OLD[i] != "" && norm(OLD[i]) == t) return 1
  if (STATIC != "" && tok ~ STATIC) return 1
  return 0
}
BEGIN {
  NEWBASE = ENVIRON["NEWBASE"]; SEC = ENVIRON["SECSUITE"]; REPLSEC = ENVIRON["REPLSEC"] + 0
  STATIC = ENVIRON["STATICRE"]; no = split(ENVIRON["OLDURIS"], OLD, "\n")
}
{
  line = $0
  if (line ~ /^[ \t]*deb(-src)?[ \t]/ && match(line, /[a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^ \t]+/)) {
    uri = substr(line, RSTART, RLENGTH)
    after = substr(line, RSTART + RLENGTH)
    pre = substr(line, 1, RSTART - 1)
    split(after, f, /[ \t]+/)
    suite = f[2]
    if (is_old(uri) && (REPLSEC == 1 || suite != SEC)) line = pre NEWBASE after
  }
  print line
}
AWK

cat > "$TMPD/rpm.awk" <<'AWK'
BEGIN { HOST = ENVIRON["HOST"]; NOPUB = ENVIRON["NOPUB"] + 0; CD = ENVIRON["CDIR"]; OFF = ENVIRON["OFFRE"] }
{
  line = $0
  if (line ~ /^[ \t]*(mirrorlist|metalink)[ \t]*=/) {
    sub(/^[ \t]*/, "", line); line = "#" line
  } else if (line ~ /^[ \t]*#?[ \t]*baseurl[ \t]*=/) {
    v = line; sub(/^[ \t]*#?[ \t]*baseurl[ \t]*=[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
    if (v ~ OFF) {
      p = v; sub(/^[a-zA-Z]+:\/\/[^\/]+/, "", p)
      if (CD != "") gsub(/\$contentdir/, CD, p)
      if (NOPUB == 1) sub(/^\/pub\//, "/", p)
      line = "baseurl=https://" HOST p
    }
  }
  print line
}
AWK
}

# =============================================================================
#  بخش ۱: تشخیص سیستم‌عامل، مدیر بسته، ابزارهای لازم
# =============================================================================
OS_ID="unknown"; OS_VERSION=""; OS_PRETTY=""; OS_LIKE=""; OS_CODENAME=""; OS_UBUNTU_CODENAME=""
PKG_MGR="unknown"; MIRROR_FAMILY=""; APT_CODENAME=""; ARCH_DEB=""; ARCH_RPM=""
HAS_CURL=false; HAS_DIG=false; HAS_HOST=false
APT_ENV=(env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 APT_LISTCHANGES_FRONTEND=none)

OSR_FILE="${OSR_FILE:-/etc/os-release}"
RESOLV_CONF="${RESOLV_CONF:-/etc/resolv.conf}"
osr() { # خواندن امن یک کلید از os-release بدون source کردن فایل
  [ -r "$OSR_FILE" ] || return 0
  sed -n -E "s/^$1=//p" "$OSR_FILE" | head -n1 | sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

detect_os() {
  OS_ID=$(osr ID); OS_ID=${OS_ID:-unknown}
  OS_VERSION=$(osr VERSION_ID); OS_PRETTY=$(osr PRETTY_NAME); OS_PRETTY=${OS_PRETTY:-$OS_ID}
  OS_LIKE=$(osr ID_LIKE); OS_CODENAME=$(osr VERSION_CODENAME); OS_UBUNTU_CODENAME=$(osr UBUNTU_CODENAME)
  local key=" $OS_ID $OS_LIKE "

  case "$key" in
    *" ubuntu "*|*" debian "*)
      PKG_MGR="apt" ;;
    *" rhel "*|*" centos "*|*" fedora "*|*" almalinux "*|*" rocky "*|*" ol "*|*" amzn "*)
      if command -v dnf >/dev/null 2>&1; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi ;;
    *" suse "*|*" opensuse "*|*" sles "*|*" opensuse-leap "*|*" opensuse-tumbleweed "*)
      PKG_MGR="zypper" ;;
    *" alpine "*)  PKG_MGR="apk" ;;
    *" arch "*)    PKG_MGR="pacman" ;;
    *)
      if   command -v apt-get >/dev/null 2>&1; then PKG_MGR="apt"
      elif command -v dnf     >/dev/null 2>&1; then PKG_MGR="dnf"
      elif command -v yum     >/dev/null 2>&1; then PKG_MGR="yum"
      elif command -v zypper  >/dev/null 2>&1; then PKG_MGR="zypper"
      elif command -v apk     >/dev/null 2>&1; then PKG_MGR="apk"
      elif command -v pacman  >/dev/null 2>&1; then PKG_MGR="pacman"
      fi ;;
  esac

  # خانواده‌ی مخزن apt: ubuntu (شامل مشتقات مثل Mint/Pop) یا debian
  MIRROR_FAMILY=""
  if [ "$PKG_MGR" = "apt" ]; then
    if [ "$OS_ID" = "ubuntu" ] || [ -n "$OS_UBUNTU_CODENAME" ]; then MIRROR_FAMILY="ubuntu"
    elif [ "$OS_ID" = "debian" ]; then MIRROR_FAMILY="debian"
    fi
  fi
  ARCH_RPM=$(uname -m)
  ARCH_DEB=$(dpkg --print-architecture 2>/dev/null || echo "")
}

apt_lists_empty() { [ -z "$(ls -A /var/lib/apt/lists 2>/dev/null | grep -v -e '^lock$' -e '^partial$')" ]; }

pkg_install() { # نصب بی‌صدا با timeout (تا مخزن کند/خراب، اسکریپت را برای همیشه نگه ندارد)
  [ "$DRY_RUN" = true ] && return 1
  case "$PKG_MGR" in
    apt)
      if timeout 120 "${APT_ENV[@]}" apt-get install -y -qq -o DPkg::Lock::Timeout=60 "$@" >/dev/null 2>&1; then return 0; fi
      if apt_lists_empty; then   # ایمیج‌های تازه معمولاً فهرست بسته ندارند
        timeout 90 "${APT_ENV[@]}" apt-get update -qq -o Acquire::Retries=0 >/dev/null 2>&1
        timeout 120 "${APT_ENV[@]}" apt-get install -y -qq -o DPkg::Lock::Timeout=60 "$@" >/dev/null 2>&1; return
      fi
      return 1 ;;
    dnf)    timeout 120 dnf install -y "$@" >/dev/null 2>&1 ;;
    yum)    timeout 120 yum install -y "$@" >/dev/null 2>&1 ;;
    zypper) timeout 120 zypper --non-interactive install "$@" >/dev/null 2>&1 ;;
    apk)    timeout 90 apk add --no-cache "$@" >/dev/null 2>&1 ;;
    pacman) timeout 120 pacman -S --noconfirm --needed "$@" >/dev/null 2>&1 ;;
    *)      return 1 ;;
  esac
}

install_dig_apt() { pkg_install bind9-dnsutils || pkg_install dnsutils; }

ensure_tools() {
  if command -v curl >/dev/null 2>&1; then HAS_CURL=true
  else
    with_spinner "نصب curl" pkg_install curl
    if command -v curl >/dev/null 2>&1; then HAS_CURL=true
    else warn "نصب curl ممکن نشد؛ تست مخزن، BBR و GitHub محدود می‌شوند."; fi
  fi
  if command -v dig >/dev/null 2>&1; then HAS_DIG=true
  else
    case "$PKG_MGR" in
      apt)     with_spinner "نصب dig (برای تست دقیق DNS)" install_dig_apt ;;
      dnf|yum|zypper) with_spinner "نصب dig (برای تست دقیق DNS)" pkg_install bind-utils ;;
      apk)     with_spinner "نصب dig (برای تست دقیق DNS)" pkg_install bind-tools ;;
      pacman)  with_spinner "نصب dig (برای تست دقیق DNS)" pkg_install bind ;;
    esac
    if command -v dig >/dev/null 2>&1; then HAS_DIG=true
    else
      command -v host >/dev/null 2>&1 && HAS_HOST=true
      warn "نصب dig ممکن نشد؛ از ابزار جایگزین (host/ping) با دقت کمتر استفاده می‌شود."
    fi
  fi
}

# =============================================================================
#  بخش ۲: تست موازی DNS و تنظیم بهترین ترکیب
#  اصلی = بهترین DNS خارجی ، دومین = بهترین DNS ایرانی ، سومین = آی‌پی دوم DNS خارجی
# =============================================================================
# فرمت: نام|آی‌پی‌ها   (فقط سرورهای بدون فیلتر تبلیغ/محتوا برای استفاده‌ی سروری)
DNS_IRAN=(
  "Shecan|178.22.122.100 185.51.200.2"
  "Electro|78.157.42.100 78.157.42.101"
  "RadarGame|10.202.10.10 10.202.10.11"
  "403.online|10.202.10.202 10.202.10.102"
  "VanillaDNS|10.202.10.100 10.202.10.101"
  "Begzar|185.55.226.26 185.55.225.25"
  "DNSPro|87.107.110.109 87.107.110.110"
  "Pishgaman|5.202.100.100 5.202.100.101"
  "Shatel|85.15.1.14 85.15.1.15"
  "Asiatech|194.36.174.161 194.36.174.162"
  "TCI|217.218.127.127 217.218.155.155"
  "Hostiran|172.29.0.100 172.29.2.100"
)
DNS_FOREIGN=(
  "Cloudflare|1.1.1.1 1.0.0.1"
  "Google|8.8.8.8 8.8.4.4"
  "Quad9|9.9.9.9 149.112.112.112"
  "Quad9-Open|9.9.9.10 149.112.112.10"
  "OpenDNS|208.67.222.222 208.67.220.220"
  "ControlD|76.76.2.0 76.76.10.0"
  "DNS.SB|185.222.222.222 45.11.45.11"
  "Yandex|77.88.8.8 77.88.8.1"
  "Level3|4.2.2.1 4.2.2.2"
  "Verisign|64.6.64.6 64.6.65.6"
  "Neustar|156.154.70.1 156.154.71.1"
  "Comodo|8.26.56.26 8.20.247.20"
  "AliDNS|223.5.5.5 223.6.6.6"
)
FALLBACK_DNS="8.8.8.8 1.1.1.1"

DNS_PRIMARY_IP=""; DNS_SECONDARY_IP=""; DNS_TERTIARY_IP=""
DNS_PRIMARY_LABEL=""; DNS_SECONDARY_LABEL=""; DNS_ALL_FAILED=false
DIAG_DNS_LINES=""; DNS_METHOD=""; DNS_DIRTY=false

# تاخیر یک سرور DNS به میلی‌ثانیه (۹۹۹۹ = ناموفق). پرس‌وجو دوبار انجام می‌شود تا کش گرم شود.
measure_latency() {
  local ip="$1" out t1 t2 s e
  if [ "$HAS_DIG" = true ]; then
    out=$(dig @"$ip" google.com A +time=2 +tries=1 +noall +answer 2>/dev/null)
    echo "$out" | grep -qE '[[:space:]]IN[[:space:]]+A[[:space:]]' || { echo 9999; return; }
    # پاسخ جعلی: صفحه‌ی مسدودسازی ISP ایران (10.10.34.34/35/36)، 0.0.0.0 یا loopback
    echo "$out" | awk '$4=="A"{print $NF}' | grep -qE '^(10\.10\.34\.3[4-6]|0\.0\.0\.0|127\.)' && { echo 9999; return; }
    out=$(dig @"$ip" google.com A +time=2 +tries=1 +noall +answer +stats 2>/dev/null)
    t2=$(echo "$out" | sed -n -E 's/.*Query time: ([0-9]+) msec.*/\1/p' | head -n1)
    [ -z "$t2" ] && t2=50
    [ "$t2" -lt 1 ] && t2=1
    echo "$t2"; return
  elif [ "$HAS_HOST" = true ]; then
    s=$(ms_now)
    if host -W 2 google.com "$ip" 2>/dev/null | grep -q 'has address'; then
      e=$(ms_now); t1=$((e - s)); [ "$t1" -lt 1 ] && t1=1; echo "$t1"; return
    fi
    echo 9999; return
  fi
  out=$(ping -c 2 -W 1 "$ip" 2>/dev/null) || { echo 9999; return; }
  t1=$(echo "$out" | tail -1 | awk -F'/' '{print $5}')
  [ -n "$t1" ] && printf '%.0f\n' "$t1" || echo 9999
}

dns_probe_item() { # "type|name|ips"
  local type name ips ip total=0 cnt=0 lat
  IFS='|' read -r type name ips <<<"$1"
  for ip in $ips; do
    lat=$(measure_latency "$ip")
    if [ "$lat" -lt 9999 ] 2>/dev/null; then total=$((total + lat)); cnt=$((cnt + 1)); fi
  done
  if [ "$cnt" -gt 0 ]; then echo "$type|$name|$ips|$((total / cnt))|$cnt"
  else echo "$type|$name|$ips|9999|0"; fi
}

print_dns_table() { # خطوط مرتب‌شده‌ی نتایج → جدول زیبا (به‌صورت پیش‌فرض ۸ سرور برتر؛ --show-all همه)
  local lines="$1" best=0 type name ips ms cnt fill mark starred=false shown=0 limit=8 hidden=0 failed=""
  [ "$SHOW_ALL" = true ] && limit=999
  best=$(echo "$lines" | awk -F'|' '$4<9999{print $4}' | sort -n | head -n1)
  printf '  %s%-3s %-14s %-9s %-10s%s\n' "$C_GRAY" "" "Provider" "Region" "Latency" "$C_RESET"
  while IFS='|' read -r type name ips ms cnt; do
    [ -z "$name" ] && continue
    local region="INT"; [ "$type" = "iran" ] && region="IR"
    if [ "$ms" -lt 9999 ]; then
      if [ "$shown" -ge "$limit" ]; then hidden=$((hidden + 1)); continue; fi
      shown=$((shown + 1))
      fill=$((best * 12 / ms)); [ "$fill" -lt 1 ] && fill=1; [ "$fill" -gt 12 ] && fill=12
      mark=" "; if [ "$ms" = "$best" ] && [ "$starred" != true ]; then mark="$S_STAR"; starred=true; fi
      printf '  %s%-3s%s %-14s %-9s %s%4d ms%s  %s%s%s%s%s\n' "$C_GOLD" "$mark" "$C_RESET" "$name" "$region" "$C_OK" "$ms" "$C_RESET" \
        "$C_ACC" "$(rep "$B_FULL" "$fill")" "$C_GRAY" "$(rep "$B_EMPTY" $((12 - fill)))" "$C_RESET"
    else
      failed+="${name}, "
    fi
  done <<<"$lines"
  [ "$hidden" -gt 0 ] && note "+ ${hidden} سرور سالم دیگر (نمایش همه: --show-all)"
  [ -n "$failed" ] && note "بدون پاسخ/جعلی: ${failed%, }"
  return 0
}

test_all_dns() {
  local items=() e
  for e in "${DNS_IRAN[@]}";    do items+=("iran|$e"); done
  for e in "${DNS_FOREIGN[@]}"; do items+=("foreign|$e"); done
  par_run "تست DNS ..." 12 "$TMPD/dns" dns_probe_item "${items[@]}"
  local all sorted
  all=$(par_collect "$TMPD/dns")
  sorted=$(echo "$all" | LC_ALL=C sort -t'|' -k4,4n)
  DIAG_DNS_LINES="$sorted"
  print_dns_table "$sorted"

  local bf bi
  bf=$(echo "$sorted" | awk -F'|' '$1=="foreign" && $4<9999{print; exit}')
  bi=$(echo "$sorted" | awk -F'|' '$1=="iran"    && $4<9999{print; exit}')
  local fname fips iname iips
  fname=$(echo "$bf" | cut -d'|' -f2); fips=$(echo "$bf" | cut -d'|' -f3)
  iname=$(echo "$bi" | cut -d'|' -f2); iips=$(echo "$bi" | cut -d'|' -f3)

  blank
  if [ -n "$fname" ] && [ -n "$iname" ]; then
    DNS_PRIMARY_IP=$(echo "$fips" | awk '{print $1}'); DNS_TERTIARY_IP=$(echo "$fips" | awk '{print $2}')
    DNS_SECONDARY_IP=$(echo "$iips" | awk '{print $1}')
    DNS_PRIMARY_LABEL="$fname"; DNS_SECONDARY_LABEL="$iname"
  elif [ -n "$fname" ]; then
    warn "هیچ DNS ایرانی پاسخ نداد؛ فقط DNS خارجی استفاده می‌شود."
    DNS_PRIMARY_IP=$(echo "$fips" | awk '{print $1}'); DNS_SECONDARY_IP=$(echo "$fips" | awk '{print $2}')
    DNS_PRIMARY_LABEL="$fname"; DNS_SECONDARY_LABEL="$fname"
  elif [ -n "$iname" ]; then
    warn "هیچ DNS خارجی پاسخ نداد؛ فقط DNS ایرانی استفاده می‌شود."
    DNS_PRIMARY_IP=$(echo "$iips" | awk '{print $1}'); DNS_SECONDARY_IP=$(echo "$iips" | awk '{print $2}')
    DNS_PRIMARY_LABEL="$iname"; DNS_SECONDARY_LABEL="$iname"
  else
    warn "هیچ‌کدام از DNS های تست‌شده پاسخ ندادند؛ مقدار ایمن پیش‌فرض استفاده می‌شود."
    DNS_PRIMARY_IP=$(echo "$FALLBACK_DNS" | awk '{print $1}'); DNS_SECONDARY_IP=$(echo "$FALLBACK_DNS" | awk '{print $2}')
    DNS_PRIMARY_LABEL="Fallback"; DNS_SECONDARY_LABEL="Fallback"; DNS_ALL_FAILED=true
  fi
  ok "اصلی: ${C_BOLD}${DNS_PRIMARY_LABEL}${C_RESET} (${DNS_PRIMARY_IP})   دومین: ${C_BOLD}${DNS_SECONDARY_LABEL}${C_RESET} (${DNS_SECONDARY_IP})"
}

dns_resolves() { # آیا با تنظیمات فعلی سیستم، حداقل یک نام resolve می‌شود؟
  local h
  for h in github.com google.com cloudflare.com; do
    timeout 6 getent hosts "$h" >/dev/null 2>&1 && return 0
  done
  return 1
}

dns_backup() {
  bk_save "$RESOLV_CONF" dns/resolv.conf
  bk_save /etc/dhcp/dhclient.conf dns/dhclient.conf
}

dns_remove_dropins() {
  rm -f /etc/systemd/resolved.conf.d/99-abrbaran-dns.conf /etc/NetworkManager/conf.d/99-abrbaran-dns.conf
  if [ -f /etc/dhcp/dhclient.conf ] && grep -q 'ABRBARAN-BEGIN' /etc/dhcp/dhclient.conf 2>/dev/null; then
    sed -i '/# ABRBARAN-BEGIN/,/# ABRBARAN-END/d' /etc/dhcp/dhclient.conf
  fi
}

dns_restore_from() { # dir (BK یا ORIG)
  local d="$1"
  chattr -i "$RESOLV_CONF" >/dev/null 2>&1 || true
  dns_remove_dropins
  if [ -e "$d/dns/resolv.conf" ] || [ -L "$d/dns/resolv.conf" ]; then
    rm -f "$RESOLV_CONF"; cp -a "$d/dns/resolv.conf" "$RESOLV_CONF"
  fi
  [ -f "$d/dns/dhclient.conf" ] && cp -a "$d/dns/dhclient.conf" /etc/dhcp/dhclient.conf
  systemctl restart systemd-resolved >/dev/null 2>&1 || true
  systemctl reload NetworkManager >/dev/null 2>&1 || true
}

apply_dns() {
  local ip1="$DNS_PRIMARY_IP" ip2="$DNS_SECONDARY_IP" ip3="$DNS_TERTIARY_IP" list
  list="$ip1 $ip2"; [ -n "$ip3" ] && [ "$ip3" != "$ip1" ] && [ "$ip3" != "$ip2" ] && list="$list $ip3"
  if [ "$DRY_RUN" = true ]; then note "(dry-run) DNS تنظیم می‌شد روی: $list"; set_st DNS skip "dry-run: $DNS_PRIMARY_LABEL + $DNS_SECONDARY_LABEL"; return 0; fi

  if [ "$DNS_ALL_FAILED" = true ] && dns_resolves; then
    ok "تست DNS ها نتیجه نداد ولی DNS فعلی سرور سالم کار می‌کند؛ برای ایمنی تغییری اعمال نشد."
    set_st DNS warn "بدون تغییر (DNS فعلی سالم است)"; return 0
  fi
  dns_backup; DNS_DIRTY=true
  local use_resolved=false
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet systemd-resolved 2>/dev/null \
     && grep -qE '^nameserver[[:space:]]+127\.0\.0\.5[34]' "$RESOLV_CONF" 2>/dev/null; then
    use_resolved=true
  fi

  if [ "$use_resolved" = true ]; then
    mkdir -p /etc/systemd/resolved.conf.d
    cat > /etc/systemd/resolved.conf.d/99-abrbaran-dns.conf <<EOF
# تنظیم‌شده توسط ABR BARAN IDC . IR
[Resolve]
DNS=${list}
FallbackDNS=${FALLBACK_DNS}
EOF
    systemctl restart systemd-resolved >/dev/null 2>&1
    resolvectl flush-caches >/dev/null 2>&1 || true
    DNS_METHOD="systemd-resolved"
  else
    # NetworkManager: جلوگیری از بازنویسی resolv.conf
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null; then
      mkdir -p /etc/NetworkManager/conf.d
      printf '# ABR BARAN IDC . IR\n[main]\ndns=none\n' > /etc/NetworkManager/conf.d/99-abrbaran-dns.conf
      systemctl reload NetworkManager >/dev/null 2>&1 || true
    fi
    # dhclient: پایدار کردن DNS بعد از تمدید lease
    if [ -f /etc/dhcp/dhclient.conf ] && ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
      sed -i '/# ABRBARAN-BEGIN/,/# ABRBARAN-END/d' /etc/dhcp/dhclient.conf
      printf '# ABRBARAN-BEGIN\nsupersede domain-name-servers %s;\n# ABRBARAN-END\n' "$(echo "$list" | sed 's/ /, /g')" >> /etc/dhcp/dhclient.conf
    fi
    chattr -i "$RESOLV_CONF" >/dev/null 2>&1 || true
    rm -f "$RESOLV_CONF"
    { echo "# تنظیم‌شده توسط ABR BARAN IDC . IR در $(date)"
      for ip in $list; do echo "nameserver $ip"; done
      echo "options timeout:2 attempts:2 rotate"; } > "$RESOLV_CONF"
    DNS_METHOD="/etc/resolv.conf"
  fi

  if dns_resolves; then
    DNS_DIRTY=false
    ok "DNS با موفقیت اعمال و با resolve واقعی تایید شد  ${C_GRAY}(روش: ${DNS_METHOD})${C_RESET}"
    set_st DNS ok "${DNS_PRIMARY_LABEL} + ${DNS_SECONDARY_LABEL}"
  else
    err "با DNS جدید هیچ نامی resolve نشد؛ بازگردانی خودکار به حالت قبل ..."
    dns_restore_from "$BK"; DNS_DIRTY=false
    set_st DNS warn "اعمال نشد (بازگردانی شد)"
    return 1
  fi
}

# =============================================================================
#  بخش ۳: مخزن (Repository) — تست موازی، رتبه‌بندی با سرعت واقعی، failover چندمرحله‌ای
# =============================================================================
# فرمت: نام|ناحیه|آدرس
#   آدرسی که به «@» ختم شود فقط ریشه‌ی سایت است؛ اسکریپت خودش مسیر درست (/ubuntu ، /repo/Ubuntu ، ...)
#   و پروتکل (http/https) را همان لحظه پیدا می‌کند. آدرس‌های نادرست/ناسالم خودکار کنار گذاشته می‌شوند.
UBUNTU_MIRRORS=(
  # ───── ایران ─────
  "ArvanCloud|IR|http://mirror.arvancloud.ir/ubuntu"
  "ArvanCloud-2|IR|https://mirror.arvancloud.com/ubuntu"
  "IranServer|IR|https://mirror.iranserver.com/ubuntu"
  "Pishgaman|IR|https://ubuntu.pishgaman.net/ubuntu"
  "SindadCloud|IR|https://ir.ubuntu.sindad.cloud/ubuntu"
  "Mobinhost|IR|https://ubuntu.mobinhost.com/ubuntu"
  "Mobinhost-2|IR|https://mirror.mobinhost.com@"
  "IUT-Isfahan|IR|http://repo.iut.ac.ir/repo/Ubuntu"
  "IUT-2|IR|https://repo.iut.ac.ir@"
  "Shatel|IR|https://mirror.shatel.ir@"
  "Pardisco|IR|https://mirrors.pardisco.co@"
  "Ubuntu-IR|IR|http://ir.archive.ubuntu.com@"
  "0-1-Cloud|IR|https://mirror.0-1.cloud@"
  "ManageIT|IR|http://mirror.manageit.ir/ubuntu"
  "AminiDC|IR|http://mirror.aminidc.com@"
  "KimiaHost|IR|https://ubuntu-mirror.kimiahost.com@"
  "DigitalVPS|IR|https://mirror.digitalvps.ir/ubuntu"
  "AtlantisCloud|IR|https://mirror.atlantiscloud.ir@"
  "Abrha|IR|https://repo.abrha.net@"
  "ParsDev|IR|https://mirror.parsdev.com@"
  "LinuxMirrors|IR|https://linuxmirrors.ir@"
  "Afranet|IR|http://mirror.afranet.com@"
  "HyperClouds|IR|https://mirrors.hyperclouds.ir@"
  "ITO-Portal|IR|https://repo-portal.ito.gov.ir/repo@"
  "Faraso|IR|http://mirror.faraso.org@"
  # ───── خارجی ─────
  "Official|INT|http://archive.ubuntu.com/ubuntu"
  "Official-DE|INT|http://de.archive.ubuntu.com/ubuntu"
  "Official-NL|INT|http://nl.archive.ubuntu.com/ubuntu"
  "Official-FR|INT|http://fr.archive.ubuntu.com/ubuntu"
  "Official-GB|INT|http://gb.archive.ubuntu.com/ubuntu"
  "Official-TR|INT|http://tr.archive.ubuntu.com/ubuntu"
  "KernelOrg|INT|https://mirrors.kernel.org/ubuntu"
  "FAU-Germany|INT|https://ftp.fau.de/ubuntu"
  "LeaseWeb|INT|https://mirror.leaseweb.com/ubuntu"
  "Init7-CH|INT|https://mirror.init7.net/ubuntu"
  "23M-US|INT|https://mirror.23m.com/ubuntu"
  "Stuttgart|INT|https://ftp.uni-stuttgart.de/ubuntu"
  "Wuerzburg|INT|https://ftp.uni-wuerzburg.de/ubuntu"
  "AARNet-AU|INT|https://mirror.aarnet.edu.au/pub/ubuntu/archive"
  "Berkeley-OCF|INT|https://mirrors.ocf.berkeley.edu/ubuntu"
  "OSUOSL|INT|https://ftp.osuosl.org/pub/ubuntu"
  "Rackspace|INT|http://mirror.rackspace.com/ubuntu"
  "Linode|INT|http://mirrors.linode.com/ubuntu"
  "DigitalOcean|INT|http://mirrors.digitalocean.com/ubuntu"
  "Selectel-RU|INT|https://mirror.selectel.ru/ubuntu"
  "Yandex|INT|http://mirror.yandex.ru/ubuntu"
  "Tsinghua|INT|https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
  "USTC|INT|https://mirrors.ustc.edu.cn/ubuntu"
  "NJU|INT|https://mirrors.nju.edu.cn/ubuntu"
  "SJTU|INT|https://mirror.sjtu.edu.cn/ubuntu"
  "Aliyun|INT|https://mirrors.aliyun.com/ubuntu"
  "Tencent|INT|https://mirrors.cloud.tencent.com/ubuntu"
  "Huawei|INT|https://repo.huaweicloud.com/ubuntu"
  "Kakao|INT|https://mirror.kakao.com/ubuntu"
  "OVHcloud|INT|https://ubuntu.mirrors.ovh.net/ubuntu"
  "Hetzner|INT|http://mirror.hetzner.com/ubuntu/packages"
)
UBUNTU_PORTS_MIRRORS=(
  "Official-Ports|INT|http://ports.ubuntu.com/ubuntu-ports"
  "ArvanCloud|IR|http://mirror.arvancloud.ir/ubuntu-ports"
  "Tsinghua|INT|https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
  "USTC|INT|https://mirrors.ustc.edu.cn/ubuntu-ports"
  "NJU|INT|https://mirrors.nju.edu.cn/ubuntu-ports"
  "Aliyun|INT|https://mirrors.aliyun.com/ubuntu-ports"
  "Yandex|INT|http://mirror.yandex.ru/ubuntu-ports"
)
DEBIAN_MIRRORS=(
  # ───── ایران ─────
  "Petiak|IR|http://archive.debian.petiak.ir/debian"
  "ArvanCloud|IR|http://mirror.arvancloud.ir/debian"
  "IranServer|IR|https://mirror.iranserver.com@"
  "Mobinhost|IR|https://mirror.mobinhost.com@"
  "Shatel|IR|https://mirror.shatel.ir@"
  "IUT-Isfahan|IR|https://repo.iut.ac.ir@"
  "Pardisco|IR|https://mirrors.pardisco.co@"
  "0-1-Cloud|IR|https://mirror.0-1.cloud@"
  "AminiDC|IR|http://mirror.aminidc.com@"
  "Abrha|IR|https://repo.abrha.net@"
  "ParsDev|IR|https://mirror.parsdev.com@"
  "LinuxMirrors|IR|https://linuxmirrors.ir@"
  "Afranet|IR|http://mirror.afranet.com@"
  "HyperClouds|IR|https://mirrors.hyperclouds.ir@"
  "ITO-Portal|IR|https://repo-portal.ito.gov.ir/repo@"
  # ───── خارجی ─────
  "Official|INT|http://deb.debian.org/debian"
  "Debian-DE|INT|http://ftp.de.debian.org/debian"
  "Debian-NL|INT|http://ftp.nl.debian.org/debian"
  "Debian-FR|INT|http://ftp.fr.debian.org/debian"
  "Debian-UK|INT|http://ftp.uk.debian.org/debian"
  "Debian-US|INT|http://ftp.us.debian.org/debian"
  "KernelOrg|INT|https://mirrors.kernel.org/debian"
  "FAU-Germany|INT|https://ftp.fau.de/debian"
  "LeaseWeb|INT|https://mirror.leaseweb.com/debian"
  "Init7-CH|INT|https://mirror.init7.net/debian"
  "Stuttgart|INT|https://ftp.uni-stuttgart.de/debian"
  "AARNet-AU|INT|https://mirror.aarnet.edu.au/debian"
  "Selectel-RU|INT|https://mirror.selectel.ru/debian"
  "Yandex|INT|http://mirror.yandex.ru/debian"
  "Tsinghua|INT|https://mirrors.tuna.tsinghua.edu.cn/debian"
  "USTC|INT|https://mirrors.ustc.edu.cn/debian"
  "NJU|INT|https://mirrors.nju.edu.cn/debian"
  "SJTU|INT|https://mirror.sjtu.edu.cn/debian"
  "Aliyun|INT|https://mirrors.aliyun.com/debian"
  "Tencent|INT|https://mirrors.cloud.tencent.com/debian"
  "Huawei|INT|https://repo.huaweicloud.com/debian"
  "OVHcloud|INT|https://debian.mirrors.ovh.net/debian"
  "Hetzner|INT|http://mirror.hetzner.com/debian/packages"
)

APT_FILES=()
APT_DIRTY=false
APT_CAND=()          # "نام|ناحیه|آدرس|میلی‌ثانیه|سرعتKB|امنیتی(0/1)"  به ترتیب اولویت
APT_CUR_IDX=-1
APT_CUR_HOST=""
APT_BEST_NAME=""
APT_NEED_UPDATES=true
APT_LAST_ERR=""
P_SUITE=""; P_ARCH=""; P_FAMILY=""
REPO_ALL_FAILED=false
DIAG_MIRROR_LINES=""
MIRROR_TRIED_SUMMARY=""

APT_ETC="${APT_ETC:-/etc/apt}"
collect_apt_files() {
  APT_FILES=()
  [ -f "$APT_ETC/sources.list" ] && APT_FILES+=("$APT_ETC/sources.list")
  local f
  if [ -d "$APT_ETC/sources.list.d" ]; then
    while IFS= read -r -d '' f; do APT_FILES+=("$f"); done \
      < <(find "$APT_ETC/sources.list.d" -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' \) -print0 2>/dev/null)
  fi
}

is_deb822() { case "$1" in *.sources) return 0 ;; esac; grep -qE '^[[:space:]]*Types:' "$1" 2>/dev/null; }

# کدنام: از os-release، سپس lsb_release، سپس خود فایل‌های مخزن (برای نسخه‌های جدید/ناشناخته)
get_apt_codename() {
  local c=""
  if [ "$MIRROR_FAMILY" = "ubuntu" ]; then c="$OS_UBUNTU_CODENAME"; fi
  [ -z "$c" ] && c="$OS_CODENAME"
  [ -z "$c" ] && command -v lsb_release >/dev/null 2>&1 && c=$(lsb_release -sc 2>/dev/null)
  if [ -z "$c" ] && [ "$MIRROR_FAMILY" = "debian" ] && [ -r /etc/debian_version ]; then
    c=$(sed -n -E 's#^([a-z]+)/.*#\1#p' /etc/debian_version | head -n1)
  fi
  if [ -z "$c" ]; then
    local f
    for f in "${APT_FILES[@]}"; do
      [ -f "$f" ] || continue
      c=$(grep -hE '^[[:space:]]*(deb |Suites:)' "$f" 2>/dev/null | grep -oE '[a-z]+-(updates|security|backports)' | head -n1 | sed -E 's/-(updates|security|backports)$//')
      [ -n "$c" ] && break
    done
  fi
  printf '%s' "$c"
}

# میزبان(های) فعلیِ مخزن اصلی — فقط از روی suite های -updates/-backports (نه PPA و نه مخزن‌های ثالث)
discover_old_uris() {
  local codename="$1" f
  for f in "${APT_FILES[@]}"; do
    [ -f "$f" ] || continue
    if is_deb822 "$f"; then
      awk -v cn="$codename" '
        function flush(   k, m) { if (u != "" && s ~ ("(^|[ \t])" cn "-(updates|backports)([ \t]|$)")) { m = split(u, a, /[ \t]+/); for (k = 1; k <= m; k++) if (a[k] != "") print a[k] }; u = ""; s = "" }
        /^[ \t]*$/ { flush(); next }
        /^[ \t]*URIs:/   { u = $0; sub(/^[ \t]*URIs:[ \t]*/, "", u) }
        /^[ \t]*Suites:/ { s = $0; sub(/^[ \t]*Suites:[ \t]*/, "", s) }
        END { flush() }' "$f" 2>/dev/null
    else
      grep -E "^[[:space:]]*deb(-src)?[[:space:]]" "$f" 2>/dev/null | grep -E "[[:space:]]${codename}-(updates|backports)([[:space:]]|\$)" \
        | grep -oE '[a-zA-Z][a-zA-Z0-9+.-]*://[^[:space:]]+'
    fi
  done | sort -u
}

apt_static_regex() {
  case "$1" in
    ubuntu) printf '%s' '^https?://([a-z0-9-]+\.)*(archive|security)\.ubuntu\.com/ubuntu/?$|^https?://ports\.ubuntu\.com/ubuntu-ports/?$|^https?://old-releases\.ubuntu\.com/ubuntu/?$' ;;
    debian) printf '%s' '^https?://([a-z0-9-]+\.)*(deb|ftp)\.debian\.org/debian/?$|^https?://httpredir\.debian\.org/debian/?$' ;;
  esac
}

# --- تست یک مسیر dist: واقعاً HTTP 200 بدهد (InRelease، وگرنه Release) → زمان را برمی‌گرداند
dist_probe() { # url suite
  local raw code t f
  for f in InRelease Release; do
    raw=$(curl -sL --max-redirs 3 -o /dev/null --connect-timeout 3 --max-time 6 -w '%{http_code} %{time_total}' "$1/dists/$2/$f" 2>/dev/null)
    code=${raw%% *}; t=${raw##* }
    if [ "$code" = "200" ]; then printf '%s' "$t"; return 0; fi
  done
  return 1
}

# فایل ایندکس بسته‌ها برای معماری این سرور وجود دارد؟ (HEAD؛ بدون دانلود)
index_probe() { # url suite arch
  local ext code
  for ext in xz gz bz2 ""; do
    code=$(curl -sIL --max-redirs 3 -o /dev/null --connect-timeout 3 --max-time 6 -w '%{http_code}' "$1/dists/$2/main/binary-$3/Packages${ext:+.$ext}" 2>/dev/null)
    [ "$code" = "200" ] && return 0
  done
  return 1
}

# سرعت واقعی دانلود (KB/s) با گرفتن ۱ مگابایت اول فایل ایندکس
speed_probe() { # url suite arch
  local ext raw code sp
  for ext in xz gz; do
    raw=$(curl -sL --max-redirs 3 -r 0-1048575 -o /dev/null --connect-timeout 3 --max-time 7 -w '%{http_code} %{speed_download}' "$1/dists/$2/main/binary-$3/Packages.$ext" 2>/dev/null)
    code=${raw%% *}; sp=${raw##* }
    if [ "$code" = "200" ] || [ "$code" = "206" ]; then
      awk -v s="$sp" 'BEGIN{printf "%d", s/1024}'; return 0
    fi
  done
  echo 0
}

AUTO_PATHS_UBUNTU=("/ubuntu" "/ubuntu-archive" "/repo/ubuntu" "/repo/Ubuntu" "/Ubuntu" "/mirror/ubuntu" "/pub/ubuntu" "")
AUTO_PATHS_DEBIAN=("/debian" "/debian-archive" "/repo/debian" "/repo/Debian" "/Debian" "/mirror/debian" "/pub/debian" "")
AUTO_PATHS_UBUNTU_PORTS=("/ubuntu-ports" "/ubuntu/ports" "/repo/ubuntu-ports")

# ریشه‌ی سایت (بدون @) → آدرس کامل و کارکرد: ابتدا دسترس‌پذیری میزبان (با http و https)، سپس مسیرهای محتمل
resolve_auto_base() {
  local base="$1" scheme rest sc other code reach="" p cand paths=()
  scheme="${base%%://*}"; rest="${base#*://}"
  [ "$scheme" = "https" ] && other="http" || other="https"
  for sc in "$scheme" "$other"; do
    code=$(curl -sI -o /dev/null --connect-timeout 3 --max-time 5 -w '%{http_code}' "$sc://$rest/" 2>/dev/null)
    if [ -n "$code" ] && [ "$code" != "000" ]; then reach="$sc"; break; fi
  done
  [ -z "$reach" ] && return 1
  if [ "$P_FAMILY" = "debian" ]; then paths=("${AUTO_PATHS_DEBIAN[@]}")
  else case "$P_ARCH" in amd64|i386) paths=("${AUTO_PATHS_UBUNTU[@]}") ;; *) paths=("${AUTO_PATHS_UBUNTU_PORTS[@]}") ;; esac; fi
  for p in "${paths[@]}"; do
    cand="$reach://$rest$p"
    if dist_probe "$cand" "$P_SUITE" >/dev/null; then printf '%s' "$cand"; return 0; fi
  done
  return 1
}

probe_mirror_item() { # "name|region|url" → OK|ms|name|region|url|sec  یا  FAIL|name|region|url|دلیل
  local name region url t1 t2="0" t3 sec=0 ms
  IFS='|' read -r name region url <<<"$1"
  if [ "${url%@}" != "$url" ]; then
    url=$(resolve_auto_base "${url%@}") || { echo "FAIL|$name|$region|${1##*|}|مسیر/دسترسی مخزن پیدا نشد"; return; }
  fi
  t1=$(dist_probe "$url" "$P_SUITE") || { echo "FAIL|$name|$region|$url|suite اصلی پاسخ نداد"; return; }
  if [ "$APT_NEED_UPDATES" = true ]; then
    t2=$(dist_probe "$url" "$P_SUITE-updates") || { echo "FAIL|$name|$region|$url|suite -updates ناقص است"; return; }
  fi
  index_probe "$url" "$P_SUITE" "$P_ARCH" || { echo "FAIL|$name|$region|$url|ایندکس بسته‌ها برای $P_ARCH موجود نیست"; return; }
  if [ "$P_FAMILY" = "ubuntu" ]; then dist_probe "$url" "$P_SUITE-security" >/dev/null && sec=1; fi
  ms=$(awk -v a="$t1" -v b="$t2" 'BEGIN{printf "%d", (a+b)*1000}')
  echo "OK|$ms|$name|$region|$url|$sec"
}

print_mirror_table() { # خطوط OK مرتب‌شده با ستون سرعت (پیش‌فرض ۱۰ برتر؛ --show-all همه)
  local lines="$1" idx=0 best_sp=1 name region url ms sp sec fill mark sp_txt limit=10 total hidden=0
  [ "$SHOW_ALL" = true ] && limit=999
  total=$(echo "$lines" | sed '/^$/d' | wc -l)
  best_sp=$(echo "$lines" | awk -F'|' '{if($5+0>m)m=$5+0}END{print (m<1?1:m)}')
  printf '  %s%-4s %-14s %-7s %-10s %-11s%s\n' "$C_GRAY" "" "Mirror" "Region" "Latency" "Speed" "$C_RESET"
  while IFS='|' read -r name region url ms sp sec; do
    [ -z "$name" ] && continue
    idx=$((idx + 1))
    if [ "$idx" -gt "$limit" ]; then hidden=$((hidden + 1)); continue; fi
    mark=" "; [ "$idx" -eq 1 ] && mark="$S_STAR"
    if [ "${sp:-0}" -gt 0 ] 2>/dev/null; then
      sp_txt=$(awk -v s="$sp" 'BEGIN{ if (s>=1024) printf "%.1f MB/s", s/1024; else printf "%d KB/s", s }')
      fill=$((sp * 10 / best_sp)); [ "$fill" -lt 1 ] && fill=1
    else sp_txt="—"; fill=0; fi
    printf '  %s%-4s%s %-14.14s %-7s %4d ms    %-11s %s%s%s%s%s\n' "$C_GOLD" "$mark" "$C_RESET" "${name/Current:/cur:}" "$region" "$ms" "$sp_txt" \
      "$C_ACC" "$(rep "$B_FULL" "$fill")" "$C_GRAY" "$(rep "$B_EMPTY" $((10 - fill)))" "$C_RESET"
  done <<<"$lines"
  [ "$hidden" -gt 0 ] && note "+ ${hidden} مخزن سالم دیگر هم به‌عنوان جایگزین (failover) آماده‌اند (نمایش همه: --show-all)"
  return 0
}

pick_best_apt_mirror() { # family codename
  local family="$1" codename="$2" e
  P_SUITE="$codename"; P_FAMILY="$family"; P_ARCH="${ARCH_DEB:-amd64}"
  local items=()
  case "$family" in
    ubuntu)
      case "$P_ARCH" in
        amd64|i386) for e in "${UBUNTU_MIRRORS[@]}"; do items+=("$e"); done ;;
        *)          for e in "${UBUNTU_PORTS_MIRRORS[@]}"; do items+=("$e"); done ;;
      esac ;;
    debian) for e in "${DEBIAN_MIRRORS[@]}"; do items+=("$e"); done ;;
  esac
  # مخزن فعلی هم یک کاندید است؛ اگر از همه بهتر بود، دست‌نخورده می‌ماند
  local old u host
  old=$(discover_old_uris "$codename")
  while IFS= read -r u; do
    [ -z "$u" ] && continue
    host=$(url_host "$u")
    items+=("Current:${host}|CUR|${u%/}")
  done <<<"$old"

  info "تست موازیِ ${#items[@]} مخزن (suite اصلی + updates + ایندکس بسته‌ها) ..."
  par_run "تست مخزن‌ها ..." 12 "$TMPD/mir" probe_mirror_item "${items[@]}"
  local all ok_lines fail_lines
  all=$(par_collect "$TMPD/mir")
  # OK|ms|name|region|url|sec  →  name|region|url|ms|sec  (مرتب بر اساس تاخیر)
  ok_lines=$(echo "$all" | grep '^OK|' | LC_ALL=C sort -t'|' -k2,2n | awk -F'|' '{print $3"|"$4"|"$5"|"$2"|"$6}')
  fail_lines=$(echo "$all" | grep '^FAIL|')
  DIAG_MIRROR_LINES=$(echo "$all" | sed -E 's/^OK\|([0-9]+)\|(.*)$/OK  \1 ms  \2/; s/^FAIL\|/FAIL  /')

  if [ -z "$ok_lines" ]; then
    APT_CAND=(); return 1
  fi

  # مرحله‌ی دوم: سنجش سرعت واقعیِ ۳ مخزن برتر ایرانی + ۳ برتر خارجی + مخزن فعلی (پشت‌سرهم تا پهنای‌باند تقسیم نشود)
  local top rest n=0 name region url ms sec sp ranked="" topn
  top=$( { echo "$ok_lines" | awk -F'|' '$2=="CUR"' | head -n 1
           echo "$ok_lines" | awk -F'|' '$2=="IR"' | head -n 3
           echo "$ok_lines" | awk -F'|' '$2=="INT"' | head -n 3; } | sed '/^$/d' )
  rest=$(echo "$ok_lines" | grep -vxFf <(echo "$top") )
  topn=$(echo "$top" | wc -l)
  while IFS='|' read -r name region url ms sec; do
    [ -z "$name" ] && continue
    n=$((n + 1)); progress_bar "$n" "$topn" "سنجش سرعت واقعی: ${name/Current:/cur:}"
    sp=$(speed_probe "$url" "$codename" "$P_ARCH")
    ranked+="${sp}|${name}|${region}|${url}|${ms}|${sec}"$'\n'
  done <<<"$top"
  progress_clear
  # مرتب‌سازی بر اساس سرعت (نزولی)؛ سپس بقیه بر اساس تاخیر
  local sorted_top
  sorted_top=$(printf '%s' "$ranked" | LC_ALL=C sort -t'|' -k1,1nr | awk -F'|' '{print $2"|"$3"|"$4"|"$5"|"$1"|"$6}')
  local rest_fmt=""
  while IFS='|' read -r name region url ms sec; do
    [ -z "$name" ] && continue
    rest_fmt+="${name}|${region}|${url}|${ms}|0|${sec}"$'\n'
  done <<<"$rest"

  local final
  final=$(printf '%s\n%s' "$sorted_top" "$rest_fmt" | sed '/^$/d')
  APT_CAND=()
  while IFS= read -r line; do APT_CAND+=("$line"); done <<<"$final"

  SPEED_MIRROR_URLS=()
  while IFS='|' read -r name region url _; do
    [ "$region" = "INT" ] || continue
    if [ "$family" = "ubuntu" ]; then SPEED_MIRROR_URLS+=("$url/dists/$codename/universe/binary-$P_ARCH/Packages.xz")
    else SPEED_MIRROR_URLS+=("$url/dists/$codename/main/binary-$P_ARCH/Packages.xz"); fi
    [ ${#SPEED_MIRROR_URLS[@]} -ge 3 ] && break
  done <<<"$final"

  print_mirror_table "$final"
  if [ -n "$fail_lines" ]; then
    local failnames; failnames=$(echo "$fail_lines" | awk -F'|' '{printf "%s%s", (NR>1?", ":""), $2}')
    note "ناسالم/ناقص (کنار گذاشته شد): $failnames"
  fi
  return 0
}

restore_apt_from() { # dir
  local d="$1" f rel
  [ -d "$d/apt" ] || return 0
  while IFS= read -r -d '' f; do
    rel="${f#"$d"/apt/}"
    cat "$f" > "$APT_ETC/$rel" 2>/dev/null
  done < <(find "$d/apt" -type f -print0 2>/dev/null)
}
restore_apt_pristine() { restore_apt_from "$BK"; }

apt_backup() {
  local f rel
  for f in "${APT_FILES[@]}"; do
    rel="${f#"$APT_ETC"/}"
    bk_save "$f" "apt/$rel"
  done
}

# بازنویسی تمام فایل‌های مخزن برای یک آدرس جدید؛ برمی‌گرداند 0 اگر چیزی تغییر کرد
apt_rewrite() { # newbase replace_security(0/1) family codename
  local nb="$1" rs="$2" family="$3" codename="$4" f out prog old re changed=1
  old=$(discover_old_uris "$codename"); re=$(apt_static_regex "$family")
  for f in "${APT_FILES[@]}"; do
    [ -f "$f" ] || continue
    if is_deb822 "$f"; then prog="$TMPD/deb822.awk"; else prog="$TMPD/classic.awk"; fi
    out=$(mktemp "$TMPD/aptw.XXXXXX")
    NEWBASE="$nb" SECSUITE="${codename}-security" REPLSEC="$rs" STATICRE="$re" OLDURIS="$old" awk -f "$prog" "$f" > "$out" 2>/dev/null
    if [ -s "$out" ] && ! cmp -s "$f" "$out"; then cat "$out" > "$f"; changed=0; fi
    rm -f "$out"
  done
  return $changed
}

apt_run() { local t="$1"; shift; timeout "$t" "${APT_ENV[@]}" apt-get "$@"; }

UPG_TOTAL=0
APT_SRC_TOTAL=0

# تعداد تقریبی suite های فعال (هر کدام یک InRelease دارد) برای نوار پیشرفت apt update
count_apt_sources() {
  local f n=0 c
  for f in "${APT_FILES[@]}"; do
    [ -f "$f" ] || continue
    if is_deb822 "$f"; then
      c=$(awk 'function fl(){ if (ok && su>0) t+=su*(nu>0?nu:1); ok=0; su=0; nu=0 }
        /^[ \t]*$/ { fl(); next }
        /^[ \t]*Types:/ { ok=1 }
        /^[ \t]*URIs:/ { x=$0; sub(/^[ \t]*URIs:[ \t]*/,"",x); nu=split(x,a,/[ \t]+/) }
        /^[ \t]*Suites:/ { x=$0; sub(/^[ \t]*Suites:[ \t]*/,"",x); su=split(x,b,/[ \t]+/) }
        END { fl(); print t+0 }' "$f" 2>/dev/null)
    else
      c=$(grep -cE '^[[:space:]]*deb[[:space:]]' "$f" 2>/dev/null)
    fi
    n=$((n + ${c:-0}))
  done
  APT_SRC_TOTAL=$n
}

apt_update_progress() { # cur|total|برچسب
  local f="$1" n h last
  n=$(grep -cE '^(Hit|Get|Ign|Err):[0-9]+ .* (InRelease|Release)( |$)' "$f" 2>/dev/null)
  last=$(grep -E '^(Hit|Get|Ign|Err):[0-9]+ ' "$f" 2>/dev/null | tail -n1 | awk '{print $2}')
  h=$(url_host "${last:-x://-}")
  printf '%s|%s|%s' "${n:-0}" "${APT_SRC_TOTAL:-0}" "${h:0:30}"
}

apt_upgrade_progress() { # cur|total|مرحله + نام بسته
  local f="$1" g u s last stage="آماده‌سازی" pkg=""
  g=$(grep -c '^Get:' "$f" 2>/dev/null); u=$(grep -c '^Unpacking' "$f" 2>/dev/null); s=$(grep -c '^Setting up' "$f" 2>/dev/null)
  last=$(grep -E '^(Get:|Unpacking |Setting up )' "$f" 2>/dev/null | tail -n1)
  case "$last" in
    Get:*)       stage="دریافت";   pkg=$(awk '{print $5}' <<<"$last") ;;
    Unpacking*)  stage="بازکردن";  pkg=$(awk '{print $2}' <<<"$last") ;;
    Setting*)    stage="نصب";      pkg=$(awk '{print $3}' <<<"$last") ;;
  esac
  printf '%s|%s|%s %s' "$((g + u + s))" "$((UPG_TOTAL * 3))" "$stage" "${pkg:0:26}"
}

# apt-get update + تحلیل لاگ. 0=سالم  1=خطای مخزن (قابل failover)  2=خطای غیرمخزنی (مثل lock)
apt_update_checked() { # پیام
  local rc bad log="$TMPD/apt-update.log"
  count_apt_sources
  SPIN_PROGRESS_FN=apt_update_progress
  with_spinner "$1" apt_run 200 update -o Acquire::Retries=1 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15 -o DPkg::Lock::Timeout=120
  rc=$?
  SPIN_PROGRESS_FN=""
  cp "$SPIN_OUT" "$log"; cat "$log" >> "$LOGFILE"
  APT_LAST_ERR=""
  if grep -qE 'Could not get lock|Unable to acquire the dpkg|dpkg was interrupted' "$log"; then
    APT_LAST_ERR="قفل dpkg/apt (فرآیند دیگری در حال اجراست)"; return 2
  fi
  if [ "$rc" -eq 124 ]; then APT_LAST_ERR="timeout"; return 1; fi
  if [ -n "$APT_CUR_HOST" ]; then
    bad=$(grep -E '^(Err:|E:|W:)' "$log" | grep -F "$APT_CUR_HOST" | head -n 3)
    if [ -n "$bad" ]; then APT_LAST_ERR=$(echo "$bad" | head -n1 | cut -c1-110); return 1; fi
    if [ "$rc" -ne 0 ]; then
      if ! grep -qE "$APT_CUR_HOST" "$log"; then APT_LAST_ERR="$(grep -E '^(Err:|E:)' "$log" | head -n1 | cut -c1-110)"; return 1; fi
      warn "برخی مخزن‌های دیگرِ سیستم (غیر از مخزن انتخابی) خطا دادند؛ مخزن انتخابی سالم است."
    fi
    return 0
  fi
  if [ "$rc" -ne 0 ]; then APT_LAST_ERR="$(grep -E '^(Err:|E:)' "$log" | head -n1 | cut -c1-110)"; return 1; fi
  return 0
}

# امتحان یک کاندید: بازگردانی حالت اولیه → بازنویسی → اعتبارسنجی با apt-get update واقعی
apt_try_candidate() { # idx family codename
  local idx="$1" family="$2" codename="$3" name region url ms sp sec rs=0 host
  IFS='|' read -r name region url ms sp sec <<<"${APT_CAND[$idx]}"
  restore_apt_pristine
  APT_DIRTY=true
  if [ "$region" = "CUR" ]; then
    APT_CUR_HOST=$(url_host "$url")
  else
    # امنیتی فقط وقتی عوض می‌شود که میزبان رسمی امنیتی در دسترس نباشد و این میرور آن را داشته باشد
    if [ "$family" = "ubuntu" ] && [ "$sec" = "1" ] && [ "$SEC_OFFICIAL_OK" != true ]; then rs=1; fi
    apt_rewrite "$url" "$rs" "$family" "$codename" >/dev/null
    APT_CUR_HOST=$(url_host "$url")
  fi
  APT_BEST_NAME="${name#Current:}"; [ "$region" = "CUR" ] && APT_BEST_NAME="مخزن فعلی (${name#Current:})"
  apt_update_checked "بررسی مخزن «${APT_BEST_NAME}» با apt update واقعی"
  local rc=$?
  if [ "$rc" -eq 0 ]; then APT_CUR_IDX=$idx; APT_DIRTY=false; return 0; fi
  [ "$rc" -eq 2 ] && return 2
  warn "مخزن «${APT_BEST_NAME}» در apt update شکست خورد  ${C_GRAY}${APT_LAST_ERR}${C_RESET}"
  MIRROR_TRIED_SUMMARY+="${APT_BEST_NAME} ✘; "
  return 1
}

# رفتن به کاندید بعدی (استفاده در ابتدا و هنگام آپدیت). 0=موفق  1=همه ناموفق → حالت اولیه برگردانده شد
apt_failover_next() {
  local i start=$((APT_CUR_IDX + 1)) tries=0 rc
  for ((i = start; i < ${#APT_CAND[@]}; i++)); do
    tries=$((tries + 1)); [ "$tries" -gt 6 ] && break
    apt_try_candidate "$i" "$P_FAMILY" "$P_SUITE"; rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 2 ] && break
    APT_CUR_IDX=$i
  done
  restore_apt_pristine; APT_DIRTY=false; APT_CUR_HOST=""
  return 1
}

SEC_OFFICIAL_OK=true
fix_repositories_apt() {
  collect_apt_files
  if [ ${#APT_FILES[@]} -eq 0 ]; then warn "فایل مخزن apt پیدا نشد؛ رد شد."; set_st REPO warn "فایل مخزن یافت نشد"; return; fi
  local family="$MIRROR_FAMILY" codename
  if [ -z "$family" ]; then
    warn "بهینه‌سازی مخزن فقط برای Ubuntu/Debian (و مشتقات آن‌ها) پشتیبانی می‌شود؛ برای ${OS_PRETTY} رد شد."
    set_st REPO skip "پشتیبانی نمی‌شود برای ${OS_PRETTY}"; return
  fi
  codename=$(get_apt_codename)
  if [ -z "$codename" ]; then warn "کدنام نسخه شناسایی نشد؛ رد شد."; set_st REPO warn "کدنام شناسایی نشد"; return; fi
  info "خانواده: ${C_BOLD}${family}${C_RESET}   کدنام: ${C_BOLD}${codename}${C_RESET}   معماری: ${C_BOLD}${ARCH_DEB}${C_RESET}"
  P_FAMILY="$family"; P_SUITE="$codename"

  if grep -rqsE "(^|[[:space:]])${codename}-updates([[:space:]]|\$)" "${APT_FILES[@]}" 2>/dev/null; then APT_NEED_UPDATES=true; else APT_NEED_UPDATES=false; fi

  # آیا میزبان رسمی امنیتی از این سرور در دسترس است؟
  SEC_OFFICIAL_OK=true
  if [ "$family" = "ubuntu" ]; then
    local securl="http://security.ubuntu.com/ubuntu"
    case "$ARCH_DEB" in amd64|i386) ;; *) securl="http://ports.ubuntu.com/ubuntu-ports" ;; esac
    dist_probe "$securl" "${codename}-security" >/dev/null || SEC_OFFICIAL_OK=false
    [ "$SEC_OFFICIAL_OK" = false ] && warn "میزبان رسمی امنیتی (security.ubuntu.com) در دسترس نیست؛ در صورت امکان، suite امنیتی هم از میرور گرفته می‌شود."
  fi

  if ! pick_best_apt_mirror "$family" "$codename"; then
    warn "هیچ مخزنی (ایرانی/خارجی) به‌طور کامل پاسخ نداد؛ تنظیمات فعلی دست‌نخورده ماند."
    REPO_ALL_FAILED=true; set_st REPO err "هیچ مخزنی در دسترس نبود"; return
  fi

  if [ "$DRY_RUN" = true ]; then
    local n; n=$(echo "${APT_CAND[0]}" | cut -d'|' -f1)
    note "(dry-run) مخزن انتخاب‌شده می‌شد: ${n#Current:}"
    set_st REPO skip "dry-run: برترین ${n#Current:}"; return
  fi

  apt_backup
  blank
  info "اعمال بهترین مخزن با اعتبارسنجی واقعی و failover خودکار روی کاندیدهای بعدی ..."
  APT_CUR_IDX=-1
  if apt_failover_next; then
    local nm="$APT_BEST_NAME"
    ok "مخزن فعال: ${C_BOLD}${nm}${C_RESET}   ${C_GRAY}(پشتیبان: ${BK}/apt)${C_RESET}"
    if [ -n "$MIRROR_TRIED_SUMMARY" ]; then note "کاندیدهای ردشده پیش از موفقیت: ${MIRROR_TRIED_SUMMARY}"; fi
    set_st REPO ok "$nm"
  else
    err "هیچ‌یک از کاندیدها اعتبارسنجی نشد؛ تنظیمات مخزن به حالت اولیه بازگردانده شد."
    set_st REPO warn "تغییری اعمال نشد (همه کاندیدها ناموفق)"
    REPO_ALL_FAILED=true
  fi
}

# =============================================================================
#  بخش ۳-ب: مخزن RPM (dnf/yum) — با همان منطق رتبه‌بندی و failover
# =============================================================================
RPM_HOSTS=(
  "ArvanCloud|IR|mirror.arvancloud.ir"
  "Mobinhost|IR|mirror.mobinhost.com"
  "AminiDC|IR|mirror.aminidc.com"
  "IranServer|IR|mirror.iranserver.com"
  "IUT-Isfahan|IR|repo.iut.ac.ir"
  "Shatel|IR|mirror.shatel.ir"
  "Pardisco|IR|mirrors.pardisco.co"
  "0-1-Cloud|IR|mirror.0-1.cloud"
  "ParsDev|IR|mirror.parsdev.com"
  "Abrha|IR|repo.abrha.net"
  "LinuxMirrors|IR|linuxmirrors.ir"
  "Afranet|IR|mirror.afranet.com"
  "SindadCentOS|IR|ir.centos.sindad.cloud"
  "Tsinghua|INT|mirrors.tuna.tsinghua.edu.cn"
  "USTC|INT|mirrors.ustc.edu.cn"
  "NJU|INT|mirrors.nju.edu.cn"
  "SJTU|INT|mirror.sjtu.edu.cn"
  "Aliyun|INT|mirrors.aliyun.com"
  "Tencent|INT|mirrors.cloud.tencent.com"
  "Huawei|INT|repo.huaweicloud.com"
  "Yandex|INT|mirror.yandex.ru"
  "Selectel-RU|INT|mirror.selectel.ru"
  "OVHcloud|INT|mirrors.ovh.net"
  "Hetzner|INT|mirror.hetzner.com"
  "KernelOrg|INT|mirrors.kernel.org"
  "LeaseWeb|INT|mirror.leaseweb.com"
  "FAU-Germany|INT|ftp.fau.de"
  "Init7-CH|INT|mirror.init7.net"
  "Stuttgart|INT|ftp.uni-stuttgart.de"
)
RPM_OFFICIAL_RE='(mirrorlist|mirror|mirrors|dl|vault|download|download\.example|repo|archives)\.(centos|rockylinux|almalinux|fedoraproject)\.org|dl\.rockylinux\.org|repo\.almalinux\.org|mirror\.centos\.org|vault\.centos\.org|download\.fedoraproject\.org'
RPM_FILES=()
RPM_SUFFIX=""      # مسیر نمونه (بعد از میزبان) با متغیرهای گسترش‌یافته برای تست
RPM_CDIR=""
RPM_CAND=()        # "name|region|host|nopub|ms|speed"
RPM_CUR_IDX=-1
RPM_CUR_HOST=""
RPM_DIRTY=false
RPM_BEST_NAME=""

rpm_collect() {
  RPM_FILES=()
  local f
  for f in /etc/yum.repos.d/*.repo; do
    [ -f "$f" ] || continue
    grep -qE "$RPM_OFFICIAL_RE" "$f" 2>/dev/null && RPM_FILES+=("$f")
  done
}

rpm_prepare_probe() {
  local raw f rel="${OS_VERSION}"
  case "$OS_ID" in
    centos) RPM_CDIR="centos" ;;
    rocky)  RPM_CDIR="pub/rocky" ;;
    almalinux) RPM_CDIR="almalinux" ;;
    *) RPM_CDIR="" ;;
  esac
  case "$OS_ID" in fedora) ;; *) rel="${OS_VERSION%%.*}" ;; esac
  for f in "${RPM_FILES[@]}"; do
    raw=$(sed -n -E 's/^[[:space:]]*#?[[:space:]]*baseurl[[:space:]]*=[[:space:]]*([^[:space:]]+).*/\1/p' "$f" | grep -E "$RPM_OFFICIAL_RE" | head -n1)
    [ -n "$raw" ] && break
  done
  [ -z "$raw" ] && return 1
  RPM_SUFFIX=$(echo "$raw" | sed -E 's#^[a-zA-Z]+://[^/]+##')
  RPM_SUFFIX=${RPM_SUFFIX//\$releasever/$rel}
  RPM_SUFFIX=${RPM_SUFFIX//\$basearch/$ARCH_RPM}
  RPM_SUFFIX=${RPM_SUFFIX//\$arch/$ARCH_RPM}
  return 0
}

rpm_probe_item() { # "name|region|host" → چند حالت مسیر (as-is / بدون pub)
  local name region host v suf cd code t best="" bt=9999 bvariant="" raw
  IFS='|' read -r name region host <<<"$1"
  for v in asis nopub; do
    suf="$RPM_SUFFIX"
    if [ -n "$RPM_CDIR" ]; then cd="$RPM_CDIR"; else cd=""; fi
    suf=${suf//\$contentdir/$cd}
    if [ "$v" = "nopub" ]; then suf=$(echo "$suf" | sed -E 's#^/pub/#/#'); fi
    raw=$(curl -sL --max-redirs 3 -o /dev/null --connect-timeout 3 --max-time 6 -w '%{http_code} %{time_total}' "https://${host}${suf}repodata/repomd.xml" 2>/dev/null)
    code=${raw%% *}; t=${raw##* }
    if [ "$code" = "200" ]; then
      t=$(awk -v a="$t" 'BEGIN{printf "%d", a*1000}')
      if [ "$t" -lt "$bt" ]; then bt=$t; bvariant=$v; fi
    fi
  done
  if [ -n "$bvariant" ]; then
    local nopub=0; [ "$bvariant" = "nopub" ] && nopub=1
    echo "OK|$bt|$name|$region|$host|$nopub"
  else echo "FAIL|$name|$region|$host|repomd.xml یافت نشد"; fi
}

rpm_restore_from() {
  local d="$1" f
  [ -d "$d/yum.repos.d" ] || return 0
  for f in "$d"/yum.repos.d/*.repo; do [ -f "$f" ] && cat "$f" > "/etc/yum.repos.d/$(basename "$f")"; done
}

rpm_run() { local t="$1"; shift; timeout "$t" "$PKG_MGR" "$@"; }

rpm_makecache_checked() {
  local rc log="$TMPD/rpm-cache.log"
  with_spinner "$1" rpm_run 150 makecache -y --setopt=timeout=15 --setopt=retries=2
  rc=$?
  cp "$SPIN_OUT" "$log"; cat "$log" >> "$LOGFILE"
  if [ -n "$RPM_CUR_HOST" ] && grep -F "$RPM_CUR_HOST" "$log" | grep -qiE 'error|fail|cannot|timed out|404|curl'; then APT_LAST_ERR="$(grep -F "$RPM_CUR_HOST" "$log" | head -n1 | cut -c1-110)"; return 1; fi
  [ "$rc" -ne 0 ] && { APT_LAST_ERR="$(grep -iE 'error|failed' "$log" | head -n1 | cut -c1-110)"; return 1; }
  return 0
}

rpm_try_candidate() {
  local idx="$1" name region host nopub ms sp f out
  IFS='|' read -r name region host nopub ms sp <<<"${RPM_CAND[$idx]}"
  rpm_restore_from "$BK"; RPM_DIRTY=true
  for f in "${RPM_FILES[@]}"; do
    out=$(mktemp "$TMPD/rpmw.XXXXXX")
    HOST="$host" NOPUB="$nopub" CDIR="$RPM_CDIR" OFFRE="$RPM_OFFICIAL_RE" awk -f "$TMPD/rpm.awk" "$f" > "$out" 2>/dev/null
    [ -s "$out" ] && cat "$out" > "$f"
    rm -f "$out"
  done
  RPM_CUR_HOST="$host"; RPM_BEST_NAME="$name"
  if rpm_makecache_checked "بررسی مخزن «${name}» با ${PKG_MGR} makecache واقعی"; then RPM_CUR_IDX=$idx; RPM_DIRTY=false; return 0; fi
  warn "مخزن «${name}» شکست خورد  ${C_GRAY}${APT_LAST_ERR}${C_RESET}"
  return 1
}

rpm_failover_next() {
  local i tries=0
  for ((i = RPM_CUR_IDX + 1; i < ${#RPM_CAND[@]}; i++)); do
    tries=$((tries + 1)); [ "$tries" -gt 5 ] && break
    rpm_try_candidate "$i" && return 0
    RPM_CUR_IDX=$i
  done
  rpm_restore_from "$BK"; RPM_DIRTY=false; RPM_CUR_HOST=""
  return 1
}

fix_repositories_rpm() {
  case "$OS_ID" in centos|rhel|almalinux|rocky|fedora) ;; *)
    warn "بهینه‌سازی مخزن برای این توزیع RPM پشتیبانی نمی‌شود (${OS_PRETTY})."; set_st REPO skip "پشتیبانی نمی‌شود"; return ;;
  esac
  rpm_collect
  if [ ${#RPM_FILES[@]} -eq 0 ]; then warn "فایل مخزن رسمی توزیع پیدا نشد؛ رد شد."; set_st REPO skip "مخزن رسمی یافت نشد"; return; fi
  if ! rpm_prepare_probe; then warn "الگوی مسیر مخزن استخراج نشد؛ رد شد."; set_st REPO skip "الگوی مسیر نامشخص"; return; fi

  info "تست موازیِ ${#RPM_HOSTS[@]} میزبان مخزن (روی مسیر واقعی repomd.xml) ..."
  par_run "تست مخزن‌ها ..." 12 "$TMPD/rmir" rpm_probe_item "${RPM_HOSTS[@]}"
  local all ok_lines
  all=$(par_collect "$TMPD/rmir")
  ok_lines=$(echo "$all" | grep '^OK|' | LC_ALL=C sort -t'|' -k2,2n)
  DIAG_MIRROR_LINES=$(echo "$all" | sed -E 's/^OK\|/OK  /; s/^FAIL\|/FAIL  /')
  if [ -z "$ok_lines" ]; then
    warn "هیچ میزبانی پاسخ نداد؛ تنظیمات فعلی دست‌نخورده ماند."; REPO_ALL_FAILED=true; set_st REPO err "هیچ مخزنی در دسترس نبود"; return
  fi
  RPM_CAND=()
  local line ms name region host nopub idx=0
  while IFS='|' read -r _ ms name region host nopub; do
    [ -z "$name" ] && continue
    RPM_CAND+=("${name}|${region}|${host}|${nopub}|${ms}|0")
    idx=$((idx + 1))
    printf '  %s%-3s%s %-14s %-7s %4d ms\n' "$C_GOLD" "$([ $idx -eq 1 ] && echo "$S_STAR")" "$C_RESET" "$name" "$region" "$ms"
  done <<<"$ok_lines"

  if [ "$DRY_RUN" = true ]; then set_st REPO skip "dry-run: برترین $(echo "${RPM_CAND[0]}" | cut -d'|' -f1)"; return; fi

  local f
  for f in "${RPM_FILES[@]}"; do bk_save "$f" "yum.repos.d/$(basename "$f")"; done
  blank; info "اعمال بهترین میزبان با اعتبارسنجی واقعی و failover خودکار ..."
  RPM_CUR_IDX=-1
  if rpm_failover_next; then
    ok "مخزن فعال: ${C_BOLD}${RPM_BEST_NAME}${C_RESET}   ${C_GRAY}(پشتیبان: ${BK}/yum.repos.d)${C_RESET}"
    set_st REPO ok "$RPM_BEST_NAME"
  else
    err "هیچ‌یک از کاندیدها معتبر نبود؛ تنظیمات به حالت اولیه بازگشت."
    set_st REPO warn "تغییری اعمال نشد (همه کاندیدها ناموفق)"; REPO_ALL_FAILED=true
  fi
}

fix_repositories() {
  if [ "$HAS_CURL" != true ]; then warn "بدون curl امکان تست مخزن‌ها نیست؛ رد شد."; set_st REPO skip "curl موجود نیست"; return; fi
  case "$PKG_MGR" in
    apt)     fix_repositories_apt ;;
    dnf|yum) fix_repositories_rpm ;;
    *)       warn "بهینه‌سازی مخزن برای مدیر بسته‌ی «${PKG_MGR}» پشتیبانی نمی‌شود."; set_st REPO skip "پشتیبانی نمی‌شود (${PKG_MGR})" ;;
  esac
}

# =============================================================================
#  بخش ۴: بررسی دسترسی GitHub (موازی) + مقایسه با قبل از تغییر DNS
# =============================================================================
GITHUB_HOSTS=("github.com" "api.github.com" "raw.githubusercontent.com" "codeload.github.com")
GITHUB_BASE_OK=-1
GITHUB_DIAG_LINES=""

gh_probe_item() {
  local h="$1" ip raw code t
  ip=$(timeout 6 getent hosts "$h" 2>/dev/null | awk '{print $1; exit}')
  if [ -z "$ip" ]; then echo "$h|NORESOLVE|-|-|-"; return; fi
  if [ "$HAS_CURL" != true ]; then echo "$h|RESOLVED|-|-|$ip"; return; fi
  raw=$(curl -o /dev/null -s -w '%{http_code} %{time_total}' --connect-timeout 4 --max-time 7 "https://${h}" 2>/dev/null)
  code=${raw%% *}; t=${raw##* }
  if [ -n "$code" ] && [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 500 ] 2>/dev/null; then echo "$h|OK|$code|$t|$ip"
  else echo "$h|HTTPSFAIL|$code|$t|$ip"; fi
}

github_count_ok() { # تعداد دامنه‌های سالم (بی‌صدا)
  par_run "" 4 "$TMPD/ghq" gh_probe_item "${GITHUB_HOSTS[@]}"
  par_collect "$TMPD/ghq" | grep -cE '\|(OK|RESOLVED)\|'
}

check_github_access() {
  par_run "بررسی GitHub ..." 4 "$TMPD/gh" gh_probe_item "${GITHUB_HOSTS[@]}"
  local all okn=0 h st code t ip
  all=$(par_collect "$TMPD/gh"); GITHUB_DIAG_LINES="$all"
  while IFS='|' read -r h st code t ip; do
    [ -z "$h" ] && continue
    case "$st" in
      OK)         printf '  %s%s%s %-26s %sHTTP %s · %.2fs · %s%s\n' "$C_OK" "$S_OK" "$C_RESET" "$h" "$C_GRAY" "$code" "$t" "$ip" "$C_RESET"; okn=$((okn + 1)) ;;
      RESOLVED)   printf '  %s%s%s %-26s %sresolve شد (%s)%s\n' "$C_OK" "$S_OK" "$C_RESET" "$h" "$C_GRAY" "$ip" "$C_RESET"; okn=$((okn + 1)) ;;
      HTTPSFAIL)  printf '  %s%s%s %-26s %sresolve شد (%s) ولی HTTPS ناموفق%s\n' "$C_WARN" "$S_WARN" "$C_RESET" "$h" "$C_GRAY" "$ip" "$C_RESET" ;;
      *)          printf '  %s%s%s %-26s %sresolve نشد%s\n' "$C_ERR" "$S_ERR" "$C_RESET" "$h" "$C_GRAY" "$C_RESET" ;;
    esac
  done <<<"$all"
  blank
  local total=${#GITHUB_HOSTS[@]}
  if [ "$okn" -eq "$total" ]; then ok "دسترسی به GitHub کامل و سالم است."; set_st GITHUB ok "کامل و سالم"
  elif [ "$okn" -gt 0 ]; then warn "دسترسی به GitHub جزئی است (${okn}/${total})."; set_st GITHUB warn "جزئی (${okn}/${total})"
  else err "هیچ‌یک از دامنه‌های GitHub از این سرور در دسترس نیست."; set_st GITHUB err "بدون دسترسی"; fi
  if [ "$GITHUB_BASE_OK" -ge 0 ] && [ "$okn" -lt "$GITHUB_BASE_OK" ]; then
    warn "نسبت به قبل از تغییر DNS، دسترسی GitHub بدتر شده (${GITHUB_BASE_OK} → ${okn}). در صورت نیاز: ${C_BOLD}--restore${C_RESET}"
    set_st GITHUB warn "افت نسبت به قبل (${GITHUB_BASE_OK}→${okn})"
  fi
}

# =============================================================================
#  بخش ۵: BBR مشروط (تست سرعت قبل/بعد) + تنظیمات کرنل/شبکه
# =============================================================================
BBR_REVERT_THRESHOLD=10
SPEED_URLS=(
  "https://speed.cloudflare.com/__down?bytes=25000000"
  "http://speedtest.tele2.net/10MB.zip"
  "https://proof.ovh.net/files/10Mb.dat"
  "http://ipv4.download.thinkbroadband.com/10MB.zip"
  "https://speed.hetzner.de/10MB.bin"
)
SPEED_URL=""
SPEED_MIRROR_URLS=()   # فایل‌های بزرگ از میرورهای بین‌المللیِ سالم (در مرحله‌ی مخزن پر می‌شود)

# اولویت با میرورهای بین‌المللی که همین الان در تست مخزن سالم بودند؛ سپس منابع عمومی.
# وضعیت هر منبع نمایش داده می‌شود تا اگر مشکلی بود علتش معلوم باشد.
pick_speed_url() {
  local u code host cands=() lines="" n=0
  cands=("${SPEED_MIRROR_URLS[@]}" "${SPEED_URLS[@]}")
  for u in "${cands[@]}"; do
    [ -z "$u" ] && continue
    n=$((n + 1)); [ "$n" -gt 8 ] && break
    host=$(url_host "$u")
    code=$(curl -4 -sL --max-redirs 3 -A 'Mozilla/5.0' -o /dev/null -r 0-65535 --connect-timeout 4 --max-time 7 -w '%{http_code}' "$u" 2>/dev/null)
    if [ "$code" = "200" ] || [ "$code" = "206" ]; then SPEED_URL="$u"; note "منبع تست سرعت: ${host} (HTTP ${code})"; return 0; fi
    lines+="${host}=${code:-000} "
  done
  note "وضعیت منابع تست: ${lines:-بدون منبع}"
  return 1
}

# میانه‌ی ۳ اندازه‌گیری سرعت (KB/s)؛ خالی = ناموفق
measure_network_speed_kbps() {
  [ "$HAS_CURL" = true ] && [ -n "$SPEED_URL" ] || { echo ""; return 1; }
  local vals=() i raw code sp
  for i in 1 2 3; do
    raw=$(curl -4 -A 'Mozilla/5.0' -o /dev/null -s -L -w '%{http_code} %{speed_download}' --connect-timeout 4 --max-time 7 "$SPEED_URL" 2>/dev/null)
    code=${raw%% *}; sp=${raw##* }; sp=${sp%%.*}
    if { [ "$code" = "200" ] || [ "$code" = "206" ]; } && [ -n "$sp" ] && [ "$sp" -gt 0 ] 2>/dev/null; then vals+=("$((sp / 1024))"); fi
  done
  [ ${#vals[@]} -eq 0 ] && { echo ""; return 1; }
  printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR]=$1}END{print a[int((NR+1)/2)]}'
}

revert_bbr() {
  local orig_cc="$1" orig_qdisc="$2"
  rm -f /etc/sysctl.d/99-abrbaran-bbr.conf /etc/modules-load.d/abrbaran-bbr.conf
  sysctl -w net.ipv4.tcp_congestion_control="${orig_cc:-cubic}" >/dev/null 2>&1 || true
  sysctl -w net.core.default_qdisc="${orig_qdisc:-pfifo_fast}" >/dev/null 2>&1 || true
}

enable_bbr() {
  local orig_cc orig_qdisc available current before after
  orig_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "cubic")
  orig_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "pfifo_fast")
  if [ "$orig_cc" = "bbr" ]; then ok "BBR از قبل روی این سرور فعال است."; set_st BBR ok "از قبل فعال بود"; return 0; fi
  if [ ! -w /proc/sys/net/ipv4/tcp_congestion_control ]; then warn "امکان تغییر پارامترهای شبکه نیست (احتمالاً کانتینر)؛ رد شد."; set_st BBR skip "کانتینر/فقط‌خواندنی"; return 1; fi
  modprobe tcp_bbr >/dev/null 2>&1 || true
  available=$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || echo "")
  if ! echo "$available" | grep -qw bbr; then warn "هسته‌ی این سرور از BBR پشتیبانی نمی‌کند."; set_st BBR skip "پشتیبانی نمی‌شود"; return 1; fi
  if [ "$HAS_CURL" != true ] || ! pick_speed_url; then
    warn "منبع تست سرعت در دسترس نبود؛ برای اطمینان BBR فعال نشد."; set_st BBR warn "تست شبکه ممکن نبود"; return 1
  fi
  with_spinner "سنجش سرعت شبکه پیش از BBR (۳ نمونه)" measure_network_speed_kbps
  before=$(tr -d ' \n' < "$SPIN_OUT")
  if [ -z "$before" ]; then warn "سنجش سرعت ممکن نشد؛ BBR فعال نشد."; set_st BBR warn "تست شبکه ممکن نبود"; return 1; fi
  info "سرعت قبل از BBR: ${C_BOLD}${before} KB/s${C_RESET}"
  if [ "$DRY_RUN" = true ]; then note "(dry-run) BBR فعال و دوباره سنجیده می‌شد."; set_st BBR skip "dry-run"; return 0; fi

  mkdir -p /etc/sysctl.d /etc/modules-load.d
  printf '# ABR BARAN IDC . IR\nnet.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr\n' > /etc/sysctl.d/99-abrbaran-bbr.conf
  echo tcp_bbr > /etc/modules-load.d/abrbaran-bbr.conf
  sysctl -p /etc/sysctl.d/99-abrbaran-bbr.conf >/dev/null 2>&1
  current=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "")
  if [ "$current" != "bbr" ]; then
    warn "فعال‌سازی BBR تایید نشد؛ بازگردانی."; revert_bbr "$orig_cc" "$orig_qdisc"; set_st BBR warn "ناموفق (بازگردانی شد)"; return 1
  fi
  with_spinner "سنجش سرعت شبکه پس از BBR (۳ نمونه)" measure_network_speed_kbps
  after=$(tr -d ' \n' < "$SPIN_OUT")
  if [ -z "$after" ]; then warn "سنجش دوم ممکن نشد؛ BBR بازگردانده شد."; revert_bbr "$orig_cc" "$orig_qdisc"; set_st BBR warn "بازگردانی شد (تست دوم ناموفق)"; return 1; fi
  info "سرعت بعد از BBR:  ${C_BOLD}${after} KB/s${C_RESET}"
  local drop; drop=$(awk -v b="$before" -v a="$after" 'BEGIN{ if (b<=0) print 0; else printf "%d", ((b-a)/b)*100 }')
  if [ "$drop" -gt "$BBR_REVERT_THRESHOLD" ]; then
    # یک بار دیگر برای حذف نوسان لحظه‌ای شبکه
    with_spinner "افت دیده شد؛ سنجش مجدد برای اطمینان" measure_network_speed_kbps
    local again; again=$(tr -d ' \n' < "$SPIN_OUT")
    [ -n "$again" ] && [ "$again" -gt "$after" ] && after=$again
    drop=$(awk -v b="$before" -v a="$after" 'BEGIN{ if (b<=0) print 0; else printf "%d", ((b-a)/b)*100 }')
  fi
  if [ "$drop" -gt "$BBR_REVERT_THRESHOLD" ]; then
    warn "BBR باعث افت حدود ${drop}٪ شد؛ به حالت قبل (${orig_cc}) بازگردانده شد."
    revert_bbr "$orig_cc" "$orig_qdisc"; set_st BBR warn "بازگردانی شد (افت ${drop}٪)"; return 1
  fi
  ok "BBR فعال و با تست قبل/بعد تایید شد."
  set_st BBR ok "فعال شد (${before} → ${after} KB/s)"
}

TUNE_PAIRS=()
tune_cur() { sysctl -n "$1" 2>/dev/null | tr '\t' ' '; }
tune_set() {
  local k="$1" v="$2" p="/proc/sys/${1//./\/}" cur
  [ -w "$p" ] || return
  cur=$(tune_cur "$k" | tr -s ' ')
  [ "$cur" = "$v" ] && return
  TUNE_PAIRS+=("$k=$v")
}
tune_raise() { # فقط اگر مقدار فعلی کمتر است
  local k="$1" v="$2" cur; cur=$(tune_cur "$k")
  [ -z "$cur" ] && return
  [ "$cur" -lt "$v" ] 2>/dev/null && tune_set "$k" "$v"
}

apply_kernel_tuning() {
  if [ ! -w /proc/sys/net/core/somaxconn ]; then warn "پارامترهای کرنل قابل تغییر نیستند (کانتینر/محدودیت)؛ رد شد."; set_st TUNE skip "کانتینر/فقط‌خواندنی"; return 1; fi
  local mem_kb mem_mb buf swap_kb; TUNE_PAIRS=()
  mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo); mem_mb=$((mem_kb / 1024))
  swap_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
  if   [ "$mem_mb" -ge 4096 ]; then buf=33554432
  elif [ "$mem_mb" -ge 1024 ]; then buf=16777216
  else buf=4194304; fi

  tune_raise net.core.somaxconn 4096
  tune_raise net.core.netdev_max_backlog 16384
  tune_raise net.ipv4.tcp_max_syn_backlog 8192
  tune_raise net.core.rmem_max "$buf"
  tune_raise net.core.wmem_max "$buf"
  tune_raise fs.file-max 1048576
  tune_set net.ipv4.tcp_fin_timeout 30
  tune_set net.ipv4.tcp_keepalive_time 600
  tune_set net.ipv4.tcp_keepalive_intvl 30
  tune_set net.ipv4.tcp_keepalive_probes 5
  tune_set net.ipv4.tcp_slow_start_after_idle 0
  tune_set net.ipv4.tcp_mtu_probing 1
  tune_set net.ipv4.tcp_tw_reuse 1
  tune_set net.ipv4.tcp_fastopen 3
  tune_set net.ipv4.ip_local_port_range "10240 65535"
  if [ -w /proc/sys/net/ipv4/tcp_rmem ]; then tune_set net.ipv4.tcp_rmem "4096 131072 $buf"; tune_set net.ipv4.tcp_wmem "4096 65536 $buf"; fi
  if [ "$mem_mb" -ge 2048 ]; then
    tune_set vm.vfs_cache_pressure 50
    [ "${swap_kb:-0}" -gt 0 ] && tune_set vm.swappiness 10
  fi

  if [ ${#TUNE_PAIRS[@]} -eq 0 ]; then ok "پارامترهای شبکه/کرنل از قبل مناسب‌اند."; set_st TUNE ok "نیازی به تغییر نبود"; return 0; fi
  info "رم: ${mem_mb}MB  ·  ${#TUNE_PAIRS[@]} پارامتر برای بهینه‌سازی:"
  local p k
  for p in "${TUNE_PAIRS[@]}"; do k=${p%%=*}; note "$k = ${p#*=}   (قبلی: $(tune_cur "$k"))"; done
  if [ "$DRY_RUN" = true ]; then set_st TUNE skip "dry-run: ${#TUNE_PAIRS[@]} پارامتر"; return 0; fi

  mkdir -p /etc/sysctl.d "$BK"
  : > "$BK/sysctl-before.conf"
  local applied=() conf=/etc/sysctl.d/99-abrbaran-tuning.conf
  { echo "# ABR BARAN IDC . IR — بهینه‌سازی کرنل/شبکه (رم: ${mem_mb}MB)"; } > "$conf"
  for p in "${TUNE_PAIRS[@]}"; do
    k=${p%%=*}
    echo "$k = $(tune_cur "$k")" >> "$BK/sysctl-before.conf"
    if sysctl -w "$k=${p#*=}" >/dev/null 2>&1; then applied+=("$p"); echo "$k = ${p#*=}" >> "$conf"; fi
  done
  ok "${#applied[@]} پارامتر اعمال و دائمی شد  ${C_GRAY}(${conf})${C_RESET}"
  set_st TUNE ok "${#applied[@]} پارامتر"
}

# =============================================================================
#  بخش ۶: Speedtest (باینری مستقیم Ookla؛ بدون اجرای اسکریپت از راه دور)
# =============================================================================
SPD_URL=""; SPD_DIR=""; SPD_FILE=""; SPD_TOTAL=0
speedtest_prepare() { # در پروسه‌ی اصلی اجرا می‌شود تا نوار پیشرفت به متغیرها دسترسی داشته باشد
  local arch sptarch
  arch=$(uname -m)
  case "$arch" in
    x86_64) sptarch="x86_64" ;; aarch64|arm64) sptarch="aarch64" ;; armv7l|armv6l) sptarch="armhf" ;; i386|i686) sptarch="i386" ;;
    *) err "معماری ($arch) برای نصب مستقیم Speedtest پشتیبانی نمی‌شود."; return 1 ;;
  esac
  SPD_URL="https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-${sptarch}.tgz"
  SPD_DIR=$(mktemp -d "$TMPD/spd.XXXXXX"); SPD_FILE="$SPD_DIR/s.tgz"
  SPD_TOTAL=$(curl -sIL --connect-timeout 4 --max-time 8 "$SPD_URL" 2>/dev/null | awk 'tolower($1)=="content-length:"{v=$2} END{gsub(/\r/,"",v); print v+0}')
  return 0
}
speedtest_dl_progress() {
  local sz=0; [ -f "$SPD_FILE" ] && sz=$(stat -c %s "$SPD_FILE" 2>/dev/null || echo 0)
  printf '%s|%s|%s KB' "$sz" "$SPD_TOTAL" "$((sz / 1024))"
}
speedtest_live() { tr '\r' '\n' < "$1" 2>/dev/null | grep -E 'Latency|Download|Upload|Server|Testing|Retrieving' | tail -n1 | sed -E 's/^ +//' | cut -c1-48; }

install_speedtest_binary() {
  if curl -fsSL --connect-timeout 5 --max-time 60 "$SPD_URL" -o "$SPD_FILE" 2>/dev/null \
     && tar -xzf "$SPD_FILE" -C "$SPD_DIR" 2>/dev/null && [ -f "$SPD_DIR/speedtest" ]; then
    install -m 755 "$SPD_DIR/speedtest" /usr/local/bin/speedtest; return 0
  fi
  return 1
}

install_speedtest() {
  local installed=false
  if command -v speedtest >/dev/null 2>&1 && speedtest --version 2>/dev/null | grep -qi ookla; then installed=true
  else
    if speedtest_prepare; then
      SPIN_PROGRESS_FN=speedtest_dl_progress
      with_spinner "دانلود و نصب Ookla Speedtest" install_speedtest_binary && installed=true
      SPIN_PROGRESS_FN=""
    fi
    if [ "$installed" != true ]; then
      warn "دانلود مستقیم ممکن نشد؛ تلاش از طریق مخزن رسمی ..."
      case "$PKG_MGR" in
        apt) timeout -k 10 60 bash -c 'curl -fsSL --max-time 20 https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash' >/dev/null 2>&1 && pkg_install speedtest && installed=true ;;
        dnf|yum) timeout -k 10 60 bash -c 'curl -fsSL --max-time 20 https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.rpm.sh | bash' >/dev/null 2>&1 && pkg_install speedtest && installed=true ;;
      esac
    fi
  fi
  if [ "$installed" = true ] && command -v speedtest >/dev/null 2>&1; then
    ok "Ookla Speedtest آماده است."
    blank
    SPIN_SUFFIX_FN=speedtest_live
    with_spinner "اجرای تست سرعت" timeout 90 speedtest --accept-license --accept-gdpr
    local rc=$?
    SPIN_SUFFIX_FN=""
    if [ $rc -eq 0 ]; then
      sed -E 's/\r/\n/g' "$SPIN_OUT" | grep -E 'Server:|ISP:|Latency:|Download:|Upload:|Result URL' | sed 's/^ */    /'
      set_st SPEED ok "نصب و تست شد"
    else warn "اجرای تست سرعت ناموفق یا timeout شد."; set_st SPEED warn "نصب شد، تست ناموفق"; fi
  else
    err "نصب Speedtest ناموفق بود."; set_st SPEED err "نصب ناموفق"
  fi
}

# =============================================================================
#  بخش ۷: منطقه‌زمانی و همگام‌سازی ساعت (بدون تداخل با ntpd-rs / ntpsec / chrony / timesyncd)
# =============================================================================
ntp_service_active() {
  local s
  for s in systemd-timesyncd chronyd chrony ntpd ntp ntpsec ntpd-rs ntpd-rs-metrics; do
    systemctl is-active --quiet "$s" 2>/dev/null && { printf '%s' "$s"; return 0; }
  done
  return 1
}

optimize_time_settings() {
  local tz_ok=true ntp_ok=true cur svc
  if [ "$DRY_RUN" = true ]; then note "(dry-run) منطقه‌زمانی Asia/Tehran و NTP بررسی می‌شد."; set_st TIME skip "dry-run"; return 0; fi
  if command -v timedatectl >/dev/null 2>&1; then
    cur=$(timedatectl show -p Timezone --value 2>/dev/null)
    if [ "$cur" != "Asia/Tehran" ]; then
      if timedatectl set-timezone Asia/Tehran >/dev/null 2>&1; then ok "منطقه‌زمانی روی Asia/Tehran تنظیم شد (قبلی: ${cur:-نامشخص})."
      else warn "تنظیم منطقه‌زمانی ناموفق بود."; tz_ok=false; fi
    else ok "منطقه‌زمانی از قبل Asia/Tehran است."; fi
  elif [ -e /usr/share/zoneinfo/Asia/Tehran ] && ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime 2>/dev/null; then
    echo "Asia/Tehran" > /etc/timezone 2>/dev/null || true; ok "منطقه‌زمانی روی Asia/Tehran تنظیم شد."
  else warn "تنظیم منطقه‌زمانی ناموفق بود."; tz_ok=false; fi

  if svc=$(ntp_service_active); then
    ok "همگام‌سازی ساعت از قبل با ${C_BOLD}${svc}${C_RESET} فعال است."
  elif [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then
    ok "ساعت سیستم هم‌اکنون همگام است."
  else
    info "سرویس همگام‌سازی ساعت فعال نیست."
    with_spinner "نصب chrony" pkg_install chrony
    systemctl enable --now chronyd >/dev/null 2>&1 || systemctl enable --now chrony >/dev/null 2>&1 || true
    if ntp_service_active >/dev/null; then ok "chrony فعال شد."; else warn "فعال‌سازی همگام‌سازی ساعت ممکن نشد."; ntp_ok=false; fi
  fi
  if [ "$tz_ok" = true ] && [ "$ntp_ok" = true ]; then set_st TIME ok "Asia/Tehran + NTP"; else set_st TIME warn "ناقص انجام شد"; fi
}

# =============================================================================
#  بخش ۸: آپدیت/آپگرید امن با failover مخزن در میانه‌ی کار
# =============================================================================
UPDATE_DONE=false
REBOOT_NEEDED=false
NET_ERR_RE='Failed to fetch|Could not resolve|Temporary failure|Hash Sum mismatch|Connection (timed out|failed|reset)|Unable to connect|404 +Not Found|Some index files failed|Err:[0-9]|File has unexpected size|Bad header line|Release file .* is not valid yet'

check_disk_space() {
  local avail_mb
  avail_mb=$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')
  if [ -z "$avail_mb" ]; then warn "بررسی فضای دیسک ممکن نشد؛ با احتیاط ادامه می‌دهیم."; return 0; fi
  if [ "$avail_mb" -lt 1024 ]; then
    err "فضای آزاد پارتیشن اصلی فقط ${avail_mb}MB است؛ حداقل ۱۰۲۴MB لازم است."
    err "برای جلوگیری از خرابی dpkg/rpm، آپدیت انجام نشد. ابتدا فضا آزاد کنید."
    return 1
  fi
  ok "فضای آزاد دیسک کافی است (${avail_mb}MB)."
}

update_upgrade_apt() {
  local attempt=0 rc
  # --- مرحله ۱: apt update (با failover) ---
  while :; do
    apt_update_checked "مرحله ۱/۲ · بروزرسانی فهرست بسته‌ها"; rc=$?
    [ "$rc" -eq 0 ] && break
    err "apt update ناموفق  ${C_GRAY}${APT_LAST_ERR}${C_RESET}"
    attempt=$((attempt + 1))
    if [ "$rc" -eq 1 ] && [ ${#APT_CAND[@]} -gt 0 ] && [ "$attempt" -le 6 ] && apt_failover_next; then
      warn "به مخزن بعدی سوییچ شد: ${C_BOLD}${APT_BEST_NAME}${C_RESET}"; continue
    fi
    UPDATE_STATUS="apt update ناموفق"; return 1
  done

  # --- مرحله ۲: upgrade (در صورت خطای شبکه/مخزن، سوییچ مخزن و ادامه از همان‌جا) ---
  attempt=0
  local log="$TMPD/apt-upgrade.log"
  while :; do
    UPG_TOTAL=$(apt_run 60 -s upgrade 2>/dev/null | grep -c '^Inst')
    [ "$UPG_TOTAL" -gt 0 ] && info "تعداد بسته‌های قابل ارتقا: ${C_BOLD}${UPG_TOTAL}${C_RESET}"
    SPIN_PROGRESS_FN=apt_upgrade_progress
    with_spinner "مرحله ۲/۲ · ارتقای بسته‌ها" apt_run 3000 upgrade -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::Retries=2
    rc=$?
    SPIN_PROGRESS_FN=""
    cp "$SPIN_OUT" "$log"; cat "$log" >> "$LOGFILE"
    [ "$rc" -eq 0 ] && break
    err "apt upgrade ناموفق  ${C_GRAY}$(grep -E '^(E:|Err:)' "$log" | head -n1 | cut -c1-100)${C_RESET}"
    attempt=$((attempt + 1))
    if grep -qE "$NET_ERR_RE" "$log" && [ ${#APT_CAND[@]} -gt 0 ] && [ "$attempt" -le 6 ]; then
      warn "علت از جنس شبکه/مخزن است؛ سوییچ به مخزن بعدی و ادامه (بسته‌های دانلودشده حفظ می‌شوند) ..."
      if apt_failover_next; then ok "مخزن جدید: ${C_BOLD}${APT_BEST_NAME}${C_RESET}"; continue; fi
    fi
    # خطای dpkg نیمه‌کاره را یک بار ترمیم می‌کنیم
    if grep -qE 'dpkg was interrupted|dpkg --configure -a' "$log" && [ "$attempt" -le 1 ]; then
      warn "dpkg نیمه‌کاره بود؛ اجرای dpkg --configure -a ..."
      DEBIAN_FRONTEND=noninteractive dpkg --configure -a >/dev/null 2>&1; continue
    fi
    tail -n 6 "$log" | sed 's/^/    /'
    UPDATE_STATUS="apt upgrade ناموفق"; return 1
  done
  [ -f /var/run/reboot-required ] && REBOOT_NEEDED=true
  return 0
}

update_upgrade_rpm() {
  local rc attempt=0 log="$TMPD/rpm-update.log"
  with_spinner "مرحله ۱/۲ · بروزرسانی اطلاعات مخزن" rpm_run 300 makecache -y
  cat "$SPIN_OUT" >> "$LOGFILE"
  while :; do
    with_spinner "مرحله ۲/۲ · آپدیت بسته‌ها" rpm_run 3000 update -y --setopt=timeout=20 --setopt=retries=3
    rc=$?
    cp "$SPIN_OUT" "$log"; cat "$log" >> "$LOGFILE"
    [ "$rc" -eq 0 ] && break
    err "${PKG_MGR} update ناموفق  ${C_GRAY}$(grep -iE 'error|failed' "$log" | head -n1 | cut -c1-100)${C_RESET}"
    attempt=$((attempt + 1))
    if grep -qiE 'curl error|cannot download|failed to download|timeout|Status code: [45]|Could not resolve' "$log" && [ ${#RPM_CAND[@]} -gt 0 ] && [ "$attempt" -le 5 ]; then
      warn "علت از جنس شبکه/مخزن است؛ سوییچ به میزبان بعدی ..."
      if rpm_failover_next; then ok "میزبان جدید: ${C_BOLD}${RPM_BEST_NAME}${C_RESET}"; continue; fi
    fi
    UPDATE_STATUS="${PKG_MGR} update ناموفق"; return 1
  done
  if command -v needs-restarting >/dev/null 2>&1; then needs-restarting -r >/dev/null 2>&1 || REBOOT_NEEDED=true
  else
    local newest running; running=$(uname -r)
    newest=$(rpm -q kernel --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' 2>/dev/null | sort -V | tail -n1)
    [ -n "$newest" ] && [ "$newest" != "$running" ] && REBOOT_NEEDED=true
  fi
  return 0
}

UPDATE_STATUS="رد شد"
update_upgrade_system() {
  if [ "$DRY_RUN" = true ]; then note "(dry-run) آپدیت اجرا نمی‌شد."; UPDATE_STATUS="dry-run"; set_st UPDATE skip "dry-run"; return 0; fi
  if ! check_disk_space; then set_st UPDATE err "کمبود فضای دیسک"; return 1; fi
  blank
  local rc=0
  case "$PKG_MGR" in
    apt)     update_upgrade_apt; rc=$? ;;
    dnf|yum) update_upgrade_rpm; rc=$? ;;
    zypper)
      with_spinner "zypper refresh" timeout 300 zypper --non-interactive refresh
      with_spinner "zypper update" timeout 3000 zypper --non-interactive update; rc=$? ;;
    apk)     with_spinner "apk upgrade" sh -c 'apk update && apk upgrade'; rc=$? ;;
    pacman)  with_spinner "pacman -Syu" timeout 3000 pacman -Syu --noconfirm; rc=$? ;;
    *)       err "مدیر بسته شناسایی نشد."; UPDATE_STATUS="مدیر بسته نامشخص"; rc=1 ;;
  esac
  if [ "$rc" -eq 0 ]; then
    UPDATE_DONE=true; UPDATE_STATUS="انجام شد"
    ok "آپدیت/آپگرید سیستم‌عامل به‌طور کامل انجام شد."
    set_st UPDATE ok "انجام شد"
  else
    set_st UPDATE err "$UPDATE_STATUS"
    note "لاگ کامل: $LOGFILE"
  fi
}

# =============================================================================
#  گزارش فنی برای NOC (فقط وقتی هیچ مخزنی در دسترس نباشد)
# =============================================================================
NETWORK_REPORT_FILE=""
generate_network_diagnostic_report() {
  info "الگوی اختلال شبکه شناسایی شد؛ تولید گزارش فنی برای زیرساخت ..."
  local ts hostname_val public_ip gateway_ip codename h
  ts=$(date '+%Y-%m-%d %H:%M:%S %Z'); hostname_val=$(hostname 2>/dev/null || echo "نامشخص")
  public_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null); [ -z "$public_ip" ] && public_ip="نامشخص"
  gateway_ip=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}'); [ -z "$gateway_ip" ] && gateway_ip="نامشخص"
  codename="${P_SUITE:-stable}"
  NETWORK_REPORT_FILE="/root/abrbaran-network-report-$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "================================================================"
    echo "گزارش فنی اختلال اتصال بین‌الملل سرور — ABR BARAN IDC . IR"
    echo "================================================================"
    echo "زمان: ${ts}"; echo "hostname: ${hostname_val}"; echo "IP عمومی: ${public_ip}"; echo "Gateway: ${gateway_ip}"
    echo "سیستم‌عامل: ${OS_PRETTY}"; echo "لاگ کامل: ${LOGFILE}"; echo
    echo "--- خلاصه ---"
    echo "هیچ‌یک از مخزن‌های تست‌شده (ایرانی و بین‌المللی) به‌طور کامل پاسخ نداد."
    [ "$DNS_ALL_FAILED" = true ] && echo "هیچ‌یک از DNS های تست‌شده هم پاسخ نداد."
    echo; echo "--- DNS (خام: type|name|ips|ms|count) ---"; echo "${DIAG_DNS_LINES:-(بدون داده)}"
    echo; echo "--- مخزن‌ها (خام) ---"; echo "${DIAG_MIRROR_LINES:-(بدون داده)}"
    echo; echo "--- ping ---"
    echo "\$ ping -c 4 1.1.1.1"; ping -c 4 -W 2 1.1.1.1 2>&1 || echo "(بدون پاسخ)"
    echo "\$ ping -c 4 8.8.8.8"; ping -c 4 -W 2 8.8.8.8 2>&1 || echo "(بدون پاسخ)"
    if [ "$gateway_ip" != "نامشخص" ]; then echo "\$ ping -c 4 ${gateway_ip}"; ping -c 4 -W 2 "$gateway_ip" 2>&1 || echo "(بدون پاسخ)"; fi
    echo; echo "--- resolve ---"
    for h in archive.ubuntu.com mirror.arvancloud.ir speed.cloudflare.com; do echo "\$ getent hosts $h"; getent hosts "$h" 2>&1 || echo "(resolve نشد)"; done
    echo; echo "--- مسیر شبکه ---"
    if command -v mtr >/dev/null 2>&1; then mtr -rw -c 10 1.1.1.1 2>&1
    elif command -v traceroute >/dev/null 2>&1; then traceroute -w 2 -m 20 1.1.1.1 2>&1
    else echo "(mtr/traceroute نصب نیست)"; fi
    echo; echo "--- curl -v ---"
    curl -v --max-time 8 "https://archive.ubuntu.com/ubuntu/dists/${codename}/Release" 2>&1 | tail -n 25
    echo "================================================================"
  } > "$NETWORK_REPORT_FILE" 2>/dev/null
  ok "گزارش ذخیره شد (قابل ارسال به NOC):"; note "$NETWORK_REPORT_FILE"
}

# =============================================================================
#  بازگردانی کامل به حالت اولیه
# =============================================================================
# =============================================================================
#  ماژول‌ها: انتخاب، منو و ابزارهای مشترک
# =============================================================================
has_word() { case ",$1," in *",$2,"*) return 0 ;; esac; return 1; }
mod_on() { # آیا این ماژول در این اجرا فعال است؟
  [ -n "$ONLY_LIST" ] && ! has_word "$ONLY_LIST" "$1" && return 1
  has_word "$SKIP_LIST" "$1" && return 1
  return 0
}
is_container() { local v; v=$(systemd-detect-virt -c 2>/dev/null); [ -n "$v" ] && [ "$v" != "none" ]; }
has_systemd() { [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; }
svc_reload() { local s; for s in "$@"; do systemctl reload "$s" >/dev/null 2>&1 && return 0; done; return 1; }

# اسپینر با برچسب زنده (آخرین خط خروجی دستور)
tail_suffix() { tail -n1 "$1" 2>/dev/null | tr -d '\r' | cut -c1-44; }
run_spin() { # msg cmd...
  local msg="$1"; shift
  SPIN_SUFFIX_FN="tail_suffix"; SPIN_PROGRESS_FN=""
  with_spinner "$msg" "$@"; local rc=$?
  SPIN_SUFFIX_FN=""
  return $rc
}

MOD_LABELS=(
  "dns|DNS هوشمند (ایرانی + خارجی، تایید با resolve واقعی)"
  "repo|مخزن/میرور بسته‌ها با تست سرعت و failover"
  "github|بررسی دسترسی به GitHub"
  "bbr|فعال‌سازی BBR با تست قبل/بعد"
  "tune|بهینه‌سازی sysctl متناسب با رم"
  "tools|ابزارهای کاربردی (git، htop، tmux، jq، ...)"
  "system|سوآپ، limits، journald، TRIM، رفع hosts"
  "docker|Docker + Compose با میرور ایران/جهان"
  "security|SSH امن‌تر، فایروال UFW، Fail2ban"
  "speedtest|تست سرعت Ookla"
  "time|منطقه‌زمانی تهران + همگام‌سازی ساعت"
  "update|آپدیت/آپگرید امن سیستم‌عامل"
)

menu_checklist() {
  local sel=() i m ans lbl n=${#MOD_LABELS[@]} out=""
  for ((i = 0; i < n; i++)); do m=${MOD_LABELS[$i]%%|*}; if [ "$m" = "docker" ]; then sel[$i]=0; else sel[$i]=1; fi; done
  while :; do
    printf '\n  %sانتخاب مرحله‌ها%s  %s(شماره را بزنید تا روشن/خاموش شود)%s\n\n' "$C_BOLD" "$C_RESET" "$C_GRAY" "$C_RESET" >/dev/tty
    for ((i = 0; i < n; i++)); do
      lbl=${MOD_LABELS[$i]#*|}
      if [ "${sel[$i]}" = 1 ]; then printf '   %s%2d%s  %s%s%s  %s\n' "$C_GOLD" $((i + 1)) "$C_RESET" "$C_OK" "$S_OK" "$C_RESET" "$lbl" >/dev/tty
      else printf '   %s%2d%s  %s○  %s%s\n' "$C_GOLD" $((i + 1)) "$C_RESET" "$C_GRAY" "$lbl" "$C_RESET" >/dev/tty; fi
    done
    printf '\n  %sa%s=همه  %sn%s=هیچ  %sEnter%s=شروع  %s0%s=بازگشت\n  %s ' "$C_GOLD" "$C_RESET" "$C_GOLD" "$C_RESET" "$C_GOLD" "$C_RESET" "$C_GOLD" "$C_RESET" "$S_ARROW" >/dev/tty
    read -r ans </dev/tty || return 1
    case "$ans" in
      "") break ;;
      0) return 1 ;;
      a|A) for ((i = 0; i < n; i++)); do sel[$i]=1; done ;;
      n|N) for ((i = 0; i < n; i++)); do sel[$i]=0; done ;;
      *) for m in $ans; do
           if [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -ge 1 ] && [ "$m" -le "$n" ]; then
             if [ "${sel[$((m - 1))]}" = 1 ]; then sel[$((m - 1))]=0; else sel[$((m - 1))]=1; fi
           fi
         done ;;
    esac
  done
  for ((i = 0; i < n; i++)); do
    [ "${sel[$i]}" = 1 ] || continue
    m=${MOD_LABELS[$i]%%|*}; out+="${out:+,}$m"
    [ "$m" = "docker" ] && DO_DOCKER=true
  done
  [ -z "$out" ] && return 1
  ONLY_LIST="$out"
  return 0
}

show_menu() { # خروجی: تنظیم ONLY_LIST / DO_* ؛ بازگشت 1 یعنی خروج
  local ch
  while :; do
    banner
    printf '\n  %sچه کاری انجام شود؟%s\n\n' "$C_BOLD" "$C_RESET"
    printf '   %s1%s  %sبهینه‌سازی کامل و هوشمند%s  %s(پیشنهادی)%s\n' "$C_GOLD" "$C_RESET" "$C_OK" "$C_RESET" "$C_GRAY" "$C_RESET"
    printf '   %s2%s  انتخاب دستی مرحله‌ها\n' "$C_GOLD" "$C_RESET"
    printf '   %s3%s  فقط نصب Docker + میرور رجیستری\n' "$C_GOLD" "$C_RESET"
    printf '   %s4%s  فقط DNS\n' "$C_GOLD" "$C_RESET"
    printf '   %s5%s  فقط مخزن/میرور بسته‌ها\n' "$C_GOLD" "$C_RESET"
    printf '   %s6%s  گزارش وضعیت سرور %s(فقط خواندنی)%s\n' "$C_GOLD" "$C_RESET" "$C_GRAY" "$C_RESET"
    printf '   %s7%s  بازگردانی تنظیمات اولیه\n' "$C_GOLD" "$C_RESET"
    printf '   %s0%s  خروج\n\n  %s ' "$C_GOLD" "$C_RESET" "$S_ARROW"
    read -r ch </dev/tty || return 1
    case "$ch" in
      1|"") BANNER_SHOWN=false; return 0 ;;
      2) menu_checklist && { BANNER_SHOWN=false; return 0; } ;;
      3) ONLY_LIST="docker"; DO_DOCKER=true; BANNER_SHOWN=false; return 0 ;;
      4) ONLY_LIST="dns"; BANNER_SHOWN=false; return 0 ;;
      5) ONLY_LIST="repo"; BANNER_SHOWN=false; return 0 ;;
      6) DO_STATUS=true; BANNER_SHOWN=false; return 0 ;;
      7) DO_RESTORE=true; BANNER_SHOWN=false; return 0 ;;
      0|q|Q) return 1 ;;
    esac
  done
}

# =============================================================================
#  گزارش وضعیت سرور (فقط خواندنی)
# =============================================================================
show_status() {
  local v k val
  printf '\n%s%s%s\n %s%s%s  %sگزارش وضعیت سرور%s\n%s%s%s\n\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET" "$C_GOLD" "$S_STEP" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"
  kv "$C_ACC$S_INFO$C_RESET" "سیستم‌عامل" "$OS_PRETTY"
  kv "$C_ACC$S_INFO$C_RESET" "کرنل / معماری" "$(uname -r) · $(uname -m)"
  v=$(systemd-detect-virt 2>/dev/null); kv "$C_ACC$S_INFO$C_RESET" "مجازی‌سازی" "${v:-نامشخص}"
  kv "$C_ACC$S_INFO$C_RESET" "پردازنده / رم" "$(nproc 2>/dev/null || echo ?) هسته · $(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)MB · سوآپ $(awk '/^SwapTotal:/{printf "%d", $2/1024}' /proc/meminfo)MB"
  kv "$C_ACC$S_INFO$C_RESET" "دیسک /" "$(df -Ph / 2>/dev/null | awk 'NR==2{print $3" از "$2" ("$5")"}')"
  kv "$C_ACC$S_INFO$C_RESET" "آپ‌تایم" "$(uptime -p 2>/dev/null | sed 's/^up //')"
  blank
  val=$(grep -E '^nameserver' "$RESOLV_CONF" 2>/dev/null | awk '{printf "%s ", $2}')
  kv "$C_ACC$S_INFO$C_RESET" "DNS فعلی" "${val:-نامشخص}"
  if [ "$PKG_MGR" = apt ]; then
    val=$(grep -rhoE '^(deb|URIs:)[^#]*' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -oE 'https?://[^/ ]+' | sort -u | sed 's#https\?://##' | head -n 4 | tr '\n' ' ')
    kv "$C_ACC$S_INFO$C_RESET" "میزبان‌های مخزن" "${val:-نامشخص}"
    val=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ')
    kv "$C_ACC$S_INFO$C_RESET" "بسته‌های قابل آپدیت" "${val:-?}"
  fi
  kv "$C_ACC$S_INFO$C_RESET" "BBR / صف" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) · $(sysctl -n net.core.default_qdisc 2>/dev/null)"
  kv "$C_ACC$S_INFO$C_RESET" "منطقه‌زمانی" "$(timedatectl show -p Timezone --value 2>/dev/null) · NTP: $(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
  [ -f /var/run/reboot-required ] && kv "$C_WARN$S_WARN$C_RESET" "ریبوت" "${C_WARN}لازم است${C_RESET}"
  blank
  if command -v docker >/dev/null 2>&1; then
    kv "$C_OK$S_OK$C_RESET" "Docker" "$(docker --version 2>/dev/null | sed -E 's/Docker version ([^,]+),.*/\1/') · $(docker compose version --short 2>/dev/null | sed 's/^/compose /')"
    val=$(docker info 2>/dev/null | sed -n '/Registry Mirrors:/,/^ [A-Z]/p' | grep -oE 'https?://[^ ]+' | tr '\n' ' ')
    kv "$C_ACC$S_INFO$C_RESET" "میرور رجیستری" "${val:-تنظیم نشده}"
    val=$(docker ps -q 2>/dev/null | wc -l); kv "$C_ACC$S_INFO$C_RESET" "کانتینر فعال" "${val}"
  else kv "$C_GRAY–$C_RESET" "Docker" "${C_GRAY}نصب نیست${C_RESET}"; fi
  local sshd; sshd=$(command -v sshd || echo /usr/sbin/sshd)
  if [ -x "$sshd" ]; then
    val=$("$sshd" -T 2>/dev/null)
    kv "$C_ACC$S_INFO$C_RESET" "SSH" "پورت $(echo "$val" | awk '$1=="port"{printf "%s ", $2}')· root: $(echo "$val" | awk '$1=="permitrootlogin"{print $2}') · رمز: $(echo "$val" | awk '$1=="passwordauthentication"{print $2}')"
  fi
  if command -v ufw >/dev/null 2>&1; then kv "$C_ACC$S_INFO$C_RESET" "فایروال ufw" "$(ufw status 2>/dev/null | head -n1 | sed 's/^Status: //;s/^وضعیت: //')"
  elif command -v firewall-cmd >/dev/null 2>&1; then kv "$C_ACC$S_INFO$C_RESET" "فایروال firewalld" "$(firewall-cmd --state 2>/dev/null || echo غیرفعال)"
  else kv "$C_GRAY–$C_RESET" "فایروال" "${C_GRAY}نصب/شناسایی نشد${C_RESET}"; fi
  if systemctl is-active fail2ban >/dev/null 2>&1; then kv "$C_OK$S_OK$C_RESET" "Fail2ban" "فعال"; else kv "$C_GRAY–$C_RESET" "Fail2ban" "${C_GRAY}غیرفعال/نصب نیست${C_RESET}"; fi
  blank
}

# =============================================================================
#  ابزارهای کاربردی
# =============================================================================
pkg_installed() {
  case "$PKG_MGR" in
    apt) dpkg -s "$1" >/dev/null 2>&1 ;;
    dnf|yum|zypper) rpm -q "$1" >/dev/null 2>&1 ;;
    apk) apk info -e "$1" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$1" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}
pkg_has_candidate() { # فقط برای apt
  apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/{ if ($2 != "(none)") f=1 } END{ exit !f }'
}
tools_install_run() {
  case "$PKG_MGR" in
    apt)
      apt_lists_empty && apt_run 120 update -qq >/dev/null 2>&1
      apt_run 900 install -y -qq -o DPkg::Lock::Timeout=60 "$@" ;;
    dnf)    timeout 900 dnf install -y "$@" ;;
    yum)    timeout 900 yum install -y "$@" ;;
    zypper) timeout 900 zypper --non-interactive install "$@" ;;
    apk)    timeout 600 apk add --no-cache "$@" ;;
    pacman) timeout 900 pacman -S --noconfirm --needed "$@" ;;
  esac
}
install_essentials() {
  local want=() missing=() p cnt=0
  case "$PKG_MGR" in
    apt)       want=(curl wget ca-certificates gnupg git nano unzip zip jq rsync lsof tmux htop ncdu net-tools bash-completion mtr-tiny) ;;
    dnf|yum)   want=(curl wget ca-certificates gnupg2 git nano unzip zip jq rsync lsof tmux htop ncdu net-tools bash-completion mtr) ;;
    zypper|apk|pacman) want=(curl wget ca-certificates git nano unzip zip jq rsync lsof tmux htop ncdu bash-completion) ;;
    *) warn "مدیر بسته‌ی «${PKG_MGR}» پشتیبانی نمی‌شود."; set_st TOOLS skip "پشتیبانی نمی‌شود"; return ;;
  esac
  for p in "${want[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  if [ "$PKG_MGR" = apt ] && [ ${#missing[@]} -gt 0 ]; then
    apt_lists_empty && [ "$DRY_RUN" != true ] && apt_run 120 update -qq >/dev/null 2>&1
    local avail=(); for p in "${missing[@]}"; do pkg_has_candidate "$p" && avail+=("$p"); done
    missing=("${avail[@]}")
  fi
  if [ ${#missing[@]} -eq 0 ]; then ok "همه‌ی ابزارهای کاربردی از قبل نصب‌اند."; set_st TOOLS ok "از قبل کامل بود"; return; fi
  note "برای نصب: ${missing[*]}"
  if [ "$DRY_RUN" = true ]; then set_st TOOLS skip "dry-run: ${#missing[@]} بسته"; return; fi
  if run_spin "نصب ${#missing[@]} ابزار کاربردی" tools_install_run "${missing[@]}"; then
    set_st TOOLS ok "${#missing[@]} بسته نصب شد"
  else
    # یکی‌یکی؛ نبودِ یک بسته نباید بقیه را خراب کند
    for p in "${missing[@]}"; do tools_install_run "$p" >/dev/null 2>&1 && cnt=$((cnt + 1)); done
    if [ "$cnt" -gt 0 ]; then warn "${cnt} از ${#missing[@]} بسته نصب شد."; set_st TOOLS warn "${cnt}/${#missing[@]} بسته"
    else warn "نصب ابزارها ممکن نشد (مخزن در دسترس نیست؟)."; set_st TOOLS warn "نصب نشد"; fi
  fi
}

# =============================================================================
#  منابع سیستم: hosts، سوآپ، limits، journald، TRIM
# =============================================================================
make_swapfile() { # size_mb
  local mb="$1"
  fallocate -l "${mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none || return 1
  chmod 600 /swapfile && mkswap -q /swapfile >/dev/null && swapon /swapfile
}
sys_hosts() {
  local h; h=$(hostname 2>/dev/null); [ -z "$h" ] && return 1
  getent hosts "$h" >/dev/null 2>&1 && return 1
  grep -qsw -- "$h" /etc/hosts && return 1
  if [ "$DRY_RUN" = true ]; then note "(dry-run) نام میزبان «$h» به /etc/hosts اضافه می‌شد."; return 1; fi
  bk_save /etc/hosts hosts
  printf '127.0.1.1 %s\n' "$h" >> /etc/hosts
  ok "نام میزبان «${h}» به /etc/hosts اضافه شد  ${C_GRAY}(رفع خطای sudo: unable to resolve host)${C_RESET}"
}
sys_swap() {
  local swap_kb mem_mb fs free_mb size_mb=2048
  swap_kb=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
  if [ "${swap_kb:-0}" -gt 0 ]; then note "سوآپ از قبل فعال است ($((swap_kb / 1024))MB)."; return 1; fi
  if is_container; then note "کانتینر: ساخت سوآپ رد شد."; return 1; fi
  mem_mb=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)
  if [ "$mem_mb" -ge 16384 ]; then note "رم بالاست؛ سوآپ لازم نیست."; return 1; fi
  fs=$(stat -f -c %T / 2>/dev/null)
  case "$fs" in btrfs|zfs|tmpfs|overlay*|nfs*) note "فایل‌سیستم ${fs} برای swapfile مناسب نیست؛ رد شد."; return 1 ;; esac
  if [ -e /swapfile ]; then note "/swapfile وجود دارد؛ دست نخورد."; return 1; fi
  free_mb=$(df -Pm / 2>/dev/null | awk 'NR==2{print $4}')
  if [ "${free_mb:-0}" -lt $((size_mb + 3072)) ]; then warn "فضای دیسک برای سوآپ ${size_mb}MB کافی نیست."; return 1; fi
  if [ "$DRY_RUN" = true ]; then note "(dry-run) سوآپ ${size_mb}MB ساخته می‌شد."; return 1; fi
  bk_save /etc/fstab fstab
  if with_spinner "ساخت سوآپ ${size_mb}MB" make_swapfile "$size_mb"; then
    grep -qs '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    mkdir -p /etc/sysctl.d
    grep -qs 'vm.swappiness' /etc/sysctl.d/99-abrbaran-tuning.conf 2>/dev/null || echo 'vm.swappiness = 10' >> /etc/sysctl.d/99-abrbaran-tuning.conf
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    return 0
  fi
  swapoff /swapfile 2>/dev/null; rm -f /swapfile
  return 1
}
sys_limits() {
  local f1=/etc/security/limits.d/99-abrbaran.conf f2=/etc/systemd/system.conf.d/99-abrbaran.conf sv lim="1048576"
  [ -f "$f1" ] && { [ ! -d /etc/systemd ] || [ -f "$f2" ]; } && return 1
  if [ "$DRY_RUN" = true ]; then note "(dry-run) سقف فایل‌های باز (nofile) افزایش می‌یافت."; return 1; fi
  mkdir -p /etc/security/limits.d
  printf '# ABR BARAN IDC . IR — سقف فایل‌های باز\n* soft nofile 1048576\n* hard nofile 1048576\nroot soft nofile 1048576\nroot hard nofile 1048576\n' > "$f1"
  if has_systemd; then
    sv=$(systemctl --version 2>/dev/null | awk 'NR==1{print $2}')
    [ "${sv:-0}" -ge 240 ] 2>/dev/null && lim="65536:524288" || lim="65536"
    mkdir -p /etc/systemd/system.conf.d
    printf '# ABR BARAN IDC . IR\n[Manager]\nDefaultLimitNOFILE=%s\n' "$lim" > "$f2"
  fi
  ok "سقف فایل‌های باز (nofile) افزایش یافت  ${C_GRAY}(با لاگین/ریبوت بعدی کامل اعمال می‌شود)${C_RESET}"
}
sys_journal() {
  local f=/etc/systemd/journald.conf.d/99-abrbaran.conf
  has_systemd || return 1
  [ -f "$f" ] && return 1
  if [ "$DRY_RUN" = true ]; then note "(dry-run) سقف حجم لاگ journald روی 200MB تنظیم می‌شد."; return 1; fi
  mkdir -p /etc/systemd/journald.conf.d
  printf '# ABR BARAN IDC . IR\n[Journal]\nSystemMaxUse=200M\nRuntimeMaxUse=64M\nMaxRetentionSec=1month\n' > "$f"
  systemctl restart systemd-journald >/dev/null 2>&1
  journalctl --vacuum-size=200M >/dev/null 2>&1
  ok "حجم لاگ journald به ۲۰۰ مگابایت محدود شد."
}
sys_trim() {
  has_systemd || return 1; is_container && return 1
  systemctl list-unit-files fstrim.timer >/dev/null 2>&1 || return 1
  systemctl is-enabled fstrim.timer >/dev/null 2>&1 && return 1
  [ "$DRY_RUN" = true ] && return 1
  systemctl enable --now fstrim.timer >/dev/null 2>&1 && ok "TRIM هفتگی دیسک (fstrim.timer) فعال شد."
}
sys_motd() {
  [ -f /etc/default/motd-news ] && grep -q '^ENABLED=1' /etc/default/motd-news || return 1
  [ "$DRY_RUN" = true ] && return 1
  bk_save /etc/default/motd-news motd-news
  sed -i 's/^ENABLED=1/ENABLED=0/' /etc/default/motd-news && ok "تبلیغات خبری MOTD اوبونتو غیرفعال شد."
}
optimize_system_resources() {
  local n=0 f
  for f in sys_hosts sys_swap sys_limits sys_journal sys_trim sys_motd; do "$f" && n=$((n + 1)); done
  if [ "$DRY_RUN" = true ]; then set_st SYSTEM skip "dry-run"
  elif [ "$n" -gt 0 ]; then set_st SYSTEM ok "${n} مورد اعمال شد"
  else ok "منابع سیستم از قبل بهینه است."; set_st SYSTEM ok "از قبل بهینه بود"; fi
}

# =============================================================================
#  Docker: نصب از میرور + میرور رجیستری ایران
# =============================================================================
DOCKER_GPG_FPR="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
# نام|آدرس پایه (ساختار: <base>/linux/<ubuntu|debian|centos|fedora|rhel>/...)
DOCKER_CE_BASES=(
  "ArvanCloud|https://mirror.arvancloud.ir/docker-ce"
  "IranServer|https://mirror.iranserver.com/docker-ce"
  "Aliyun|https://mirrors.aliyun.com/docker-ce"
  "Tencent|https://mirrors.cloud.tencent.com/docker-ce"
  "Huawei|https://repo.huaweicloud.com/docker-ce"
  "Tsinghua|https://mirrors.tuna.tsinghua.edu.cn/docker-ce"
  "USTC|https://mirrors.ustc.edu.cn/docker-ce"
  "NJU|https://mirrors.nju.edu.cn/docker-ce"
  "SJTU|https://mirror.sjtu.edu.cn/docker-ce"
  "Azure-CN|https://mirror.azure.cn/docker-ce"
  "Official|https://download.docker.com"
)
# رجیستری‌های میرور Docker Hub (هرکدام که زنده نباشد خودکار حذف می‌شود)
DOCKER_REGISTRIES=(
  "ArvanCloud|https://docker.arvancloud.ir"
  "IranServer|https://docker.iranserver.com"
  "HaioCloud|https://docker.haiocloud.com"
  "Docker.ir|https://registry.docker.ir"
  "HamDocker|https://hub.hamdocker.ir"
  "Focker|https://focker.ir"
  "Mobinhost|https://docker.mobinhost.com"
  "Pardisco|https://docker.pardisco.co"
  "Google|https://mirror.gcr.io"
  "DaoCloud|https://docker.m.daocloud.io"
  "Tencent|https://mirror.ccs.tencentyun.com"
  "1ms.run|https://docker.1ms.run"
)
DOCKER_FLAVOR=""; DOCKER_CODENAMES=(); DOCKER_RPMVER=""

docker_flavor() {
  case "$PKG_MGR" in
    apt) [ "$MIRROR_FAMILY" = "debian" ] && echo debian || echo ubuntu ;;
    dnf|yum) case "$OS_ID" in fedora) echo fedora ;; rhel) echo rhel ;; *) echo centos ;; esac ;;
  esac
}

docker_probe_item() { # "name|base" → OK|ms|name|base|code  یا  FAIL|name|base|دلیل
  local name base c r code ms found="" vers v
  IFS='|' read -r name base <<<"$1"
  if [ "$PKG_MGR" = apt ]; then
    for c in "${DOCKER_CODENAMES[@]}"; do
      r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --connect-timeout 4 --max-time 8 "$base/linux/$DOCKER_FLAVOR/dists/$c/Release" 2>/dev/null)
      code=${r%% *}
      [ "$code" = 000 ] && break
      [ "$code" = 200 ] && { found=$c; break; }
    done
  else
    vers="$DOCKER_RPMVER 9"
    for v in $vers; do
      r=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --connect-timeout 4 --max-time 8 "$base/linux/$DOCKER_FLAVOR/$v/$ARCH_RPM/stable/repodata/repomd.xml" 2>/dev/null)
      code=${r%% *}
      [ "$code" = 000 ] && break
      [ "$code" = 200 ] && { found=$v; break; }
    done
  fi
  if [ -z "$found" ]; then echo "FAIL|$name|$base|HTTP ${code:-000}"; return; fi
  ms=$(awk -v t="${r##* }" 'BEGIN{printf "%d", t*1000}')
  echo "OK|$ms|$name|$base|$found"
}

docker_speed_probe() { # base code → KB/s
  local url
  [ "$PKG_MGR" = apt ] || { echo 0; return; }
  url="$1/linux/$DOCKER_FLAVOR/dists/$2/stable/binary-$ARCH_DEB/Packages.gz"
  curl -s -r 0-1048575 -o /dev/null -w '%{speed_download}' --connect-timeout 4 --max-time 12 "$url" 2>/dev/null | awk '{printf "%d", $1/1024}'
}

docker_install_apt() { # base code
  local base="$1" code="$2" key=/etc/apt/keyrings/docker.asc lst=/etc/apt/sources.list.d/docker.list fpr
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL --connect-timeout 5 --max-time 40 "$base/linux/$DOCKER_FLAVOR/gpg" -o "$key" || { echo "دریافت کلید GPG ناموفق"; return 11; }
  if command -v gpg >/dev/null 2>&1; then
    fpr=$(gpg --show-keys --with-colons "$key" 2>/dev/null | awk -F: '$1=="fpr"{print $10}')
    echo "$fpr" | grep -q "$DOCKER_GPG_FPR" || { echo "اثر انگشت کلید GPG با کلید رسمی Docker نمی‌خواند"; rm -f "$key"; return 12; }
  fi
  chmod a+r "$key"
  echo "deb [arch=$ARCH_DEB signed-by=$key] $base/linux/$DOCKER_FLAVOR $code stable" > "$lst"
  apt_run 150 update -qq -o Dir::Etc::sourcelist="sources.list.d/docker.list" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" || { echo "apt update مخزن Docker ناموفق"; return 13; }
  apt_run 1200 install -y -o DPkg::Lock::Timeout=60 docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 14
}
docker_install_rpm() { # base ver
  local base="$1" ver="$2"
  cat > /etc/yum.repos.d/docker-ce.repo <<EOF
[docker-ce-stable]
name=Docker CE Stable (ABR BARAN)
baseurl=$base/linux/$DOCKER_FLAVOR/$ver/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=$base/linux/$DOCKER_FLAVOR/gpg
EOF
  timeout 1200 "$PKG_MGR" install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}
docker_install_distro() { # نصب از بسته‌های خودِ توزیع (آخرین راه)
  case "$PKG_MGR" in
    apt)
      apt_lists_empty && apt_run 120 update -qq >/dev/null 2>&1
      apt_run 1200 install -y -o DPkg::Lock::Timeout=60 docker.io || return 1
      apt_run 300 install -y docker-compose-v2 >/dev/null 2>&1 || apt_run 300 install -y docker-compose-plugin >/dev/null 2>&1 || apt_run 300 install -y docker-compose >/dev/null 2>&1
      return 0 ;;
    dnf|yum) [ "$OS_ID" = fedora ] && timeout 1200 "$PKG_MGR" install -y moby-engine docker-compose || { echo "این توزیع بسته‌ی docker در مخزن خودش ندارد (podman را بررسی کنید)"; return 1; } ;;
    zypper)  timeout 1200 zypper --non-interactive install docker docker-compose ;;
    apk)     timeout 900 apk add --no-cache docker docker-cli-compose ;;
    pacman)  timeout 1200 pacman -S --noconfirm --needed docker docker-compose ;;
    *) return 1 ;;
  esac
}
docker_enable_service() {
  if has_systemd; then systemctl enable --now docker >/dev/null 2>&1 || systemctl restart docker >/dev/null 2>&1
  elif command -v rc-update >/dev/null 2>&1; then rc-update add docker boot >/dev/null 2>&1; service docker start >/dev/null 2>&1
  else service docker start >/dev/null 2>&1; fi
  local i; for i in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && return 0; sleep 2; done
  return 1
}

docker_do_install() { # 0=نصب شد
  local codename lines ranked="" n=0 name base code ms sp ok_n tried=0 rc line okl
  DOCKER_FLAVOR=$(docker_flavor)
  codename=$(get_apt_codename)
  if [ "$PKG_MGR" = apt ]; then
    if [ -n "$MIRROR_FAMILY" ] && [ -n "$codename" ] && [ -n "$ARCH_DEB" ]; then
      if [ "$DOCKER_FLAVOR" = ubuntu ]; then DOCKER_CODENAMES=("$codename" noble jammy); else DOCKER_CODENAMES=("$codename" trixie bookworm); fi
    fi
  elif [ "$PKG_MGR" = dnf ] || [ "$PKG_MGR" = yum ]; then
    if [ "$DOCKER_FLAVOR" = fedora ]; then DOCKER_RPMVER="$OS_VERSION"; else DOCKER_RPMVER="${OS_VERSION%%.*}"; fi
  fi

  local use_repo=false
  { [ "$PKG_MGR" = apt ] && [ ${#DOCKER_CODENAMES[@]} -gt 0 ]; } && use_repo=true
  { [ "$PKG_MGR" = dnf ] || [ "$PKG_MGR" = yum ]; } && [ -n "$DOCKER_RPMVER" ] && use_repo=true
  [ "$HAS_CURL" != true ] && use_repo=false

  if [ "$use_repo" = true ]; then
    info "تست موازیِ ${#DOCKER_CE_BASES[@]} میرور مخزن Docker (مسیر ${DOCKER_FLAVOR}) ..."
    par_run "تست میرور Docker ..." 12 "$TMPD/dk" docker_probe_item "${DOCKER_CE_BASES[@]}"
    lines=$(par_collect "$TMPD/dk" | grep '^OK|' | LC_ALL=C sort -t'|' -k2,2n)
    if [ -n "$lines" ]; then
      # سنجش سرعت واقعی ۳ میرور سریع‌تر
      while IFS='|' read -r _ ms name base code; do
        [ -z "$name" ] && continue
        n=$((n + 1)); [ "$n" -gt 3 ] && { ranked+="0|${ms}|${name}|${base}|${code}"$'\n'; continue; }
        progress_bar "$n" 3 "سنجش سرعت: $name"
        sp=$(docker_speed_probe "$base" "$code")
        ranked+="${sp}|${ms}|${name}|${base}|${code}"$'\n'
      done <<<"$lines"
      progress_clear
      ranked=$(printf '%s' "$ranked" | LC_ALL=C sort -t'|' -k1,1nr -k2,2n)
      printf '  %s%-4s %-12s %-10s %-11s%s\n' "$C_GRAY" "" "Mirror" "Latency" "Speed" "$C_RESET"
      local idx=0
      while IFS='|' read -r sp ms name base code; do
        [ -z "$name" ] && continue
        idx=$((idx + 1)); [ "$idx" -gt 6 ] && break
        printf '  %s%-4s%s %-12s %4d ms    %s\n' "$C_GOLD" "$([ "$idx" = 1 ] && echo "$S_STAR")" "$C_RESET" "$name" "$ms" \
          "$([ "$sp" -gt 0 ] 2>/dev/null && awk -v s="$sp" 'BEGIN{ if (s>=1024) printf "%.1f MB/s", s/1024; else printf "%d KB/s", s }' || echo '—')"
      done <<<"$ranked"
      if [ "$DRY_RUN" = true ]; then
        DOCKER_DRY_PICK=$(echo "$ranked" | sed -n 1p | cut -d'|' -f3); note "(dry-run) Docker از «${DOCKER_DRY_PICK}» نصب می‌شد."; return 1
      fi
      while IFS='|' read -r sp ms name base code; do
        [ -z "$name" ] && continue
        tried=$((tried + 1)); [ "$tried" -gt 3 ] && break
        if [ "$PKG_MGR" = apt ]; then run_spin "نصب Docker از «${name}»" docker_install_apt "$base" "$code"; rc=$?
        else run_spin "نصب Docker از «${name}»" docker_install_rpm "$base" "$code"; rc=$?; fi
        if [ "$rc" -eq 0 ] && command -v docker >/dev/null 2>&1; then
          DOCKER_SRC="$name"; docker_enable_service && return 0
          warn "Docker نصب شد ولی سرویس بالا نیامد."; return 0
        fi
        warn "نصب از «${name}» ناموفق بود؛ ${C_GRAY}$(grep -v '^$' "$SPIN_OUT" 2>/dev/null | tail -n1 | cut -c1-90)${C_RESET}"
        rm -f /etc/apt/sources.list.d/docker.list /etc/yum.repos.d/docker-ce.repo
      done <<<"$ranked"
    else
      warn "هیچ میرور مخزن Docker (حتی رسمی) از این سرور در دسترس نیست."
    fi
  fi
  [ "$DRY_RUN" = true ] && return 1
  info "تلاش با بسته‌ی خودِ توزیع (از مخزن سیستم) ..."
  if run_spin "نصب Docker از مخزن ${OS_ID}" docker_install_distro && command -v docker >/dev/null 2>&1; then
    DOCKER_SRC="مخزن ${OS_ID}"; docker_enable_service; return 0
  fi
  return 1
}

docker_registry_probe_item() { # "name|url" → OK|score|name|url|full  یا FAIL|name|url|دلیل
  local name url r code m mcode ms full=0 score
  IFS='|' read -r name url <<<"$1"
  r=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 4 --max-time 8 "$url/v2/" 2>/dev/null)
  case "$r" in 200|401) ;; *) echo "FAIL|$name|$url|HTTP ${r:-000}"; return ;; esac
  m=$(curl -s -o /dev/null -w '%{http_code} %{time_total}' --connect-timeout 4 --max-time 12 \
      -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
      "$url/v2/library/hello-world/manifests/latest" 2>/dev/null)
  mcode=${m%% *}
  case "$mcode" in 200) full=1 ;; 401) full=0 ;; *) echo "FAIL|$name|$url|manifest HTTP ${mcode:-000}"; return ;; esac
  ms=$(awk -v t="${m##* }" 'BEGIN{printf "%d", t*1000}')
  score=$ms; [ "$full" = 0 ] && score=$((ms + 3000))
  echo "OK|$score|$name|$url|$full|$ms"
}

DOCKER_DAEMON_JSON="${DOCKER_DAEMON_JSON:-/etc/docker/daemon.json}"
docker_write_daemon_json() { # urls...
  local f="$DOCKER_DAEMON_JSON"
  mkdir -p "$(dirname "$f")"
  [ -f "$f" ] && bk_save "$f" docker/daemon.json
  if command -v python3 >/dev/null 2>&1; then
    python3 -I - "$f" "$@" 2>/dev/null <<'PY'
import json, os, sys
p, mirrors = sys.argv[1], sys.argv[2:]
d = {}
if os.path.exists(p) and os.path.getsize(p) > 0:
    with open(p) as fh:
        d = json.load(fh)
d["registry-mirrors"] = mirrors
d.setdefault("log-driver", "json-file")
lo = d.setdefault("log-opts", {})
lo.setdefault("max-size", "10m")
lo.setdefault("max-file", "3")
tmp = p + ".abrbaran.tmp"
with open(tmp, "w") as fh:
    json.dump(d, fh, indent=2)
    fh.write("\n")
os.replace(tmp, p)
PY
  elif command -v jq >/dev/null 2>&1 && { [ ! -s "$f" ] || jq -e . "$f" >/dev/null 2>&1; }; then
    local cur='{}'; [ -s "$f" ] && cur=$(cat "$f")
    printf '%s' "$cur" | jq --argjson m "$(printf '%s\n' "$@" | jq -R . | jq -s .)" \
      '. + {"registry-mirrors": $m} | .["log-driver"] //= "json-file" | .["log-opts"] = ({"max-size":"10m","max-file":"3"} + (.["log-opts"] // {}))' > "$f.abrbaran.tmp" \
      && mv "$f.abrbaran.tmp" "$f"
  elif [ ! -s "$f" ]; then
    local list="" u; for u in "$@"; do list+="${list:+, }\"$u\""; done
    printf '{\n  "registry-mirrors": [%s],\n  "log-driver": "json-file",\n  "log-opts": {"max-size": "10m", "max-file": "3"}\n}\n' "$list" > "$f"
  else
    return 2
  fi
}

docker_setup_registry_mirrors() {
  local lines top n=0 name url full ms score picks=() names=() before rc
  [ "$HAS_CURL" = true ] || { warn "بدون curl امکان تست رجیستری‌ها نیست."; set_st DOCKER warn "نصب شد؛ میرور رجیستری بررسی نشد"; return; }
  info "تست موازیِ ${#DOCKER_REGISTRIES[@]} میرور رجیستری Docker Hub ..."
  par_run "تست رجیستری‌ها ..." 12 "$TMPD/dr" docker_registry_probe_item "${DOCKER_REGISTRIES[@]}"
  lines=$(par_collect "$TMPD/dr")
  top=$(echo "$lines" | grep '^OK|' | LC_ALL=C sort -t'|' -k2,2n)
  if [ -z "$top" ]; then
    warn "هیچ میرور رجیستری در دسترس نبود؛ تنظیمات Docker دست‌نخورده ماند."
    note "می‌توانید بعداً با «--only docker» دوباره امتحان کنید."
    set_st DOCKER warn "میرور رجیستری در دسترس نبود"; return
  fi
  printf '  %s%-4s %-12s %-10s %-9s%s\n' "$C_GRAY" "" "Registry" "Latency" "Pull API" "$C_RESET"
  while IFS='|' read -r _ score name url full ms; do
    [ -z "$name" ] && continue
    n=$((n + 1))
    [ "$n" -le 8 ] && printf '  %s%-4s%s %-12s %4d ms    %s\n' "$C_GOLD" "$([ "$n" -le 3 ] && echo "$S_STAR")" "$C_RESET" "$name" "$ms" "$([ "$full" = 1 ] && echo 'OK' || echo 'auth')"
    if [ ${#picks[@]} -lt 3 ]; then picks+=("$url"); names+=("$name"); fi
  done <<<"$top"
  local fails; fails=$(echo "$lines" | grep '^FAIL|' | awk -F'|' '{printf "%s%s", (NR>1?", ":""), $2}')
  [ -n "$fails" ] && note "ناسالم/بدون پاسخ: $fails"
  if [ "$DRY_RUN" = true ]; then note "(dry-run) میرورها تنظیم می‌شد: ${names[*]}"; set_st DOCKER skip "dry-run"; return; fi

  docker_write_daemon_json "${picks[@]}"; rc=$?
  if [ "$rc" -ne 0 ]; then
    warn "daemon.json فعلی قابل ادغام نبود (فرمت نامعتبر یا python3/jq موجود نیست)؛ دست نخورد."
    set_st DOCKER warn "daemon.json ادغام نشد"; return
  fi
  if has_systemd; then systemctl restart docker >/dev/null 2>&1; else service docker restart >/dev/null 2>&1; fi
  local i okd=false; for i in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && { okd=true; break; }; sleep 2; done
  if [ "$okd" != true ]; then
    warn "Docker پس از تنظیم جدید بالا نیامد؛ فایل قبلی بازگردانده شد."
    if [ -f "$BK/docker/daemon.json" ]; then cp -a "$BK/docker/daemon.json" /etc/docker/daemon.json; else rm -f /etc/docker/daemon.json; fi
    if has_systemd; then systemctl restart docker >/dev/null 2>&1; else service docker restart >/dev/null 2>&1; fi
    set_st DOCKER err "تنظیم میرور ناموفق (بازگردانی شد)"; return
  fi
  ok "میرور رجیستری تنظیم شد: ${C_BOLD}${names[*]}${C_RESET}  ${C_GRAY}(/etc/docker/daemon.json)${C_RESET}"
  # تایید واقعی با یک pull کوچک
  before=$(docker images -q hello-world 2>/dev/null)
  if run_spin "تایید واقعی: docker pull hello-world" timeout 100 docker pull -q hello-world; then
    [ -z "$before" ] && docker rmi hello-world >/dev/null 2>&1
    set_st DOCKER ok "${DOCKER_SRC:+نصب از ${DOCKER_SRC} · }میرور ${names[0]}"
  else
    warn "pull آزمایشی ناموفق بود؛ شاید میرور موقتاً کند است. دوباره امتحان: ${C_BOLD}docker pull hello-world${C_RESET}"
    set_st DOCKER warn "نصب/تنظیم شد؛ pull آزمایشی ناموفق"
  fi
}

setup_docker() {
  DOCKER_SRC=""
  local ver freshly=false
  if command -v docker >/dev/null 2>&1; then
    ver=$(docker --version 2>/dev/null | sed -E 's/Docker version ([^,]+),.*/\1/')
    ok "Docker از قبل نصب است ${C_GRAY}(نسخه ${ver})${C_RESET}"
    if ! docker info >/dev/null 2>&1; then
      [ "$DRY_RUN" != true ] && has_systemd && systemctl start docker >/dev/null 2>&1
      docker info >/dev/null 2>&1 || { warn "سرویس Docker فعال نیست؛ میرور رجیستری تنظیم نشد."; set_st DOCKER warn "سرویس Docker فعال نیست"; return; }
    fi
    if ! confirm "میرور رجیستری Docker (ایران/جهان) تست و تنظیم شود؟" "" y; then info "رد شد."; set_st DOCKER skip "رد شد"; return; fi
  else
    note "Docker نصب نیست. docker.com از ایران معمولاً مسدود است؛ اسکریپت از میرورهای سالم نصب می‌کند و کلید GPG را راستی‌آزمایی می‌کند."
    if ! confirm "Docker Engine + Compose نصب شود؟" "$([ "$DO_DOCKER" = true ] && echo yes)" n; then
      info "رد شد. (برای نصب خودکار: --docker)"; set_st DOCKER skip "رد شد"; return
    fi
    if ! docker_do_install; then
      if [ "$DRY_RUN" = true ]; then set_st DOCKER skip "dry-run: نصب از ${DOCKER_DRY_PICK:-?}"; return; fi
      err "نصب Docker انجام نشد."; set_st DOCKER err "نصب نشد"; return
    fi
    freshly=true
    ver=$(docker --version 2>/dev/null | sed -E 's/Docker version ([^,]+),.*/\1/')
    ok "Docker نصب شد ${C_GRAY}(نسخه ${ver})${C_RESET}"
    command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && ok "Docker Compose: ${C_BOLD}$(docker compose version --short 2>/dev/null)${C_RESET}"
  fi
  docker_setup_registry_mirrors
  if [ "$freshly" = true ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    note "برای اجرای docker بدون sudo:  sudo usermod -aG docker $SUDO_USER   (دسترسی گروه docker معادل root است)"
  fi
}

# =============================================================================
#  امنیت: SSH امن‌تر (بدون ریسک قفل شدن)، فایروال UFW، Fail2ban
# =============================================================================
SSHD_BIN=""
ssh_find() { SSHD_BIN=$(command -v sshd 2>/dev/null); [ -z "$SSHD_BIN" ] && [ -x /usr/sbin/sshd ] && SSHD_BIN=/usr/sbin/sshd; [ -n "$SSHD_BIN" ]; }
ssh_ports() {
  local p=""
  ssh_find && p=$("$SSHD_BIN" -T 2>/dev/null | awk '$1=="port"{print $2}' | sort -un | tr '\n' ' ')
  [ -z "$p" ] && p=$(ss -tlnpH 2>/dev/null | awk '/sshd/{a=$4; sub(/.*:/,"",a); print a}' | sort -un | tr '\n' ' ')
  echo "${p:-22}"
}
ssh_tune_and_audit() {
  ssh_find || { note "sshd نصب نیست؛ رد شد."; set_st SSHT skip "sshd نصب نیست"; return; }
  local main=/etc/ssh/sshd_config conf=/etc/ssh/sshd_config.d/99-abrbaran.conf eff want kv key val cur lines="" total=0 changed=0 eff2 took=0
  if ! grep -qsE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' "$main"; then
    note "sshd_config از drop-in پشتیبانی نمی‌کند؛ برای ایمنی تغییری نمی‌دهم."; set_st SSHT skip "بدون drop-in"
  elif ! "$SSHD_BIN" -t >/dev/null 2>&1; then
    warn "پیکربندی فعلی sshd معتبر نیست؛ دست نخورد."; set_st SSHT warn "پیکربندی فعلی نامعتبر"
  else
    eff=$("$SSHD_BIN" -T 2>/dev/null)
    for kv in "ClientAliveInterval 60" "ClientAliveCountMax 3" "LoginGraceTime 30" "MaxAuthTries 4" "UseDNS no" "TCPKeepAlive yes"; do
      key=${kv%% *}; val=${kv#* }; key=$(echo "$key" | tr 'A-Z' 'a-z')
      echo "$eff" | awk -v k="$key" '$1==k{f=1} END{exit !f}' || continue
      cur=$(echo "$eff" | awk -v k="$key" '$1==k{print $2; exit}')
      [ "$cur" = "$val" ] && continue
      lines+="${kv}"$'\n'; total=$((total + 1))
    done
    if [ "$total" -eq 0 ]; then ok "پارامترهای SSH از قبل مناسب‌اند."; set_st SSHT ok "از قبل مناسب بود"
    elif [ "$DRY_RUN" = true ]; then note "(dry-run) تغییرات SSH: $(echo "$lines" | tr '\n' ';')"; set_st SSHT skip "dry-run"
    else
      printf '# ABR BARAN IDC . IR — تنظیمات امن و پایدار SSH\n%s' "$lines" > "$conf"
      if "$SSHD_BIN" -t >/dev/null 2>&1; then
        eff2=$("$SSHD_BIN" -T 2>/dev/null)
        while read -r key val; do
          [ -z "$key" ] && continue
          key=$(echo "$key" | tr 'A-Z' 'a-z')
          [ "$(echo "$eff2" | awk -v k="$key" '$1==k{print $2; exit}')" = "$val" ] && took=$((took + 1))
        done <<<"$lines"
        svc_reload ssh sshd || service ssh reload >/dev/null 2>&1 || service sshd reload >/dev/null 2>&1
        ok "SSH: ${took} از ${total} پارامتر اعمال شد  ${C_GRAY}(نشست‌های فعلی قطع نمی‌شوند)${C_RESET}"
        [ "$took" -lt "$total" ] && note "بعضی مقادیر را فایل دیگری در sshd_config.d (با اولویت بالاتر) تعیین کرده است."
        set_st SSHT ok "${took}/${total} پارامتر"
      else
        rm -f "$conf"; warn "تنظیم SSH معتبر نبود و برگردانده شد."; set_st SSHT warn "بازگردانی شد"
      fi
    fi
  fi
  # ممیزی: فقط گزارش می‌دهد و تغییر نمی‌دهد (تا مدیر سرور قفل نشود)
  local pr pw ports
  eff=$("$SSHD_BIN" -T 2>/dev/null); pr=$(echo "$eff" | awk '$1=="permitrootlogin"{print $2}'); pw=$(echo "$eff" | awk '$1=="passwordauthentication"{print $2}')
  ports=$(ssh_ports)
  if [ "$pw" = yes ] && { [ "$pr" = yes ] || [ "$pr" = without-password ]; }; then
    warn "ورود root با رمز فعال است؛ هدف اصلی حملات brute-force."
    note "توصیه: کلید SSH بسازید و بعد PasswordAuthentication no. اسکریپت عمداً خودش این را عوض نمی‌کند تا قفل نشوید."
  fi
  [ "$ports" = "22 " ] && note "SSH روی پورت پیش‌فرض ۲۲ است (تغییر پورت اختیاری است؛ Fail2ban/فایروال مهم‌ترند)."
}

listening_public_ports() { # tcp|udp
  local proto="$1" flag="-tlnH"; [ "$proto" = udp ] && flag="-ulnH"
  ss $flag 2>/dev/null | awk '{a=$4; if (a ~ /^(0\.0\.0\.0|\*|\[::\]):[0-9]+$/) {sub(/.*:/,"",a); print a}}' | sort -un
}
firewall_setup() {
  local sp tcp udp p plan_t="" plan_u="" t u
  if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    ok "firewalld فعال است؛ دست نخورد."; set_st FW ok "firewalld از قبل فعال"; return
  fi
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi '^Status: active'; then
    ok "ufw از قبل فعال است؛ دست نخورد."; set_st FW ok "ufw از قبل فعال"; return
  fi
  if [ "$PKG_MGR" != apt ] && ! command -v ufw >/dev/null 2>&1; then
    note "برای این توزیع نصب فایروال خودکار پشتیبانی نمی‌شود (firewalld را دستی فعال کنید)."; set_st FW skip "پشتیبانی نمی‌شود"; return
  fi
  sp=$(ssh_ports)
  plan_t="$sp"; for p in $(listening_public_ports tcp) 80 443; do case " $plan_t " in *" $p "*) ;; *) plan_t+=" $p" ;; esac; done
  for p in $(listening_public_ports udp); do case "$p" in 68|546|5353|323) continue ;; esac; plan_u+=" $p"; done
  note "پورت‌های SSH (با محدودیت نرخ): ${sp}"
  note "پورت‌های TCP که باز می‌مانند: $(echo "$plan_t" | tr -s ' ')"
  [ -n "$plan_u" ] && note "پورت‌های UDP که باز می‌مانند:${plan_u}"
  note "بقیه‌ی ورودی‌ها مسدود می‌شود؛ خروجی آزاد است."
  if ! confirm "فایروال UFW با این قوانین فعال شود؟" "$([ "$DO_FIREWALL" = true ] && echo yes)" n; then info "رد شد. (فعال‌سازی خودکار: --firewall)"; set_st FW skip "رد شد"; return; fi
  if [ "$DRY_RUN" = true ]; then set_st FW skip "dry-run"; return; fi
  if ! command -v ufw >/dev/null 2>&1; then run_spin "نصب ufw" tools_install_run ufw || { err "نصب ufw ممکن نشد."; set_st FW err "نصب ufw ناموفق"; return; }; fi
  ufw default deny incoming >/dev/null 2>&1; ufw default allow outgoing >/dev/null 2>&1
  for p in $sp; do ufw limit "${p}/tcp" >/dev/null 2>&1; done
  for t in $plan_t; do case " $sp " in *" $t "*) ;; *) ufw allow "${t}/tcp" >/dev/null 2>&1 ;; esac; done
  for u in $plan_u; do ufw allow "${u}/udp" >/dev/null 2>&1; done
  ufw --force enable >/dev/null 2>&1
  if ! ufw status 2>/dev/null | grep -qi '^Status: active'; then err "فعال‌سازی ufw ناموفق بود."; set_st FW err "فعال نشد"; return; fi
  ok "فایروال UFW فعال شد."
  if tty_usable && [ "$AUTO_YES" != true ]; then
    local ans=""
    printf '\n  %s%s%s اگر اتصال SSH شما سالم است %sEnter%s بزنید. در غیر این صورت ظرف ۴۵ ثانیه فایروال خودکار خاموش می‌شود ... ' "$C_WARN" "$S_WARN" "$C_RESET" "$C_BOLD" "$C_RESET" >/dev/tty
    if ! read -r -t 45 ans </dev/tty; then
      ufw --force disable >/dev/null 2>&1
      printf '\n' >/dev/tty; warn "تایید نشد؛ فایروال برای جلوگیری از قفل شدن غیرفعال شد."; set_st FW warn "تایید نشد؛ غیرفعال شد"; return
    fi
    printf '\n' >/dev/tty
  fi
  command -v docker >/dev/null 2>&1 && note "Docker قوانین iptables خودش را دارد و پورت‌های publish‌شده از ufw رد می‌شوند؛ برای خصوصی نگه داشتن از 127.0.0.1:پورت:پورت استفاده کنید."
  set_st FW ok "UFW فعال ($(echo "$plan_t" | wc -w) پورت TCP)"
}

fail2ban_setup() {
  local ports cip="" conf=/etc/fail2ban/jail.d/abrbaran.local backend="auto" ign
  if ! confirm "Fail2ban (مسدودسازی خودکار حملات brute-force به SSH) نصب و فعال شود؟" "$([ "$DO_FAIL2BAN" = true ] && echo yes)" n; then
    info "رد شد. (فعال‌سازی خودکار: --fail2ban)"; set_st F2B skip "رد شد"; return
  fi
  if [ "$DRY_RUN" = true ]; then note "(dry-run) fail2ban نصب می‌شد."; set_st F2B skip "dry-run"; return; fi
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    run_spin "نصب fail2ban" tools_install_run fail2ban || { err "نصب fail2ban ممکن نشد."; set_st F2B err "نصب ناموفق"; return; }
  fi
  [ "$PKG_MGR" = apt ] && pkg_installed python3-systemd || { [ "$PKG_MGR" = apt ] && pkg_install python3-systemd; }
  ports=$(ssh_ports | tr -s ' ' | sed 's/ *$//; s/ /,/g')
  cip=${SSH_CLIENT%% *}
  ign="127.0.0.1/8 ::1"; [ -n "$cip" ] && ign+=" $cip"
  { [ -f /var/log/auth.log ] || [ -f /var/log/secure ]; } || backend="systemd"
  mkdir -p /etc/fail2ban/jail.d
  printf '# ABR BARAN IDC . IR\n[DEFAULT]\nbantime = 1h\nfindtime = 10m\nmaxretry = 5\nignoreip = %s\n\n[sshd]\nenabled = true\nport = %s\nbackend = %s\n' "$ign" "${ports:-22}" "$backend" > "$conf"
  if has_systemd; then systemctl enable --now fail2ban >/dev/null 2>&1; systemctl restart fail2ban >/dev/null 2>&1; else service fail2ban restart >/dev/null 2>&1; fi
  sleep 3
  if fail2ban-client status sshd >/dev/null 2>&1; then
    ok "Fail2ban فعال شد  ${C_GRAY}(۵ تلاش ناموفق ⇒ ۱ ساعت مسدود · IP فعلی شما مستثنی است)${C_RESET}"; set_st F2B ok "فعال (jail: sshd)"
  else
    warn "Fail2ban نصب شد ولی jail «sshd» بالا نیامد؛ بررسی: journalctl -u fail2ban"; set_st F2B warn "jail بالا نیامد"
  fi
}

setup_security() {
  ssh_tune_and_audit
  blank
  firewall_setup
  blank
  fail2ban_setup
}


do_restore() {
  banner
  step_restore_header
  local src="$ORIG"
  [ -d "$src" ] || src="$(readlink -f "$BACKUP_ROOT/latest" 2>/dev/null)"
  if [ ! -d "${src:-/nonexistent}" ] && [ ! -e /etc/sysctl.d/99-abrbaran-tuning.conf ] && [ ! -e /etc/sysctl.d/99-abrbaran-bbr.conf ]; then
    warn "هیچ پشتیبانی از اجراهای قبلی پیدا نشد."; return 1
  fi
  info "منبع بازگردانی: ${src}"
  [ -d "$src/apt" ] && { restore_apt_from "$src"; ok "فایل‌های مخزن apt بازگردانده شد."; }
  [ -d "$src/yum.repos.d" ] && { rpm_restore_from "$src"; ok "فایل‌های مخزن RPM بازگردانده شد."; }
  dns_restore_from "$src"; ok "تنظیمات DNS بازگردانده شد."
  rm -f /etc/sysctl.d/99-abrbaran-bbr.conf /etc/sysctl.d/99-abrbaran-tuning.conf /etc/modules-load.d/abrbaran-bbr.conf
  if [ -f /etc/ssh/sshd_config.d/99-abrbaran.conf ]; then
    rm -f /etc/ssh/sshd_config.d/99-abrbaran.conf; svc_reload ssh sshd; ok "تنظیمات SSH اختصاصی حذف شد."
  fi
  rm -f /etc/security/limits.d/99-abrbaran.conf /etc/systemd/system.conf.d/99-abrbaran.conf /etc/systemd/journald.conf.d/99-abrbaran.conf
  rm -f /etc/fail2ban/jail.d/abrbaran.local
  if [ -d "$src/docker" ] || [ -f /etc/docker/daemon.json ]; then
    if [ -f "$src/docker/daemon.json" ]; then cp -a "$src/docker/daemon.json" /etc/docker/daemon.json; ok "daemon.json داکر بازگردانده شد."
    elif grep -qs 'registry-mirrors' /etc/docker/daemon.json 2>/dev/null; then rm -f /etc/docker/daemon.json; ok "daemon.json ساخته‌شده توسط اسکریپت حذف شد."; fi
    has_systemd && systemctl is-active docker >/dev/null 2>&1 && systemctl restart docker >/dev/null 2>&1
  fi
  [ -f "$src/hosts" ] && ! grep -qsxF "$(tail -n1 /etc/hosts)" "$src/hosts" && cp -a "$src/hosts" /etc/hosts
  sysctl --system >/dev/null 2>&1; ok "تنظیمات sysctl اختصاصی حذف شد (تا ریبوت بعدی مقادیر زنده‌ی کرنل ممکن است باقی بماند)."
  command -v apt-get >/dev/null 2>&1 && with_spinner "apt update" apt_run 120 update >/dev/null 2>&1
  blank; ok "بازگردانی کامل شد."
  note "نصب‌شده‌ها (بسته‌ها، Docker، swapfile، UFW) عمداً حذف نمی‌شوند؛ فقط تنظیمات اسکریپت برگشت."
}
step_restore_header() { printf '\n%s%s%s\n %s%s%s  بازگردانی تنظیمات اولیه\n%s%s%s\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET" "$C_GOLD" "$S_STEP" "$C_RESET" "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"; }

# =============================================================================
#  گزارش نهایی و ریبوت امن
# =============================================================================
print_summary() {
  local dur=$(( $(date +%s) - SCRIPT_START_EPOCH )) key label val kind text icon col
  printf '\n%s%s%s\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"
  printf ' %s%s%s  %sگزارش نهایی%s\n' "$C_GOLD" "$S_STEP" "$C_RESET" "$C_BOLD" "$C_RESET"
  printf '%s%s%s\n\n' "$C_GRAY" "$(rep "$HR_CH" 60)" "$C_RESET"
  kv "${C_OK}${S_OK}${C_RESET}" "سیستم‌عامل" "$OS_PRETTY  ${C_GRAY}(${PKG_MGR})${C_RESET}"
  for key in DNS:"DNS" REPO:"مخزن (Repository)" GITHUB:"دسترسی به GitHub" BBR:"BBR" TUNE:"تنظیمات کرنل/شبکه" TOOLS:"ابزارهای کاربردی" SYSTEM:"منابع سیستم" DOCKER:"Docker" SSHT:"SSH" FW:"فایروال" F2B:"Fail2ban" SPEED:"Speedtest" TIME:"منطقه‌زمانی و ساعت" UPDATE:"آپدیت/آپگرید"; do
    case "${key%%:*}" in
      DNS) mod_on dns || continue ;; REPO) mod_on repo || continue ;; GITHUB) mod_on github || continue ;;
      BBR) mod_on bbr || continue ;; TUNE) mod_on tune || continue ;; TOOLS) mod_on tools || continue ;;
      SYSTEM) mod_on system || continue ;; DOCKER) mod_on docker || continue ;;
      SSHT|FW|F2B) mod_on security || continue ;;
      SPEED) mod_on speedtest || continue ;; TIME) mod_on time || continue ;; UPDATE) mod_on update || continue ;;
    esac
    label=${key#*:}; val=$(get_st "${key%%:*}"); kind=${val%%|*}; text=${val#*|}
    case "$kind" in
      ok)   icon="${C_OK}${S_OK}${C_RESET}";   col="$C_OK" ;;
      warn) icon="${C_WARN}${S_WARN}${C_RESET}"; col="$C_WARN" ;;
      err)  icon="${C_ERR}${S_ERR}${C_RESET}";  col="$C_ERR" ;;
      *)    icon="${C_GRAY}–${C_RESET}";         col="$C_GRAY" ;;
    esac
    kv "$icon" "$label" "${col}${text}${C_RESET}"
  done
  kv "${C_ACC}${S_INFO}${C_RESET}" "مدت اجرا" "$((dur / 60)) دقیقه و $((dur % 60)) ثانیه"
  blank
  note "لاگ کامل:      $LOGFILE"
  [ -d "$BK" ] && [ -n "$(ls -A "$BK" 2>/dev/null)" ] && note "پشتیبان‌ها:     $BK"
  [ -n "$NETWORK_REPORT_FILE" ] && note "گزارش فنی NOC: $NETWORK_REPORT_FILE"
  [ "$DRY_RUN" != true ] && note "بازگردانی همه‌ی تغییرات:  sudo bash $(basename "$0") --restore"
  blank
}

reboot_flow() {
  if [ "$UPDATE_DONE" != true ]; then return; fi
  if [ "$REBOOT_NEEDED" != true ]; then ok "ریبوت لازم نیست؛ هیچ بسته‌ی حیاتی (کرنل/کتابخانه‌ی اصلی) نیاز به راه‌اندازی مجدد ندارد."; return; fi
  warn "برای اعمال کامل آپدیت‌ها (کرنل/کتابخانه‌ها) ریبوت لازم است."
  note "ریبوت آنی وسط SSH خطرناک است؛ در صورت تایید، ریبوت با ۶۰ ثانیه تاخیر زمان‌بندی می‌شود."
  if confirm "همین الان ریبوت زمان‌بندی شود؟" "$([ "$FORCE_REBOOT" = true ] && echo yes)" n; then
    info "ریبوت امن برای ۶۰ ثانیه‌ی دیگر زمان‌بندی شد؛ برای لغو:  ${C_BOLD}shutdown -c${C_RESET}"
    shutdown -r +1 "ABR BARAN IDC . IR: ریبوت جهت اعمال آپدیت‌ها" >/dev/null 2>&1 &
  else
    info "ریبوت انجام نشد. هر زمان مناسب بود:  ${C_BOLD}sudo reboot${C_RESET}"
  fi
}

# =============================================================================
#  پاکسازی و مدیریت قطع ناگهانی (Ctrl+C / kill) — بازگردانی خودکار تغییرات نیمه‌کاره
# =============================================================================
cleanup() {
  [ "$IS_TTY" = true ] && printf '\r\033[K' >&3 2>/dev/null
  [ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
  sleep 0.2
}

on_interrupt() {
  trap - INT TERM
  printf '\n'
  warn "اجرا متوقف شد؛ بررسی تغییرات نیمه‌کاره ..."
  jobs -p 2>/dev/null | xargs -r kill 2>/dev/null
  if [ "$APT_DIRTY" = true ];  then restore_apt_pristine; warn "مخزن apt به حالت سالم قبلی بازگردانده شد."; fi
  if [ "$RPM_DIRTY" = true ];  then rpm_restore_from "$BK"; warn "مخزن RPM به حالت سالم قبلی بازگردانده شد."; fi
  if [ "$DNS_DIRTY" = true ];  then dns_restore_from "$BK"; warn "DNS به حالت سالم قبلی بازگردانده شد."; fi
  exit 130
}

# =============================================================================
#  برنامه‌ی اصلی
# =============================================================================
main() {
  parse_args "$@"
  setup_ui
  if [ "$(id -u)" -ne 0 ]; then
    err "این اسکریپت باید با دسترسی root اجرا شود:  sudo bash $0"; exit 1
  fi
  # منوی تعاملی: فقط وقتی هیچ آرگومانی داده نشده و ترمینال واقعی است
  if [ "$ARGC" -eq 0 ] && [ "$IS_TTY" = true ] && tty_usable; then
    show_menu || { echo; exit 0; }
  fi
  # فعال‌سازی صریح Docker/Firewall/Fail2ban مرحله‌ی مربوط را هم روشن نگه می‌دارد
  if [ "$DO_DOCKER" = true ] && [ -n "$ONLY_LIST" ] && ! has_word "$ONLY_LIST" docker; then ONLY_LIST+=",docker"; fi
  if { [ "$DO_FIREWALL" = true ] || [ "$DO_FAIL2BAN" = true ]; } && [ -n "$ONLY_LIST" ] && ! has_word "$ONLY_LIST" security; then ONLY_LIST+=",security"; fi
  count_steps

  TMPD=$(mktemp -d /tmp/abrbaran.XXXXXX) || { echo "ساخت پوشه‌ی موقت ناموفق بود" >&2; exit 1; }
  local ts; ts=$(date +%Y%m%d_%H%M%S)
  BK="$BACKUP_ROOT/$ts"; ORIG="$BACKUP_ROOT/original"
  if [ "$DO_RESTORE" != true ] && [ "$DO_STATUS" != true ] && [ "$DRY_RUN" != true ]; then
    mkdir -p "$BK" && ln -sfn "$BK" "$BACKUP_ROOT/latest"
  fi
  write_awk_programs
  trap cleanup EXIT
  trap on_interrupt INT TERM

  LOGFILE="/root/abrbaran-optimizer-${ts}.log"
  : > "$LOGFILE"; chmod 600 "$LOGFILE"
  # خروجی هم روی ترمینال و هم در لاگ (کدهای رنگ از لاگ حذف می‌شوند)
  exec > >(tee >(sed -u $'s/\033\\[[0-9;?]*[A-Za-z]//g' >> "$LOGFILE")) 2>&1

  detect_os
  if [ "$DO_RESTORE" = true ]; then do_restore; exit $?; fi
  if [ "$DO_STATUS" = true ]; then banner; show_status; exit 0; fi

  banner
  info "لاگ کامل این اجرا:  ${C_GRAY}${LOGFILE}${C_RESET}"
  [ -n "$ONLY_LIST" ] && info "فقط این مرحله‌ها: ${C_BOLD}${ONLY_LIST}${C_RESET}"

  # ───────── تشخیص سیستم ─────────
  step "تشخیص سیستم و آماده‌سازی ابزارها"
  ok "سیستم‌عامل: ${C_BOLD}${OS_PRETTY}${C_RESET}   ${C_GRAY}(مدیر بسته: ${PKG_MGR}${OS_LIKE:+ · مشابه: $OS_LIKE})${C_RESET}"
  command -v systemd-detect-virt >/dev/null 2>&1 && { v=$(systemd-detect-virt 2>/dev/null); [ -n "$v" ] && [ "$v" != "none" ] && note "مجازی‌سازی: $v"; }
  ensure_tools

  if mod_on dns; then
    step "تست و تنظیم DNS"
    GITHUB_BASE_OK=$(github_count_ok)
    test_all_dns
    apply_dns
  fi

  if mod_on repo; then
    step "بهینه‌سازی مخزن (Repository)"
    fix_repositories
    if [ "$REPO_ALL_FAILED" = true ] && [ "$DNS_ALL_FAILED" = true ]; then generate_network_diagnostic_report; fi
  fi

  if mod_on github; then
    step "بررسی دسترسی به GitHub"
    check_github_access
  fi

  if mod_on bbr || mod_on tune; then
    step "شبکه و کرنل (BBR + sysctl)"
    if mod_on bbr; then enable_bbr; else set_st BBR skip "رد شد"; fi
    if mod_on bbr && mod_on tune; then blank; fi
    if mod_on tune; then apply_kernel_tuning; else set_st TUNE skip "رد شد"; fi
  fi

  local sf="" uf="" tf="" xf=""
  [ "$FORCE_SKIP_SPEEDTEST" = true ] && sf="no"
  [ -z "$sf" ] && [ "$AUTO_YES" = true ] && sf="yes"
  [ "$FORCE_SKIP_UPDATE" = true ] && uf="no"
  [ -z "$uf" ] && [ "$AUTO_YES" = true ] && uf="yes"
  [ "$AUTO_YES" = true ] && { tf="yes"; xf="yes"; }
  [ "$DRY_RUN" = true ] && { sf="no"; }

  if mod_on tools; then
    step "ابزارهای کاربردی سرور"
    if confirm "ابزارهای پرکاربرد (git، htop، tmux، jq، ncdu، ...) نصب شوند؟" "$xf" y; then install_essentials
    else info "رد شد."; set_st TOOLS skip "رد شد"; fi
  fi

  if mod_on system; then
    step "منابع سیستم (سوآپ، limits، journald، TRIM)"
    if confirm "منابع سیستم بهینه شود؟ (سوآپ در صورت نبودن، افزایش سقف فایل‌ها، محدودسازی لاگ، TRIM)" "$xf" y; then optimize_system_resources
    else info "رد شد."; set_st SYSTEM skip "رد شد"; fi
  fi

  if mod_on docker; then
    step "Docker و میرور رجیستری"
    setup_docker
  fi

  if mod_on security; then
    step "امنیت (SSH · فایروال · Fail2ban)"
    setup_security
  fi

  if mod_on speedtest; then
    step "تست سرعت (Ookla Speedtest)"
    if [ "$HAS_CURL" = true ] && confirm "Ookla Speedtest نصب و تست سرعت گرفته شود؟" "$sf" n; then install_speedtest
    else info "رد شد."; set_st SPEED skip "رد شد"; fi
  fi

  if mod_on time; then
    step "منطقه‌زمانی و همگام‌سازی ساعت"
    if confirm "منطقه‌زمانی روی ایران (Asia/Tehran) تنظیم و ساعت همگام شود؟" "$tf" y; then optimize_time_settings
    else info "رد شد."; set_st TIME skip "رد شد"; fi
  fi

  if mod_on update; then
    step "آپدیت/آپگرید سیستم‌عامل"
    if confirm "سیستم‌عامل آپدیت/آپگرید شود؟" "$uf" y; then update_upgrade_system
    else info "رد شد."; set_st UPDATE skip "رد شد"; fi
  fi

  print_summary
  reboot_flow
  blank
}

# اجرا فقط وقتی مستقیم صدا زده شود (نه وقتی برای تست source می‌شود)
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
