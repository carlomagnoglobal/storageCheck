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

| # | Function | Purpose |
|---|---|---|
| 1 | `full_audit` | Read-only deep scan with a recommendations summary at the end |
| 2 | `quick_clean` | Deletes a fixed list of well-known safe cache/log paths, no per-item prompt |
| 3 | `interactive_clean` | Broader/more aggressive than the wizard — offers IDEs, LM Studio models, VSCode extensions one-by-one via `safe_delete` (always prompts) |
| 4 | `ai_tools_audit` | Lists AI IDE/tool footprints (`_ai_tools_list`) |
| 5 | `app_support_deep` | Drill-down into `~/Library/Application Support`, Group Containers, JetBrains |
| 6 | `lmstudio_manager` | LM Studio model/extension inventory + optional deletion |
| 7 | `cloud_audit` | **Read-only**, reports OneDrive/iCloud/Dropbox/WhatsApp/Telegram size — never offers to delete these |
| 8 | `save_report` | Dumps a plain-text snapshot to `~/storage_report_<timestamp>.txt` |
| 9 | `find_large_files` | `find`-based search by minimum file size, user-supplied |
| **10** | `safe_wizard` | **The core feature.** Pattern-based 3-tier classifier — see below |
| 11 | `generate_feedback` | Produces `~/claude_code_feedback_<timestamp>.md`: a structured diagnostic dump meant to be fed back into a Claude Code session to improve this script |
| 0 | exit | — |

### The 3-tier model (option 10, `safe_wizard`)

Every candidate path is tagged with exactly one tier:

- **🟢 SAFE** — caches, logs, temp, updater payloads. Apps rebuild these automatically; zero data loss. Offered for one-click bulk deletion (`_wizard_auto_safe`) or itemized review (`_wizard_pick`).
- **🟡 REVIEW** — re-downloadable but not "free" to lose (AI models, IDE installs, extensions). Always itemized, never bulk-deleted.
- **🔴 PROTECTED** — never shown, never offered, no matter what. Enforced by `_wiz_protected()`, a hard guard checked before any path is even added to the candidate list.

**`_wiz_protected()` is the single safety-critical function in this codebase.** It currently blocks (case-insensitive substring match on the full path): OneDrive, Dropbox, Google Drive/CloudStorage, iCloud (`Mobile Documents`/`CloudDocs`), WhatsApp, Telegram, `~/Library/Mail`, Keychains, Photos library, Office/Outlook. Any change that touches the candidate-building logic in `safe_wizard` must keep every path through `_wiz_protected()` before it reaches `CANDIDATES`.

SAFE candidates come from two sources, both pattern-based (not hardcoded per-app paths, so they generalize to any Mac):
1. Whole-tree roots: `~/Library/Caches`, `~/Library/Logs`, `~/.Trash`, `~/.cache`, `Saved Application State`, Xcode `DerivedData`/CoreSimulator caches.
2. A `find`-based scan under `~/Library/Application Support` and `~/Library/Containers` (maxdepth 5, `-prune`d at the match so it never recurses into a matched dir) for directory names matching `Cache`, `Caches`, `Code Cache`, `*Cache`, `CachedData`, `CachedExtensionVSIXs`, `logs`, `Crashpad`, `tmp` — each individually re-checked against `_wiz_protected()` before being added.

### `generate_feedback` (option 11)

Read-only. Writes a Markdown report containing: environment info, the script's *current* classification rules (so an LLM has context on what already exists), a full installed-app inventory (`system_profiler` + `/Applications` + `~/Applications` with bundle IDs via `plutil`), a storage inventory with paths, and an orphan/match analysis via `_match_folder()`.

`_match_folder()` is **informational only** — it feeds the feedback report, it does **not** drive any deletion in `safe_wizard`. Keep it that way; it's intentionally a weaker, exploratory heuristic (segment-token matching, ≥4 chars, `com.apple.*` short-circuits to `APPLE-SYSTEM`) used to spot candidate rules for humans/Claude Code to review, not to greenlight deletes directly.

## Safety invariants (do not regress)

