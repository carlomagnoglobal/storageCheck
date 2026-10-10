# storageCheck

![Platform](https://img.shields.io/badge/platform-macOS-black?logo=apple&logoColor=white)
![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnu-bash&logoColor=white)
![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)

An interactive terminal tool for auditing Mac disk usage with a **Safe Cleanup Wizard** that intelligently identifies files safe to delete without touching system files, installed apps, or personal data.

## Features

The menu is grouped into four sections. All ANALYZE screens are read-only.

### 🔍 Analyze
- **Full Audit**: deep scan of home, Library, AI tools, caches and snapshots, with recommendations
- **Storage Visualizer**: bar or pie view of what is using your disk
- **Find Large Files**: files above a size you choose (e.g. `500M`, `2G`), largest first
- **Cloud & Sync Audit**: sizes of OneDrive, iCloud, Google Drive, Dropbox, WhatsApp, Telegram (never deletes)
- **AI Tools Audit**: footprint of AI IDEs and tools (LM Studio, Cursor, Claude, Codex, …)
- **App Support Deep Dive**: drill into `~/Library/Application Support`, Group Containers, JetBrains

### 🧹 Clean
- **🪄 Safe Cleanup Wizard**: the core feature, a pattern-based 3-tier classifier (see below)
- **Quick Clean**: one confirmation for well-known caches and logs (same protection guard as the wizard)
- **Interactive Clean**: asks item by item about IDEs, LM Studio models and VSCode extensions
- **Time Machine & Backups**: local APFS snapshots and iPhone/iPad backups

### 📦 Manage
- **Applications**: paged, sortable, filterable list of every app with sizes. Delete apps, **move them to a USB/external drive** (leaving a launcher link), restore them, or relink apps whose launcher is missing
- **VSCode Extensions**: VS Code, Cursor, Windsurf, VSCodium and other forks: browse, delete, back up to Desktop
- **LM Studio** / **Ollama**: model inventory with per-model deletion

### 🧰 Tools
- **Save Report to File**: plain-text snapshot at `~/storage_report_<timestamp>.txt`
- **Generate Feedback File**: Markdown diagnostic dump to feed back into Claude Code to improve the rules

### The Safe Cleanup Wizard

Every candidate gets exactly one tier:

- **🟢 SAFE**: caches, logs, temp files, updater payloads, Trash. Apps rebuild these. Offered for one-click bulk or item-by-item deletion.
- **🟡 REVIEW**: re-downloadable but not free to lose (AI models, IDEs, extensions, `~/.cache`, leftover dot-folders whose app seems gone). Always item by item, never bulk.
- **🔴 PROTECTED**: never shown, never offered. Blocks macOS data (`com.apple.*`), cloud sync (OneDrive, Dropbox, Google Drive/DriveFS, iCloud, CloudKit, Box, pCloud, Nextcloud, Synology, MEGA), messaging (WhatsApp, Telegram), Mail, Keychains, Photos and Office/Outlook, including their cache subfolders.

Cache roots such as `~/Library/Caches` are scanned child by child, so a protected folder inside one is skipped rather than deleted along with it.

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

```bash
bash storage_check.sh
```

Pick an option from the numbered menu. Each screen returns to the menu when done; `0` exits. Menu numbers can change between versions, so this README refers to features by name.

- **Quick cleanup:** Safe Cleanup Wizard → `a` (auto-clean all 🟢 items), or Quick Clean.
- **Find what is big:** Storage Visualizer, Full Audit, Find Large Files.
- **Free space without uninstalling:** Applications → `m` to move an app to an external drive.

**Tip:** grant your terminal **Full Disk Access** (System Settings → Privacy & Security). Without it, macOS hides some folders, so sizes come out too low and folders like Trash can't be cleaned.

## Safety Design

- **Nothing is deleted without explicit confirmation** (bulk actions show the total and ask once)
- **Cloud and sync stores are read-only** — reported but never touched
- **System and personal data are protected** — no macOS files, Keychains, Photos, Mail ever offered
- **Every deletion is guarded**: existence checks before removal, no empty-variable deletions, and freed space is only reported for what was actually removed
- **Pattern-based, not hardcoded** — safe rules generalize across different Macs and app configurations

### The Safe Wizard's Protection Model

The Safe Wizard's `_wiz_protected()` function is the safety-critical guard. It blocks any path containing (case-insensitive substring match):

- macOS: `/com.apple.*`, `/group.com.apple.*`
- Cloud/sync: OneDrive, Dropbox, Google Drive (incl. DriveFS), CloudStorage, iCloud (Mobile Documents, CloudDocs), CloudKit, Box, pCloud, Nextcloud, Synology, MEGA
- Messaging: WhatsApp, Telegram
- Personal: Keychains, Photos library, Mail, Office/Outlook data

This guard is applied **before any candidate is offered for deletion**, ensuring nothing outside SAFE/REVIEW/PROTECTED tiers ever reaches the user's prompt.

## Files

- `storage_check.sh` — Single-file executable (~2300 lines). Organized as: color helpers → main menu → menu functions → shared helpers
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

1. Run **Generate Feedback File** (TOOLS menu) to create a detailed diagnostic report
2. Share the generated `~/claude_code_feedback_*.md` file with your report
3. Include the option you were using when the issue occurred

## License

MIT. See [LICENSE](LICENSE).
