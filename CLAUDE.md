# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Repo

- **Name:** `storageCheck`
- **Executable:** `storage_check.sh` (single file, pure Bash, no build step)
- **Target:** macOS only (Bash 3.2, the system default — do **not** use Bash 4+ syntax: no `${var^}`, no `declare -A`, no `mapfile`, no `readarray`)
- **Runtime deps:** all macOS built-ins (`du`, `df`, `find`, `plutil`, `tmutil`, `diskutil`, `system_profiler`, `sw_vers`, `sysctl`). No package manager, no external libraries.

## What this is

An interactive terminal tool that audits Mac disk usage and — its core feature — a **Safe Cleanup Wizard** that finds files it can confidently say are safe to delete (caches, logs, re-downloadable data) without ever touching macOS itself, installed apps, or the user's personal/sync data.

The user runs it via:
```bash
chmod +x storage_check.sh
bash storage_check.sh
```
It opens a numbered menu (`main_menu`) and loops until the user exits.

## Architecture

One file, organized as: color/format helpers → `main_menu` (dispatcher) → one function per menu option → shared helpers at the bottom.

The menu is grouped into ANALYZE / CLEAN / MANAGE / TOOLS. **Menu numbers have been renumbered before and will be again — treat the `case` block in `main_menu` as the source of truth and refer to features by function name, not by number.**

| # | Group | Function | Purpose |
|---|---|---|---|
| 1 | Analyze | `full_audit` | Read-only deep scan with a recommendations summary at the end |
| 2 | Analyze | `storage_visualizer` | Bar/pie view of space, ordered tiny → big |
| 3 | Analyze | `find_large_files` | `find`-based search by minimum file size, user-supplied |
| 4 | Analyze | `cloud_audit` | **Read-only**, reports OneDrive/iCloud/Dropbox/WhatsApp/Telegram size — never offers to delete these |
| 5 | Analyze | `ai_tools_audit` | Lists AI IDE/tool footprints (`_ai_tools_list`) |
| 6 | Analyze | `app_support_deep` | Drill-down into `~/Library/Application Support`, Group Containers, JetBrains |
| **7** | Clean | `safe_wizard` | **The core feature.** Pattern-based 3-tier classifier — see below |
| 8 | Clean | `quick_clean` | Deletes a fixed list of well-known safe cache/log paths, one confirm for the batch |
| 9 | Clean | `interactive_clean` | Broader/more aggressive than the wizard — offers IDEs, LM Studio models, VSCode extensions one-by-one via `safe_delete` (always prompts) |
| 10 | Clean | `time_machine_manager` | Local APFS snapshots + iOS/iPadOS device backups |
| 11 | Manage | `applications_manager` | Paged TUI over installed apps: delete, move to USB, restore, relink — see below |
| 12 | Manage | `vscode_manager` | VSCode extensions: browse, delete, backup |
| 13 | Manage | `lmstudio_manager` | LM Studio model/extension inventory + optional deletion |
| 14 | Manage | `ollama_manager` | Ollama model management |
| 15 | Tools | `save_report` | Dumps a plain-text snapshot to `~/storage_report_<timestamp>.txt` |
| 16 | Tools | `generate_feedback` | Produces `~/claude_code_feedback_<timestamp>.md`: a structured diagnostic dump meant to be fed back into a Claude Code session to improve this script |
| 0 | — | exit | — |

### The 3-tier model (`safe_wizard`)

Every candidate path is tagged with exactly one tier:

- **🟢 SAFE** — caches, logs, temp, updater payloads. Apps rebuild these automatically; zero data loss. Offered for one-click bulk deletion (`_wizard_auto_safe`) or itemized review (`_wizard_pick`).
- **🟡 REVIEW** — re-downloadable but not "free" to lose (AI models, IDE installs, extensions). Always itemized, never bulk-deleted.
- **🔴 PROTECTED** — never shown, never offered, no matter what. Enforced by `_wiz_protected()`, a hard guard checked before any path is even added to the candidate list.

**`_wiz_protected()` is the single safety-critical function in this codebase.** It currently blocks (case-insensitive substring match on the full path): anything under `/com.apple.*` or `/group.com.apple.*`; OneDrive, Dropbox, Google Drive (`DriveFS` included — its `content_cache` holds offline and not-yet-uploaded files), CloudStorage, iCloud (`Mobile Documents`/`CloudDocs`), CloudKit, Box, pCloud, Nextcloud, Synology, MEGA; WhatsApp, Telegram; `~/Library/Mail`, Keychains, Photos library, Office/Outlook. Any change that touches the candidate-building logic in `_wizard_collect` must keep every path through `_wiz_protected()` before it reaches `CANDIDATES`.

