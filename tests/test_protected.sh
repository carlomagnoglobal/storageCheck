#!/bin/bash
# Safety tests for storage_check.sh — run from the repo root:
#   bash tests/test_protected.sh
#
# Builds a fake $HOME with protected data (sync engines, messaging, macOS
# containers, mail, keychains) next to ordinary caches, then checks that:
#   - _wiz_protected blocks every protected path and passes ordinary caches
#   - the wizard scan (_wizard_collect) never offers a protected path,
#     never offers a dot-folder leftover as SAFE, and lists no path twice
#   - quick_clean's preview never includes a protected path
#   - --dry-run deletes nothing; _rm_tracked reports honestly
# Nothing outside the temporary fixture is touched.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/storage_check.sh"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }

bash -n "$SCRIPT" && ok "bash -n syntax check" || bad "bash -n syntax check"

FIX=$(mktemp -d) || { echo "mktemp failed"; exit 1; }
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX"

# mk <dir> [kb]: directory holding one file of the given size (default 2MB,
# above the scan's 1MB noise floor). Real bytes, not sparse, so du sees them.
mk() { mkdir -p "$HOME/$1"; dd if=/dev/zero of="$HOME/$1/blob" bs=1024 count="${2:-2048}" 2>/dev/null; }

PROTECTED_DIRS=(
  "Library/Application Support/Google/DriveFS/1234/content_cache"
  "Library/Application Support/Google/DriveFS/1234/thumbnails_cache"
  "Library/Application Support/OneDrive/Cache"
  "Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite/Cache"
  "Library/Group Containers/UBF8T346G9.Office/Cache"
  "Library/Application Support/Dropbox/Cache"
  "Library/CloudStorage/GoogleDrive-me/Cache"
  "Library/Mobile Documents/com~apple~CloudDocs/Cache"
  "Library/Application Support/CloudDocs/session/Cache"
  "Library/Application Support/Box/Box/cache"
  "Library/Containers/com.apple.Safari/Data/Library/Caches"
  "Library/Group Containers/group.com.apple.notes/Caches"
  "Library/Containers/net.whatsapp.WhatsApp/Data/Library/Caches"
  "Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/Cache"
  "Library/Caches/com.apple.bird"
  "Library/Caches/CloudKit"
  "Library/Caches/net.whatsapp.WhatsApp"
  "Library/Caches/ru.keepcoder.Telegram"
  "Library/Caches/com.microsoft.OneDrive"
  "Library/Logs/com.apple.xpc.launchd"
  "Library/Saved Application State/com.apple.Terminal.savedState"
  "Library/Mail/V10/cache"
  "Library/Keychains/login"
)
SAFE_DIRS=(
  "Library/Caches/com.spotify.client"
  "Library/Caches/foo-updater"
  "Library/Caches/com.example.app.ShipIt"
  "Library/Logs/SomeApp"
  "Library/Application Support/Code/Cache"
  "Library/Application Support/Code/CachedData"
  "Library/Containers/com.example.app/Data/Library/Caches"
  ".Trash"
)
for d in "${PROTECTED_DIRS[@]}" "${SAFE_DIRS[@]}"; do mk "$d"; done
mk ".cache/huggingface"
mk ".ollama/models"; mk ".codeium/data"; mk ".windsurf/data"
mkdir -p "$HOME/Applications"; ln -s /tmp "$HOME/Applications/MovedToUSB.app"

# Load the functions without starting the menu (source guard), then stub UI.
# shellcheck disable=SC1090
source "$SCRIPT"
clear() { :; }; sleep() { :; }; press_any_key() { :; }; _back_to_menu() { :; }

echo ""; echo "_wiz_protected"
for d in "${PROTECTED_DIRS[@]}"; do
  _wiz_protected "$HOME/$d" && ok "blocks  $d" || bad "LEAKS   $d"
