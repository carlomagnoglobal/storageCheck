#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║      MAC STORAGE MANAGER v3.8 — by Claude                    ║
# ║      Audit · Analyze · Clean · Report · Wizard · Feedback    ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m';    BRED='\033[1;31m'
YELLOW='\033[0;33m'; BYELLOW='\033[1;33m'
GREEN='\033[0;32m';  BGREEN='\033[1;32m'
CYAN='\033[0;36m';   BCYAN='\033[1;36m'
BLUE='\033[0;34m';   BBLUE='\033[1;34m'
MAGENTA='\033[0;35m';BMAGENTA='\033[1;35m'
WHITE='\033[1;37m';  BOLD='\033[1m'
DIM='\033[2m';       RESET='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
divider()  { echo -e "${DIM}────────────────────────────────────────────────────────────${RESET}"; }
section()  { echo ""; echo -e "${BOLD}${BCYAN}$1${RESET}"; divider; }
success()  { echo -e "  ${BGREEN}✅ $1${RESET}"; }
warning()  { echo -e "  ${BYELLOW}⚠️  $1${RESET}"; }
danger()   { echo -e "  ${BRED}🔥 $1${RESET}"; }
info()     { echo -e "  ${CYAN}ℹ️  $1${RESET}"; }
skipped()  { echo -e "  ${DIM}── $1${RESET}"; }

color_size() {
  local size=$1
  if   echo "$size" | grep -qE '^[0-9]+(\.[0-9]+)?G'; then echo -e "${BRED}${BOLD}$size${RESET}"
  elif echo "$size" | grep -qE '^[0-9]+(\.[0-9]+)?M'; then echo -e "${YELLOW}$size${RESET}"
  else echo -e "${DIM}$size${RESET}"; fi
}

human_kb() {
  echo "$1" | awk '{
    if($1>=1048576) printf "%.1fG", $1/1048576
    else if($1>=1024) printf "%.1fM", $1/1024
    else printf "%dK", $1
  }'
}

# ── Run state, temp files, interrupt handling ─────────────────
DRY_RUN=0          # --dry-run: every deletion/move is reported, none performed
TMP_PATHS=""       # newline-separated temp files/dirs, removed on any exit
PENDING_MSG=""     # set during a move/restore's no-man's-land; shown if interrupted

# mktemp wrapper that registers the result for cleanup.
# usage: _mktemp VAR [-d]   — sets VAR; must NOT be called as $(_mktemp),
# since a command substitution is a subshell and the registration would be lost.
_mktemp() {
  local __var="$1" __t; shift
  __t=$(mktemp "$@" 2>/dev/null) || return 1
  TMP_PATHS="${TMP_PATHS}${__t}"$'\n'
  printf -v "$__var" '%s' "$__t"
}

_cleanup() {
  local t
  while IFS= read -r t; do
    case "$t" in /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) rm -rf "$t" 2>/dev/null ;; esac
  done <<< "$TMP_PATHS"
  TMP_PATHS=""
}

_on_interrupt() {
  trap - INT TERM
  echo ""
  if [ -n "$PENDING_MSG" ]; then
    echo -e "  ${BRED}🔥 Interrupted mid-operation.${RESET}"
    echo -e "  ${BYELLOW}$PENDING_MSG${RESET}"
  else
    echo -e "  ${DIM}Interrupted.${RESET}"
  fi
  wait 2>/dev/null   # let background du jobs finish before deleting their temp dir
  _cleanup
  exit 130
}

# Returns 0 (and says so) when --dry-run should block a destructive action.
_dry_block() {
  [ "$DRY_RUN" -eq 1 ] || return 1
  info "Dry run: $1 — nothing changed"
  return 0
}

# Volume that holds user data. Since Catalina, "/" is the small read-only
# system volume, so `df /` under-reports usage (e.g. 22% vs a real 77%).
# Free space is shared across the APFS container, but Used/% are not.
DATA_VOL="/System/Volumes/Data"; [ -d "$DATA_VOL" ] || DATA_VOL="/"

# Fills DISK_PCT / DISK_USED / DISK_FREE / DISK_TOTAL / DISK_COLOR from df.
_disk_stats() {
  DISK_PCT=$(df "$DATA_VOL" | awk 'NR==2{gsub(/%/,"",$5); print $5}')
  DISK_TOTAL=$(df -h "$DATA_VOL" | awk 'NR==2{print $2}')
  DISK_USED=$(df -h "$DATA_VOL" | awk 'NR==2{print $3}')
  DISK_FREE=$(df -h "$DATA_VOL" | awk 'NR==2{print $4}')
  if   [ "$DISK_PCT" -ge 80 ]; then DISK_COLOR="${BRED}"
  elif [ "$DISK_PCT" -ge 60 ]; then DISK_COLOR="${BYELLOW}"
  else DISK_COLOR="${BGREEN}"; fi
}

# Echoes a plain █/░ bar of $1 characters for the current DISK_PCT.
_disk_bar_str() {
  local len=${1:-40} i bar=""
  local filled=$(( DISK_PCT * len / 100 )); local empty=$(( len - filled ))
  for ((i=0;i<filled;i++)); do bar+="█"; done
  for ((i=0;i<empty;i++)); do bar+="░"; done
  echo "$bar"
}

# Height of the terminal window, in rows.
# NOTE: do not use `$(tput lines)` here. tput reads the window size with an
# ioctl on its own stdout; inside a command substitution that is a pipe, the
# ioctl fails and tput silently reports the terminfo default (usually 24)
# instead of the real window. Ask the controlling terminal directly.
# Redirect stderr BEFORE opening /dev/tty: bash applies redirections left to
# right, and if /dev/tty cannot be opened (no controlling terminal, e.g. when
# the script is piped) the shell's own error would otherwise reach the screen.
_term_lines() {
  local l
  # stdin is the terminal for a normal run; /dev/tty covers a redirected stdin.
  l=$(stty size 2>/dev/null | awk '{print $1}')
  case "$l" in ''|*[!0-9]*) l=$(stty size 2>/dev/null < /dev/tty | awk '{print $1}') ;; esac
  case "$l" in ''|*[!0-9]*) l="$LINES" ;; esac
  case "$l" in ''|*[!0-9]*) l=$(tput lines 2>/dev/null) ;; esac
  case "$l" in ''|*[!0-9]*) l=24 ;; esac
  [ "$l" -lt 10 ] && l=10
  echo "$l"
}

# Colored size from KB, padded to 8 visible columns (ANSI-safe alignment).
_size_cell() {
  local s; s=$(human_kb "${1:-0}")
  local n=$(( 8 - ${#s} )); [ "$n" -lt 1 ] && n=1
  printf "%s%*s" "$(color_size "$s")" "$n" ""
}

confirm() {
  echo -ne "\n  ${BYELLOW}❓ $1 [y/N]: ${RESET}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# rm -rf an existing path and echo the KB actually reclaimed ($2 = size
# before, minus whatever is left behind). Returns 1 if anything survived
# (e.g. no Full Disk Access, file in use), so callers report it honestly.
_rm_tracked() {
  local path="$1" before="${2:-0}" left
  if [ -z "$path" ] || [ ! -e "$path" ]; then echo 0; return 1; fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "  ${DIM}[dry run] would delete: $path${RESET}" >&2
    echo "$before"; return 0
  fi
  rm -rf "$path" 2>/dev/null
  if [ -e "$path" ]; then
    left=$(du -sk "$path" 2>/dev/null | cut -f1); left=${left:-0}
    [ "$left" -gt "$before" ] && left=$before
    echo $((before-left)); return 1
  fi
  echo "$before"
}

# Moves a path to the Trash, so the user can undo it (Finder → Put Back).
# Uses macOS's /usr/bin/trash when present, else asks Finder. Returns 1 if
# the path is still there afterwards. Space is reclaimed only once the
# Trash is emptied, so callers report trashed KB separately from freed KB.
_to_trash() {
  local path="$1"
  if [ -z "$path" ] || { [ ! -e "$path" ] && [ ! -L "$path" ]; }; then return 1; fi
  if [ "$DRY_RUN" -eq 1 ]; then
    echo -e "  ${DIM}[dry run] would move to Trash: $path${RESET}" >&2
    return 0
  fi
  if [ -x /usr/bin/trash ]; then
    /usr/bin/trash "$path" >/dev/null 2>&1
  else
    osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' \
              -e 'end run' "$path" >/dev/null 2>&1
  fi
  [ ! -e "$path" ] && [ ! -L "$path" ]
}

# Removes a REVIEW-tier item: Trash first (undoable); permanent rm only if
# that fails AND the user agrees. Prints its own result line and sets
# RM_FREED / RM_TRASHED (KB) — globals, so don't call it inside $(...).
_remove_undoable() {
  local path="$1" kb="${2:-0}" label="$3"
  RM_FREED=0; RM_TRASHED=0
  if _to_trash "$path"; then
    RM_TRASHED=$kb
    success "Moved to Trash: $label ${DIM}($(human_kb "$kb"))${RESET}"
    return 0
  fi
  [ -e "$path" ] || return 1
  warning "Could not move $label to the Trash."
  if ! confirm "Delete it permanently instead?"; then skipped "Kept $label"; return 1; fi
  if RM_FREED=$(_rm_tracked "$path" "$kb"); then
    success "Deleted $label ${DIM}($(human_kb "$kb"))${RESET}"
    return 0
  fi
  danger "Could not fully delete $label (in use, or needs Full Disk Access)"
  return 1
}

# Sizes many paths at once: reads DU_PATHS[0..n-1], fills DU_KB[0..n-1].
# du is I/O-bound, so xargs -P runs several at a time (no batch stragglers);
# "$1" labels a live "Sizing N/M" counter. Empty paths size as 0.
_du_batch() {
  local label="${1:-items}" n=${#DU_PATHS[@]} i work="" out done_n
  DU_KB=()
  [ "$n" -eq 0 ] && return
  _mktemp work -d || work=""
  if [ -z "$work" ]; then   # no temp dir: fall back to serial
    for ((i=0; i<n; i++)); do
      DU_KB[$i]=$( [ -n "${DU_PATHS[$i]}" ] && du -sk "${DU_PATHS[$i]}" 2>/dev/null | cut -f1 )
      DU_KB[$i]=${DU_KB[$i]:-0}
    done
    return
  fi
  out="$work/out"; : > "$out"
  for ((i=0; i<n; i++)); do [ -n "${DU_PATHS[$i]}" ] && printf '%s\0' "${DU_PATHS[$i]}"; done \
    | xargs -0 -P 8 -n 1 du -sk 2>/dev/null > "$out" &
  local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    done_n=$(wc -l < "$out" | tr -d ' ')
    printf "\r  ${DIM}Sizing %d/%d %s…${RESET}" "$done_n" "$n" "$label"
    command sleep 0.2
  done
  wait "$pid" 2>/dev/null
  printf "\r%-70s\r" ""
  # Join results back to input order by exact path (du echoes its argument).
  local kb
  i=0
  while IFS= read -r kb; do DU_KB[$i]=${kb:-0}; i=$((i+1)); done < <(
    { printf '%s\n' "${DU_PATHS[@]}"; echo "--END--"; cat "$out"; } | awk -F'\t' '
      !sep && $0=="--END--" { sep=1; next }
      !sep { order[++n]=$0; next }
      { kb=$1; sub(/^[^\t]*\t/, ""); size[$0]=kb }
      END { for (i=1;i<=n;i++) print ((order[i] in size) ? size[order[i]] : 0) }')
  rm -rf "$work"
}

# Snapshot of running GUI apps as "|name|bundle-name|bundle-id|…" (lowercase),
# from the .app bundles of every running process. Used to warn before
# deleting the cache of an app that is open (it can crash or rewrite it).
_running_snapshot() {
  RUNNING="|"
  local app info nm bn bid
  while IFS= read -r app; do
    [ -d "$app" ] || continue
    info="$app/Contents/Info.plist"
    nm=$(basename "$app" .app)
    bn=$(plutil -extract CFBundleName raw "$info" 2>/dev/null)
    bid=$(plutil -extract CFBundleIdentifier raw "$info" 2>/dev/null)
    RUNNING="$RUNNING$(printf '%s|%s|%s|' "$nm" "$bn" "$bid" | tr '[:upper:]' '[:lower:]' | sed 's/||*/|/g')"
  done < <(ps -axo comm= 2>/dev/null | awk '{ i=index($0, ".app/"); if (i) print substr($0, 1, i+3) }' | sort -u)
}

# True if the app owning a ~/Library cache/log/state path is running
# (per the last _running_snapshot). Sets RUNNING_OWNER for messages.
_owner_running() {
  local p="$1" rel owner
  RUNNING_OWNER=""
  case "$p" in
    "$HOME/Library/Caches/"*|"$HOME/Library/Application Support/"*|"$HOME/Library/Containers/"*|\
    "$HOME/Library/Saved Application State/"*|"$HOME/Library/Logs/"*) ;;
    *) return 1 ;;
  esac
  rel=${p#"$HOME/Library/"}; rel=${rel#*/}; owner=${rel%%/*}; owner=${owner%.savedState}
  [ -n "$owner" ] || return 1
  case "$RUNNING" in
    *"|$(echo "$owner" | tr '[:upper:]' '[:lower:]')|"*) RUNNING_OWNER="$owner"; return 0 ;;
  esac
  return 1
}

# Standard prompt for submenu action keys, e.g. ask_choice "d=delete  m=move  b=back"
menu_group() { echo -e "\n  ${DIM}─── $1 ───${RESET}"; }
ask_choice() { echo -ne "\n  ${BCYAN}$1 › ${RESET}"; }
press_any_key() { echo ""; echo -ne "  ${DIM}Press any key to continue...${RESET}"; read -rn1; }


# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════
# The menu is a loop: every feature function simply returns to it (via
# _back_to_menu or a plain `return`). Features must not call main_menu
# themselves — that recursion grew the call stack for the whole session.
main_menu() {
  local choice
  while true; do
    _main_menu_draw
    # EOF on stdin (closed pipe, Ctrl-D) would otherwise spin this loop forever.
    read -r choice || { echo ""; exit 0; }
    case "$choice" in
      1) full_audit ;;       2) storage_visualizer ;;
      3) find_large_files ;; 4) cloud_audit ;;
      5) ai_tools_audit ;;   6) app_support_deep ;;
      7) safe_wizard ;;      8) quick_clean ;;
      9) interactive_clean ;;10) time_machine_manager ;;
      11) applications_manager ;; 12) vscode_manager ;;
      13) lmstudio_manager ;; 14) ollama_manager ;;
      15) save_report ;;     16) generate_feedback ;;
      0)
        local free_now; free_now=$(df -h "$DATA_VOL" | awk 'NR==2{print $4}')
        echo -e "\n  ${BGREEN}Goodbye! 👋 Free space now: ${BYELLOW}${free_now}${RESET}\n"
        exit 0
        ;;
      "") ;;   # bare Enter just redraws
      *) warning "Invalid option"; sleep 1 ;;
    esac
  done
}

