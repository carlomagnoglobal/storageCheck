#!/bin/bash

# ╔══════════════════════════════════════════════════════════════╗
# ║      MAC STORAGE MANAGER v3.2 — by Claude                    ║
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

confirm() {
  echo -ne "\n  ${BYELLOW}❓ $1 [y/N]: ${RESET}"
  read -r answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# Standard prompt for submenu action keys, e.g. ask_choice "d=delete  m=move  b=back"
menu_group() { echo -e "\n  ${DIM}─── $1 ───${RESET}"; }
ask_choice() { echo -ne "\n  ${BCYAN}$1 › ${RESET}"; }
press_any_key() { echo ""; echo -ne "  ${DIM}Press any key to continue...${RESET}"; read -rn1; }

REPORT_FILE="$HOME/storage_report_$(date '+%Y%m%d_%H%M%S').txt"

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════
main_menu() {
  clear
  echo ""
  echo -e "${BMAGENTA}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BMAGENTA}║     🖥️  MAC STORAGE MANAGER v3.5                         ║${RESET}"
  echo -e "${BMAGENTA}║     $(date '+%a %d %b %Y — %H:%M')                              ║${RESET}"
  echo -e "${BMAGENTA}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  local used_pct=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
  local total=$(df -h / | awk 'NR==2{print $2}')
  local used=$(df -h / | awk 'NR==2{print $3}')
  local avail=$(df -h / | awk 'NR==2{print $4}')
  local bar_len=40
  local filled=$(( used_pct * bar_len / 100 )); local empty=$(( bar_len - filled ))
  local bar=""
  for ((i=0;i<filled;i++)); do bar+="█"; done
  for ((i=0;i<empty;i++)); do bar+="░"; done
  if   [ "$used_pct" -ge 80 ]; then bc="${BRED}"
  elif [ "$used_pct" -ge 60 ]; then bc="${BYELLOW}"
  else bc="${BGREEN}"; fi

  echo -e "  ${BOLD}Disk:${RESET} ${bc}[${bar}] ${used_pct}%${RESET}"
  echo -e "  ${DIM}Used: ${used}  |  Free: ${avail}  |  Total: ${total}${RESET}"
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
  read -r choice
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
      local free_now=$(df -h / | awk 'NR==2{print $4}')
      echo -e "\n  ${BGREEN}Goodbye! 👋 Free space now: ${BYELLOW}${free_now}${RESET}\n"
      exit 0
      ;;
    *) warning "Invalid option"; sleep 1; main_menu ;;
  esac
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
    # Cloud/sync platforms: library & container paths
    *onedrive*|*dropbox*|*"google drive"*|*googledrive*|*cloudstorage*|*"mobile documents"*|*clouddocs*) return 0 ;;
    # Messaging apps
    *whatsapp*|*telegram*|*"group.net.whatsapp"*)                                        return 0 ;;
    # Apple system apps & services
    *"/library/mail"*|*com.apple.mail*|*"/applications/mail.app"*|*keychain*|*"/library/photos"*|*"/applications/photos.app"*|*photoslibrary*) return 0 ;;
    # Microsoft apps
    *"ubf8t346g9.office"*|*com.microsoft.outlook*|*com.microsoft.onedrive*|*"outlook.app"*) return 0 ;;
  esac
  return 1
}