done
for d in "${SAFE_DIRS[@]}"; do
  _wiz_protected "$HOME/$d" && bad "over-blocks $d" || ok "passes  $d"
done

echo ""; echo "_wizard_collect"
_wizard_collect >/dev/null 2>&1
paths=""; fail_before=$FAIL
for c in "${CANDIDATES[@]}"; do
  IFS='|' read -r tier kb path label note <<< "$c"
  paths="$paths$path"$'\n'
  rel="${path#$HOME/}"
  for d in "${PROTECTED_DIRS[@]}"; do
    case "$path/" in "$HOME/$d/"*) bad "protected offered: $rel" ;; esac
    # a candidate that CONTAINS a protected dir would sweep it along
    case "$HOME/$d/" in "$path/"*) bad "candidate $rel contains protected $d" ;; esac
  done
  case "$rel" in .*/*|.Trash) ;; .*) [ "$tier" = "SAFE" ] && bad "dot-folder offered as SAFE: $rel" ;; esac
  case "$path" in *.app) [ -L "$path" ] && bad "external-drive launcher offered: $rel" ;; esac
done
for d in "${SAFE_DIRS[@]}"; do
  printf '%s' "$paths" | grep -qxF "$HOME/$d" && ok "offers  $d" || bad "missing $d"
done
dups=$(printf '%s' "$paths" | sort | uniq -d)
[ -z "$dups" ] && ok "no path listed twice" || bad "duplicates: $dups"
[ "$FAIL" -eq "$fail_before" ] && ok "${#CANDIDATES[@]} candidates: none protected, none containing a protected dir"

echo ""; echo "quick_clean preview"
confirm() { return 1; }   # decline: preview only
quick_clean >/dev/null 2>&1
leak=0
while IFS='|' read -r kb path label; do
  [ -z "$path" ] && continue
  for d in "${PROTECTED_DIRS[@]}"; do
    case "$path/" in "$HOME/$d/"*) bad "quick_clean offers protected $d"; leak=1 ;; esac
    case "$HOME/$d/" in "$path/"*) bad "quick_clean $path contains protected $d"; leak=1 ;; esac
  done
done <<< "$PREVIEW"
[ "$leak" -eq 0 ] && ok "no protected path in quick_clean preview"
printf '%s' "$PREVIEW" | grep -q "/\.codeium|\|/\.windsurf|" && bad "quick_clean offers IDE dot-folders" || ok "no IDE dot-folders in quick_clean"

echo ""; echo "deletion"
DRY_RUN=1
got=$(_rm_tracked "$HOME/.Trash" 2048 2>/dev/null)
[ -e "$HOME/.Trash/blob" ] && [ "$got" = "2048" ] && ok "dry run keeps files, reports would-free size" || bad "dry run deleted or misreported"
DRY_RUN=0
mk "victim"
got=$(_rm_tracked "$HOME/victim" 2048) && [ ! -e "$HOME/victim" ] && [ "$got" = "2048" ] \
  && ok "_rm_tracked deletes and reports size" || bad "_rm_tracked real delete"
_rm_tracked "" 5 >/dev/null && bad "_rm_tracked accepted empty path" || ok "_rm_tracked refuses empty path"
mk "locked"; chmod 500 "$HOME/locked"     # blob can't be unlinked
got=$(_rm_tracked "$HOME/locked" 2048); rc=$?
chmod 700 "$HOME/locked"
[ "$rc" -ne 0 ] && [ "$got" -lt 2048 ] && ok "_rm_tracked reports partial failure" || bad "_rm_tracked hid a failed delete (rc=$rc got=$got)"

echo ""; echo "_du_batch"
mk "sz/a b"; mk "sz/trail" 1024
DU_PATHS=("$HOME/sz/a b" "" "$HOME/sz/missing" "$HOME/sz/trail/" "$HOME/sz/a b")
_du_batch test >/dev/null 2>&1
[ "${DU_KB[0]}" -ge 2048 ] && [ "${DU_KB[1]}" = 0 ] && [ "${DU_KB[2]}" = 0 ] \
  && [ "${DU_KB[3]}" -ge 1024 ] && [ "${DU_KB[3]}" -lt 2048 ] && [ "${DU_KB[4]}" = "${DU_KB[0]}" ] \
  && ok "sizes land in input order (spaces, empty, missing, trailing /, duplicate)" \
  || bad "_du_batch results: ${DU_KB[*]}"

echo ""; echo "new REVIEW sources"
old() { touch -t 202001010000 "$HOME/$1"; }
mk ".npm/_cacache"
mkdir -p "$HOME/Downloads"
dd if=/dev/zero of="$HOME/Downloads/Old Installer.dmg" bs=1024 count=12288 2>/dev/null; old "Downloads/Old Installer.dmg"
dd if=/dev/zero of="$HOME/Downloads/new.dmg" bs=1024 count=12288 2>/dev/null
mk "code/oldproj/node_modules/pkg" 12288; old "code/oldproj/node_modules"
mk "code/newproj/node_modules/pkg" 12288
mk "code/oldproj/node_modules/pkg/node_modules/x" 12288; old "code/oldproj/node_modules/pkg/node_modules"; old "code/oldproj/node_modules"
_wizard_collect >/dev/null 2>&1
tier_of() { local c t kb p l n; for c in "${CANDIDATES[@]}"; do IFS='|' read -r t kb p l n <<< "$c"; [ "$p" = "$HOME/$1" ] && { echo "$t"; return; }; done; echo none; }
[ "$(tier_of .npm/_cacache)" = REVIEW ]                  && ok "npm cache is REVIEW"            || bad "npm cache: $(tier_of .npm/_cacache)"
[ "$(tier_of "Downloads/Old Installer.dmg")" = REVIEW ] && ok "old installer is REVIEW"        || bad "old installer: $(tier_of "Downloads/Old Installer.dmg")"
[ "$(tier_of Downloads/new.dmg)" = none ]               && ok "recent installer not offered"   || bad "recent installer offered"
[ "$(tier_of code/oldproj/node_modules)" = REVIEW ]     && ok "stale node_modules is REVIEW"   || bad "stale node_modules: $(tier_of code/oldproj/node_modules)"
[ "$(tier_of code/newproj/node_modules)" = none ]       && ok "fresh node_modules not offered" || bad "fresh node_modules offered"
[ "$(tier_of code/oldproj/node_modules/pkg/node_modules)" = none ] && ok "nested node_modules not listed separately" || bad "nested node_modules listed"

echo ""; echo "_owner_running"
_running_snapshot
case "$RUNNING" in *"|finder|"*"|com.apple.finder|"*) ok "live snapshot sees Finder" ;; *) bad "live snapshot missed Finder: ${RUNNING:0:80}" ;; esac
RUNNING="|spotify|com.spotify.client|code|"
_owner_running "$HOME/Library/Caches/com.spotify.client"            && ok "running app's cache detected (bundle id)"   || bad "missed running bundle id"
_owner_running "$HOME/Library/Application Support/Code/Cache"       && ok "running app's cache detected (bundle name)" || bad "missed running bundle name"
_owner_running "$HOME/Library/Caches/com.example.other"             && bad "false positive on idle app" || ok "idle app not flagged"
_owner_running "$HOME/.Trash"                                       && bad "non-app path flagged"       || ok "non-app path not flagged"

echo ""; echo "_app_leftovers"
# Never touch the real Trash from tests: "trash" into the fixture instead.
_to_trash() { mkdir -p "$HOME/.Trash"; mv "$1" "$HOME/.Trash/" 2>/dev/null; [ ! -e "$1" ]; }
B="com.test.goneapp"
mk "Library/Containers/$B"; mk "Library/Application Support/GoneApp"; mk "Library/Group Containers/ABCDE12345.$B"
mkdir -p "$HOME/Library/Preferences"; echo x > "$HOME/Library/Preferences/$B.plist"
mk "Library/Containers/com.test.otherapp"
gone_bid=("$B"); gone_name=("GoneApp")
echo a | _app_leftovers >/dev/null 2>&1
gone=1
for p in "Library/Containers/$B" "Library/Application Support/GoneApp" "Library/Group Containers/ABCDE12345.$B" "Library/Preferences/$B.plist"; do
  [ -e "$HOME/$p" ] && { bad "leftover not removed: $p"; gone=0; }
done
[ "$gone" -eq 1 ] && ok "all leftovers of the removed app moved to Trash"
[ -e "$HOME/Library/Containers/com.test.otherapp" ] && ok "other apps' data untouched" || bad "other app's data removed"
[ -e "$HOME/Library/Containers/com.apple.Safari" ] && ok "protected data untouched" || bad "protected data removed"
gone_bid=("com.apple.Safari"); gone_name=("Safari")
mk "Library/Containers/com.apple.Safari/Data/x"
echo a | _app_leftovers >/dev/null 2>&1
[ -e "$HOME/Library/Containers/com.apple.Safari" ] && ok "com.apple.* app leftovers never offered" || bad "com.apple.* leftovers removed"
gone_bid=(""); gone_name=("NoBid"); mk "Library/Application Support/NoBid"
echo a | _app_leftovers >/dev/null 2>&1
[ -e "$HOME/Library/Application Support/NoBid" ] && ok "no bundle id → nothing matched" || bad "name-only match removed data"

echo ""; echo "Applications Manager: parsing helpers"
[ "$(_parse_size_kb 500M)" = 512000 ]   && ok "500M parsed"  || bad "500M → $(_parse_size_kb 500M)"
[ "$(_parse_size_kb 1.5g)" = 1572864 ]  && ok "1.5g parsed"  || bad "1.5g → $(_parse_size_kb 1.5g)"
[ "$(_parse_size_kb 200)" = 204800 ]    && ok "bare number is MB" || bad "200 → $(_parse_size_kb 200)"
[ "$(_parse_size_kb 800KB)" = 800 ]     && ok "800KB parsed" || bad "800KB → $(_parse_size_kb 800KB)"
_parse_size_kb "big" >/dev/null && bad "junk size accepted" || ok "junk size rejected"
_parse_size_kb "5T" >/dev/null && bad "unknown unit accepted" || ok "unknown unit rejected"
T=$(( $(date -j -u -f "%Y-%m-%d %H:%M:%S" "2026-10-10 00:00:00" +%s) / 86400 ))
out=$(printf '%s\n' "2026-01-01 05:00:00 +0000" "(null)" "2024-02-29 23:59:59 +0000" "2026-10-10 12:00:00 +0000" | _days_since "$T" | tr '\n' ' ')
[ "$out" = "282 -1 954 0 " ] && ok "_days_since: dates, leap day, (null)" || bad "_days_since → $out"
KEY=x; printf '\033[C' | { _read_key; [ "$KEY" = right ]; } && ok "_read_key: → arrow" || bad "_read_key arrow"
printf 'd'      | { _read_key; [ "$KEY" = d ]; }     && ok "_read_key: single key, no Enter" || bad "_read_key single key"
printf '\n'     | { _read_key; [ -z "$KEY" ]; }      && ok "_read_key: Enter is empty"       || bad "_read_key Enter"

echo ""; echo "Applications Manager: filters and sort (_apps_view)"
APP_N=5
APP_NAME=(x Alpha Beta Gamma Delta Echo); APP_LNAME=(x alpha beta gamma delta echo)
APP_KB=(0 100 5000 300000 2000000 50); APP_LOC=(x /App /App "~/App" /App /App)
APP_STATE=(x ok admin ext ext lock); APP_TARGET=(x "" "" "$HOME" "/nonexistent/Delta.app" "")
APP_USED=(x 5 200 -1 400 -2); APP_RUN=(x 1 0 0 0 0); APPS_USED_OK=1
APPS_SCOPE=all; APPS_SORT=size_desc; APPS_PAGE=1
vis() { _apps_view; local v="" i; for i in "${VIS[@]}"; do v="$v${APP_NAME[$i]} "; done; echo "$v"; }
_apps_clear_filters
[ "$(vis)" = "Delta Gamma Beta Alpha Echo " ] && ok "no filter: all, biggest first" || bad "no filter → $(vis)"
APPS_F_NAME="ALP";      [ "$(vis)" = "Alpha " ] && ok "name filter, case-insensitive" || bad "name → $(vis)"
APPS_F_NAME="*";        [ "$(vis)" = "" ] && ok "name filter treats * literally" || bad "glob name → $(vis)"
_apps_clear_filters; APPS_F_MINKB=$(_parse_size_kb 1M); [ "$(vis)" = "Delta Gamma Beta " ] && ok "min size filter" || bad "minsize → $(vis)"
_apps_clear_filters; APPS_F_USED=180; [ "$(vis)" = "Delta Beta " ] && ok "unused 180d+: dated only" || bad "used180 → $(vis)"
_apps_clear_filters; APPS_F_USED=-1;  [ "$(vis)" = "Gamma " ] && ok "no-usage-record filter" || bad "used-1 → $(vis)"
APPS_USED_OK=0; [ "$(vis)" = "Delta Gamma Beta Alpha Echo " ] && ok "last-used filter off without Spotlight data" || bad "noSpotlight → $(vis)"; APPS_USED_OK=1
_apps_clear_filters; APPS_F_STATE=ext;     [ "$(vis)" = "Gamma " ] && ok "state: external (drive connected)" || bad "ext → $(vis)"
APPS_F_STATE=offline; [ "$(vis)" = "Delta " ] && ok "state: drive offline" || bad "offline → $(vis)"
APPS_F_STATE=lock;    [ "$(vis)" = "Echo " ]  && ok "state: protected" || bad "lock → $(vis)"
_apps_clear_filters; APPS_F_RUN=yes; [ "$(vis)" = "Alpha " ] && ok "running only" || bad "run yes → $(vis)"
APPS_F_RUN=no; [ "$(vis)" = "Delta Gamma Beta Echo " ] && ok "not running" || bad "run no → $(vis)"
_apps_clear_filters; APPS_F_MINKB=200; APPS_F_STATE=ok; APPS_F_RUN=no; [ "$(vis)" = "" ] && ok "filters combine (AND)" || bad "combo → $(vis)"
_apps_clear_filters; APPS_SORT=size_asc; [ "$(vis)" = "Echo Alpha Beta Gamma Delta " ] && ok "sort: small first" || bad "size_asc → $(vis)"
APPS_SORT=name; [ "$(vis)" = "Alpha Beta Delta Echo Gamma " ] && ok "sort: name" || bad "name sort → $(vis)"
APPS_SORT=used; [ "$(vis)" = "Delta Beta Alpha Gamma Echo " ] && ok "sort: oldest use first, no record, unknown last" || bad "used sort → $(vis)"
APPS_SCOPE=usr; APPS_SORT=size_desc; [ "$(vis)" = "Gamma " ] && ok "scope ~/Applications" || bad "scope → $(vis)"
APPS_SCOPE=all

echo ""; echo "Applications Manager: size cache"
SYS=$(mktemp -d); trap 'rm -rf "$FIX" "$SYS"' EXIT
APPS_SYS_DIR="$SYS"
mkapp() { mkdir -p "$1/Contents"; echo '<plist/>' > "$1/Contents/Info.plist"; dd if=/dev/zero of="$1/Contents/blob" bs=1024 count="$2" 2>/dev/null; }
rm -f "$HOME/Applications/MovedToUSB.app"   # earlier fixture; no Info.plist, so never cacheable
mkapp "$SYS/One.app" 2048; mkapp "$HOME/Applications/Two.app" 1024
eval "$(declare -f _du_batch | sed '1s/_du_batch/_du_batch_real/')"
_du_batch() { DU_SIZED=$((DU_SIZED + ${#DU_PATHS[@]})); _du_batch_real "$@"; }
kb_of() { local i; for ((i=1; i<=APP_N; i++)); do [ "${APP_NAME[$i]}" = "$1" ] && echo "${APP_KB[$i]}"; done; }
[ -f "$APPS_CACHE" ] && rm -f "$APPS_CACHE"
DU_SIZED=0; _apps_scan >/dev/null 2>&1
[ "$APP_N" -eq 2 ] && [ "$DU_SIZED" -eq 2 ] && ok "first scan sizes every app" || bad "first scan: N=$APP_N sized=$DU_SIZED"
[ "$(kb_of One)" -ge 2048 ] && [ "$(kb_of Two)" -ge 1024 ] && ok "sizes are right" || bad "sizes: One=$(kb_of One) Two=$(kb_of Two)"
[ -f "$APPS_CACHE" ] && [ "$(wc -l < "$APPS_CACHE" | tr -d ' ')" = 2 ] && ok "cache written" || bad "cache missing"
DU_SIZED=0; _apps_scan >/dev/null 2>&1
[ "$DU_SIZED" -eq 0 ] && [ "$(kb_of One)" -ge 2048 ] && ok "second scan answered from cache" || bad "second scan sized $DU_SIZED, One=$(kb_of One)"
touch -t 202001010000 "$SYS/One.app/Contents/Info.plist"
DU_SIZED=0; _apps_scan >/dev/null 2>&1
[ "$DU_SIZED" -eq 1 ] && ok "updated app (Info.plist changed) re-sized alone" || bad "after update sized $DU_SIZED"
printf 'garbage\nmore\tgarbage\n\x01\n' > "$APPS_CACHE"
DU_SIZED=0; _apps_scan >/dev/null 2>&1
[ "$DU_SIZED" -eq 2 ] && [ "$(kb_of Two)" -ge 1024 ] && ok "corrupt cache → full re-size, correct sizes" || bad "corrupt cache: sized $DU_SIZED"
rm -rf "$HOME/Applications/Two.app"
DU_SIZED=0; _apps_scan >/dev/null 2>&1
[ "$APP_N" -eq 1 ] && [ "$DU_SIZED" -eq 0 ] && ok "removed app drops out, nothing re-sized" || bad "after removal N=$APP_N sized=$DU_SIZED"

echo ""; echo "Applications Manager: keys (headless)"
clear() { :; }
applications_manager < <(printf 'feo\nb') >/dev/null 2>&1
[ "$APPS_F_STATE" = ok ] && [ "$APPS_F_RUN" = yes ] && ok "f panel: e/o cycle state and running" || bad "panel → state=$APPS_F_STATE run=$APPS_F_RUN"
applications_manager < <(printf 'feo\ncb') >/dev/null 2>&1
[ "$APPS_F_STATE" = any ] && [ "$APPS_F_RUN" = any ] && ok "c clears every filter" || bad "clear → state=$APPS_F_STATE run=$APPS_F_RUN"
applications_manager < <(printf 'ss') >/dev/null 2>&1   # EOF must end the loop, not spin
# (keys come in via < <(…), not a pipe: a pipe would run the screen in a subshell)
[ "$APPS_SORT" = name ] && ok "s cycles sort; EOF leaves the screen" || bad "sort → $APPS_SORT"
DRY_RUN=1; applications_manager < <(printf 'd\nb') >/dev/null 2>&1; DRY_RUN=0
[ -d "$SYS/One.app" ] && ok "dry-run: [d]elete removes nothing" || bad "dry-run delete removed an app"
echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