_main_menu_draw() {
  clear
  echo ""
  echo -e "${BMAGENTA}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BMAGENTA}║     🖥️  MAC STORAGE MANAGER v3.8                         ║${RESET}"
  echo -e "${BMAGENTA}║     $(date '+%a %d %b %Y — %H:%M')                              ║${RESET}"
  echo -e "${BMAGENTA}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  _disk_stats
  echo -e "  ${BOLD}Disk:${RESET} ${DISK_COLOR}[$(_disk_bar_str 40)] ${DISK_PCT}%${RESET}"
  echo -e "  ${DIM}Used: ${DISK_USED}  |  Free: ${DISK_FREE}  |  Total: ${DISK_TOTAL}${RESET}"
  [ "$DRY_RUN" -eq 1 ] && echo -e "  ${BYELLOW}🧪 DRY RUN — nothing will be deleted, moved or changed${RESET}"
  [ "${NO_FDA:-0}" -eq 1 ] && echo -e "  ${DIM}⚠️  No Full Disk Access: some sizes undercount and Trash can't be emptied.${RESET}" \
    && echo -e "  ${DIM}   Grant it: System Settings → Privacy & Security → Full Disk Access → your terminal.${RESET}"
  echo ""
  divider

  menu_group "🔍 ANALYZE (read-only)"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 1 "Full Audit" "scan everything"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 2 "Storage Visualizer" "bar/pie view of space"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 3 "Find Large Files" "files above a chosen size"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 4 "Cloud & Sync Audit" "OneDrive, iCloud, Dropbox · read-only"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 5 "AI Tools Audit" "IDEs, models, extensions · read-only"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 6 "App Support Deep Dive" "find hidden data · read-only"

  menu_group "🧹 CLEAN"
  printf "  ${BGREEN}${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 7 "🪄 Safe Cleanup Wizard" "guided, OS-safe"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 8 "Quick Clean" "one-confirm cache/log cleanup"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 9 "Interactive Clean" "choose item by item"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 10 "Time Machine & Backups" "snapshots, iOS backups"

  menu_group "📦 MANAGE"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 11 "Applications" "browse, uninstall, move to USB"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 12 "VSCode Extensions" "extensions: browse, delete, backup"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 13 "LM Studio" "manage local AI models"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 14 "Ollama" "manage Ollama AI models"

  menu_group "🧰 TOOLS"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 15 "Save Report to File" "export full audit"
  printf "  ${BOLD}%2d)${RESET} %-28s ${DIM}%s${RESET}\n" 16 "Generate Feedback File" "diagnostic dump for Claude Code"

  divider
  printf "  ${BOLD}%2d)${RESET} %-28s\n" 0 "❌ Exit"
  divider
  echo -ne "\n  ${BCYAN}Choose an option: ${RESET}"
}

# ══════════════════════════════════════════════════════════════
#   ★ 7) SAFE CLEANUP WIZARD  (the headline feature)
# ══════════════════════════════════════════════════════════════
#
#   Classifies everything into 3 tiers:
#     🟢 SAFE     — caches/logs/updaters/leftovers. Never touches the
#                   OS or installed apps. Apps simply rebuild these.
#     🟡 REVIEW   — re-downloadable but takes time/bandwidth
#                   (AI models, IDE extensions). You decide.
#     🔴 PROTECTED— user data & sync (OneDrive, WhatsApp, iCloud,
#                   Documents). The wizard NEVER offers these.
#
# Hard PROTECTED guard — returns 0 (true) if a path must NEVER be offered.
# Covers macOS system data, cloud-sync engines, messaging stores, mail,
# keychains and personal media. Cache subfolders inside these are skipped
# too (conservative: we don't poke sync engines even for their caches).
_wiz_protected() {
  local low=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  case "$low" in
    # macOS-owned data: anything under a com.apple.* / group.com.apple.* folder
    # (Containers, Caches, Saved Application State, ...). Never offered.
    */com.apple.*|*/group.com.apple.*)                                                    return 0 ;;
    # Cloud/sync platforms: library & container paths. DriveFS is Google
    # Drive's engine — its content_cache holds offline + not-yet-uploaded files.
    *onedrive*|*dropbox*|*"google drive"*|*googledrive*|*drivefs*|*cloudstorage*|*"mobile documents"*|*clouddocs*|*/cloudkit*) return 0 ;;
    *"/application support/box/"*|*com.box.desktop*|*pcloud*|*nextcloud*|*synology*|*megasync*|*"mega limited"*) return 0 ;;
    # Messaging apps
    *whatsapp*|*telegram*|*"group.net.whatsapp"*)                                        return 0 ;;
    # Apple system apps & services
    *"/library/mail"*|*com.apple.mail*|*"/applications/mail.app"*|*keychain*|*"/library/photos"*|*"/applications/photos.app"*|*photoslibrary*) return 0 ;;
    # Microsoft apps
    *"ubf8t346g9.office"*|*com.microsoft.outlook*|*com.microsoft.onedrive*|*"outlook.app"*) return 0 ;;
  esac
  return 1
}

_wizard_header() {
  clear
  echo -e "${BGREEN}${BOLD}🪄  SAFE CLEANUP WIZARD${RESET}  ${DIM}(v3.8 pattern engine)${RESET}"
  divider
  echo -e "  Offers only items that are ${BGREEN}safe by design${RESET}: caches, logs, temp & re-downloadables."
  echo -e "  It ${BRED}never${RESET} touches macOS system data, cloud sync, chats, mail, or your files."
  echo -e "  ${DIM}🟢 safe (auto-rebuilds) · 🟡 re-downloadable (you decide) · 🔴 protected (hidden)${RESET}"
  echo ""
}

safe_wizard() {
  _wizard_header
  info "Scanning by universal cache/log patterns (works on any Mac)..."
  _wizard_collect

  # The scan is slow, so the menu loops over the same CANDIDATES
  # (listing and invalid keys no longer trigger a rescan).
  local wchoice c tier kb path label note safe_total review_total
  while true; do
    safe_total=0; review_total=0
    for c in "${CANDIDATES[@]}"; do
      IFS='|' read -r tier kb path label note <<< "$c"
      [ "$tier" = "SAFE" ]   && safe_total=$((safe_total+kb))
      [ "$tier" = "REVIEW" ] && review_total=$((review_total+kb))
    done

    echo ""
    divider
    echo -e "  ${BGREEN}🟢 Safe to delete now:${RESET}        ${BOLD}$(human_kb $safe_total)${RESET}"
    echo -e "  ${BYELLOW}🟡 Re-downloadable (review):${RESET}  ${BOLD}$(human_kb $review_total)${RESET}"
    echo -e "  ${BRED}🔴 Protected (never touched):${RESET} ${DIM}macOS data, cloud sync, chats, mail, your files${RESET}"
    divider

    echo ""
    echo -e "  ${BOLD}How would you like to proceed?${RESET}"
    echo -e "  ${BOLD}a)${RESET} ${BGREEN}Auto-clean ALL 🟢 safe items${RESET} ${DIM}(recommended, instant)${RESET}"
    echo -e "  ${BOLD}p)${RESET} Pick items one-by-one ${DIM}(includes 🟡 review items)${RESET}"
    echo -e "  ${BOLD}l)${RESET} List everything first ${DIM}(no deletion)${RESET}"
    echo -e "  ${BOLD}b)${RESET} Back to menu"
    ask_choice "[a]uto  [p]ick  [l]ist  [b]ack"
    read -r wchoice

    case "$wchoice" in
      a|A) _wizard_auto_safe; return ;;
      p|P) _wizard_pick; return ;;
      l|L) _wizard_list; _wizard_header ;;
      b|B|q|Q) return ;;
      *) warning "Invalid option — try one of the keys shown"; sleep 1; _wizard_header ;;
    esac
  done
}