These hold today and any change must preserve them:

1. **Nothing is deleted without going through `_wiz_protected()` first**, for every code path that adds to `CANDIDATES` in `safe_wizard`.
2. **`com.apple.*` and `group.com.apple.*` are never offered for deletion.** (They were previously misclassified as `ORPHAN?` by an earlier, substring-based version of `_match_folder` — this was the bug that motivated the v3.2 rewrite. Do not reintroduce substring matching on short tokens; segment matching requires ≥4 chars.)
3. **Sync/cloud and messaging stores are read-only everywhere**, including their own cache subfolders (`cloud_audit` reports sizes but never deletes; `_wiz_protected` blocks even `.../OneDrive.../Cache`).
4. **`quick_clean` and `interactive_clean` only ever touch paths that exist** (`[ -e "$path" ]` before any `rm -rf`) and report the freed size before deleting.
5. **No `rm -rf` on a variable that could be empty or unset.** Every deletion site is `path`-guarded; if you add a new one, guard it the same way (`[ -e "$path" ] && rm -rf "$path"`, never a bare `rm -rf "$var"`).
6. **Every menu function returns to `main_menu` via `_back_to_menu`** (or loops back directly, as `safe_wizard`'s `l` option does) — don't leave a dead-end function that exits the script outside option `0`.

## Style conventions already in use

- snake_case function names; helpers used only inside one function are prefixed `_` (e.g. `_wiz_protected`, `_ai_tools_list`).
- Color vars are pre-defined at the top (`RED`/`BRED`/`YELLOW`/`BYELLOW`/`GREEN`/`BGREEN`/`CYAN`/`BCYAN`/`BLUE`/`BBLUE`/`MAGENTA`/`BMAGENTA`/`BOLD`/`DIM`/`RESET`) — reuse these, don't invent new ANSI codes inline.
- Output helpers: `section "title"`, `success "msg"`, `warning "msg"`, `danger "msg"`, `info "msg"`, `skipped "msg"`, `divider`. Use these instead of raw `echo -e` for anything user-facing.
- Sizes are tracked in **KB internally** (`du -sk`) and converted for display only at the last moment via `human_kb()`. Don't parse `du -sh` output for arithmetic — it's not reliably parseable across locales/sizes.
- `confirm "question"` returns shell true/false for `[[ "$answer" =~ ^[Yy]$ ]]`; use it for any new per-item prompt instead of rolling a new read/case block.
- All deletion happens through `rm -rf` after an explicit existence check; there is no trash/recycle step — be conservative, this is permanent.

## Known limitations / open items

- `cloud_audit`, `app_support_deep`, `ai_tools_audit` are read-only by design — if asked to add deletion there, route it through the same `_wiz_protected()` guard rather than writing new ad-hoc checks.
- `_match_folder()`'s segment list is rebuilt by scanning `/Applications`, `~/Applications`, `/System/Applications`, `/Applications/Utilities` every run (`generate_feedback` only) — this is intentionally not cached; keep it that way since installed apps can change between runs.
- The script assumes a single-user `$HOME` and does not support being run as root or against another user's home directory.
- No automated tests exist; validate changes with `bash -n storage_check.sh` (syntax) and, for any change to `safe_wizard`/`_wiz_protected`, manually trace a few real paths through the guard (see the PR description template below) before considering the change done.

## When making changes

- Preserve `bash -n storage_check.sh` passing with zero warnings.
- If you change anything in `safe_wizard`'s candidate-building or `_wiz_protected()`, state explicitly in your summary which PROTECTED categories you tested against and that none of them leaked into `CANDIDATES`.
- Prefer extending the pattern-based `find` scan (point 2 under SAFE, above) over adding new hardcoded per-app paths — hardcoded paths don't generalize to other users' Macs and are exactly what the v3.1 → v3.2 rewrite moved away from.
- If the user supplies a `claude_code_feedback_*.md` file (generated by option 11), treat section 5 (orphan/match analysis) as **advisory data to design new pattern rules from**, not as a ready-made deletion list — every new rule derived from it must still pass through `_wiz_protected()`.
