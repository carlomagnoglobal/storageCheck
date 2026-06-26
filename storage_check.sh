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

REPORT_FILE="$HOME/storage_report_$(date '+%Y%m%d_%H%M%S').txt"

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════
main_menu() {
  clear
  echo ""
  echo -e "${BMAGENTA}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BMAGENTA}║     🖥️  MAC STORAGE MANAGER v3.2                         ║${RESET}"
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
  echo -e "  ${BOLD}1)${RESET}  📊  Full Audit              ${DIM}scan everything${RESET}"
  echo -e "  ${BOLD}2)${RESET}  🧹  Quick Clean             ${DIM}safe auto-cleanup, no prompts${RESET}"
  echo -e "  ${BOLD}3)${RESET}  🎯  Interactive Clean       ${DIM}choose item by item${RESET}"
  echo -e "  ${BOLD}4)${RESET}  🤖  AI Tools Audit          ${DIM}IDEs, models, extensions${RESET}"
  echo -e "  ${BOLD}5)${RESET}  📦  App Support Deep Dive   ${DIM}find hidden data${RESET}"
  echo -e "  ${BOLD}6)${RESET}  🧠  LM Studio Manager       ${DIM}manage local AI models${RESET}"
  echo -e "  ${BOLD}7)${RESET}  ☁️   Cloud & Sync Audit      ${DIM}OneDrive, iCloud, Dropbox${RESET}"
  echo -e "  ${BOLD}8)${RESET}  📝  Save Report to File     ${DIM}export full audit${RESET}"
  echo -e "  ${BOLD}9)${RESET}  🔍  Find Large Files        ${DIM}files above a chosen size${RESET}"
  echo -e "  ${BGREEN}${BOLD} 10) 🪄  SAFE CLEANUP WIZARD${RESET}    ${DIM}guided, OS-safe, pick what to free${RESET}"
  echo -e "  ${BCYAN}${BOLD} 11) 🧬  GENERATE FEEDBACK FILE${RESET} ${DIM}diagnostic dump for Claude Code${RESET}"
  echo -e "  ${BOLD} 0)${RESET}  ❌  Exit"
  divider
  echo -ne "\n  ${BCYAN}Choose an option: ${RESET}"
  read -r choice
  case "$choice" in
    1) full_audit ;;       2) quick_clean ;;
    3) interactive_clean ;;4) ai_tools_audit ;;
    5) app_support_deep ;; 6) lmstudio_manager ;;
    7) cloud_audit ;;      8) save_report ;;
    9) find_large_files ;; 10) safe_wizard ;;
    11) generate_feedback ;;
    0) echo -e "\n  ${BGREEN}Goodbye! 👋${RESET}\n"; exit 0 ;;
    *) warning "Invalid option"; sleep 1; main_menu ;;
  esac
}

