# storageCheck

An interactive terminal tool for auditing Mac disk usage with a **Safe Cleanup Wizard** that intelligently identifies files safe to delete without touching system files, installed apps, or personal data.

## Features

### Core Functionality

- **Full Audit** — Deep scan with comprehensive recommendations
- **Quick Clean** — One-click deletion of well-known safe cache/log paths
- **Interactive Clean** — Itemized deletion of IDE caches, LM Studio models, VSCode extensions
- **Safe Cleanup Wizard** — Pattern-based 3-tier classifier that separates safe, review-needed, and protected files
- **Large File Search** — Find files above a minimum size threshold
- **Cloud & Sync Audit** — Read-only reporting of OneDrive, iCloud, Dropbox, WhatsApp, Telegram footprints
- **LM Studio Manager** — Inventory and optional cleanup of LM Studio model downloads
- **Ollama Manager** — Inventory and optional cleanup of Ollama model downloads
- **App Support Deep Dive** — Drill down into `~/Library/Application Support` for cache discovery
- **AI Tools Audit** — Detailed footprint of IDE and AI tool installations
- **Storage Reports** — Export findings to a timestamped text file

### The Safe Cleanup Wizard (Option 11)

The core feature uses a **3-tier classification model**:

- **🟢 SAFE** — Caches, logs, temp files, updater payloads. Apps rebuild these automatically; zero data loss. Offered for bulk or itemized deletion.
- **🟡 REVIEW** — Re-downloadable content (AI models, IDE installations, extensions). Always itemized, never bulk-deleted.
- **🔴 PROTECTED** — Never shown or offered for deletion. Blocks: cloud stores (OneDrive, Dropbox, iCloud, Google Drive), messaging apps (WhatsApp, Telegram), system files, personal data, Keychains, Photos library.

All candidates pass through a hardened safety guard before being offered for deletion.

## Requirements

- **macOS** (Bash 3.2, the system default)
- **Built-in tools only:** `du`, `df`, `find`, `plutil`, `tmutil`, `diskutil`, `system_profiler`, `sw_vers`, `sysctl`
- No external dependencies, no package manager required

## Installation

```bash
# Clone the repository
git clone https://github.com/carlomagnoglobal/storageCheck.git
cd storageCheck

# Make the script executable
chmod +x storage_check.sh

# Run it
bash storage_check.sh
```

## Usage

Simply run the script and select from the numbered menu:

```bash
bash storage_check.sh
```

You'll see an interactive menu with options 1–11 plus exit (0). Each option runs independently and returns to the menu when complete.

### Menu Options

| # | Option | Purpose |
|---|---|---|
| 1 | Full Audit | Read-only deep scan with recommendations summary |
| 2 | Quick Clean | Automatic deletion of well-known safe paths (caches, logs, temp) |
| 3 | Interactive Clean | Itemized selection for IDE caches, LM Studio models, extensions |
| 4 | AI Tools Audit | List IDE/tool footprints (Cursor, Copilot, LM Studio, etc.) |
| 5 | App Support Deep | Explore `~/Library/Application Support` for cache patterns |
| 6 | LM Studio Manager | Inventory and optional deletion of LM Studio models |
| 7 | Ollama Manager | Inventory and optional deletion of Ollama models |
| 8 | Cloud Audit | Read-only report: OneDrive, iCloud, Dropbox, messaging app sizes |
| 9 | Save Report | Export findings to timestamped plain-text file |
| 10 | Large File Search | Find files above a user-specified size threshold |
| 11 | Safe Wizard | **Core feature** — pattern-based 3-tier classifier with bulk/itemized options |
| 12 | Generate Feedback | Create diagnostic Markdown report for debugging or Claude Code integration |
| 13 | Time Machine & Backups | Delete local TM snapshots and iOS device backups |
| 0 | Exit | — |

### Common Workflows

**Quick cleanup:**
- Option 2 (Quick Clean) for automatic removal of well-known safe paths
- Or Option 11 (Safe Wizard) for guided, pattern-based selection

**Investigate disk usage:**
- Option 1 (Full Audit) for a complete overview
- Option 10 (Large File Search) to find specific size ranges
- Option 8 (Cloud Audit) to see sync folder sizes without deletion

**Deep maintenance:**
- Option 5 (App Support Deep Dive) to explore `~/Library/Application Support`
- Option 6 (LM Studio Manager) to review LM Studio model downloads
- Option 7 (Ollama Manager) to review Ollama model downloads
- Option 13 (Time Machine & Backups) to delete local snapshots and iOS device backups
- Option 12 (Generate Feedback) to create a diagnostic report

## Safety Design

- **Nothing is deleted without explicit confirmation** or one-click bulk action (Quick Clean only)
- **Cloud and sync stores are read-only** — reported but never touched
- **System and personal data are protected** — no macOS files, Keychains, Photos, Mail ever offered
- **Every deletion is guarded** — existence checks before removal, no empty variable deletions
- **Pattern-based, not hardcoded** — safe rules generalize across different Macs and app configurations

### The Safe Wizard's Protection Model

The Safe Wizard's `_wiz_protected()` function is the safety-critical guard. It blocks any path containing (case-insensitive substring match):

- Cloud/sync: OneDrive, Dropbox, Google Drive, CloudStorage, iCloud (Mobile Documents, CloudDocs)
- Messaging: WhatsApp, Telegram
- System: Keychains, Photos library, Mail, Office/Outlook data

This guard is applied **before any candidate is offered for deletion**, ensuring nothing outside SAFE/REVIEW/PROTECTED tiers ever reaches the user's prompt.

## Files

- `storage_check.sh` — Single-file executable (~1500 lines). Organized as: color helpers → main menu → menu functions → shared helpers
- `CLAUDE.md` — Development notes, architecture overview, safety invariants, contribution guidelines
- `README.md` — This file

## Development

When modifying the script:

- **Syntax check:** `bash -n storage_check.sh` must pass with zero warnings
- **Safety testing:** Changes to the Safe Wizard or `_wiz_protected()` must document which PROTECTED categories were tested against
- **Pattern-based design:** Prefer extending pattern-based rules (find-based scans for Cache, logs, etc.) over adding hardcoded per-app paths
- **Deletion guards:** Every `rm -rf` must be preceded by an existence check (`[ -e "$path" ] &&`)
- **No variable dangers:** Never delete with an unset or potentially empty variable

See `CLAUDE.md` for detailed architecture and known limitations.

## Known Limitations

- Single-user `$HOME` only; not designed for root or multi-user scenarios
- Cloud storage auditing is read-only by design
- No automated test suite (manual validation via syntax check + path tracing)
- Installed app inventory is rebuilt on each run (not cached)

## Support

For issues, suggestions, or diagnostic data:

1. Run **Option 11 (Generate Feedback)** to create a detailed diagnostic report
2. Share the generated `~/claude_code_feedback_*.md` file with your report
3. Include the option you were using when the issue occurred

## License

See repository for license details.
