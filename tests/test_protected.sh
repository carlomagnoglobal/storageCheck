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

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