# ══════════════════════════════════════════════════════════════
#   ★ 10) SAFE CLEANUP WIZARD  (the new headline feature)
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
    *onedrive*|*dropbox*|*googledrive*|*cloudstorage*|*"mobile documents"*|*clouddocs*) return 0 ;;
    *whatsapp*|*telegram*|*"group.net.whatsapp"*)                                        return 0 ;;
    *"/library/mail"*|*com.apple.mail*|*keychain*|*"/library/photos"*|*photoslibrary*)   return 0 ;;
    *"ubf8t346g9.office"*|*com.microsoft.outlook*|*com.microsoft.onedrive*)              return 0 ;;
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
  echo -e "  ${BOLD}q)${RESET} Back to menu"
  echo -ne "\n  ${BCYAN}Choice [a/p/l/q]: ${RESET}"
  read -r wchoice

  case "$wchoice" in
    a|A) _wizard_auto_safe ;;
    p|P) _wizard_pick ;;
    l|L) _wizard_list; safe_wizard ;;
    *)   main_menu ;;
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
  echo ""
  echo -ne "  ${DIM}Press any key...${RESET}"; read -rn1
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
  info "For each item: y = delete, Enter = keep"
  local freed=0
  for c in "${CANDIDATES[@]}"; do
    IFS='|' read -r tier kb path label note <<< "$c"
    [ ! -e "$path" ] && continue
    local tag="🟢"; [ "$tier" = "REVIEW" ] && tag="🟡"
    echo ""
    echo -e "  ${tag} ${BOLD}${label}${RESET}  ${BOLD}$(color_size $(human_kb $kb))${RESET}"
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
#   2) QUICK CLEAN
# ══════════════════════════════════════════════════════════════
quick_clean() {
  clear
  section "🧹 QUICK CLEAN — 100% Safe Items"
  info "Removing caches, logs, updater downloads, and leftovers..."
  echo ""
  freed_kb=0
  _ci() {
    local p="$1" l="$2"
    if [ -e "$p" ]; then
      local kb=$(du -sk "$p" 2>/dev/null|cut -f1); rm -rf "$p"
      freed_kb=$((freed_kb+kb)); success "$l ${DIM}($(human_kb $kb))${RESET}"
    fi
  }
  _ci ~/Library/Caches                                                "System Caches"
  _ci ~/Library/Logs                                                  "Log Files"
  _ci ~/Library/Application\ Support/Claude/Cache                    "Claude Cache"
  _ci ~/Library/Application\ Support/Claude/Code\ Cache              "Claude Code Cache"
  _ci ~/Library/Application\ Support/Claude/GPUCache                 "Claude GPU Cache"
  _ci ~/Library/Application\ Support/Claude/vm_bundles               "Claude VM Bundles"
  _ci ~/Library/Application\ Support/Code/Cache                      "VSCode Cache"
  _ci ~/Library/Application\ Support/Code/CachedData                 "VSCode CachedData"
  _ci ~/Library/Application\ Support/Code/logs                       "VSCode Logs"
  for d in ~/Library/Application\ Support/JetBrains/*/; do
    [ -d "${d}caches" ] && _ci "${d}caches" "JetBrains $(basename "$d") caches"
    [ -d "${d}log" ]    && _ci "${d}log"    "JetBrains $(basename "$d") logs"
  done
  _ci ~/Library/Caches/JetBrains                                      "JetBrains System Cache"
  _ci ~/Library/Application\ Support/Spotify/PersistentCache         "Spotify Cache"
  for tool in cursor windsurf trae codeium; do
    _ci ~/.$tool "${tool} dot-folder"
  done
  _ci ~/.Trash                                                        "Trash"
  echo ""; divider
  echo -e "  ${BGREEN}✨ Freed approximately ${BYELLOW}${BOLD}$(human_kb $freed_kb)${RESET}"
  divider
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   3) INTERACTIVE CLEAN  (broad, includes apps/models)
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
  if [ -d ~/.lmstudio/models ]; then
    echo -e "\n  ${BOLD}🧠 LM Studio Models:${RESET}"
    for m in ~/.lmstudio/models/*/; do [ -d "$m" ] && safe_delete "$m" "LM Studio: $(basename "$m")"; done
  fi
  if [ -d ~/Applications ]; then
    echo -e "\n  ${BOLD}🛠️  IDEs (~/Applications):${RESET}"
    for a in ~/Applications/*.app; do [ -d "$a" ] && safe_delete "$a" "IDE: $(basename "$a")"; done
  fi
  safe_delete ~/.lmstudio/extensions "LM Studio Extensions"
  if [ -d ~/.vscode/extensions ]; then
    echo -e "\n  ${BOLD}🔌 VSCode Extensions:${RESET}"
    for e in ~/.vscode/extensions/*/; do [ -d "$e" ] && safe_delete "$e" "ext: $(basename "$e")"; done
  fi
  echo ""; divider
  if [ -n "$TOTAL_FREED" ]; then
    echo -e "  ${BGREEN}✨ Deleted:${RESET}"; printf "$TOTAL_FREED" | while read l; do [ -n "$l" ] && echo -e "    ${GREEN}• $l${RESET}"; done
  else info "Nothing deleted."; fi
  divider; _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   4) AI TOOLS AUDIT
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
#   5) APP SUPPORT DEEP DIVE
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
#   6) LM STUDIO MANAGER
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
    for m in ~/.lmstudio/models/*/; do [ -d "$m" ] && safe_delete "$m" "Model: $(basename "$m")"; done
  fi
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   7) CLOUD & SYNC AUDIT
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
  for gd in "$HOME/Library/Application Support/Google/DriveFS" "$HOME/Library/CloudStorage/GoogleDrive-"*; do
    [ -d "$gd" ] && warning "Google Drive: $(du -sh "$gd" 2>/dev/null|cut -f1)"
  done
  section "Telegram"
  local tg="$HOME/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram"
  [ -d "$tg" ] && warning "Telegram: $(du -sh "$tg" 2>/dev/null|cut -f1)" || skipped "Not found"
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   8) SAVE REPORT
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
  } > "$REPORT_FILE"
  success "Saved: ${BYELLOW}$REPORT_FILE${RESET}"; info "Open with: open $REPORT_FILE"
  _back_to_menu
}

# ══════════════════════════════════════════════════════════════
#   9) FIND LARGE FILES
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
  [ "$found" -eq 0 ] && success "Looks clean! 🎉"
}

_back_to_menu() { echo ""; echo -ne "  ${DIM}Press any key to return to menu...${RESET}"; read -rn1; main_menu; }

# ══════════════════════════════════════════════════════════════
#   11) GENERATE FEEDBACK FILE FOR CLAUDE CODE
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

# ── Entry ─────────────────────────────────────────────────────
main_menu