safe_wizard() {
  clear
  echo -e "${BGREEN}${BOLD}🪄  SAFE CLEANUP WIZARD${RESET}  ${DIM}(v3.2 pattern engine)${RESET}"
  divider
  echo -e "  Offers only items that are ${BGREEN}safe by design${RESET}: caches, logs, temp & re-downloadables."
  echo -e "  It ${BRED}never${RESET} touches macOS system data, cloud sync, chats, mail, or your files."
  echo -e "  ${DIM}🟢 safe (auto-rebuilds) · 🟡 re-downloadable (you decide) · 🔴 protected (hidden)${RESET}"
  echo ""

  CANDIDATES=()   # entries: "TIER|kb|path|label|note"
  add_candidate() {
    local tier="$1" path="$2" label="$3" note="$4"
    [ -e "$path" ] || return
    _wiz_protected "$path" && return
    local kb=$(du -sk "$path" 2>/dev/null | cut -f1); [ -z "$kb" ] && kb=0
    [ "$kb" -gt 0 ] && CANDIDATES+=("$tier|$kb|$path|$label|$note")
  }

  info "Scanning by universal cache/log patterns (works on any Mac)..."

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

  # ───── 🟢 SAFE: whole-tree cache/log roots (their entire purpose) ─────
  add_candidate SAFE "$HOME/Library/Caches"                       "All app caches (~/Library/Caches)" "Every app rebuilds these"
  add_candidate SAFE "$HOME/Library/Logs"                         "Application logs"                  "Diagnostic text only"
  add_candidate SAFE "$HOME/.Trash"                               "Trash bin"                         "Already-deleted files"
  add_candidate SAFE "$HOME/.cache"                               "Generic ~/.cache"                  "Dev tool scratch cache"
  add_candidate SAFE "$HOME/Library/Saved Application State"      "Saved window state"                "Just window positions"

  # ───── 🟢 SAFE: Xcode dev caches (you have Xcode installed) ─────
  add_candidate SAFE "$HOME/Library/Developer/Xcode/DerivedData"  "Xcode · DerivedData"               "Rebuilds on next build"
  add_candidate SAFE "$HOME/Library/Developer/CoreSimulator/Caches" "CoreSimulator caches"            "Rebuilds automatically"

  # ───── 🟢 SAFE: cache/log/temp dirs INSIDE app data (pattern scan) ─────
  # Matches Cache, Caches, Code Cache, *Cache (GPUCache/Dawn*Cache/ShaderCache),
  # CachedData, logs, Crashpad, tmp — at any depth, pruned so we never recurse
  # into a matched dir. The PROTECTED guard skips sync/messaging/mail paths.
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    _wiz_protected "$hit" && continue
    local kb=$(du -sk "$hit" 2>/dev/null | cut -f1); [ -z "$kb" ] && kb=0
    [ "$kb" -lt 1024 ] && continue   # ignore <1MB noise
    local owner=$(echo "$hit" | sed -E "s|$HOME/Library/(Application Support\|Containers)/||; s|/.*||")
    CANDIDATES+=("SAFE|$kb|$hit|${owner} · $(basename "$hit")|App cache/log — rebuilds")
  done < <(find "$HOME/Library/Application Support" "$HOME/Library/Containers" \
              -maxdepth 5 -type d \( \
                 -iname "Cache" -o -iname "Caches" -o -iname "Code Cache" \
                 -o -iname "*Cache" -o -iname "CachedData" -o -iname "CachedExtensionVSIXs" \
                 -o -iname "logs" -o -iname "Crashpad" -o -iname "tmp" \
              \) -prune -print 2>/dev/null)

  # ───── 🟢 SAFE: updater caches (downloaded installers, pattern) ─────
  for up in "$HOME/Library/Caches"/*[Uu]pdater* "$HOME/Library/Caches"/*-updater; do
    [ -d "$up" ] && add_candidate SAFE "$up" "Updater cache · $(basename "$up")" "Old downloaded installers"
  done
  for shipit in "$HOME/Library/Caches"/*.ShipIt; do
    [ -d "$shipit" ] && add_candidate SAFE "$shipit" "Squirrel updater · $(basename "$shipit")" "Old auto-update payload"
  done

  # ───── 🟢 SAFE: confirmed leftovers (owning app NOT installed) ─────
  for tool in cursor windsurf trae codeium antigravity comet manus qwen wispr ollama; do
    case "$INSTALLED" in *" $tool "*|*"$tool"*) continue ;; esac   # app present → skip
    add_candidate SAFE "$HOME/.$tool"                            "Leftover · .$tool"        "Owning app not installed"
  done

  # ───── 🟡 REVIEW: large but re-downloadable / re-installable ─────
  add_candidate REVIEW "$HOME/.vscode/extensions"                "VSCode extensions (~/.vscode)" "Re-installable from Marketplace"
  add_candidate REVIEW "$HOME/.lmstudio/extensions"              "LM Studio · runtimes/extensions" "Re-downloadable"
  for m in "$HOME/.lmstudio/models"/*/; do
    [ -d "$m" ] && add_candidate REVIEW "$m" "LM Studio model · $(basename "$m")" "Re-downloadable from catalog"
  done
  # IDEs in ~/Applications — the single biggest opportunity on this Mac
  for a in "$HOME/Applications"/*.app; do
    [ -d "$a" ] && add_candidate REVIEW "$a" "IDE · $(basename "$a")" "Re-installable (JetBrains Toolbox etc.)"
  done

  # ── Tally ─────────────────────────────────────────────────
  local safe_total=0 review_total=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ "$tier" = "SAFE" ]   && safe_total=$((safe_total+kb))
    [ "$tier" = "REVIEW" ] && review_total=$((review_total+kb))
  done

  echo ""
  divider
  echo -e "  ${BGREEN}🟢 Safe to delete now:${RESET}        ${BOLD}$(human_kb $safe_total)${RESET}"
  echo -e "  ${BYELLOW}🟡 Re-downloadable (review):${RESET}  ${BOLD}$(human_kb $review_total)${RESET}"
  echo -e "  ${BRED}🔴 Protected (never touched):${RESET} ${DIM}OneDrive, WhatsApp, iCloud, your files${RESET}"
  divider

  # ── Action menu ───────────────────────────────────────────
  echo ""
  echo -e "  ${BOLD}How would you like to proceed?${RESET}"
  echo -e "  ${BOLD}a)${RESET} ${BGREEN}Auto-clean ALL 🟢 safe items${RESET} ${DIM}(recommended, instant)${RESET}"
  echo -e "  ${BOLD}p)${RESET} Pick items one-by-one ${DIM}(includes 🟡 review items)${RESET}"
  echo -e "  ${BOLD}l)${RESET} List everything first ${DIM}(no deletion)${RESET}"
  echo -e "  ${BOLD}b)${RESET} Back to menu"
  ask_choice "[a]uto  [p]ick  [l]ist  [b]ack"
  read -r wchoice

  case "$wchoice" in
    a|A) _wizard_auto_safe ;;
    p|P) _wizard_pick ;;
    l|L) _wizard_list; safe_wizard ;;
    b|B|q|Q) main_menu ;;
    *) warning "Invalid option — try one of the keys shown"; sleep 1; safe_wizard ;;
  esac
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
    main_menu; return
  fi

  echo ""
  local freed=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    if [ "$tier" = "SAFE" ] && [ -e "$path" ]; then
      rm -rf "$path"
      freed=$((freed+kb))
      success "$label ${DIM}($(human_kb $kb))${RESET}"
    fi
  done
  echo ""
  divider
  echo -e "  ${BGREEN}✨ Done! Freed ${BYELLOW}${BOLD}$(human_kb $freed)${RESET}"
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
  info "$total_items items to review — y = delete, Enter = keep"

  local freed=0 item_num=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ ! -e "$path" ] && continue
    item_num=$((item_num+1))
    local tag="🟢"; [ "$tier" = "REVIEW" ] && tag="🟡"
    echo ""
    echo -e "  ${tag} [${item_num}/${total_items}] ${BOLD}${label}${RESET}  ${BOLD}$(color_size $(human_kb $kb))${RESET}"
    echo -e "     ${DIM}${note}${RESET}"
    echo -e "     ${DIM}${path}${RESET}"
    echo -ne "     ${BYELLOW}Delete? [y/N]: ${RESET}"
    read -r ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      rm -rf "$path"
      freed=$((freed+kb))
      success "Deleted ${DIM}($(human_kb $kb))${RESET}"
    else
      skipped "Kept"
    fi
  done
  echo ""
  divider
  echo -e "  ${BGREEN}✨ Total freed: ${BYELLOW}${BOLD}$(human_kb $freed)${RESET}"
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
  df -h / | awk 'NR==2 {printf "  Total:     %s\n  Used:      %s (%s)\n  Available: %s\n",$2,$3,$5,$4}'
  local purge=$(df / | awk 'NR==2{print $4}')
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
  echo -e "  ${BGREEN}${BOLD}👉 Tip: use option 10 (Safe Cleanup Wizard) to free space safely.${RESET}"
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
  info "Scanning caches, logs, updater downloads, and leftovers..."
  echo ""

  # Pass 1: scan and build "kb|path|label" preview lines (same paths as before)
  PREVIEW="" ; total_kb=0
  _qc_scan() {
    local p="$1" l="$2"
    [ -e "$p" ] || return
    local kb=$(du -sk "$p" 2>/dev/null|cut -f1); kb=${kb:-0}
    PREVIEW="${PREVIEW}${kb}|${p}|${l}"$'\n'
    total_kb=$((total_kb+kb))
  }
  _qc_scan ~/Library/Caches                                          "System Caches"
  _qc_scan ~/Library/Logs                                            "Log Files"
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
  _qc_scan ~/Library/Caches/JetBrains                                "JetBrains System Cache"
  _qc_scan ~/Library/Application\ Support/Spotify/PersistentCache    "Spotify Cache"
  for tool in cursor windsurf trae codeium; do
    _qc_scan ~/."$tool" "${tool} dot-folder"
  done
  _qc_scan ~/.Trash                                                  "Trash"

  # Check if anything was found
  if [ "$total_kb" -eq 0 ]; then
    success "Nothing to clean — already tidy! 🎉"
    _back_to_menu
    return
  fi

  # Show preview
  section "Items to be deleted"
  while IFS='|' read -r kb path label; do
    [ -z "$kb" ] && continue
    printf "  %-9s %s\n" "$(color_size $(human_kb "$kb"))" "$label"
  done <<< "$PREVIEW"

  # Single confirmation
  echo ""; divider
  if ! confirm "Delete all of the above ($(human_kb $total_kb))? This is safe — apps rebuild these automatically."; then
    skipped "Nothing deleted"
    _back_to_menu
    return
  fi

  # Pass 2: Delete and report
  echo ""
  local freed_kb=0
  while IFS='|' read -r kb path label; do
    [ -z "$kb" ] && continue
    if [ -e "$path" ]; then
      rm -rf "$path"
      success "$label ${DIM}($(human_kb $kb))${RESET}"
      freed_kb=$((freed_kb+kb))
    fi
  done <<< "$PREVIEW"

  echo ""; divider
  echo -e "  ${BGREEN}✨ Freed approximately ${BYELLOW}${BOLD}$(human_kb $freed_kb)${RESET}"
  divider
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   9) INTERACTIVE CLEAN
# ══════════════════════════════════════════════════════════════
#   Broader/more aggressive than the wizard—offers IDEs, LM Studio models, VSCode extensions one-by-one
# ══════════════════════════════════════════════════════════════
TOTAL_FREED=""
safe_delete() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    local size=$(du -sh "$path" 2>/dev/null|cut -f1)
    if confirm "Delete ${label} (${size})?"; then
      rm -rf "$path"; success "Deleted ${label} — ${BYELLOW}${size}${RESET}"
      TOTAL_FREED="${TOTAL_FREED}${size} ← ${label}\n"
    else skipped "Skipped ${label}"; fi
  fi
}
interactive_clean() {
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
    echo -e "  ${BGREEN}✨ Deleted:${RESET}"; printf "$TOTAL_FREED" | while read l; do [ -n "$l" ] && echo -e "    ${GREEN}• $l${RESET}"; done
  else info "Nothing deleted."; fi
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
      echo "$models" | while read name id size modified; do
        printf "  %-30s %-10s %s\n" "$name" "$size" "$modified"
      done
    fi
  fi
  echo ""; info "Models re-download anytime via: ollama pull <model>"
  if confirm "Start interactive model deletion?"; then
    if command -v ollama >/dev/null 2>&1; then
      ollama list 2>/dev/null | tail -n +2 | while read name id size modified; do
        echo "  Removing: $name"
        ollama rm "$name" 2>/dev/null
      done
    fi
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
  clear; section "📝 SAVING FULL REPORT"; info "→ $REPORT_FILE"; echo ""
  {
    echo "MAC STORAGE REPORT — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Host: $(hostname) | macOS: $(sw_vers -productVersion)"
    echo "================================================"
    echo ""; echo "DISK"; df -h /
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
  local fs num
  if echo "$ms" | grep -qiE '^[0-9]+G$'; then num=$(echo "$ms"|grep -oE '[0-9]+'); fs="+$((num*1024))M"
  else num=$(echo "$ms"|grep -oE '[0-9]+'); fs="+${num}M"; fi
  echo ""; info "Scanning for files > ${BYELLOW}${ms}${RESET}... (a moment)"; echo ""
  find ~ -type f -size $fs 2>/dev/null | while read f; do
    printf "  %-10s %s\n" "$(color_size $(du -sh "$f" 2>/dev/null|cut -f1))" "$f"
  done | sort -rh | head -30
  echo ""; info "Top 30 shown."
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
  local tmp; tmp=$(mktemp)
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
  local rows=14 cols=28
  for ((y=0; y<rows; y++)); do
    local line="  "
    for ((x=0; x<cols; x++)); do
      local ch=$(awk -v x="$x" -v y="$y" -v cols="$cols" -v rows="$rows" -v n="$n" -v boundstr="$(printf '%s ' "${pcts[@]}")" '
        BEGIN{
          pi=3.14159265358979
          cx=(cols-1)/2.0; cy=(rows-1)/2.0
          dx=(x-cx)/ (cols/2.0); dy=(y-cy)/(rows/2.0)
          dist=sqrt(dx*dx+dy*dy)
          if (dist>1.0) { print " "; exit }
          ang=atan2(-dy,dx)*180/pi
          if (ang<0) ang+=360
          pct = ang/360*100
          split(boundstr, b, " ")
          for (k=1;k<=n;k++) { if (pct<=b[k]) { print k; exit } }
          print n
        }
      ')
      if [ "$ch" = " " ]; then
        line+=" "
      else
        local slot=$((ch-1))
        line+="${palette_colors[$slot]}${palette_chars[$slot]}${RESET}"
      fi
    done
    echo -e "$line"
  done
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
  [ -d ~/.lmstudio/models ] && { info "LM Studio models: $(du -sh ~/.lmstudio/models 2>/dev/null|cut -f1) — option 6 to manage"; found=1; }
  [ -d ~/.ollama/models ] && { info "Ollama models: $(du -sh ~/.ollama/models 2>/dev/null|cut -f1) — option 7 to manage"; found=1; }
  [ "$found" -eq 0 ] && success "Looks clean! 🎉"
}

_back_to_menu() { echo ""; echo -ne "  ${DIM}Press any key to return to menu...${RESET}"; read -rn1; main_menu; }

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
    echo "- Generator: storage_check.sh v3.2"
    echo ""
    echo "---"
    echo ""
    echo "## 0. INSTRUCTIONS FOR CLAUDE CODE (the improver)"
    echo ""
    echo "You are improving the bash tool \`storage_check.sh\`. Use the data below to make it better at TWO things:"
    echo ""
    echo "1. **Detect deletable files dynamically.** Today the Safe Cleanup Wizard (option 10) uses a hardcoded"
    echo "   list of paths. Replace/augment it with rules that work on ANY Mac by reasoning from sections 4-6:"
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
    df -h /
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
    echo "### 2a. Current \`_match_folder\` heuristic"
    echo '```'
    echo "lowercase the folder name, then:"
    echo " 1) hit if it equals / contains / is-contained-by any installed bundle id"
    echo " 2) else strip reverse-dns prefix to last token; hit if it matches any installed app name (token >=4 chars)"
    echo " 3) else => ORPHAN?"
    echo '```'
    echo "### 2b. Wizard SAFE list (hardcoded today)"
    echo '```'
    echo "~/Library/Caches (whole), ~/Library/Logs, ~/.Trash, ~/.cache"
    echo "Claude: Cache, Code Cache, GPUCache, DawnWebGPUCache, DawnGraphiteCache, vm_bundles"
    echo "VSCode: Cache, CachedData, CachedExtensionVSIXs, logs"
    echo "JetBrains: Caches/JetBrains + per-IDE caches/ and log/"
    echo "Updaters: draw.io-updater, manus-updater, qwen-updater, ms-playwright-go, waveterm-updater"
    echo "Misc: Caches/aws, Spotify PersistentCache+cache, Comet, Google, SiriTTS"
    echo "Leftovers (only if app NOT installed): .cursor .windsurf .trae .codeium .antigravity + App Support"
    echo '```'
    echo "### 2c. Wizard REVIEW list"
    echo '```'
    echo "~/.lmstudio/extensions ; ~/.lmstudio/models/* (per model)"
    echo '```'
    echo "### 2d. PROTECTED (never offered) — keep & expand"
    echo '```'
    echo "OneDrive, iCloud(Mobile Documents), Dropbox, Google Drive(DriveFS/CloudStorage),"
    echo "WhatsApp, Telegram, Photos, Mail, Documents/Pictures/Movies, installed-app preferences"
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
      tmutil deletelocalsnapshots / 2>/dev/null && success "All local snapshots deleted" \
        || warning "Could not delete snapshots (may require Full Disk Access)"
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
    for bk in "$mb"/*/; do
      [ -d "$bk" ] && safe_delete "$bk" "Device backup: $(basename "$bk")"
    done
  fi

  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#  11) APPLICATIONS MANAGER
# ══════════════════════════════════════════════════════════════
applications_manager() {
  clear
  section "📱 APPLICATIONS MANAGER"
  echo -e "  ${DIM}Deletion moves the app to Trash — changes are permanent.${RESET}\n"

  local found=0

  section "/Applications  (system-wide)"
  if [ -d /Applications ]; then
    found=1
    du -sk /Applications/*.app 2>/dev/null | sort -rn | while read kb path; do
      printf "  %-10s %s\n" "$(color_size $(human_kb $kb))" "$(basename "$path")"
    done
  else
    skipped "Not found"
  fi

  section "~/Applications  (user installs)"
  if [ -d "$HOME/Applications" ]; then
    found=1
    du -sk "$HOME/Applications"/*.app 2>/dev/null | sort -rn | while read kb path; do
      printf "  %-10s %s\n" "$(color_size $(human_kb $kb))" "$(basename "$path")"
    done
  else
    skipped "Not found"
  fi

  [ "$found" -eq 0 ] && { info "No applications found."; _back_to_menu; return; }

  echo ""
  info "Total /Applications: $(du -sh /Applications 2>/dev/null | cut -f1)"
  [ -d "$HOME/Applications" ] && info "Total ~/Applications: $(du -sh "$HOME/Applications" 2>/dev/null | cut -f1)"

  echo ""
  local am_loop=1
  while [ "$am_loop" -eq 1 ]; do
    ask_choice "[d]elete  [m]ove to USB  [r]estore  [x]relink missing  [b]ack"
    read -r am_choice
    case "$am_choice" in
      d) _delete_apps_multi ;;
      m) _move_app_to_usb ;;
      r) _restore_app_from_usb ;;
      x) _relink_missing_apps ;;
      b|B|q|Q) am_loop=0 ;;
      *) warning "Invalid option — try one of the keys shown" ;;
    esac
  done

  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   DELETE ONE OR MORE APPS (numbered multi-select)
# ══════════════════════════════════════════════════════════════
_delete_apps_multi() {
  section "🗑️  Select apps to delete"

  # Collect apps sorted by size descending
  local app_list app_list_unsorted app
  app_list_unsorted=$(find /Applications "$HOME/Applications" -maxdepth 1 -name "*.app" -type d ! -type l 2>/dev/null)
  app_list=$(echo "$app_list_unsorted" | while read app; do
    local kb; kb=$(du -sk "$app" 2>/dev/null | cut -f1)
    echo "$kb	$app"
  done | sort -rn | cut -f2)

  local -a app_paths app_locked
  local idx=1
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    app_paths[$idx]="$app"
    local kb; kb=$(du -sk "$app" 2>/dev/null | cut -f1)
    if _wiz_protected "$app"; then
      app_locked[$idx]=1
      printf "  %2d) %-9s %s  ${BRED}🔒 PROTECTED${RESET}\n" "$idx" "$(color_size $(human_kb "${kb:-0}"))" "$(basename "$app")"
    else
      app_locked[$idx]=0
      printf "  %2d) %-9s %s\n" "$idx" "$(color_size $(human_kb "${kb:-0}"))" "$(basename "$app")"
    fi
    idx=$((idx+1))
  done <<< "$app_list"

  if [ "$idx" -eq 1 ]; then
    info "No deletable apps found."
    return
  fi

  echo -ne "\n  ${BCYAN}App number(s) to delete ${DIM}(e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; return; }

  local -a idxs
  idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; return
  fi

  # Filter out protected apps
  local -a selectable
  for i in "${idxs[@]}"; do
    if [ "${app_locked[$i]:-0}" -eq 1 ]; then
      danger "'$(basename "${app_paths[$i]}")' is protected (sync/messaging app) — skipped. Manage it from the app itself."
    else
      selectable+=("$i")
    fi
  done

  if [ "${#selectable[@]}" -eq 0 ]; then
    skipped "Nothing selectable was chosen"
    return
  fi

  echo ""; info "Selected for deletion:"
  local total_kb=0 i
  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    local kb; kb=$(du -sk "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
    total_kb=$((total_kb+kb))
    printf "  - %-9s %s\n" "$(color_size $(human_kb "$kb"))" "$(basename "$p")"
  done

  echo ""
  if ! confirm "Delete these ${#selectable[@]} app(s), freeing ~$(human_kb "$total_kb")? This moves them to Trash-equivalent (permanent rm)."; then
    skipped "Cancelled"; return
  fi

  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    if [ -e "$p" ]; then
      if ! _app_removable "$p"; then
        danger "'$(basename "$p")' was installed with admin rights (root-owned files) — delete it via Finder instead (asks for your admin password). Skipped."
        continue
      fi
      rm -rf "$p" 2>/dev/null
      if [ -e "$p" ]; then
        danger "Could not fully delete '$(basename "$p")' (permission denied) — it may need Finder/admin removal."
      else
        success "Deleted $(basename "$p")"
      fi
    fi
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

  # Collect apps sorted by size descending
  local app_list app_list_unsorted app
  app_list_unsorted=$(find /Applications "$HOME/Applications" -maxdepth 1 -name "*.app" -type d ! -type l 2>/dev/null)
  app_list=$(echo "$app_list_unsorted" | while read app; do
    local kb; kb=$(du -sk "$app" 2>/dev/null | cut -f1)
    echo "$kb	$app"
  done | sort -rn | cut -f2)

  local -a app_paths app_locked
  local idx=1
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    app_paths[$idx]="$app"
    local kb; kb=$(du -sk "$app" 2>/dev/null | cut -f1)
    if _wiz_protected "$app"; then
      app_locked[$idx]=1
      printf "  %2d) %-9s %s  ${BRED}🔒 PROTECTED${RESET}\n" "$idx" "$(color_size $(human_kb "${kb:-0}"))" "$(basename "$app")"
    else
      app_locked[$idx]=0
      printf "  %2d) %-9s %s\n" "$idx" "$(color_size $(human_kb "${kb:-0}"))" "$(basename "$app")"
    fi
    idx=$((idx+1))
  done <<< "$app_list"

  if [ "$idx" -eq 1 ]; then
    info "No movable apps found (already-moved apps are symlinks — use [r]estore)."
    return
  fi

  echo -ne "\n  ${BCYAN}App number(s) to move ${DIM}(e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; return
  fi

  # Filter out protected apps
  local -a selectable
  for i in "${sel_idxs[@]}"; do
    if [ "${app_locked[$i]:-0}" -eq 1 ]; then
      danger "'$(basename "${app_paths[$i]}")' is protected (sync/messaging app) — skipped. Manage it from the app itself."
    else
      selectable+=("$i")
    fi
  done

  if [ "${#selectable[@]}" -eq 0 ]; then
    skipped "Nothing selectable was chosen"
    return
  fi

  local vols; vols=$(_external_volumes)
  if [ -z "$vols" ]; then
    warning "No external/USB drives are mounted. Connect one and try again."
    return
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
  [ -z "$vsel" ] && { skipped "Cancelled"; return; }
  local vol="${vol_names[$vsel]}"
  if [ -z "$vol" ] || [ ! -d "/Volumes/$vol" ]; then
    warning "Invalid selection"; return
  fi

  local dest_dir="/Volumes/$vol/AppsOnExternal"
  local avail_kb; avail_kb=$(df -k "/Volumes/$vol" 2>/dev/null | awk 'NR==2{print $4}'); avail_kb=${avail_kb:-0}

  echo ""; info "Selected to move:"
  local total_kb=0 i
  for i in "${selectable[@]}"; do
    local p="${app_paths[$i]}"
    local kb; kb=$(du -sk "$p" 2>/dev/null | cut -f1); kb=${kb:-0}
    total_kb=$((total_kb+kb))
    printf "  - %-9s %s\n" "$(color_size $(human_kb "$kb"))" "$(basename "$p")"
  done

  if [ "$total_kb" -gt "$avail_kb" ]; then
    danger "Not enough free space on '$vol' ($(human_kb "$avail_kb") free, need $(human_kb "$total_kb") total)"
    return
  fi

  echo ""
  if ! confirm "Move these ${#selectable[@]} app(s) ($(human_kb "$total_kb")) to '$vol'? They will only launch while this drive is connected."; then
    skipped "Cancelled"; return
  fi

  mkdir -p "$dest_dir"
  for i in "${selectable[@]}"; do
    local app="${app_paths[$i]}"
    local app_name; app_name=$(basename "$app")
    local dest="$dest_dir/$app_name"
    local app_kb; app_kb=$(du -sk "$app" 2>/dev/null | cut -f1); app_kb=${app_kb:-0}

    local use_sudo=0
    if ! _app_removable "$app"; then
      warning "'$app_name' was installed with admin rights (root-owned files)."
      if confirm "Complete the move with your admin password (sudo)?"; then
        use_sudo=1
      else
        skipped "Skipped '$app_name'"
        continue
      fi
    fi

    if [ -e "$dest" ]; then
      local dest_size; dest_size=$(du -sk "$dest" 2>/dev/null | cut -f1); dest_size=${dest_size:-0}
      warning "'$app_name' already has a copy on '$vol' ($(human_kb "$dest_size"), from a previous move)."
      if confirm "Overwrite it with a fresh copy from the internal disk? (n = decide next)"; then
        rm -rf "$dest"
      elif [ "$dest_size" -gt 0 ] && confirm "Use the EXISTING external copy instead, and free the internal one? (it may be older)"; then
        rm -rf "$app"
        if [ -e "$app" ]; then
          danger "Could not fully remove '$app_name' — restoring it from the external copy."
          ditto "$dest" "$app" 2>/dev/null
          continue
        fi
        ln -s "$dest" "$app"
        success "Linked '$app_name' to existing external copy — freed $(human_kb "$app_kb") on internal disk"
        continue
      else
        skipped "Skipped '$app_name'"
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
      continue
    fi

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
      continue
    fi
    success "Moved '$app_name' — freed $(human_kb "$app_kb") on internal disk"
  done
}

# ══════════════════════════════════════════════════════════════
#   RESTORE APP FROM USB DRIVE
# ══════════════════════════════════════════════════════════════
_restore_app_from_usb() {
  section "🔄 Restore App from USB / External Drive"

  local -a link_paths
  local -a link_targets
  local idx=1
  for app in /Applications/*.app "$HOME/Applications"/*.app; do
    [ -L "$app" ] || continue
    local target; target=$(readlink "$app")
    link_paths[$idx]="$app"
    link_targets[$idx]="$target"
    local status="${BGREEN}connected${RESET}"
    [ -e "$target" ] || status="${BRED}drive not connected${RESET}"
    printf "  %2d) %-40s -> %s [%b]\n" "$idx" "$(basename "$app")" "$target" "$status"
    idx=$((idx+1))
  done

  if [ "$idx" -eq 1 ]; then
    info "No externally-moved apps found."
    return
  fi

  echo -ne "\n  ${BCYAN}App number(s) to restore ${DIM}(e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; return
  fi

  echo ""; info "Selected to restore:"
  local i
  for i in "${sel_idxs[@]}"; do
    printf "  - %s\n" "$(basename "${link_paths[$i]}")"
  done

  echo ""
  if ! confirm "Restore these ${#sel_idxs[@]} app(s) back to internal disk?"; then
    skipped "Cancelled"; return
  fi

  for i in "${sel_idxs[@]}"; do
    local app="${link_paths[$i]}"
    local target="${link_targets[$i]}"
    local app_name; app_name=$(basename "$app")

    if [ ! -e "$target" ]; then
      danger "Target '$target' is not reachable — skipping '$app_name'"
      continue
    fi

    local restore_path="$app"
    rm -f "$app"
    echo -n "  Copying '$app_name' back to internal disk... "
    if ditto "$target" "$restore_path" 2>/dev/null && [ -d "$restore_path" ] && [ -n "$(ls -A "$restore_path" 2>/dev/null)" ]; then
      echo -e "${BGREEN}done${RESET}"
    else
      echo -e "${BRED}failed${RESET}"
      danger "Restore failed for '$app_name' — re-linking to external copy so it stays usable."
      rm -rf "$restore_path" 2>/dev/null
      ln -s "$target" "$restore_path"
      continue
    fi

    success "Restored '$app_name' to internal disk"
    if confirm "Delete the external copy at '$target'?"; then
      rm -rf "$target"
      success "Removed external copy"
    fi
  done
}

# ══════════════════════════════════════════════════════════════
#   RELINK APPS WITH A MISSING LAUNCHER LINK
#   (bundle still on external AppsOnExternal, but the symlink in
#    /Applications or ~/Applications is gone — recreate it without
#    copying/moving any bytes)
# ══════════════════════════════════════════════════════════════
_relink_missing_apps() {
  section "🔗 Relink Apps with Missing Launcher"

  local vols; vols=$(_external_volumes)
  if [ -z "$vols" ]; then
    warning "No external/USB drives are mounted. Connect one and try again."
    return
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
    return
  fi

  info "Found $((idx-1)) app(s) on external drive(s) with no launcher in /Applications or ~/Applications:"
  local i
  for ((i=1; i<idx; i++)); do
    local kb; kb=$(du -sk "${cand_bundle[$i]}" 2>/dev/null | cut -f1); kb=${kb:-0}
    printf "  %2d) %-9s %-30s ${DIM}%s${RESET}\n" "$i" "$(color_size $(human_kb "$kb"))" "${cand_name[$i]}" "${cand_bundle[$i]}"
  done

  echo -ne "\n  ${BCYAN}App number(s) to relink ${DIM}(e.g. 2 or 1,3,5-7)${RESET}${BCYAN}, blank to cancel: ${RESET}"
  read -r sel
  [ -z "$sel" ] && { skipped "Cancelled"; return; }

  local -a sel_idxs
  sel_idxs=($(_parse_selection "$sel" $((idx-1))))
  if [ "${#sel_idxs[@]}" -eq 0 ]; then
    warning "No valid selection"; return
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

  local relinked=0
  for i in "${sel_idxs[@]}"; do
    local bundle="${cand_bundle[$i]}" name="${cand_name[$i]}"
    local target="$dest_base/$name"

    if _wiz_protected "$target" || _wiz_protected "$bundle"; then
      danger "'$name' is protected — skipped."
      continue
    fi
    if [ -e "$target" ] || [ -L "$target" ]; then
      warning "'$name' already exists at '$target' — skipped."
      continue
    fi

    ln -s "$bundle" "$target" 2>/dev/null
    if [ -L "$target" ]; then
      success "Relinked '$name' -> $bundle"
      relinked=$((relinked+1))
    else
      danger "Could not create the launcher link for '$name' at '$target'."
    fi
  done

  echo ""
  info "$relinked app(s) relinked."
}

# ══════════════════════════════════════════════════════════════
#   12) VSCODE EXTENSION MANAGER
# ══════════════════════════════════════════════════════════════
vscode_manager() {
  local -a VARIANTS
  local -a PATHS
  local -a LABELS

  VARIANTS=("$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" \
            "$HOME/.vscode-oss/extensions" "$HOME/.vscodium/extensions" \
            "$HOME/.cursor/extensions" "$HOME/.windsurf-next/extensions" \
            "$HOME/.windsurf/extensions" "$HOME/.trae/extensions" \
            "$HOME/.antigravity-ide/extensions" "$HOME/.devin/extensions" \
            "$HOME/.positon/extensions" "$HOME/.kiro/extensions")

  LABELS=("VS Code" "VS Code Insiders" "VSCodium (1)" "VSCodium (2)" \
          "Cursor" "Windsurf (next)" "Windsurf" "Trae" \
          "Antigravity IDE" "Devin" "Positon" "Kiro")

  local found=0
  local idx=0

  clear
  section "🔌 VSCODE EXTENSION MANAGER"

  for var in "${VARIANTS[@]}"; do
    if [ -d "$var" ]; then
      PATHS+=("$var")
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

# ── Entry ─────────────────────────────────────────────────────
main_menu