# Fills CANDIDATES ("TIER|kb|path|label|note"). Every path goes through
# _wiz_protected() before it is queued — keep it that way. Paths are queued
# first and sized at the end in one parallel _du_batch pass.
_wizard_collect() {
  CANDIDATES=()
  local -a QT QP QL QN QM
  local qn=0
  # add_candidate TIER path label note [min_kb]
  add_candidate() {
    local tier="$1" path="$2" label="$3" note="$4" min="${5:-1}"
    [ -e "$path" ] || return
    _wiz_protected "$path" && return
    QT[$qn]="$tier"; QP[$qn]="$path"; QL[$qn]="$label"; QN[$qn]="$note"; QM[$qn]="$min"
    qn=$((qn+1))
  }

  # Build a set of installed app identifiers for accurate leftover detection
  local INSTALLED=" "
  for b in /Applications "$HOME/Applications" /System/Applications; do
    [ -d "$b" ] || continue
    for a in "$b"/*.app; do
      [ -d "$a" ] || continue
      INSTALLED="$INSTALLED$(basename "$a" .app | tr '[:upper:]' '[:lower:]') "
      local bid=$(plutil -extract CFBundleIdentifier raw "$a/Contents/Info.plist" 2>/dev/null | tr '[:upper:]' '[:lower:]')
      [ -n "$bid" ] && INSTALLED="$INSTALLED$bid "
    done
  done

  # ───── 🟢 SAFE: cache/log roots, one candidate per child ─────
  # Never the root as a whole: the guard has to see each child, otherwise
  # e.g. ~/Library/Caches/com.apple.bird or a WhatsApp/OneDrive cache inside
  # would be swept along. Children < 1MB are skipped as noise. Updater
  # downloads (*updater*, *.ShipIt) live here too and get a clearer label.
  local d dn
  for d in "$HOME/Library/Caches"/*; do
    dn=$(basename "$d")
    case "$dn" in
      *.ShipIt)              add_candidate SAFE "$d" "Squirrel updater · $dn" "Old auto-update payload" 1024 ;;
      *[Uu]pdater*)          add_candidate SAFE "$d" "Updater cache · $dn"    "Old downloaded installers" 1024 ;;
      *)                     add_candidate SAFE "$d" "Cache · $dn"            "App rebuilds it" 1024 ;;
    esac
  done
  for d in "$HOME/Library/Logs"/*; do
    add_candidate SAFE "$d" "Logs · $(basename "$d")" "Diagnostic text only" 1024
  done
  for d in "$HOME/Library/Saved Application State"/*; do
    add_candidate SAFE "$d" "Window state · $(basename "$d" .savedState)" "Just window positions" 1024
  done
  add_candidate SAFE "$HOME/.Trash"                               "Trash bin"                         "Already-deleted files"

  # ───── 🟢 SAFE: Xcode dev caches (you have Xcode installed) ─────
  add_candidate SAFE "$HOME/Library/Developer/Xcode/DerivedData"  "Xcode · DerivedData"               "Rebuilds on next build"
  add_candidate SAFE "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator caches"            "Rebuilds automatically"

  # ───── 🟢 SAFE: cache/log/temp dirs INSIDE app data (pattern scan) ─────
  # Matches Cache, Caches, Code Cache, *Cache (GPUCache/Dawn*Cache/ShaderCache),
  # CachedData, logs, Crashpad, tmp — at any depth, pruned so we never recurse
  # into a matched dir. The PROTECTED guard skips sync/messaging/mail paths.
  local hit owner
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    owner=${hit#"$HOME/Library/"}; owner=${owner#*/}; owner=${owner%%/*}
    add_candidate SAFE "$hit" "${owner} · $(basename "$hit")" "App cache/log — rebuilds" 1024
  done < <(find "$HOME/Library/Application Support" "$HOME/Library/Containers" \
              -maxdepth 5 -type d \( \
                 -iname "Cache" -o -iname "Caches" -o -iname "Code Cache" \
                 -o -iname "*Cache" -o -iname "CachedData" -o -iname "CachedExtensionVSIXs" \
                 -o -iname "logs" -o -iname "Crashpad" -o -iname "tmp" \
              \) -prune -print 2>/dev/null)

  # ───── 🟡 REVIEW: likely leftovers (no .app AND no CLI of that name) ─────
  # REVIEW, never SAFE: a dot-folder can hold models, settings or logins, and
  # "no .app found" is a guess (e.g. Homebrew's ollama CLI has no bundle).
  for tool in cursor windsurf trae codeium antigravity comet manus qwen wispr ollama; do
    case "$INSTALLED" in *" $tool "*|*"$tool"*) continue ;; esac   # app present → skip
    command -v "$tool" >/dev/null 2>&1 && continue                  # CLI present → skip
    add_candidate REVIEW "$HOME/.$tool"                          "Leftover? · .$tool"       "No app or CLI found — check before deleting"
  done

  # ───── 🟡 REVIEW: large but re-downloadable / re-installable ─────
  add_candidate REVIEW "$HOME/.cache"                            "Generic ~/.cache"         "Dev tool caches — may hold big re-downloads (e.g. HuggingFace models)"
  add_candidate REVIEW "$HOME/.vscode/extensions"                "VSCode extensions (~/.vscode)" "Re-installable from Marketplace"
  add_candidate REVIEW "$HOME/.lmstudio/extensions"              "LM Studio · runtimes/extensions" "Re-downloadable"
  for m in "$HOME/.lmstudio/models"/*/; do
    [ -d "$m" ] && add_candidate REVIEW "$m" "LM Studio model · $(basename "$m")" "Re-downloadable from catalog"
  done
  # IDEs in ~/Applications — the single biggest opportunity on this Mac
  for a in "$HOME/Applications"/*.app; do
    # A symlink is a launcher for an app moved to an external drive — never rm it here.
    [ -L "$a" ] && continue
    [ -d "$a" ] && add_candidate REVIEW "$a" "IDE · $(basename "$a")" "Re-installable (JetBrains Toolbox etc.)"
  done

  # ───── 🟡 REVIEW: developer caches (each tool's standard location) ─────
  # Re-downloadable, but a full re-download/re-index costs time — so REVIEW.
  for d in "$HOME/Library/Developer/Xcode/"*" DeviceSupport"/*; do
    add_candidate REVIEW "$d" "Xcode device support · $(basename "$d")" "Re-copied from the device when it next connects" 1024
  done
  add_candidate REVIEW "$HOME/Library/Developer/Xcode/Archives" "Xcode · Archives"     "Old app builds — only needed to re-ship or symbolicate them" 1024
  add_candidate REVIEW "$HOME/.npm/_cacache"                    "npm cache"            "Re-downloaded on next install" 1024
  add_candidate REVIEW "$HOME/Library/pnpm/store"               "pnpm store"           "Re-downloaded on next install" 1024
  add_candidate REVIEW "$HOME/.gradle/caches"                   "Gradle caches"        "Re-downloaded on next build" 1024
  add_candidate REVIEW "$HOME/.m2/repository"                   "Maven repository"     "Re-downloaded on next build" 1024
  add_candidate REVIEW "$HOME/.cargo/registry"                  "Cargo registry"       "Re-downloaded on next build" 1024
  add_candidate REVIEW "$HOME/go/pkg/mod"                       "Go module cache"      "Re-downloaded on next build (same as go clean -modcache)" 1024
  add_candidate REVIEW "$HOME/.cocoapods/repos"                 "CocoaPods spec repos" "Re-cloned on next pod install" 1024

  # node_modules not touched for 90+ days, in project folders under $HOME
  # (Library and dot-folders pruned; nested node_modules never entered).
  local nm
  while IFS= read -r nm; do
    add_candidate REVIEW "$nm" "node_modules · $(basename "$(dirname "$nm")")" "Untouched 90+ days — npm install restores it" 10240
  done < <(find "$HOME" -maxdepth 6 \( -path "$HOME/Library" -o \( -name '.*' ! -path "$HOME" \) \) -prune \
              -o -type d -name node_modules -prune -mtime +90 -print 2>/dev/null)

  # ───── 🟡 REVIEW: old installers & firmware ─────
  local f
  while IFS= read -r f; do
    add_candidate REVIEW "$f" "Old download · $(basename "$f")" "Installer/archive, untouched 30+ days" 10240
  done < <(find "$HOME/Downloads" -maxdepth 2 -type f \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.zip' \
              -o -iname '*.iso' -o -iname '*.xip' \) -mtime +30 2>/dev/null)
  for f in "$HOME/Library/iTunes/"*" Software Updates"/*.ipsw; do
    add_candidate REVIEW "$f" "Device firmware · $(basename "$f")" "Re-downloaded if ever needed for a restore" 1024
  done

  # ── Size everything in one parallel pass, then apply each min size ──
  DU_PATHS=("${QP[@]}")
  _du_batch "candidates"
  local i
  for ((i=0; i<qn; i++)); do
    [ "${DU_KB[$i]:-0}" -ge "${QM[$i]}" ] && CANDIDATES+=("${QT[$i]}|${DU_KB[$i]}|${QP[$i]}|${QL[$i]}|${QN[$i]}")
  done
}

_wizard_list() {
  section "🟢 SAFE ITEMS"
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ "$tier" = "SAFE" ] && printf "  %-9s %-34s ${DIM}%s${RESET}\n" "$(color_size $(human_kb $kb))" "$label" "$note"
  done
  section "🟡 REVIEW ITEMS"
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ "$tier" = "REVIEW" ] && printf "  %-9s %-34s ${DIM}%s${RESET}\n" "$(color_size $(human_kb $kb))" "$label" "$note"
  done
  press_any_key
}

_wizard_auto_safe() {
  echo ""
  local total=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ "$tier" = "SAFE" ] && total=$((total+kb))
  done

  if ! confirm "Delete ALL 🟢 safe items ($(human_kb $total))? This is reversible-safe (apps rebuild them)"; then
    return
  fi

  # Caches of apps that are open right now are skipped: the app may crash,
  # or simply rewrite them a moment later.
  _running_snapshot
  echo ""
  local freed=0 got fails=0 busy="" busy_n=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ "$tier" = "SAFE" ] && [ -e "$path" ] || continue
    if _owner_running "$path"; then
      busy_n=$((busy_n+1))
      case "$busy" in *"$RUNNING_OWNER"*) ;; *) busy="${busy:+$busy, }$RUNNING_OWNER" ;; esac
      continue
    fi
    if got=$(_rm_tracked "$path" "$kb"); then
      success "$label ${DIM}($(human_kb $kb))${RESET}"
    else
      warning "$label — only partly removed ${DIM}(in use, or needs Full Disk Access)${RESET}"
      fails=$((fails+1))
    fi
    freed=$((freed+got))
  done
  echo ""
  divider
  echo -e "  ${BGREEN}✨ Done! Freed ${BYELLOW}${BOLD}$(human_kb $freed)${RESET}"
  [ "$fails" -gt 0 ] && warning "$fails item(s) could not be fully removed"
  [ "$busy_n" -gt 0 ] && info "Skipped $busy_n item(s) of running apps ($busy) — quit them and run the wizard again"
  divider
  _back_to_menu
}

_wizard_pick() {
  echo ""
  # Count total items to review
  local total_items=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ -e "$path" ] && total_items=$((total_items+1))
  done
  info "$total_items items to review — y = remove, Enter = keep"
  info "🟢 items are deleted; 🟡 items go to the Trash (undo with Finder → Put Back)"

  _running_snapshot
  local freed=0 trashed=0 item_num=0 got
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ ! -e "$path" ] && continue
    item_num=$((item_num+1))
    local tag="🟢"; [ "$tier" = "REVIEW" ] && tag="🟡"
    echo ""
    echo -e "  ${tag} [${item_num}/${total_items}] ${BOLD}${label}${RESET}  ${BOLD}$(color_size $(human_kb $kb))${RESET}"
    echo -e "     ${DIM}${note}${RESET}"
    echo -e "     ${DIM}${path}${RESET}"
    _owner_running "$path" && echo -e "     ${BYELLOW}⚠️  ${RUNNING_OWNER} is running — quit it first, or it may crash${RESET}"
    echo -ne "     ${BYELLOW}Remove? [y/N]: ${RESET}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      if [ "$tier" = "REVIEW" ]; then
        _remove_undoable "$path" "$kb" "$label"
        freed=$((freed+RM_FREED)); trashed=$((trashed+RM_TRASHED))
      elif got=$(_rm_tracked "$path" "$kb"); then
        success "Deleted ${DIM}($(human_kb $kb))${RESET}"
        freed=$((freed+got))
      else
        warning "Only partly removed ${DIM}($(human_kb $got) freed — in use, or needs Full Disk Access)${RESET}"
        freed=$((freed+got))
      fi
    else
      skipped "Kept"
    fi
  done
  echo ""
  divider
  echo -e "  ${BGREEN}✨ Total freed: ${BYELLOW}${BOLD}$(human_kb $freed)${RESET}"
  [ "$trashed" -gt 0 ] && info "$(human_kb $trashed) moved to the Trash — empty it to reclaim that space"
  divider
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   1) FULL AUDIT
# ══════════════════════════════════════════════════════════════
#   Read-only deep scan with a recommendations summary at the end
# ══════════════════════════════════════════════════════════════
full_audit() {
  clear
  echo -e "${BOLD}${BCYAN}📊 FULL STORAGE AUDIT${RESET} ${DIM}— $(date '+%Y-%m-%d %H:%M')${RESET}"
  divider

  section "💾 DISK OVERVIEW"
  df -h "$DATA_VOL" | awk 'NR==2 {printf "  Total:     %s\n  Used:      %s (%s)\n  Available: %s\n",$2,$3,$5,$4}'
  info "Tip: macOS may show extra 'purgeable' space not freed until needed"

  section "📁 HOME DIRECTORY — Top 25"
  du -sh ~/* ~/.[^.]* 2>/dev/null | sort -rh | head -25 | while read size path; do
    printf "  %-10s %s\n" "$(color_size $size)" "$(basename "$path")"
  done

  section "🧹 LIBRARY OVERVIEW"
  for folder in "Application Support" "Caches" "Containers" "Group Containers" "Developer" "Logs" "Mail"; do
    [ -d "$HOME/Library/$folder" ] && printf "  %-10s %s\n" "$(color_size $(du -sh "$HOME/Library/$folder" 2>/dev/null|cut -f1))" "$folder"
  done

  section "🤖 AI TOOLS"; _ai_tools_list

  section "📦 APP SUPPORT — Top 15"
  du -sh ~/Library/Application\ Support/*/ 2>/dev/null | sort -rh | head -15 | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done

  section "🗂️  GROUP CONTAINERS — Top 10"
  du -sh ~/Library/Group\ Containers/*/ 2>/dev/null | sort -rh | head -10 | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done

  section "🗑️  CACHES — Top 10"
  du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh | head -10 | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done

  section "📱 USER APPLICATIONS — Top 10"
  [ -d ~/Applications ] && du -sh ~/Applications/*/ 2>/dev/null | sort -rh | head -10 | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done

  section "⏱️  TIME MACHINE SNAPSHOTS"
  local snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -i snapshot)
  [ -z "$snaps" ] && success "No local snapshots" || echo "$snaps" | while read s; do warning "$s"; done

  section "💡 RECOMMENDATIONS"; _print_recommendations

  echo ""
  echo -e "  ${BGREEN}${BOLD}👉 Tip: use the Safe Cleanup Wizard (CLEAN menu) to free space safely.${RESET}"
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   8) QUICK CLEAN
# ══════════════════════════════════════════════════════════════
#   Deletes a fixed list of well-known safe cache/log paths
# ══════════════════════════════════════════════════════════════
quick_clean() {
  clear
  section "🧹 QUICK CLEAN — 100% Safe Items"
  info "Scanning caches and logs (skips protected data and running apps)..."
  echo ""

  # Pass 1: scan and build "kb|path|label" preview lines. Every path goes
  # through _wiz_protected(), same as the wizard.
  PREVIEW="" ; total_kb=0 ; QC_BUSY=""
  _running_snapshot
  _qc_scan() {
    local p="$1" l="$2"
    [ -e "$p" ] || return
    _wiz_protected "$p" && return
    if _owner_running "$p"; then   # open app: leave its cache alone
      case "$QC_BUSY" in *"$RUNNING_OWNER"*) ;; *) QC_BUSY="${QC_BUSY:+$QC_BUSY, }$RUNNING_OWNER" ;; esac
      return
    fi
    local kb=$(du -sk "$p" 2>/dev/null|cut -f1); kb=${kb:-0}
    [ "$kb" -gt 0 ] || return
    PREVIEW="${PREVIEW}${kb}|${p}|${l}"$'\n'
    total_kb=$((total_kb+kb))
  }
  # Cache/log roots child by child, so protected children (com.apple.*,
  # sync and messaging caches) are skipped instead of swept along.
  local d
  for d in ~/Library/Caches/*; do _qc_scan "$d" "App caches (~/Library/Caches)"; done
  for d in ~/Library/Logs/*;   do _qc_scan "$d" "Log files (~/Library/Logs)"; done
  _qc_scan ~/Library/Application\ Support/Claude/Cache               "Claude Cache"
  _qc_scan ~/Library/Application\ Support/Claude/Code\ Cache         "Claude Code Cache"
  _qc_scan ~/Library/Application\ Support/Claude/GPUCache            "Claude GPU Cache"
  _qc_scan ~/Library/Application\ Support/Claude/vm_bundles          "Claude VM Bundles"
  _qc_scan ~/Library/Application\ Support/Code/Cache                 "VSCode Cache"
  _qc_scan ~/Library/Application\ Support/Code/CachedData            "VSCode CachedData"
  _qc_scan ~/Library/Application\ Support/Code/logs                  "VSCode Logs"
  for d in ~/Library/Application\ Support/JetBrains/*/; do
    [ -d "${d}caches" ] && _qc_scan "${d}caches" "JetBrains $(basename "$d") caches"
    [ -d "${d}log" ]    && _qc_scan "${d}log"    "JetBrains $(basename "$d") logs"
  done
  _qc_scan ~/Library/Application\ Support/Spotify/PersistentCache    "Spotify Cache"
  _qc_scan ~/.Trash                                                  "Trash"

  [ -n "$QC_BUSY" ] && info "Skipping caches of running apps: $QC_BUSY ${DIM}(quit them to include)${RESET}"

  # Check if anything was found
  if [ "$total_kb" -eq 0 ]; then
    success "Nothing to clean — already tidy! 🎉"
    _back_to_menu
    return
  fi

  # Show preview
  # Preview is grouped by label (the Caches/Logs roots expand to many paths).
  section "Items to be deleted"
  printf '%s' "$PREVIEW" | awk -F'|' '
    NF>=3 { if (!($3 in s)) order[++n]=$3; s[$3]+=$1; c[$3]++ }
    END   { for (i=1;i<=n;i++) print s[order[i]] "|" order[i] "|" c[order[i]] }
  ' | while IFS='|' read -r kb label cnt; do
    local extra=""; [ "$cnt" -gt 1 ] && extra=" ${DIM}($cnt folders)${RESET}"
    printf "  %s %b\n" "$(_size_cell "$kb")" "$label$extra"
  done

  # Single confirmation
  echo ""; divider
  if ! confirm "Delete all of the above ($(human_kb $total_kb))? This is safe — apps rebuild these automatically."; then
    skipped "Nothing deleted"
    _back_to_menu
    return
  fi

  # Pass 2: Delete and report
  echo ""
  local freed_kb=0 got fails=0
  while IFS='|' read -r kb path label; do
    [ -z "$kb" ] && continue
    if [ -e "$path" ]; then
      got=$(_rm_tracked "$path" "$kb") || fails=$((fails+1))
      freed_kb=$((freed_kb+got))
    fi
  done <<< "$PREVIEW"

  echo ""; divider
  echo -e "  ${BGREEN}✨ Freed approximately ${BYELLOW}${BOLD}$(human_kb $freed_kb)${RESET}"
  [ "$fails" -gt 0 ] && warning "$fails folder(s) could not be fully removed (in use, or needs Full Disk Access)"
  divider
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   9) INTERACTIVE CLEAN
# ══════════════════════════════════════════════════════════════
#   Broader/more aggressive than the wizard—offers IDEs, LM Studio models, VSCode extensions one-by-one
# ══════════════════════════════════════════════════════════════
# Per-item "remove X?" used by the REVIEW-type screens (models, IDEs,
# extensions, device backups). Items go to the Trash, so they can be put
# back; TOTAL_FREED collects a summary line per item.
TOTAL_FREED=""; TOTAL_TRASHED_KB=0
safe_delete() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    local kb; kb=$(du -sk "$path" 2>/dev/null | cut -f1); kb=${kb:-0}
    if confirm "Remove ${label} ($(human_kb "$kb"))? It goes to the Trash"; then
      if _remove_undoable "$path" "$kb" "$label"; then
        local where=""; [ "$RM_TRASHED" -gt 0 ] && where=" (in Trash)"
        TOTAL_FREED="${TOTAL_FREED}$(human_kb "$kb") ← ${label}${where}\n"
        TOTAL_TRASHED_KB=$((TOTAL_TRASHED_KB+RM_TRASHED))
      fi
    else skipped "Skipped ${label}"; fi
  fi
}
interactive_clean() {
  TOTAL_FREED=""; TOTAL_TRASHED_KB=0   # summary below is for this run only
  clear
  section "🎯 INTERACTIVE CLEAN"
  info "Asks before each deletion. Includes apps & models (more aggressive than the wizard)."
  echo ""

  local item_num=0
  if [ -d ~/.lmstudio/models ]; then
    echo -e "\n  ${BOLD}🧠 LM Studio Models:${RESET}"
    for m in ~/.lmstudio/models/*/; do
      [ -d "$m" ] || continue
      item_num=$((item_num+1))
      echo -ne "  [${item_num}] "
      safe_delete "$m" "LM Studio: $(basename "$m")"
    done
  fi
  if [ -d ~/Applications ]; then
    echo -e "\n  ${BOLD}🛠️  IDEs (~/Applications):${RESET}"
    for a in ~/Applications/*.app; do
      [ -d "$a" ] || continue
      item_num=$((item_num+1))
      echo -ne "  [${item_num}] "
      safe_delete "$a" "IDE: $(basename "$a")"
    done
  fi
  if [ -d ~/.lmstudio/extensions ]; then
    item_num=$((item_num+1))
    echo -ne "  [${item_num}] "
    safe_delete ~/.lmstudio/extensions "LM Studio Extensions"
  fi
  if [ -d ~/.vscode/extensions ]; then
    echo -e "\n  ${BOLD}🔌 VSCode Extensions:${RESET}"
    for e in ~/.vscode/extensions/*/; do
      [ -d "$e" ] || continue
      item_num=$((item_num+1))
      echo -ne "  [${item_num}] "
      safe_delete "$e" "ext: $(basename "$e")"
    done
  fi
  echo ""; divider
  if [ -n "$TOTAL_FREED" ]; then
    echo -e "  ${BGREEN}✨ Removed:${RESET}"; printf "$TOTAL_FREED" | while read -r l; do [ -n "$l" ] && echo -e "    ${GREEN}• $l${RESET}"; done
    [ "$TOTAL_TRASHED_KB" -gt 0 ] && info "$(human_kb "$TOTAL_TRASHED_KB") is in the Trash — empty it to reclaim the space"
  else info "Nothing removed."; fi
  divider; _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   5) AI TOOLS AUDIT
# ══════════════════════════════════════════════════════════════
#   Lists AI IDE/tool footprints (read-only)
# ══════════════════════════════════════════════════════════════
ai_tools_audit() {
  clear
  section "🤖 AI TOOLS — Dot-folders"; _ai_tools_list
  section "App Support data"
  for t in Claude Cursor Windsurf Trae Codeium Antigravity Comet Continue Aider Qwen; do
    [ -d "$HOME/Library/Application Support/$t" ] && \
      printf "  %-10s %s\n" "$(color_size $(du -sh "$HOME/Library/Application Support/$t" 2>/dev/null|cut -f1))" "$t"
  done
  section "💡 Tips"
  info "Each AI IDE keeps its own models/extensions/index caches"
  info "Keep 1-2 IDEs; uninstall the rest via their uninstallers"
  info "VSCode: 'code --list-extensions' to review"
  _back_to_menu
}
_ai_tools_list() {
  local T=(
    "$HOME/.lmstudio:LM Studio" "$HOME/.vscode:VSCode" "$HOME/.cursor:Cursor"
    "$HOME/.windsurf:Windsurf" "$HOME/.trae:Trae" "$HOME/.antigravity:Antigravity"
    "$HOME/.codeium:Codeium" "$HOME/.lingma:Lingma" "$HOME/.codex:Codex"
    "$HOME/.gemini:Gemini CLI" "$HOME/.claude:Claude CLI" "$HOME/.continue:Continue"
    "$HOME/.aider:Aider" "$HOME/.wallaby:Wallaby"
  )
  for e in "${T[@]}"; do
    local p="${e%%:*}" l="${e##*:}"
    if [ -d "$p" ]; then printf "  %-10s %s\n" "$(color_size $(du -sh "$p" 2>/dev/null|cut -f1))" "$l  ${DIM}($p)${RESET}"
    else echo -e "  ${DIM}──         $l — not found${RESET}"; fi
  done
}

