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

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