SAFE candidates come from two sources, both pattern-based (not hardcoded per-app paths, so they generalize to any Mac):
1. Cache/log roots **child by child** (each child ≥1MB is its own candidate and goes through the guard): `~/Library/Caches/*`, `~/Library/Logs/*`, `~/Library/Saved Application State/*`. **Never add a root like `~/Library/Caches` as one candidate** — the guard would only see the root and sweep protected children (`com.apple.bird`, WhatsApp/OneDrive caches) along with it. Updater payloads (`*updater*`, `*.ShipIt`) are just relabelled children, so they are not counted twice. Whole-tree only where nothing protected can live inside: `~/.Trash`, Xcode `DerivedData`, CoreSimulator caches.
2. A `find`-based scan under `~/Library/Application Support` and `~/Library/Containers` (maxdepth 5, `-prune`d at the match so it never recurses into a matched dir) for directory names matching `Cache`, `Caches`, `Code Cache`, `*Cache`, `CachedData`, `CachedExtensionVSIXs`, `logs`, `Crashpad`, `tmp` — each individually re-checked against `_wiz_protected()` before being added.

The scan lives in `_wizard_collect`; `safe_wizard` runs it once and then loops its menu over the same `CANDIDATES` (listing doesn't rescan). REVIEW also holds `~/.cache` (can hold HuggingFace models) and dot-folder leftovers (`~/.cursor`, `~/.ollama`, …) that have neither a matching `.app` nor a CLI on `PATH` — never SAFE, since "no .app" is only a guess. `~/Applications/*.app` symlinks (external-drive launchers) are skipped.

More REVIEW sources: developer caches at each tool's standard location (Xcode DeviceSupport/Archives, `~/.npm/_cacache`, pnpm store, Gradle, Maven, Cargo, Go module cache, CocoaPods repos), `node_modules` untouched 90+ days (`find $HOME -maxdepth 6`, `~/Library` and dot-folders pruned, nested `node_modules` never entered), `.dmg/.pkg/.zip/.iso/.xip` in `~/Downloads` untouched 30+ days, and `.ipsw` firmware. Docker's VM disk and simulators are **tips only** in `_print_recommendations` (point at `docker system prune` / `xcrun simctl delete unavailable`) — never candidates.

Candidates are queued by `add_candidate` (guard first) and sized at the end in one `_du_batch` pass. **Running apps:** `_running_snapshot` + `_owner_running` map a `~/Library/{Caches,Application Support,Containers,Logs,Saved Application State}/<owner>` path to a running `.app` (by name, CFBundleName or bundle id). Auto-clean and `quick_clean` skip those; pick mode warns.

### The Applications Manager screen (`applications_manager`)

A full-screen, redrawn TUI built on **one cached scan** — the pattern to follow if another manager screen gets the same treatment.

- `_apps_scan` fills parallel indexed arrays `APP_PATH/NAME/KB/LOC/STATE/TARGET[1..APP_N]` (Bash 3.2: no associative arrays). `APP_STATE` is one of `ok` / `ext` (symlink to an external drive) / `lock` (`_wiz_protected`) / `admin` (bundle not owned by the user). Sizing goes through the shared `_du_batch` (fill `DU_PATHS[0..]`, read `DU_KB[0..]`): `xargs -P 8 du -sk`, joined back by path, with a `Sizing N/M` counter. Use it for any new bulk sizing instead of a serial `du` loop.
- `_apps_view` derives `VIS[]` — the visible rows after scope, name filter and sort — and the page geometry. **Row number N on screen is `VIS[N-1]`**; every sub-action maps the user's number back through `VIS`, so numbering stays consistent across pages, filters and sort orders.
- `_apps_screen` draws header box + table + key bar. `_apps_result <ok> <skipped> <failed> <freed_kb>` closes every action and sets `APPS_DIRTY=1`, which makes the loop rescan.
- The sub-actions (`_delete_apps_multi`, `_move_app_to_usb`, `_restore_app_from_usb`, `_relink_missing_apps`) **must not scan the disk themselves** — that was the original performance bug. Read the cache.
- `APP_STATE=admin` is advisory (a cheap `[ -O ]` check for the table glyph). It never authorizes anything: `_app_removable()` remains the real guard at action time.

### `generate_feedback`

Read-only. Writes a Markdown report containing: environment info, the script's *current* classification rules (so an LLM has context on what already exists), a full installed-app inventory (`system_profiler` + `/Applications` + `~/Applications` with bundle IDs via `plutil`), a storage inventory with paths, and an orphan/match analysis via `_match_folder()`.

`_match_folder()` is **informational only** — it feeds the feedback report, it does **not** drive any deletion in `safe_wizard`. Keep it that way; it's intentionally a weaker, exploratory heuristic (segment-token matching, ≥4 chars, `com.apple.*` short-circuits to `APPLE-SYSTEM`) used to spot candidate rules for humans/Claude Code to review, not to greenlight deletes directly.

## Safety invariants (do not regress)

These hold today and any change must preserve them:

1. **Nothing is deleted without going through `_wiz_protected()` first**, for every code path that adds to `CANDIDATES` in `_wizard_collect` (and every path `quick_clean` adds to its preview).
2. **`com.apple.*` and `group.com.apple.*` are never offered for deletion.** (They were previously misclassified as `ORPHAN?` by an earlier, substring-based version of `_match_folder` — this was the bug that motivated the v3.2 rewrite. Do not reintroduce substring matching on short tokens; segment matching requires ≥4 chars.)
3. **Sync/cloud and messaging stores are read-only everywhere**, including their own cache subfolders (`cloud_audit` reports sizes but never deletes; `_wiz_protected` blocks even `.../OneDrive.../Cache`).
4. **`quick_clean` and `interactive_clean` only ever touch paths that exist** (`[ -e "$path" ]` before any `rm -rf`) and report the freed size before deleting. `quick_clean` also runs every path through `_wiz_protected()`, scanning the Caches/Logs roots child by child like the wizard.
5. **No `rm -rf` on a variable that could be empty or unset.** Every deletion site is `path`-guarded; if you add a new one, guard it the same way (`[ -e "$path" ] && rm -rf "$path"`, never a bare `rm -rf "$var"`).
6. **Every menu function returns to `main_menu`'s loop** — by ending with `_back_to_menu` (waits for a key, then returns) or a plain `return`. **Never call `main_menu` from a feature**: it is a `while true` loop now, and calling it recursively grows the call stack for the whole session (the pre-v3.7 design). Don't leave a dead-end function that exits the script outside option `0`.
7. **Apps that live on an external drive are never `rm`'d from the manager.** The entry in `/Applications` is only a launcher symlink; removing it would orphan the bundle on the drive. `_delete_apps_multi` refuses `APP_STATE=ext` and points at `[r]estore`.
8. **REVIEW items and apps go to the Trash, not `rm`** (`_remove_undoable` → `_to_trash`: `/usr/bin/trash`, else Finder). Permanent `rm` happens only if trashing fails *and* the user confirms again. SAFE caches are still `rm`'d via `_rm_tracked`. Report trashed KB separately — it isn't reclaimed until the Trash is emptied.
9. **App leftovers (`_app_leftovers`) are matched only by bundle id** (read before the app is trashed) in the standard per-app folders, plus the exact app name under Application Support/Caches/Logs. No bundle id → nothing is offered. If any still-installed app has the same bundle id, its data is left alone. Every path goes through `_wiz_protected()`.

## Style conventions already in use

- snake_case function names; helpers used only inside one function are prefixed `_` (e.g. `_wiz_protected`, `_ai_tools_list`).
- Color vars are pre-defined at the top (`RED`/`BRED`/`YELLOW`/`BYELLOW`/`GREEN`/`BGREEN`/`CYAN`/`BCYAN`/`BLUE`/`BBLUE`/`MAGENTA`/`BMAGENTA`/`BOLD`/`DIM`/`RESET`) — reuse these, don't invent new ANSI codes inline.
- `--dry-run` sets `DRY_RUN=1`: `_rm_tracked` only prints `[dry run] would delete` (to stderr, so `$(...)` captures stay clean), and other destructive actions (app delete/move/restore/relink, snapshot deletion, `ollama rm`) start with `_dry_block "what" && return`. Any new destructive action needs one of the two.
- Temp files: use `_mktemp VAR [-d]` (registers the path; `_cleanup` removes it on exit or Ctrl-C). Never `x=$(_mktemp)` — the subshell loses the registration.
- During a move/restore's dangerous window (app removed, launcher not yet linked), set `PENDING_MSG` to recovery instructions; the INT/TERM trap prints it. Clear it once the window closes.
- Deletion helper: `_rm_tracked <path> <kb_before>` does the `rm -rf`, echoes the KB actually reclaimed and returns 1 if anything survived (no Full Disk Access, file in use). Use it for new deletion sites so "Freed X" totals stay honest.
- Disk numbers come from `$DATA_VOL` (`/System/Volumes/Data`, falling back to `/`). Don't use `df /` — since Catalina that is the small read-only system volume and under-reports usage (22% vs a real 77% on the dev Mac).
- Output helpers: `section "title"`, `success "msg"`, `warning "msg"`, `danger "msg"`, `info "msg"`, `skipped "msg"`, `divider`. Use these instead of raw `echo -e` for anything user-facing.
- Sizes are tracked in **KB internally** (`du -sk`) and converted for display only at the last moment via `human_kb()`. Don't parse `du -sh` output for arithmetic — it's not reliably parseable across locales/sizes.
- `confirm "question"` returns shell true/false for `[[ "$answer" =~ ^[Yy]$ ]]`; use it for any new per-item prompt instead of rolling a new read/case block.
- SAFE-tier deletion is `rm -rf` (via `_rm_tracked`) after an explicit existence check — permanent, so be conservative. Everything re-downloadable or user-chosen (REVIEW items, apps, models, extensions, device backups, app leftovers) goes through `_remove_undoable` so it lands in the Trash.

## Known limitations / open items

- `cloud_audit`, `app_support_deep`, `ai_tools_audit` are read-only by design — if asked to add deletion there, route it through the same `_wiz_protected()` guard rather than writing new ad-hoc checks.
- `_match_folder()`'s segment list is rebuilt by scanning `/Applications`, `~/Applications`, `/System/Applications`, `/Applications/Utilities` every run (`generate_feedback` only) — this is intentionally not cached; keep it that way since installed apps can change between runs.
- The script assumes a single-user `$HOME` and does not support being run as root or against another user's home directory.
- Tests: `bash tests/test_protected.sh` (65 checks; it also covers `_du_batch`, the new REVIEW sources, `_owner_running` and `_app_leftovers`, with `_to_trash` stubbed so nothing reaches the real Trash) builds a fake `$HOME` (sync engines, messaging, `com.apple.*`, mail, keychains next to ordinary caches) and checks `_wiz_protected`, `_wizard_collect`, the `quick_clean` preview, `_rm_tracked` and dry-run. **Run it after any change to `_wiz_protected`, `_wizard_collect` or `quick_clean`**, and add a fixture dir for every new protected category. The script can be `source`d without starting the menu (the entry block only runs when `BASH_SOURCE[0] = $0`), so interactive screens can be exercised headlessly by sourcing it, stubbing `clear`/`confirm`/`_back_to_menu`, and piping keystrokes in.
- The version string appears in four places — the file header comment, the `main_menu` banner, the `safe_wizard` "pattern engine" label, and the `Generator:` line in `generate_feedback`. They are all **v3.8**, as is `VERSION` in the entry block (used by `--version`); update all five together (`grep -n 'v3\.[0-9]'`). Note this is a display version only, distinct from the historical "v3.2 rewrite" referenced above.

## When making changes

- Preserve `bash -n storage_check.sh` passing with zero warnings, and `bash tests/test_protected.sh` passing (run both with `/bin/bash`, the 3.2 target).
- If you change anything in `safe_wizard`'s candidate-building or `_wiz_protected()`, state explicitly in your summary which PROTECTED categories you tested against and that none of them leaked into `CANDIDATES`.
- Prefer extending the pattern-based `find` scan (point 2 under SAFE, above) over adding new hardcoded per-app paths — hardcoded paths don't generalize to other users' Macs and are exactly what the v3.1 → v3.2 rewrite moved away from.
- If the user supplies a `claude_code_feedback_*.md` file (generated by `generate_feedback`), treat section 5 (orphan/match analysis) as **advisory data to design new pattern rules from**, not as a ready-made deletion list — every new rule derived from it must still pass through `_wiz_protected()`.