# ══════════════════════════════════════════════════════════════
#   6) APP SUPPORT DEEP DIVE
# ══════════════════════════════════════════════════════════════
#   Drill-down into ~/Library/Application Support, Group Containers, JetBrains (read-only)
# ══════════════════════════════════════════════════════════════
app_support_deep() {
  clear
  section "📦 APPLICATION SUPPORT — Top 25"
  du -sh ~/Library/Application\ Support/*/ 2>/dev/null | sort -rh | head -25 | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done
  section "🗂️  GROUP CONTAINERS — Full"
  du -sh ~/Library/Group\ Containers/*/ 2>/dev/null | sort -rh | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done
  section "📊 JETBRAINS DETAIL"
  du -sh ~/Library/Application\ Support/JetBrains/*/ 2>/dev/null | sort -rh | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   13) LM STUDIO MANAGER
# ══════════════════════════════════════════════════════════════
#   LM Studio model/extension inventory + optional deletion
# ══════════════════════════════════════════════════════════════
lmstudio_manager() {
  clear
  section "🧠 LM STUDIO MODEL MANAGER"
  [ ! -d ~/.lmstudio ] && { info "LM Studio not found."; _back_to_menu; return; }
  echo -e "  Total: ${BRED}${BOLD}$(du -sh ~/.lmstudio 2>/dev/null|cut -f1)${RESET}\n"
  section "Models"
  [ -d ~/.lmstudio/models ] && du -sh ~/.lmstudio/models/*/ 2>/dev/null | sort -rh | \
    while read s p; do
      printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"
      du -sh "$p"/*/ 2>/dev/null | sort -rh | while read s2 p2; do printf "    %-8s %s\n" "$(color_size $s2)" "$(basename "$p2")"; done
    done
  section "Extensions"
  [ -d ~/.lmstudio/extensions ] && du -sh ~/.lmstudio/extensions/*/ 2>/dev/null | sort -rh | \
    while read s p; do printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"; done
  echo ""; info "Models re-download anytime from the catalog"
  if confirm "Start interactive model deletion?"; then
    local model_num=0
    for m in ~/.lmstudio/models/*/; do
      [ -d "$m" ] || continue
      model_num=$((model_num+1))
      echo -ne "  [${model_num}] "
      safe_delete "$m" "Model: $(basename "$m")"
    done
  fi
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   14) OLLAMA MANAGER
# ══════════════════════════════════════════════════════════════
#   Ollama model inventory + optional deletion
# ══════════════════════════════════════════════════════════════
ollama_manager() {
  clear
  section "🦙 OLLAMA MODEL MANAGER"
  [ ! -d ~/.ollama ] && { info "Ollama not found."; _back_to_menu; return; }
  echo -e "  Total: ${BRED}${BOLD}$(du -sh ~/.ollama 2>/dev/null|cut -f1)${RESET}\n"
  section "Directory Breakdown"
  du -sh ~/.ollama/*/ 2>/dev/null | sort -rh | while read s p; do
    printf "  %-10s %s\n" "$(color_size $s)" "$(basename "$p")"
  done
  if command -v ollama >/dev/null 2>&1; then
    echo ""
    section "Installed Models (ollama list)"
    local models=$(ollama list 2>/dev/null | tail -n +2)
    if [ -z "$models" ]; then
      info "No models installed"
    else
      echo "$models" | while read -r name id size unit modified; do
        printf "  %-30s %-10s %s\n" "$name" "$size $unit" "$modified"
      done
    fi
  fi
  echo ""; info "Models re-download anytime via: ollama pull <model>"
  if command -v ollama >/dev/null 2>&1 && confirm "Start interactive model deletion (asks per model)?"; then
    # Read the list first: confirm() reads stdin, so it can't sit inside a
    # `ollama list | while read` pipe (it would eat the model list).
    local -a o_names o_sizes
    local name id size unit rest k=0
    while read -r name id size unit rest; do
      [ -z "$name" ] && continue
      o_names[$k]="$name"; o_sizes[$k]="$size $unit"; k=$((k+1))
    done < <(ollama list 2>/dev/null | tail -n +2)
    for ((k=0; k<${#o_names[@]}; k++)); do
      if confirm "Remove model ${o_names[$k]} (${o_sizes[$k]})?"; then
        if _dry_block "ollama rm ${o_names[$k]}"; then :
        elif ollama rm "${o_names[$k]}" >/dev/null 2>&1; then
          success "Removed ${o_names[$k]}"
        else
          danger "Could not remove ${o_names[$k]} (is the Ollama server running?)"
        fi
      else
        skipped "Kept ${o_names[$k]}"
      fi
    done
  fi
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   4) CLOUD & SYNC AUDIT
# ══════════════════════════════════════════════════════════════
#   Read-only, reports OneDrive/iCloud/Dropbox/WhatsApp/Telegram size — never offers to delete these
# ══════════════════════════════════════════════════════════════
cloud_audit() {
  clear
  section "☁️  CLOUD & SYNC AUDIT"
  echo -e "  ${DIM}These hold your real files — handle via each app, not by deleting folders.${RESET}"
  local od="$HOME/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite"
  section "OneDrive"
  [ -d "$od" ] && { danger "OneDrive local: $(du -sh "$od" 2>/dev/null|cut -f1)"; \
    info "Enable Files On-Demand → menu bar → Settings → 'Free up space'"; } || success "Not found"
  section "WhatsApp"
  local wa="$HOME/Library/Group Containers/group.net.whatsapp.WhatsApp.shared"
  [ -d "$wa" ] && { warning "WhatsApp data: $(du -sh "$wa" 2>/dev/null|cut -f1)"; \
    info "Clear inside app: Settings → Storage and Data → Manage Storage"; } || skipped "Not found"
  section "iCloud Drive"
  local ic="$HOME/Library/Mobile Documents"
  [ -d "$ic" ] && warning "iCloud local: $(du -sh "$ic" 2>/dev/null|cut -f1)" || success "No local data"
  section "Google Drive"
  local gd_found=0
  if [ -d "$HOME/Library/Application Support/Google/DriveFS" ]; then
    warning "Google Drive (DriveFS): $(du -sh "$HOME/Library/Application Support/Google/DriveFS" 2>/dev/null|cut -f1)"
    gd_found=1
  fi
  for gd in "$HOME/Library/CloudStorage/GoogleDrive-"*; do
    [ -d "$gd" ] && { warning "Google Drive (CloudStorage): $(du -sh "$gd" 2>/dev/null|cut -f1)"; gd_found=1; }
  done
  [ "$gd_found" -eq 0 ] && success "Not found"
  section "Dropbox"
  local db="$HOME/Dropbox"
  [ -d "$db" ] && { warning "Dropbox local: $(du -sh "$db" 2>/dev/null|cut -f1)"; \
    info "Manage via Dropbox Settings"; } || success "Not found"
  section "Telegram"
  local tg="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
  [ -d "$tg" ] && warning "Telegram: $(du -sh "$tg" 2>/dev/null|cut -f1)" || skipped "Not found"
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   15) SAVE REPORT TO FILE
# ══════════════════════════════════════════════════════════════
#   Dumps a plain-text snapshot to ~/storage_report_<timestamp>.txt
# ══════════════════════════════════════════════════════════════
save_report() {
  local REPORT_FILE="$HOME/storage_report_$(date '+%Y%m%d_%H%M%S').txt"
  clear; section "📝 SAVING FULL REPORT"; info "→ $REPORT_FILE"; echo ""
  {
    echo "MAC STORAGE REPORT — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname) | macOS: $(sw_vers -productVersion)"
    echo "================================================"
    echo ""; echo "DISK"; df -h "$DATA_VOL"
    echo ""; echo "HOME — Top 30"; du -sh ~/* ~/.[^.]* 2>/dev/null | sort -rh | head -30
    echo ""; echo "LIBRARY"
    for f in "Application Support" Caches Containers "Group Containers" Developer Logs; do
      [ -d "$HOME/Library/$f" ] && printf "  %-8s  %s\n" "$(du -sh "$HOME/Library/$f" 2>/dev/null|cut -f1)" "$f"
    done
    echo ""; echo "APP SUPPORT"; du -sh ~/Library/Application\ Support/*/ 2>/dev/null | sort -rh
    echo ""; echo "GROUP CONTAINERS"; du -sh ~/Library/Group\ Containers/*/ 2>/dev/null | sort -rh
    echo ""; echo "CACHES"; du -sh ~/Library/Caches/*/ 2>/dev/null | sort -rh
    echo ""; echo "USER APPS"; [ -d ~/Applications ] && du -sh ~/Applications/*/ 2>/dev/null | sort -rh
    echo ""; echo "LM STUDIO MODELS"; [ -d ~/.lmstudio/models ] && du -sh ~/.lmstudio/models/*/ 2>/dev/null | sort -rh
    echo ""; echo "OLLAMA MODELS"; [ -d ~/.ollama/models ] && du -sh ~/.ollama/models/blobs/* 2>/dev/null | sort -rh
  } > "$REPORT_FILE"
  success "Saved: ${BYELLOW}$REPORT_FILE${RESET}"; info "Open with: open $REPORT_FILE"
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   3) FIND LARGE FILES
# ══════════════════════════════════════════════════════════════
#   Find-based search by minimum file size, user-supplied (read-only)
# ══════════════════════════════════════════════════════════════
find_large_files() {
  clear; section "🔍 FIND LARGE FILES"
  echo -ne "  ${BCYAN}Minimum size? ${RESET}${DIM}(e.g. 200M, 500M, 1G) [500M]: ${RESET}"; read -r ms; ms=${ms:-500M}
  local mb
  ms=$(echo "$ms" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  if   [[ "$ms" =~ ^([0-9]+)G$ ]];     then mb=$(( BASH_REMATCH[1] * 1024 ))
  elif [[ "$ms" =~ ^([0-9]+)M?$ ]];    then mb=${BASH_REMATCH[1]}
  else warning "Not a size: '$ms' — use a number with M or G, e.g. 500M"; _back_to_menu; return; fi
  [ "$mb" -lt 1 ] && mb=1
  echo ""; info "Scanning for files > ${BYELLOW}${ms}${RESET}... (a moment)"; echo ""
  # Sort on raw size first, color last (sorting colored text scrambles the
  # order). stat's apparent size matches what `find -size` filtered on; du
  # would show the allocated size, which is tiny for sparse files.
  local found=0 b f
  while IFS=$'\t' read -r b f; do
    [ -z "$b" ] && continue
    printf "  %s %s\n" "$(_size_cell $(( b / 1024 )))" "$f"; found=$((found+1))
  done < <(find ~ -type f -size +"${mb}"M -exec stat -f '%z%t%N' {} + 2>/dev/null | sort -rn | head -30)
  echo ""
  if [ "$found" -eq 0 ]; then info "No files larger than ${ms} found."; else info "Top $found shown, largest first."; fi
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   2) STORAGE VISUALIZER
# ══════════════════════════════════════════════════════════════
#   Read-only: bar / pie of top consumers
# ══════════════════════════════════════════════════════════════
# Builds a ranked "kb\tlabel" list (top 9 + a synthesized "Other" row)
# so both renderers below share one dataset. Written to a temp file
# since Bash 3.2 has no associative arrays.
_viz_collect() {
  local tmp; _mktemp tmp || return
  { du -sk ~/* ~/.[^.]* 2>/dev/null; [ -d /Applications ] && du -sk /Applications 2>/dev/null; } | \
    awk -F'\t' '{n=split($2,parts,"/"); print $1"\t"parts[n]}' | sort -rn > "$tmp"

  local total_kb; total_kb=$(awk -F'\t' '{s+=$1} END{print s+0}' "$tmp")
  awk -F'\t' -v total="$total_kb" '
    NR<=9 { print; kept+=$1; next }
    { other+=$1 }
    END { if (other>0) print other"\tOther" }
  ' "$tmp"
  rm -f "$tmp"
}

_viz_bar_chart() {
  local data="$1" total_kb="$2"
  local max_width=40
  echo "$data" | while IFS=$'\t' read -r kb label; do
    [ -z "$kb" ] && continue
    local pct bar_len i bar=""
    pct=$(awk -v k="$kb" -v t="$total_kb" 'BEGIN{ if(t>0) printf "%.1f", k*100/t; else print "0.0" }')
    bar_len=$(awk -v k="$kb" -v t="$total_kb" -v w="$max_width" 'BEGIN{ if(t>0){v=k*w/t; if(v<1 && k>0)v=1; printf "%d", v} else print 0 }')
    for ((i=0;i<bar_len;i++)); do bar+="█"; done
    for ((i=bar_len;i<max_width;i++)); do bar+="░"; done
    local sizecolor="${DIM}"
    if   awk -v p="$pct" 'BEGIN{exit !(p>=20)}'; then sizecolor="${BRED}${BOLD}"
    elif awk -v p="$pct" 'BEGIN{exit !(p>=8)}';  then sizecolor="${BYELLOW}"
    else sizecolor="${CYAN}"; fi
    printf "  %-22.22s ${sizecolor}%-9s${RESET} ${sizecolor}%s${RESET} %5s%%\n" "$label" "$(human_kb "$kb")" "$bar" "$pct"
  done
}

_viz_pie_chart() {
  local data="$1" total_kb="$2"
  local palette_chars=('█' '▓' '▒' '░' '●' '◆' '▲' '■' '◇' '○')
  local palette_colors=("${BRED}" "${BYELLOW}" "${BGREEN}" "${BCYAN}" "${BMAGENTA}" "${BBLUE}" "${RED}" "${YELLOW}" "${GREEN}" "${CYAN}")

  local labels=() kbs=() pcts=()
  local idx=0 cum=0
  while IFS=$'\t' read -r kb label; do
    [ -z "$kb" ] && continue
    labels[$idx]="$label"; kbs[$idx]="$kb"
    idx=$((idx+1))
  done <<< "$data"
  local n=$idx

  # Cumulative percentage boundaries, computed once in one awk pass.
  local bounds; bounds=$(
    printf '%s\n' "${kbs[@]}" | awk -v t="$total_kb" '
      { c+=$1; if(t>0) printf "%.4f\n", c*100/t; else print "0" }
    '
  )
  local i=0
  while read -r b; do pcts[$i]="$b"; i=$((i+1)); done <<< "$bounds"

  echo ""
  # Whole disc in ONE awk run (it used to start awk once per cell: 392
  # processes). Colors/chars go in as "|"-joined lists; awk -v turns the
  # \033 in the color vars into real escape bytes.
  local rows=14 cols=28 IFS_OLD="$IFS"
  local colors chars
  IFS='|'; colors="${palette_colors[*]}"; chars="${palette_chars[*]}"; IFS="$IFS_OLD"
  awk -v cols="$cols" -v rows="$rows" -v n="$n" -v boundstr="$(printf '%s ' "${pcts[@]}")" \
      -v colors="$colors" -v chars="$chars" -v reset="$RESET" '
    BEGIN {
      pi = 3.14159265358979
      split(boundstr, b, " "); split(colors, C, "|"); split(chars, H, "|")
      cx = (cols-1)/2.0; cy = (rows-1)/2.0
      for (y = 0; y < rows; y++) {
        line = "  "
        for (x = 0; x < cols; x++) {
          dx = (x-cx)/(cols/2.0); dy = (y-cy)/(rows/2.0)
          if (sqrt(dx*dx+dy*dy) > 1.0) { line = line " "; continue }
          ang = atan2(-dy, dx)*180/pi; if (ang < 0) ang += 360
          pct = ang/360*100; k = n
          for (j = 1; j <= n; j++) if (pct <= b[j]) { k = j; break }
          line = line C[k] H[k] reset
        }
        print line
      }
    }'
  echo ""
  for ((i=0; i<n; i++)); do
    local pct_disp
    pct_disp=$(awk -v k="${kbs[$i]}" -v t="$total_kb" 'BEGIN{ if(t>0) printf "%.1f", k*100/t; else print "0.0" }')
    printf "  ${palette_colors[$i]}%s${RESET} %-22.22s %-9s %5s%%\n" "${palette_chars[$i]}" "${labels[$i]}" "$(human_kb "${kbs[$i]}")" "$pct_disp"
  done
}

storage_visualizer() {
  local data total_kb
  clear; section "📊 STORAGE VISUALIZER"
  info "Scanning home directory and /Applications for top consumers..."
  data=$(_viz_collect)
  data=$(echo "$data" | tail -r)
  total_kb=$(echo "$data" | awk -F'\t' '{s+=$1} END{print s+0}')

  local loop=1
  while [ "$loop" -eq 1 ]; do
    clear; section "📊 STORAGE VISUALIZER"
    echo -e "  ${BOLD}Total scanned:${RESET} $(human_kb "$total_kb")"
    echo ""
    echo -e "  ${BOLD}1)${RESET} 📶  Bar chart   ${DIM}proportional treemap-style bars${RESET}"
    echo -e "  ${BOLD}2)${RESET} 🥧  Pie chart   ${DIM}ASCII circular breakdown${RESET}"
    echo -e "  ${BOLD}b)${RESET} ⬅️   Back to main menu"
    ask_choice "[1]  [2]  [b]ack"
    read -r vchoice
    case "$vchoice" in
      1) clear; section "📶 BAR CHART — Top Space Consumers"; _viz_bar_chart "$data" "$total_kb"; echo ""; press_any_key ;;
      2) clear; section "🥧 PIE CHART — Top Space Consumers"; _viz_pie_chart "$data" "$total_kb"; press_any_key ;;
      b|B|q|Q|0) loop=0 ;;
      *) warning "Invalid option — try one of the keys shown"; sleep 1 ;;
    esac
  done
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   RECOMMENDATIONS ENGINE
# ══════════════════════════════════════════════════════════════
_print_recommendations() {
  local found=0
  local cache_kb=$(du -sk ~/Library/Caches 2>/dev/null|cut -f1)
  [ "${cache_kb:-0}" -gt 500000 ] 2>/dev/null && { danger "Caches: $(du -sh ~/Library/Caches 2>/dev/null|cut -f1) — run wizard"; found=1; }
  [ -d ~/Library/Caches/JetBrains ] && { danger "JetBrains cache: $(du -sh ~/Library/Caches/JetBrains 2>/dev/null|cut -f1) — safe to clear"; found=1; }
  local ide=0; [ -d ~/Applications ] && ide=$(ls -d ~/Applications/*.app 2>/dev/null|wc -l|tr -d ' ')
  [ "$ide" -gt 3 ] && { warning "${ide} IDEs in ~/Applications ($(du -sh ~/Applications 2>/dev/null|cut -f1)) — uninstall unused"; found=1; }
  [ -d "$HOME/Library/Group Containers/UBF8T346G9.OneDriveSyncClientSuite" ] && { warning "OneDrive local data — use Files On-Demand"; found=1; }
  [ -d ~/.lmstudio/models ] && { info "LM Studio models: $(du -sh ~/.lmstudio/models 2>/dev/null|cut -f1) — use the LM Studio manager"; found=1; }
  [ -d ~/.ollama/models ] && { info "Ollama models: $(du -sh ~/.ollama/models 2>/dev/null|cut -f1) — use the Ollama manager"; found=1; }
  # Tool-managed stores: never rm these directly, point at the tool instead.
  local dk="$HOME/Library/Containers/com.docker.docker/Data/vms"
  [ -d "$dk" ] && { info "Docker VM disk: $(du -sh "$dk" 2>/dev/null|cut -f1) — reclaim with 'docker system prune' (never delete the file)"; found=1; }
  local sims="$HOME/Library/Developer/CoreSimulator/Devices"
  [ -d "$sims" ] && command -v xcrun >/dev/null 2>&1 && \
    { info "iOS simulators: $(du -sh "$sims" 2>/dev/null|cut -f1) — 'xcrun simctl delete unavailable' removes outdated ones"; found=1; }
  [ "$found" -eq 0 ] && success "Looks clean! 🎉"
}

# Waits for a key, then returns — the caller returns into main_menu's loop.
_back_to_menu() { echo ""; echo -ne "  ${DIM}Press any key to return to menu...${RESET}"; read -rn1; }

# ══════════════════════════════════════════════════════════════
#   16) GENERATE FEEDBACK FILE FOR CLAUDE CODE
# ══════════════════════════════════════════════════════════════
#
#   Produces a single structured Markdown file engineered to be fed
#   to Claude Code (Opus). Its purpose: give the model everything it
#   needs to improve THIS script's ability to (1) detect deletable
#   files dynamically and (2) detect every installed program and map
#   it to its data/cache folders.
#
generate_feedback() {
  clear
  section "🧬 GENERATE FEEDBACK FILE FOR CLAUDE CODE"
  local FB="$HOME/claude_code_feedback_$(date '+%Y%m%d_%H%M%S').md"
  info "Collecting deep diagnostics — this can take 30-60s (system_profiler is slow)..."
  echo ""

  step() { echo -e "  ${CYAN}▸ $1${RESET}"; }

  # ---- helpers used only here ----------------------------------
  _bid() { plutil -extract CFBundleIdentifier raw "$1/Contents/Info.plist" 2>/dev/null; }
  _ver() { plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null; }

  # Build authoritative lists of installed apps (names + bundle ids),
  # plus a SEGMENT set used for precise matching (tokens >=4 chars only).
  step "Indexing installed applications..."
  local APP_NAMES=() APP_BIDS=()
  local SEG=" "   # space-delimited set of distinctive tokens (len>=4)
  _add_seg() { local t="$1"; [ ${#t} -ge 4 ] || return; case "$SEG" in *" $t "*) ;; *) SEG="$SEG$t " ;; esac; }
  for base in /Applications "$HOME/Applications" /System/Applications /Applications/Utilities; do
    [ -d "$base" ] || continue
    for app in "$base"/*.app; do
      [ -d "$app" ] || continue
      local nm=$(basename "$app" .app | tr '[:upper:]' '[:lower:]')
      APP_NAMES+=("$nm")
      # app-name tokens (split on space/punct)
      for t in $(echo "$nm" | tr -cs 'a-z0-9' ' '); do _add_seg "$t"; done
      local b=$(_bid "$app" | tr '[:upper:]' '[:lower:]')
      [ -n "$b" ] && { APP_BIDS+=("$b"); for t in $(echo "$b" | tr '.' ' '); do _add_seg "$t"; done; }
    done
  done

  # Classify a Library subfolder name. Returns:
  #   APPLE-SYSTEM  → com.apple.* (never deletable; OS-owned)
  #   MATCHED (...) → a confidently-installed third-party app owns it
  #   ORPHAN?       → no installed app matched (informational only)
  # Matching is SEGMENT-EXACT (>=4 chars) to avoid the old substring noise
  # (e.g. R.app/name "r" no longer matches everything; "go"/"arc" excluded).
  _match_folder() {
    local f=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    case "$f" in com.apple.*|group.com.apple.*) echo "APPLE-SYSTEM"; return ;; esac
    # exact bundle-id equality
    for b in "${APP_BIDS[@]}"; do [ "$b" = "$f" ] && { echo "MATCHED ($b)"; return; }; done
    # strip team-id (10 alnum) / reverse-dns / group prefixes, then test each segment
    local stripped=$(echo "$f" | sed -E 's/^[a-z0-9]{10}\.//; s/^(group|com|org|net|io|ai|im|md|dev)\.//')
    for tok in $(echo "$stripped" | tr -cs 'a-z0-9' ' '); do
      [ ${#tok} -ge 4 ] || continue
      case "$SEG" in *" $tok "*) echo "MATCHED (seg:$tok)"; return ;; esac
    done
    echo "ORPHAN?"
  }

  # ---- write file: header + instructions -----------------------
  step "Writing header & instructions..."
  {
    echo "# CLAUDE CODE FEEDBACK FILE"
    echo "## storage_check.sh — diagnostic dump for script improvement"
    echo ""
    echo "- Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- Host: $(hostname)"
    echo "- Generator: storage_check.sh v3.8"
    echo ""
    echo "---"
    echo ""
    echo "## 0. INSTRUCTIONS FOR CLAUDE CODE (the improver)"
    echo ""
    echo "You are improving the bash tool \`storage_check.sh\`. Use the data below to make it better at TWO things:"
    echo ""
    echo "1. **Detect deletable files dynamically.** The Safe Cleanup Wizard (\`safe_wizard\`) is pattern-based (section 2b)."
    echo "   Improve its rules so they work on ANY Mac by reasoning from sections 4-6:"
    echo "   classify each Library subfolder as SAFE (cache/log/updater/orphan), REVIEW (re-downloadable), or"
    echo "   PROTECTED (user data / sync / installed-app config)."
    echo "2. **Detect every installed program and map it to its data folders.** Use sections 3 and 5 to build a"
    echo "   robust app->folder map so the wizard can confidently flag *orphaned* leftovers (data whose owning"
    echo "   app is no longer installed) as safe to remove."
    echo ""
    echo "**Concrete asks:**"
    echo "- Improve the \`_match_folder\` heuristic (section 2a) using the MATCHED/ORPHAN results in section 5."
    echo "  Note false positives (real app data flagged ORPHAN) and false negatives (orphan flagged MATCHED)."
    echo "- Propose SAFE-by-pattern rules (folder names ending in \`-updater\`, \`Cache\`, \`/logs\`, \`/Crashpad\`,"
    echo "  \`Code Cache\`, \`GPUCache\`, \`Service Worker/CacheStorage\`, etc.)."
    echo "- Flag anything in section 6 (large + unclassified) worth adopting, and state which tier."
    echo "- Keep PROTECTED conservative: never propose deleting sync data (OneDrive/iCloud/Dropbox/Google Drive),"
    echo "  messaging stores (WhatsApp/Telegram), Photos, Mail, Keychains, or app *settings/preferences*."
    echo "- Output a unified diff or full updated function bodies, plus a short changelog."
    echo ""
    echo "**Privacy note:** this file lists folder and app names from this Mac. Review before sharing."
    echo ""
    echo "---"
    echo ""
    echo "## 1. ENVIRONMENT"
    echo '```'
    echo "macOS: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "Model: $(sysctl -n hw.model 2>/dev/null)"
    echo "Chip:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
    echo "RAM:   $(( $(sysctl -n hw.memsize 2>/dev/null) / 1073741824 )) GB"
    echo "Shell: $SHELL  |  Bash: $BASH_VERSION"
    echo '```'
    echo "### Disk (df)"
    echo '```'
    df -h "$DATA_VOL"
    echo '```'
    echo "### APFS layout & purgeable space"
    echo '```'
    diskutil apfs list 2>/dev/null | grep -E "Container|Volume|Capacity|Used|Snapshot" | head -40
    echo "--- purgeable ---"
    diskutil info / 2>/dev/null | grep -iE "free|purgeable|available"
    echo '```'
  } > "$FB"

  # ---- current rules -------------------------------------------
  step "Dumping current script classification rules..."
  {
    echo ""; echo "---"; echo ""
    echo "## 2. CURRENT SCRIPT RULES (context for the improver)"
    echo ""
    echo "### 2a. Current \`_match_folder\` heuristic (informational only — never drives deletion)"
    echo '```'
    echo "lowercase the folder name, then:"
    echo " 1) com.apple.* / group.com.apple.* => APPLE-SYSTEM"
    echo " 2) exact equality with an installed bundle id => MATCHED"
    echo " 3) strip a 10-char team-id prefix and one reverse-dns prefix (group/com/org/net/io/ai/im/md/dev),"
    echo "    split into tokens; any token >=4 chars that equals a token of an installed app name or bundle id"
    echo "    => MATCHED (segment match, never substring)"
    echo " 4) else => ORPHAN?"
    echo '```'
    echo "### 2b. Wizard SAFE rules (pattern-based)"
    echo '```'
    echo "~/Library/Caches/*, ~/Library/Logs/*, ~/Library/Saved Application State/* — each child >=1MB, one by one"
    echo "  (children named *updater* / *.ShipIt are labelled as updater payloads)"
    echo "~/.Trash ; Xcode DerivedData ; CoreSimulator/Caches"
    echo "find ~/Library/Application Support + ~/Library/Containers, maxdepth 5, -prune at match, >=1MB:"
    echo "  dir names Cache, Caches, Code Cache, *Cache, CachedData, CachedExtensionVSIXs, logs, Crashpad, tmp"
    echo "Every candidate passes _wiz_protected() first (see 2d)."
    echo '```'
    echo "### 2c. Wizard REVIEW rules"
    echo '```'
    echo "~/.cache ; ~/.vscode/extensions ; ~/.lmstudio/extensions ; ~/.lmstudio/models/* (per model)"
    echo "~/Applications/*.app (not symlinks) ; dot-folder leftovers ~/.cursor .windsurf .trae .codeium"
    echo "  .antigravity .comet .manus .qwen .wispr .ollama — only if neither a matching .app nor CLI exists"
    echo '```'
    echo "### 2d. PROTECTED (_wiz_protected, case-insensitive substring on full path) — keep & expand"
    echo '```'
    echo "*/com.apple.*, */group.com.apple.* ; OneDrive, Dropbox, Google Drive (incl. DriveFS), CloudStorage,"
    echo "iCloud (Mobile Documents, CloudDocs), CloudKit, Box, pCloud, Nextcloud, Synology, MEGA ;"
    echo "WhatsApp, Telegram ; Mail, Keychains, Photos ; Office (UBF8T346G9.Office) / Outlook"
    echo "Out of scope by construction (never scanned): Documents, Desktop, Pictures, Movies, Preferences"
    echo '```'
  } >> "$FB"

  # ---- installed apps ------------------------------------------
  step "Inventorying installed applications (system_profiler)..."
  {
    echo ""; echo "---"; echo ""
    echo "## 3. INSTALLED APPLICATIONS"
    echo ""
    echo "### 3a. Authoritative (system_profiler): name | version | source | path"
    echo '```'
    system_profiler SPApplicationsDataType 2>/dev/null | awk '
      /^    [A-Za-z0-9].*:$/ {name=$0; sub(/:$/,"",name); gsub(/^ +/,"",name)}
      /Version:/ {v=$2}
      /Obtained from:/ {src=$3; for(i=4;i<=NF;i++) src=src" "$i}
      /Location:/ {loc=$0; sub(/.*Location: /,"",loc); printf "%-32s | %-12s | %-14s | %s\n", name, v, src, loc; v="";src="";loc=""}
    ' | sort
    echo '```'
    echo "### 3b. /Applications & ~/Applications: name | bundleID | version | size"
    echo '```'
    for base in /Applications "$HOME/Applications"; do
      [ -d "$base" ] || continue
      echo "## $base"
      for app in "$base"/*.app; do
        [ -d "$app" ] || continue
        printf "%-30s | %-40s | %-10s | %s\n" "$(basename "$app")" "$(_bid "$app")" "$(_ver "$app")" "$(du -sh "$app" 2>/dev/null|cut -f1)"
      done
    done
    echo '```'
    echo "### 3c. Homebrew casks"
    echo '```'
    if command -v brew >/dev/null 2>&1; then brew list --cask 2>/dev/null; else echo "(brew not installed)"; fi
    echo '```'
    echo "### 3d. Mac App Store apps (mas)"
    echo '```'
    if command -v mas >/dev/null 2>&1; then mas list 2>/dev/null; else echo "(mas not installed)"; fi
    echo '```'
    echo "### 3e. Dotfile-based programs in \$HOME"
    echo '```'
    du -sh ~/.[^.]* 2>/dev/null | sort -rh | head -40
    echo '```'
  } >> "$FB"

  # ---- storage inventory ---------------------------------------
  step "Dumping full storage inventory (with paths)..."
  {
    echo ""; echo "---"; echo ""
    echo "## 4. STORAGE INVENTORY (full paths + sizes, sorted)"
    for label in \
      "Application Support:$HOME/Library/Application Support" \
      "Caches:$HOME/Library/Caches" \
      "Containers:$HOME/Library/Containers" \
      "Group Containers:$HOME/Library/Group Containers" \
      "Saved Application State:$HOME/Library/Saved Application State" \
      "WebKit:$HOME/Library/WebKit" \
      "HTTPStorages:$HOME/Library/HTTPStorages"; do
      local name="${label%%:*}" path="${label#*:}"
      [ -d "$path" ] || continue
      echo ""; echo "### $name"; echo '```'
      du -sh "$path"/*/ 2>/dev/null | sort -rh
      echo '```'
    done
  } >> "$FB"

  # ---- orphan analysis (key section) ---------------------------
  step "Running orphan / deletable analysis (key section)..."
  {
    echo ""; echo "---"; echo ""
    echo "## 5. ORPHAN / DELETABLE ANALYSIS"
    echo ""
    echo "SIZE | FOLDER | MATCH-RESULT. 'ORPHAN?' = no installed app matched (candidate SAFE delete)."
    echo "MATCHED = owning app appears installed (keep / treat as live app data)."
    for area in "Application Support:$HOME/Library/Application Support" \
                "Caches:$HOME/Library/Caches" \
                "Containers:$HOME/Library/Containers" \
                "Group Containers:$HOME/Library/Group Containers"; do
      local name="${area%%:*}" path="${area#*:}"
      [ -d "$path" ] || continue
      echo ""; echo "### $name"; echo '```'
      du -sh "$path"/*/ 2>/dev/null | sort -rh | while read sz p; do
        printf "%-8s %-44s %s\n" "$sz" "$(basename "$p")" "$(_match_folder "$(basename "$p")")"
      done
      echo '```'
    done
  } >> "$FB"

  # ---- unclassified large items --------------------------------
  step "Computing unclassified large items..."
  {
    echo ""; echo "---"; echo ""
    echo "## 6. UNCLASSIFIED LARGE ITEMS ( > ~200 MB, not in current SAFE/REVIEW lists )"
    echo ""
    echo "Highest-value targets for new rules. Improver should assign a tier to each."
    echo '```'
    local KNOWN="caches|logs|trash|cache|vm_bundles|cacheddata|cachedextensionvsixs|jetbrains|updater|aws|spotify|comet|google|siritts|lmstudio|cursor|windsurf|trae|codeium|antigravity"
    du -sh ~/Library/Application\ Support/*/ ~/Library/Caches/*/ ~/Library/Group\ Containers/*/ ~/Library/Containers/*/ ~/* ~/.[^.]* 2>/dev/null \
    | sort -rh | while read sz p; do
      if echo "$sz" | grep -qE '^[0-9]+(\.[0-9]+)?G' || echo "$sz" | grep -qE '^[2-9][0-9]{2}(\.[0-9]+)?M|^[0-9]{4,}M'; then
        local low=$(basename "$p" | tr '[:upper:]' '[:lower:]')
        echo "$low" | grep -qE "$KNOWN" || printf "%-8s %s\n" "$sz" "$p"
      fi
    done | head -40
    echo '```'
  } >> "$FB"

  # ---- notes + template ----------------------------------------
  step "Appending notes & improvement template..."
  {
    echo ""; echo "---"; echo ""
    echo "## 7. NOTES / OBSERVED EDGE CASES"
    echo "- Folders matched only by short tokens (<4 chars) are skipped to avoid false matches."
    echo "- Reverse-DNS prefixes and the 10-char Apple team-ID prefix are stripped before name matching."
    echo "- TODO for improver: list any folder in section 5 whose MATCH-RESULT looks wrong."
    echo ""
    echo "## 8. SUGGESTED IMPROVEMENTS (Claude Code: fill this in)"
    echo "- [ ] New SAFE-by-pattern rules:"
    echo "- [ ] New REVIEW rules:"
    echo "- [ ] PROTECTED additions:"
    echo "- [ ] Improved _match_folder logic:"
    echo "- [ ] Items from section 6 to adopt (with tier):"
    echo "- [ ] Changelog summary:"
    echo ""
    echo "_End of feedback file._"
  } >> "$FB"

  echo ""; divider
  success "Feedback file created:"
  echo -e "      ${BYELLOW}$FB${RESET}"
  echo ""
  info "Review it (contains app/folder names from your Mac), then share with Claude Code:"
  echo -e "      ${DIM}open \"$FB\"${RESET}"
  echo -e "      ${DIM}# or inside Claude Code:  cat \"$FB\"${RESET}"
  divider
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#  10) TIME MACHINE & BACKUPS MANAGER
# ══════════════════════════════════════════════════════════════
time_machine_manager() {
  clear
  section "⏱️  TIME MACHINE & BACKUPS MANAGER"

  section "Local Time Machine Snapshots"
  local snaps
  snaps=$(tmutil listlocalsnapshots / 2>/dev/null | grep -i snapshot)
  if [ -z "$snaps" ]; then
    success "No local snapshots"
  else
    echo "$snaps" | while read s; do warning "$s"; done
    local snap_count
    snap_count=$(tmutil listlocalsnapshotdates / 2>/dev/null | grep -v '^$' | wc -l | tr -d ' ')
    info "$snap_count snapshot(s) found — safe to delete, macOS recreates them automatically"
    echo ""
    if confirm "Delete ALL local Time Machine snapshots?"; then
      if _dry_block "snapshot deletion"; then :
      elif tmutil deletelocalsnapshots / 2>/dev/null; then success "All local snapshots deleted"
      else warning "Could not delete snapshots (may require Full Disk Access)"; fi
    fi
  fi

  section "iOS / iPadOS Device Backups (MobileSync)"
  local mb="$HOME/Library/Application Support/MobileSync/Backup"
  if [ ! -d "$mb" ] || [ -z "$(ls -A "$mb" 2>/dev/null)" ]; then
    success "No device backups found"
  else
    local total
    total=$(du -sh "$mb" 2>/dev/null | cut -f1)
    warning "Total device backups: $total"
    info "Each folder below is one device backup"
    echo ""
    local dev when
    for bk in "$mb"/*/; do
      [ -d "$bk" ] || continue
      # Info.plist names the device; fall back to the UDID folder name.
      dev=$(plutil -extract "Device Name" raw "${bk}Info.plist" 2>/dev/null)
      when=$(plutil -extract "Last Backup Date" raw "${bk}Info.plist" 2>/dev/null | cut -c1-10)
      safe_delete "$bk" "Device backup: ${dev:-$(basename "$bk")}${when:+ (last backup $when)}"
    done
  fi

  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#  11) APPLICATIONS MANAGER
# ══════════════════════════════════════════════════════════════
#
#   Full-screen paged view over a single cached scan. State lives in
#   globals so the sub-actions (delete/move/restore) can reuse the scan
#   and the on-screen numbering instead of re-walking the disk:
#
#     APP_PATH/NAME/KB/LOC/STATE/TARGET[1..APP_N]  the cache
#     VIS[]        visible rows after scope+filter+sort; row number N
#                  on screen is VIS[N-1]
#     APPS_DIRTY   set by any action that changed the disk -> rescan
#
applications_manager() {
  APPS_PAGE=1; APPS_SORT="size_desc"; APPS_FILTER=""; APPS_SCOPE="all"; APPS_DIRTY=0
  _apps_scan

  local am_loop=1 am_choice
  while [ "$am_loop" -eq 1 ]; do
    if [ "$APPS_DIRTY" -eq 1 ]; then APPS_DIRTY=0; _apps_scan; fi
    _apps_view
    _apps_screen
    ask_choice "[d]elete [m]ove [r]estore [x]relink · [n/p]age [/]filter [s]ort [t]scope [R]escan · [b]ack"
    read -r am_choice
    case "$am_choice" in
      n|N) [ "$APPS_PAGE" -lt "$APPS_PAGES" ] && APPS_PAGE=$((APPS_PAGE+1)) ;;
      p|P) [ "$APPS_PAGE" -gt 1 ] && APPS_PAGE=$((APPS_PAGE-1)) ;;
      /)   echo -ne "\n  ${BCYAN}Filter by name ${DIM}(blank clears)${RESET}${BCYAN}: ${RESET}"
           read -r APPS_FILTER; APPS_PAGE=1 ;;
      s|S) case "$APPS_SORT" in
             size_desc) APPS_SORT="size_asc" ;;
             size_asc)  APPS_SORT="name" ;;
             *)         APPS_SORT="size_desc" ;;
           esac; APPS_PAGE=1 ;;
      t|T) case "$APPS_SCOPE" in
             all) APPS_SCOPE="sys" ;;
             sys) APPS_SCOPE="usr" ;;
             *)   APPS_SCOPE="all" ;;
           esac; APPS_PAGE=1 ;;
      R)   _apps_scan; APPS_PAGE=1 ;;
      d|D) _delete_apps_multi ;;
      m|M) _move_app_to_usb ;;
      r)   _restore_app_from_usb ;;
      x|X) _relink_missing_apps ;;
      b|B|q|Q) am_loop=0 ;;
      "") ;;   # bare Enter just redraws
      *) warning "Invalid option — try one of the keys shown"; sleep 1 ;;
    esac
  done
}

# ── Scan every .app once into the cache, with a live progress counter ──
_apps_scan() {
  clear
  section "📱 APPLICATIONS MANAGER"
  APP_PATH=(); APP_NAME=(); APP_KB=(); APP_LOC=(); APP_STATE=(); APP_TARGET=()
  APP_N=0

  local -a raw
  local app
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    { [ -e "$app" ] || [ -L "$app" ]; } || continue
    raw+=("$app")
  done

  local total=${#raw[@]}
  if [ "$total" -eq 0 ]; then return; fi

  # Pass 1 — cheap metadata (no disk walk): name, location, state, target.
  local idx=1 target
  local -a measure   # path whose size we need, per index ("" = skip)
  for app in "${raw[@]}"; do
    APP_PATH[$idx]="$app"
    APP_NAME[$idx]="$(basename "$app" .app)"
    case "$app" in "$HOME"/*) APP_LOC[$idx]="~/App" ;; *) APP_LOC[$idx]="/App" ;; esac
    APP_TARGET[$idx]=""
    APP_KB[$idx]=0
    measure[$idx]=""

    if [ -L "$app" ]; then
      target=$(readlink "$app")
      APP_TARGET[$idx]="$target"
      APP_STATE[$idx]="ext"
      [ -e "$target" ] && measure[$idx]="$target"
    else
      measure[$idx]="$app"
      if _wiz_protected "$app"; then
        APP_STATE[$idx]="lock"
      elif [ ! -O "$app" ]; then
        # Top-level bundle not owned by us -> installed with admin rights.
        # Advisory only; _app_removable still gates every actual removal.
        APP_STATE[$idx]="admin"
      else
        APP_STATE[$idx]="ok"
      fi
    fi
    idx=$((idx+1))
  done
  APP_N=$((idx-1))

  # Pass 2 — sizes, in parallel (du is I/O-bound, external volumes
  # especially). DU_PATHS is 0-based; the cache is 1-based.
  local i
  DU_PATHS=()
  for ((i=1; i<=APP_N; i++)); do DU_PATHS[$((i-1))]="${measure[$i]}"; done
  _du_batch "apps"
  for ((i=1; i<=APP_N; i++)); do APP_KB[$i]=${DU_KB[$((i-1))]:-0}; done
}

# ── Rebuild VIS from the cache: scope filter, name filter, sort order ──
_apps_view() {
  VIS=()
  local i rows="" sorted k n
  for ((i=1; i<=APP_N; i++)); do
    case "$APPS_SCOPE" in
      sys) [ "${APP_LOC[$i]}" = "/App" ]  || continue ;;
      usr) [ "${APP_LOC[$i]}" = "~/App" ] || continue ;;
    esac
    if [ -n "$APPS_FILTER" ]; then
      echo "${APP_NAME[$i]}" | grep -qiF -- "$APPS_FILTER" || continue
    fi
    rows="$rows${APP_KB[$i]}	${APP_NAME[$i]}	$i
"
  done

  if [ -n "$rows" ]; then
    case "$APPS_SORT" in
      size_asc) sorted=$(printf '%s' "$rows" | sort -t'	' -k1,1n) ;;
      name)     sorted=$(printf '%s' "$rows" | sort -t'	' -k2,2f) ;;
      *)        sorted=$(printf '%s' "$rows" | sort -t'	' -k1,1nr) ;;
    esac
    while IFS='	' read -r k n i; do
      [ -n "$i" ] && VIS+=("$i")
    done <<< "$sorted"
  fi

  # Page geometry (recomputed each draw so window resizes are picked up).
  # chrome = box(4) + disk bar(1) + column header(1) + 3 dividers/page line(3)
  #          + prompt(2) + 1 spare; the filter line adds one more.
  local lines; lines=$(_term_lines)
  local chrome=12
  [ -n "$APPS_FILTER" ] && chrome=13
  APPS_ROWS=$(( lines - chrome ))
  [ "$APPS_ROWS" -lt 5 ] && APPS_ROWS=5
  local count=${#VIS[@]}
  APPS_PAGES=$(( (count + APPS_ROWS - 1) / APPS_ROWS ))
  [ "$APPS_PAGES" -lt 1 ] && APPS_PAGES=1
  [ "$APPS_PAGE" -gt "$APPS_PAGES" ] && APPS_PAGE=$APPS_PAGES
  [ "$APPS_PAGE" -lt 1 ] && APPS_PAGE=1
}

# ── Draw the whole screen ──────────────────────────────────────
_apps_screen() {
  clear
  local count=${#VIS[@]}
  local i total_kb=0
  for i in "${VIS[@]}"; do total_kb=$(( total_kb + ${APP_KB[$i]} )); done

  local scope_label sort_label
  case "$APPS_SCOPE" in
    sys) scope_label="/Applications" ;;
    usr) scope_label="~/Applications" ;;
    *)   scope_label="all" ;;
  esac
  case "$APPS_SORT" in
    size_asc) sort_label="size (small first)" ;;
    name)     sort_label="name" ;;
    *)        sort_label="size (big first)" ;;
  esac

  _disk_stats
  local left right pad
  echo -e "${BMAGENTA}╭─ APPLICATIONS ───────────────────────────────────────────╮${RESET}"
  left="$count apps · $(human_kb "$total_kb")"
  right="Free ${DISK_FREE} of ${DISK_TOTAL}"
  pad=$(( 56 - ${#left} - ${#right} )); [ "$pad" -lt 1 ] && pad=1
  printf "${BMAGENTA}│${RESET} %s%*s%s ${BMAGENTA}│${RESET}\n" "$left" "$pad" "" "$right"
  left="scope: $scope_label"
  right="sort: $sort_label"
  pad=$(( 56 - ${#left} - ${#right} )); [ "$pad" -lt 1 ] && pad=1
  printf "${BMAGENTA}│${RESET} %s%*s%s ${BMAGENTA}│${RESET}\n" "$left" "$pad" "" "$right"
  if [ -n "$APPS_FILTER" ]; then
    printf "${BMAGENTA}│${RESET} %-56.56s ${BMAGENTA}│${RESET}\n" "filter: \"$APPS_FILTER\"  (press / and enter blank to clear)"
  fi
  echo -e "${BMAGENTA}╰──────────────────────────────────────────────────────────╯${RESET}"
  echo -e "  ${DISK_COLOR}[$(_disk_bar_str 40)] ${DISK_PCT}%${RESET}"

  if [ "$count" -eq 0 ]; then
    if [ "$APP_N" -eq 0 ]; then
      info "No applications found."
    else
      info "No apps match the current filter/scope."
    fi
    echo ""
    divider
    return
  fi

  echo -e "  ${DIM} #   SIZE      NAME                             LOC    STATE${RESET}"
  divider

  local start=$(( (APPS_PAGE - 1) * APPS_ROWS ))
  local end=$(( start + APPS_ROWS )); [ "$end" -gt "$count" ] && end=$count
  local pos state_cell
  for ((pos=start; pos<end; pos++)); do
    i=${VIS[$pos]}
    case "${APP_STATE[$i]}" in
      lock)  state_cell="${BRED}🔒 protected${RESET}" ;;
      admin) state_cell="${BYELLOW}⛨ admin${RESET}" ;;
      ext)   if [ -n "${APP_TARGET[$i]}" ] && [ -e "${APP_TARGET[$i]}" ]; then
               state_cell="${BCYAN}↗ external${RESET}"
             else
               state_cell="${BRED}↗ drive offline${RESET}"
             fi ;;
      *)     state_cell="${BGREEN}●${RESET}" ;;
    esac
    printf "  %2d  %s %-32.32s %-6s %b\n" \
      "$((pos+1))" "$(_size_cell "${APP_KB[$i]}")" "${APP_NAME[$i]}" "${APP_LOC[$i]}" "$state_cell"
  done

  divider
  printf "  ${DIM}page %d/%d · showing %d-%d of %d${RESET}\n" \
    "$APPS_PAGE" "$APPS_PAGES" "$((start+1))" "$end" "$count"
}

# ── Post-action summary: counts, space reclaimed, new free space ──
#   usage: _apps_result <ok> <skipped> <failed> <freed_kb> [trashed_kb]
_apps_result() {
  echo ""
  divider
  printf "  ${BGREEN}%d done${RESET}   ${DIM}%d skipped${RESET}   ${BRED}%d failed${RESET}\n" \
    "${1:-0}" "${2:-0}" "${3:-0}"
  [ "${4:-0}" -gt 0 ] && info "Reclaimed ~$(human_kb "$4") on the internal disk"
  [ "${5:-0}" -gt 0 ] && info "$(human_kb "$5") is in the Trash — empty it to reclaim the space (or Put Back to undo)"
  info "Free space now: $(df -h "$DATA_VOL" | awk 'NR==2{print $4}')"
  divider
  [ "${1:-0}" -gt 0 ] && APPS_DIRTY=1
  press_any_key
}

# ══════════════════════════════════════════════════════════════
#   DELETE ONE OR MORE APPS (numbered multi-select)
# ══════════════════════════════════════════════════════════════
_delete_apps_multi() {
  section "🗑️  Delete apps"
  if _dry_block "deleting apps"; then press_any_key; return; fi
  local n=${#VIS[@]}
  if [ "$n" -eq 0 ]; then
    info "No apps in the current view."; press_any_key; return
  fi

  # Map on-screen row numbers (1..n across all pages) onto the cache.
  local -a app_paths app_locked
  local pos gi idx=1
  for ((pos=0; pos<n; pos++)); do
    gi=${VIS[$pos]}
    app_paths[$idx]="${APP_PATH[$gi]}"
    case "${APP_STATE[$gi]}" in
      lock) app_locked[$idx]=1 ;;
      ext)  app_locked[$idx]=2 ;;
      *)    app_locked[$idx]=0 ;;
    esac
    idx=$((idx+1))
  done

  echo -ne "\n  ${BCYAN}App number(s) to delete ${DIM}(from the list, e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; press_any_key; return; }

  local -a idxs
  idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; press_any_key; return
  fi

  # Filter out protected and externally-hosted apps
  local -a selectable
  local skip_n=0 i
  for i in "${idxs[@]}"; do
    if [ "${app_locked[$i]:-0}" -eq 1 ]; then
      danger "'$(basename "${app_paths[$i]}")' is protected (sync/messaging app) — skipped. Manage it from the app itself."
      skip_n=$((skip_n+1))
    elif [ "${app_locked[$i]:-0}" -eq 2 ]; then
      warning "'$(basename "${app_paths[$i]}")' lives on an external drive (this is just a launcher link) — use [r]estore, or delete it on the drive. Skipped."
      skip_n=$((skip_n+1))
    else
      selectable+=("$i")
    fi
  done

  if [ "${#selectable[@]}" -eq 0 ]; then
    skipped "Nothing selectable was chosen"
    _apps_result 0 "$skip_n" 0 0
    return
  fi

  echo ""; info "Selected for deletion:"
  local total_kb=0
  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    local kb; kb=$(du -sk "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
    total_kb=$((total_kb+kb))
    printf "  - %s %s\n" "$(_size_cell "$kb")" "$(basename "$p")"
  done

  echo ""
  if ! confirm "Move these ${#selectable[@]} app(s) (~$(human_kb "$total_kb")) to the Trash? (undo with Finder → Put Back)"; then
    skipped "Cancelled"; press_any_key; return
  fi

  local ok_n=0 fail_n=0 freed_kb=0 trashed_kb=0
  local -a gone_bid gone_name
  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    if [ -e "$p" ]; then
      local kb; kb=$(du -sk "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
      if ! _app_removable "$p"; then
        danger "'$(basename "$p")' was installed with admin rights (root-owned files) — delete it via Finder instead (asks for your admin password). Skipped."
        skip_n=$((skip_n+1))
        continue
      fi
      # Read the bundle id before it's gone: it is how leftovers are found.
      local bid; bid=$(plutil -extract CFBundleIdentifier raw "$p/Contents/Info.plist" 2>/dev/null)
      if _remove_undoable "$p" "$kb" "$(basename "$p")"; then
        ok_n=$((ok_n+1)); freed_kb=$((freed_kb+RM_FREED)); trashed_kb=$((trashed_kb+RM_TRASHED))
        gone_bid+=("$bid"); gone_name+=("$(basename "$p" .app)")
      else
        fail_n=$((fail_n+1))
      fi
    fi
  done

  # Offer each removed app's leftover data (settings, caches, containers).
  if [ "${#gone_name[@]}" -gt 0 ]; then
    _app_leftovers
    freed_kb=$((freed_kb+LEFT_FREED)); trashed_kb=$((trashed_kb+LEFT_TRASHED))
  fi

  _apps_result "$ok_n" "$skip_n" "$fail_n" "$freed_kb" "$trashed_kb"
}

# ── Leftover data of just-removed apps (AppCleaner-style) ──────
# Reads gone_bid[] / gone_name[] from the caller (_delete_apps_multi).
# Looks only at the standard per-app locations, named by bundle id (or the
# exact app name), and skips an app entirely if another installed copy
# still uses the same bundle id. Every path goes through _wiz_protected().
# Sets LEFT_FREED / LEFT_TRASHED (KB).
_app_leftovers() {
  LEFT_FREED=0; LEFT_TRASHED=0
  local L="$HOME/Library" k b nm cand p seen="|"
  local -a lp lk ll

  # Bundle ids of every app still installed, to protect shared data.
  local live="|" a
  for a in /Applications/*.app "$HOME/Applications"/*.app; do
    [ -e "$a" ] || continue
    live="$live$(plutil -extract CFBundleIdentifier raw "$a/Contents/Info.plist" 2>/dev/null | tr '[:upper:]' '[:lower:]')|"
  done

  for ((k=0; k<${#gone_name[@]}; k++)); do
    b="${gone_bid[$k]}"; nm="${gone_name[$k]}"
    [ -n "$b" ] || continue   # no bundle id → nothing we can match safely
    case "$live" in *"|$(echo "$b" | tr '[:upper:]' '[:lower:]')|"*)
      info "$nm: another installed copy uses $b — its data is left alone"; continue ;;
    esac
    for cand in \
      "$L/Containers/$b" "$L/Application Scripts/$b" "$L/Caches/$b" "$L/Application Support/$b" \
      "$L/Preferences/$b.plist" "$L/Saved Application State/$b.savedState" \
      "$L/HTTPStorages/$b" "$L/HTTPStorages/$b.binarycookies" "$L/WebKit/$b" "$L/Logs/$b" \
      "$L/Cookies/$b.binarycookies" "$L/Group Containers/group.$b" "$L/Group Containers/"*".$b" \
      "$L/Application Support/$nm" "$L/Caches/$nm" "$L/Logs/$nm"; do
      [ -e "$cand" ] || continue
      _wiz_protected "$cand" && continue
      # case-insensitive filesystem: dedupe on the lowercased path
      p=$(echo "$cand" | tr '[:upper:]' '[:lower:]')
      case "$seen" in *"|$p|"*) continue ;; esac
      seen="$seen$p|"
      lp+=("$cand"); ll+=("$nm")
    done
  done
  [ "${#lp[@]}" -eq 0 ] && return

  DU_PATHS=("${lp[@]}"); _du_batch "leftovers"
  echo ""; info "Leftover data from the removed app(s):"
  local i total=0
  for ((i=0; i<${#lp[@]}; i++)); do
    lk[$i]=${DU_KB[$i]:-0}; total=$((total+lk[$i]))
    printf "  %2d) %s %-18.18s ${DIM}%s${RESET}\n" "$((i+1))" "$(_size_cell "${lk[$i]}")" "${ll[$i]}" "${lp[$i]#$HOME/}"
  done
  echo -ne "\n  ${BCYAN}Move to Trash: [a]ll ($(human_kb "$total")), numbers (e.g. 1,3), or Enter to keep: ${RESET}"
  local sel; read -r sel
  local -a pick
  case "$sel" in
    "") skipped "Kept all leftovers"; return ;;
    a|A) for ((i=1; i<=${#lp[@]}; i++)); do pick+=("$i"); done ;;
    *) pick=($(_parse_selection "$sel" "${#lp[@]}")) ;;
  esac
  for i in "${pick[@]}"; do
    _remove_undoable "${lp[$((i-1))]}" "${lk[$((i-1))]}" "${lp[$((i-1))]#$HOME/}"
    LEFT_FREED=$((LEFT_FREED+RM_FREED)); LEFT_TRASHED=$((LEFT_TRASHED+RM_TRASHED))
  done
}

# ── Selection parsing (used by app delete/move/restore below) ──
# Expands "2,4,7-9" into sorted, deduped, in-range line-per-index output.
_parse_selection() {
  local input="$1" max="$2"
  echo "$input" | tr ',' '\n' | while read -r tok; do
    tok=$(echo "$tok" | tr -d ' ')
    [ -z "$tok" ] && continue
    if echo "$tok" | grep -qE '^[0-9]+-[0-9]+$'; then
      local a="${tok%-*}" b="${tok#*-}"
      [ "$a" -gt "$b" ] && { local t="$a"; a="$b"; b="$t"; }
      local n
      for ((n=a; n<=b; n++)); do
        [ "$n" -ge 1 ] && [ "$n" -le "$max" ] && echo "$n"
      done
    elif echo "$tok" | grep -qE '^[0-9]+$'; then
      [ "$tok" -ge 1 ] && [ "$tok" -le "$max" ] && echo "$tok"
    fi
  done | sort -n | uniq
}

# ── Ownership check (used by app delete/move below) ────────────
# Returns 0 (true) if the current user owns every file in the bundle,
# i.e. rm -rf can fully remove it without admin rights. Apps installed
# by a root installer (e.g. Microsoft Office) fail this and must not be
# offered for delete/move — a partial rm would corrupt the app.
_app_removable() {
  local app="$1"
  [ -n "$(find "$app" ! -user "$(id -un)" -print 2>/dev/null | head -1)" ] && return 1
  return 0
}

# ── External volume discovery (used by move/restore below) ─────
# Lists mounted /Volumes/* entries whose filesystem device id differs
# from "/", i.e. excludes the boot volume (robust across APFS
# firmlinks, unlike matching on volume name).
_external_volumes() {
  local boot_dev; boot_dev=$(stat -f %d / 2>/dev/null)
  for v in /Volumes/*/; do
    [ -d "$v" ] || continue
    local vol_dev; vol_dev=$(stat -f %d "$v" 2>/dev/null)
    [ -z "$vol_dev" ] && continue
    [ "$vol_dev" = "$boot_dev" ] && continue
    local name; name=$(basename "$v")
    local avail_kb; avail_kb=$(df -k "$v" 2>/dev/null | awk 'NR==2{print $4}')
    printf "%s\t%s\n" "$name" "${avail_kb:-0}"
  done
}

# ══════════════════════════════════════════════════════════════
#   MOVE APP TO USB DRIVE  (symlink trick, ditto-verified)
# ══════════════════════════════════════════════════════════════
_move_app_to_usb() {
  section "🔌 Move App to USB / External Drive"
  if _dry_block "moving apps"; then press_any_key; return; fi
  local n=${#VIS[@]}
  if [ "$n" -eq 0 ]; then
    info "No apps in the current view."; press_any_key; return
  fi

  # Map on-screen row numbers (1..n across all pages) onto the cache.
  local -a app_paths app_locked
  local pos gi idx=1
  for ((pos=0; pos<n; pos++)); do
    gi=${VIS[$pos]}
    app_paths[$idx]="${APP_PATH[$gi]}"
    case "${APP_STATE[$gi]}" in
      lock) app_locked[$idx]=1 ;;
      ext)  app_locked[$idx]=2 ;;
      *)    app_locked[$idx]=0 ;;
    esac
    idx=$((idx+1))
  done

  echo -ne "\n  ${BCYAN}App number(s) to move ${DIM}(from the list, e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; press_any_key; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; press_any_key; return
  fi

  # Filter out protected and already-external apps
  local -a selectable
  local skip_n=0 i
  for i in "${sel_idxs[@]}"; do
    if [ "${app_locked[$i]:-0}" -eq 1 ]; then
      danger "'$(basename "${app_paths[$i]}")' is protected (sync/messaging app) — skipped. Manage it from the app itself."
      skip_n=$((skip_n+1))
    elif [ "${app_locked[$i]:-0}" -eq 2 ]; then
      skipped "'$(basename "${app_paths[$i]}")' already lives on an external drive — skipped."
      skip_n=$((skip_n+1))
    else
      selectable+=("$i")
    fi
  done

  if [ "${#selectable[@]}" -eq 0 ]; then
    skipped "Nothing selectable was chosen"
    _apps_result 0 "$skip_n" 0 0
    return
  fi

  local vols; vols=$(_external_volumes)
  if [ -z "$vols" ]; then
    warning "No external/USB drives are mounted. Connect one and try again."
    press_any_key; return
  fi

  echo ""; info "Mounted external volumes:"
  local -a vol_names
  idx=1
  while IFS=$'\t' read -r vname vavail; do
    vol_names[$idx]="$vname"
    printf "  %2d) %-20s %s free\n" "$idx" "$vname" "$(human_kb "$vavail")"
    idx=$((idx+1))
  done <<< "$vols"

  echo -ne "\n  ${BCYAN}Destination volume number (blank to cancel): ${RESET}"
  read -r vsel
  [ -z "$vsel" ] && { skipped "Cancelled"; press_any_key; return; }
  local vol="${vol_names[$vsel]}"
  if [ -z "$vol" ] || [ ! -d "/Volumes/$vol" ]; then
    warning "Invalid selection"; press_any_key; return
  fi

  local dest_dir="/Volumes/$vol/AppsOnExternal"
  local avail_kb; avail_kb=$(df -k "/Volumes/$vol" 2>/dev/null | awk 'NR==2{print $4}'); avail_kb=${avail_kb:-0}

  echo ""; info "Selected to move:"
  local total_kb=0 i
  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    local kb; kb=$(du -sk "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
    total_kb=$((total_kb+kb))
    printf "  - %s %s\n" "$(_size_cell "$kb")" "$(basename "$p")"
  done

  if [ "$total_kb" -gt "$avail_kb" ]; then
    danger "Not enough free space on '$vol' ($(human_kb "$avail_kb") free, need $(human_kb "$total_kb") total)"
    press_any_key; return
  fi

  echo ""
  if ! confirm "Move these ${#selectable[@]} app(s) ($(human_kb "$total_kb")) to '$vol'? They will only launch while this drive is connected."; then
    skipped "Cancelled"; press_any_key; return
  fi

  local ok_n=0 fail_n=0 freed_kb=0
  mkdir -p "$dest_dir"
  for i in "${selectable[@]}"; do
    local app="${app_paths[$i]}"
    local app_name; app_name=$(basename "$app")
    local dest="$dest_dir/$app_name"
    local app_kb; app_kb=$(du -sk "$app" 2>/dev/null | cut -f1); app_kb=${app_kb:-0}
    PENDING_MSG=""

    local use_sudo=0
    if ! _app_removable "$app"; then
      warning "'$app_name' was installed with admin rights (root-owned files)."
      if confirm "Complete the move with your admin password (sudo)?"; then
        use_sudo=1
      else
        skipped "Skipped '$app_name'"
        skip_n=$((skip_n+1))
        continue
      fi
    fi

    if [ -e "$dest" ]; then
      local dest_size; dest_size=$(du -sk "$dest" 2>/dev/null | cut -f1); dest_size=${dest_size:-0}
      warning "'$app_name' already has a copy on '$vol' ($(human_kb "$dest_size"), from a previous move)."
      if confirm "Overwrite it with a fresh copy from the internal disk? (n = decide next)"; then
        rm -rf "$dest"
      elif [ "$dest_size" -gt 0 ] && confirm "Use the EXISTING external copy instead, and free the internal one? (it may be older)"; then
        PENDING_MSG="'$app_name' is safe at: $dest — open Applications → [x] relink to recreate its launcher."
        rm -rf "$app"
        if [ -e "$app" ]; then
          danger "Could not fully remove '$app_name' — restoring it from the external copy."
          ditto "$dest" "$app" 2>/dev/null
          fail_n=$((fail_n+1))
          continue
        fi
        ln -s "$dest" "$app"
        success "Linked '$app_name' to existing external copy — freed $(human_kb "$app_kb") on internal disk"
        ok_n=$((ok_n+1)); freed_kb=$((freed_kb+app_kb))
        continue
      else
        skipped "Skipped '$app_name'"
        skip_n=$((skip_n+1))
        continue
      fi
    fi

    echo -n "  Copying '$app_name' to external drive... "
    if ditto "$app" "$dest" 2>/dev/null && [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
      echo -e "${BGREEN}done${RESET}"
    else
      echo -e "${BRED}failed${RESET}"
      danger "Copy failed or destination is empty — '$app_name' left untouched."
      rm -rf "$dest" 2>/dev/null
      fail_n=$((fail_n+1))
      continue
    fi

    PENDING_MSG="'$app_name' is safe at: $dest — open Applications → [x] relink to recreate its launcher."
    if [ "$use_sudo" -eq 1 ]; then
      info "Removing '$app_name' with admin rights (you may be asked for your password)..."
      sudo rm -rf "$app"
    else
      rm -rf "$app" 2>/dev/null
    fi
    if [ -e "$app" ]; then
      danger "Could not fully remove '$app_name' from the internal disk."
      echo -n "  Repairing '$app_name' from the external copy... "
      if { [ "$use_sudo" -eq 1 ] && sudo ditto "$dest" "$app" 2>/dev/null; } || ditto "$dest" "$app" 2>/dev/null; then
        echo -e "${BGREEN}done${RESET}"
        warning "'$app_name' was restored in place — nothing was moved."
      else
        echo -e "${BRED}failed${RESET}"
        danger "'$app_name' may be damaged. A full copy is safe at: $dest — restore it with Finder or reinstall the app."
      fi
      fail_n=$((fail_n+1))
      continue
    fi
    local link_ok=0
    if [ "$use_sudo" -eq 1 ]; then
      sudo ln -s "$dest" "$app" 2>/dev/null && link_ok=1
    else
      ln -s "$dest" "$app" 2>/dev/null && link_ok=1
    fi
    if [ "$link_ok" -eq 0 ]; then
      danger "Could not create the launcher link for '$app_name'. The app now lives only at: $dest"
      fail_n=$((fail_n+1))
      continue
    fi
    success "Moved '$app_name' — freed $(human_kb "$app_kb") on internal disk"
    ok_n=$((ok_n+1)); freed_kb=$((freed_kb+app_kb))
  done
  PENDING_MSG=""

  _apps_result "$ok_n" "$skip_n" "$fail_n" "$freed_kb"
}

# ══════════════════════════════════════════════════════════════
#   RESTORE APP FROM USB DRIVE
# ══════════════════════════════════════════════════════════════
_restore_app_from_usb() {
  section "🔄 Restore App from USB / External Drive"
  if _dry_block "restoring apps"; then press_any_key; return; fi

  # Externally-hosted apps come from the cached scan (renumbered here,
  # since this is a subset of the main list).
  local -a link_paths
  local -a link_targets
  local idx=1 gi
  for ((gi=1; gi<=APP_N; gi++)); do
    [ "${APP_STATE[$gi]}" = "ext" ] || continue
    local app="${APP_PATH[$gi]}" target="${APP_TARGET[$gi]}"
    link_paths[$idx]="$app"
    link_targets[$idx]="$target"
    local status="${BGREEN}connected${RESET}"
    [ -e "$target" ] || status="${BRED}drive not connected${RESET}"
    printf "  %2d) %-40s -> %s [%b]\n" "$idx" "$(basename "$app")" "$target" "$status"
    idx=$((idx+1))
  done

  if [ "$idx" -eq 1 ]; then
    info "No externally-moved apps found."
    press_any_key; return
  fi

  echo -ne "\n  ${BCYAN}App number(s) to restore ${DIM}(numbers from THIS list, e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; press_any_key; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; press_any_key; return
  fi

  echo ""; info "Selected to restore:"
  local i
  for i in "${sel_idxs[@]}"; do
    printf "  - %s\n" "$(basename "${link_paths[$i]}")"
  done

  echo ""
  if ! confirm "Restore these ${#sel_idxs[@]} app(s) back to internal disk?"; then
    skipped "Cancelled"; press_any_key; return
  fi

  local ok_n=0 skip_n=0 fail_n=0
  for i in "${sel_idxs[@]}"; do
    local app="${link_paths[$i]}"
    local target="${link_targets[$i]}"
    local app_name; app_name=$(basename "$app")

    if [ ! -e "$target" ]; then
      danger "Target '$target' is not reachable — skipping '$app_name'"
      skip_n=$((skip_n+1))
      continue
    fi

    local restore_path="$app"
    PENDING_MSG="'$app_name' is still complete at: $target — delete any partial copy at '$app', then open Applications → [x] relink."
    rm -f "$app"
    echo -n "  Copying '$app_name' back to internal disk... "
    if ditto "$target" "$restore_path" 2>/dev/null && [ -d "$restore_path" ] && [ -n "$(ls -A "$restore_path" 2>/dev/null)" ]; then
      echo -e "${BGREEN}done${RESET}"
    else
      echo -e "${BRED}failed${RESET}"
      danger "Restore failed for '$app_name' — re-linking to external copy so it stays usable."
      rm -rf "$restore_path" 2>/dev/null
      ln -s "$target" "$restore_path"
      PENDING_MSG=""
      fail_n=$((fail_n+1))
      continue
    fi

    PENDING_MSG=""
    success "Restored '$app_name' to internal disk"
    ok_n=$((ok_n+1))
    if confirm "Delete the external copy at '$target'?"; then
      rm -rf "$target"
      success "Removed external copy"
    fi
  done

  _apps_result "$ok_n" "$skip_n" "$fail_n" 0
}

# ══════════════════════════════════════════════════════════════
#   RELINK APPS WITH A MISSING LAUNCHER LINK
#   (bundle still on external AppsOnExternal, but the symlink in
#    /Applications or ~/Applications is gone — recreate it without
#    copying/moving any bytes)
# ══════════════════════════════════════════════════════════════
_relink_missing_apps() {
  section "🔗 Relink Apps with Missing Launcher"
  if _dry_block "relinking apps"; then press_any_key; return; fi

  local vols; vols=$(_external_volumes)
  if [ -z "$vols" ]; then
    warning "No external/USB drives are mounted. Connect one and try again."
    press_any_key; return
  fi

  local -a cand_bundle cand_name
  local idx=1
  local vname vavail
  while IFS=$'\t' read -r vname vavail; do
    local ext_dir="/Volumes/$vname/AppsOnExternal"
    [ -d "$ext_dir" ] || continue
    local bundle
    for bundle in "$ext_dir"/*.app; do
      [ -d "$bundle" ] || continue
      local name; name=$(basename "$bundle")
      local sys_target="/Applications/$name"
      local usr_target="$HOME/Applications/$name"
      if [ -e "$sys_target" ] || [ -L "$sys_target" ] || [ -e "$usr_target" ] || [ -L "$usr_target" ]; then
        continue
      fi
      cand_bundle[$idx]="$bundle"
      cand_name[$idx]="$name"
      idx=$((idx+1))
    done
  done <<< "$vols"

  if [ "$idx" -eq 1 ]; then
    info "No missing links found — every external app already has a launcher."
    press_any_key; return
  fi

  info "Found $((idx-1)) app(s) on external drive(s) with no launcher in /Applications or ~/Applications:"
  local i
  for ((i=1; i<idx; i++)); do
    local kb; kb=$(du -sk "${cand_bundle[$i]}" 2>/dev/null | cut -f1); kb=${kb:-0}
    printf "  %2d) %s %-30s ${DIM}%s${RESET}\n" "$i" "$(_size_cell "$kb")" "${cand_name[$i]}" "${cand_bundle[$i]}"
  done

  echo -ne "\n  ${BCYAN}App number(s) to relink ${DIM}(numbers from THIS list, e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; press_any_key; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; press_any_key; return
  fi

  echo ""
  echo -ne "  ${BCYAN}Link into [a] /Applications (system-wide, needs admin) or [u] ~/Applications (user)? ${RESET}"
  read -r loc_choice
  local dest_base="/Applications"
  case "$loc_choice" in
    u|U) dest_base="$HOME/Applications" ;;
    *) dest_base="/Applications" ;;
  esac
  mkdir -p "$dest_base" 2>/dev/null

  local relinked=0 skip_n=0 fail_n=0
  for i in "${sel_idxs[@]}"; do
    local bundle="${cand_bundle[$i]}" name="${cand_name[$i]}"
    local target="$dest_base/$name"

    if _wiz_protected "$target" || _wiz_protected "$bundle"; then
      danger "'$name' is protected — skipped."
      skip_n=$((skip_n+1))
      continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      warning "'$name' already exists at '$target' — skipped."
      skip_n=$((skip_n+1))
      continue
    fi

    ln -s "$bundle" "$target" 2>/dev/null
    if [ -L "$target" ]; then
      success "Relinked '$name' -> $bundle"
      relinked=$((relinked+1))
    else
      danger "Could not create the launcher link for '$name' at '$target'."
      fail_n=$((fail_n+1))
    fi
  done

  _apps_result "$relinked" "$skip_n" "$fail_n" 0
}

# ══════════════════════════════════════════════════════════════
#   12) VSCODE EXTENSION MANAGER
# ══════════════════════════════════════════════════════════════
vscode_manager() {
  local -a VARIANTS
  local -a LABELS

  VARIANTS=("$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" \
            "$HOME/.vscode-oss/extensions" "$HOME/.vscodium/extensions" \
            "$HOME/.cursor/extensions" "$HOME/.windsurf-next/extensions" \
            "$HOME/.windsurf/extensions" "$HOME/.trae/extensions" \
            "$HOME/.antigravity-ide/extensions" "$HOME/.devin/extensions" \
            "$HOME/.positron/extensions" "$HOME/.kiro/extensions")

  LABELS=("VS Code" "VS Code Insiders" "VSCodium (1)" "VSCodium (2)" \
          "Cursor" "Windsurf (next)" "Windsurf" "Trae" \
          "Antigravity IDE" "Devin" "Positron" "Kiro")

  local found=0
  local idx=0

  clear
  section "🔌 VSCODE EXTENSION MANAGER"

  for var in "${VARIANTS[@]}"; do
    if [ -d "$var" ]; then
      found=1
    fi
    ((idx++))
  done

  [ "$found" -eq 0 ] && { info "No VSCode-variant installations detected."; _back_to_menu; return; }

  idx=0
  for var in "${VARIANTS[@]}"; do
    if [ -d "$var" ]; then
      local label="${LABELS[$idx]}"
      echo ""
      section "── $label ──"
      echo -e "  ${BOLD}Total: ${BRED}${BOLD}$(du -sh "$var" 2>/dev/null | cut -f1)${RESET}\n"

      du -sh "$var"/*/ 2>/dev/null | sort -rh | while read size path; do
        printf "  %-10s %s\n" "$(color_size $size)" "$(basename "$path")"
      done
    fi
    ((idx++))
  done

  echo ""
  info "Extension disable/enable: available only when IDE is running"
  info "Use backup below to create recovery archives"
  echo ""

  local submenu_loop=1
  while [ "$submenu_loop" -eq 1 ]; do
    ask_choice "[d]elete  [k] backup  [b]ack"
    read -r subchoice
    case "$subchoice" in
      d)
        if confirm "Delete all extensions from all detected variants?"; then
          section "Deleting extensions"
          idx=0
          for var in "${VARIANTS[@]}"; do
            if [ -d "$var" ]; then
              local label="${LABELS[$idx]}"
              for ext in "$var"/*/; do
                [ -d "$ext" ] && safe_delete "$ext" "$(basename "$ext") [$label]"
              done
            fi
            ((idx++))
          done
        fi
        ;;
      k|K)
        section "Backing up extensions"
        local backup_dir="$HOME/Desktop"
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local any_backed=0

        idx=0
        for var in "${VARIANTS[@]}"; do
          if [ -d "$var" ]; then
            local label="${LABELS[$idx]}"
            local safe_label=$(echo "$label" | tr ' ()' '_' | tr '[:upper:]' '[:lower:]')
            local backup_file="$backup_dir/${safe_label}_extensions_${timestamp}.tar.gz"

            echo ""
            echo -n "  Backing up $label... "
            if tar -czf "$backup_file" -C "$(dirname "$var")" "$(basename "$var")" 2>/dev/null; then
              local backup_size=$(du -sh "$backup_file" | cut -f1)
              success "backed up to Desktop (${backup_size})"
              success "$backup_file"
            else
              warning "failed to backup $label"
            fi
          fi
          ((idx++))
        done
        ;;
      b|B|q|Q)
        submenu_loop=0
        ;;
      *)
        warning "Invalid option — try one of the keys shown"
        ;;
    esac
  done

  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   ENTRY
# ══════════════════════════════════════════════════════════════
VERSION="3.8"

_usage() {
  cat <<USAGE
storage_check.sh v$VERSION — macOS disk audit & safe cleanup

Usage: bash storage_check.sh [options]

  -n, --dry-run   Show what would be deleted/moved; change nothing
  -h, --help      Show this help
  -v, --version   Print the version
USAGE
}

_parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -n|--dry-run) DRY_RUN=1 ;;
      -h|--help)    _usage; exit 0 ;;
      -v|--version) echo "storage_check.sh v$VERSION"; exit 0 ;;
      *) echo "Unknown option: $1" >&2; _usage >&2; exit 2 ;;
    esac
    shift
  done
}

# Refuses unsupported environments and detects missing Full Disk Access.
_preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "storage_check.sh only supports macOS." >&2; exit 1
  fi
  if [ "$(id -u)" -eq 0 ]; then
    echo "Don't run storage_check.sh as root or with sudo — it manages YOUR home folder" >&2
    echo "and asks for admin rights itself only where needed." >&2
    exit 1
  fi
  # FDA-protected folders that exist on every Mac. If one exists but can't
  # be listed, the terminal lacks Full Disk Access (no prompt is triggered).
  NO_FDA=0
  local d
  for d in "$HOME/Library/Safari" "$HOME/Library/Mail"; do
    if [ -d "$d" ] && ! ls "$d" >/dev/null 2>&1; then NO_FDA=1; break; fi
  done
}

# Run only when executed, not when sourced (tests source this file).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _parse_args "$@"
  _preflight
  trap _on_interrupt INT TERM
  trap _cleanup EXIT
  main_menu
fi
