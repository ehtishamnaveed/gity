# Gity — Usage Guide

## Quick Start

```bash
gity
```

## Main Menu Overview

Gity's main menu provides quick access to all features:

```
╔═══════════════════════════════════════════════════╗
║           GITY - TUI Git Hub                      ║
╚═══════════════════════════════════════════════════╝

📊 Dashboard (Repos Needing Work)
📂 Browse All Repositories
📅 Activity Timeline
🕰️ Stale Repos
🌿 Branch Health
⚡ Bulk Actions
🔍 Search Across Repos
🐙 GitHub Repos
🔗 Clone Repository
✨ Create New Repository
🔄 Refresh Cache
❌ Exit
```

---

## Visualization Features

### 📊 Dashboard (Repos Needing Work)

The dashboard provides an at-a-glance view of all your repos, categorized by urgency:

```
╔════════════════════════════════════════════════════════════╗
║                 📊 REPOS NEEDING ATTENTION               ║
╠════════════════════════════════════════════════════════════╣
║  Total: 12 repos scanned
╠════════════════════════════════════════════════════════════╣
║  🔴 CRITICAL (2 repos)
║  
║    ✎ ultra-fast-carousel    3 file(s) changed
║    ↕ dynamicleo            3↑, 2↓
╠════════════════════════════════════════════════════════════╣
║  🟡 WARNINGS (1 repos)
║  
║    ↑ wordpress-manager      2 commit(s) ahead
╠════════════════════════════════════════════════════════════╣
║  🟢 HEALTHY (9 repos)
║  
║    ● gity                  All synced
║    ● terraform-config       All synced
╚════════════════════════════════════════════════════════════╝
```

**Legend:**
- `●` Clean — nothing to commit
- `✎` Changes — uncommitted changes
- `↑` Ahead — commits to push
- `↓` Behind — commits to pull
- `↕` Diverged — both ahead and behind

---

### 📅 Activity Timeline

View your recent work across all repos:

```
╔════════════════════════════════════════════════════════════╗
║              📅 ACTIVITY TIMELINE                       ║
║              (Last 7 days)                             ║
╠════════════════════════════════════════════════════════════╣
║  Today
║    gity           fix: menu mismatch
║    gity           add: bulk actions feature
║    dynamicleo     Enhancement: Hero animations
╠════════════════════════════════════════════════════════════╣
║  Yesterday
║    wordpress      add: plugin installer
║    plugins-repo   chore: update deps
╠════════════════════════════════════════════════════════════╣
║  Mar 25
║    terraform      fix: bucket permissions
╚════════════════════════════════════════════════════════════╝
```

**Keyboard shortcuts:**
- `1` — Last day
- `7` — Last week (default)
- `30` — Last month

---

### 🕰️ Stale Repos

Find abandoned projects you forgot about:

```
╔════════════════════════════════════════════════════════════╗
║                  🕰️ STALE REPOS                        ║
╠════════════════════════════════════════════════════════════╣
║  ⚠️ Stale/Abandoned repos (5)
║  
║    ⚠️  180 days   old-experiment    "initial commit"
║    🔴   90 days   demo-app-2024     "add feature x"
║    🔴   60 days   scratch-notes     "update readme"
║    🟡   45 days   antigravity       "fix build"
║    🟡   35 days   random-scripts    "cleanup"
╠════════════════════════════════════════════════════════════╣
║  Active/Recent: 7 repos
╚════════════════════════════════════════════════════════════╝
```

**Thresholds:**
- `🟡 Yellow` — 30-60 days inactive
- `🔴 Red` — 60-90 days inactive
- `⚠️ Dark Red` — 90+ days abandoned

---

### 🌿 Branch Health

Check the state of branches across all repos:

```
╔════════════════════════════════════════════════════════════╗
║                  🌿 BRANCH HEALTH                      ║
╠════════════════════════════════════════════════════════════╣
║  🟢 gity              3 branches  •  master
║  🟡 dynamicleo        8 branches  •  ehtisham/design
║      • 3 stale branches
║  🟢 ultra-fast-carousel  1 branch  •  master
║  🔴 terraform-config   12 branches •  main
║      • 7 stale branches
╚════════════════════════════════════════════════════════════╝
```

---

## Core Features

### Browse All Repositories

Opens a searchable list of all discovered Git repos with **status indicators**. Recent repos appear at the top.

### Search Across Repos

Search for any text or file across all your repositories at once:

1. Enter your search query
2. Gity greps through every repo
3. Results show file path and matching line
4. Select a result to open that repo directly

### Bulk Actions

Select multiple repos and perform actions on all of them at once:

1. **Select repos** — Use `Tab` to multi-select
2. **Choose action:**
   - **Pull All** — `git pull` on each repo
   - **Push All** — `git push` on each repo
   - **Status All** — View git status
   - **Commit All** — Add and commit with one message
   - **Custom Command** — Run any command (use `{repo}` for path)

### GitHub Integration

Browse and clone repositories from your GitHub account:

1. Requires `gh` CLI (`brew install gh` or from cli.github.com)
2. Authenticate with `gh auth login`
3. Browse your top 100 repos
4. Clone directly or open in browser

### Clone Repository

Prompts for a Git URL (HTTPS or SSH). Clones into `~/Documents/Github/<repo-name>`.

### Create New Repository

Prompts for a name. Creates the directory, initializes Git, adds `README.md`, and makes initial commit.

### Refresh Cache

Rescans your home directory for new Git repositories.

---

## Repository Actions

After selecting a repo:

### Open in Lazygit (TUI)
Launches `lazygit` pointed at that repository.

### Browse Files (fzf)
Opens a fuzzy-searchable file browser. Shows ALL files in the repo.

### Open in Default Editor
Uses `$EDITOR` if set, otherwise platform default.

### Open in File Manager
Opens in your system's file browser.

### Copy Path to Clipboard
Copies the repo path (requires `xclip`/`xsel`/`wl-copy`).

---

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `↑` / `↓` or `j` / `k` | Navigate options |
| `Enter` | Select |
| `Escape` | Go back |
| `Tab` | Multi-select (Bulk Actions) |
| `Q` | Quit (in visualization views) |
| `R` | Refresh (Dashboard) |
| `1/7/30` | Timeline timeframe |
| Type | Fuzzy search filter |

---

## Troubleshooting

### "lazygit not found"
```bash
# Arch
sudo pacman -S lazygit
# Ubuntu
sudo apt install lazygit
# macOS
brew install lazygit
```

### "fzf not found"
```bash
# Arch
sudo pacman -S fzf
# Ubuntu
sudo apt install fzf
# macOS
brew install fzf
```

### Clipboard not working
Install `xclip` (X11), `xsel`, or `wl-copy` (Wayland).

### GitHub Repos not working
```bash
gh auth status    # Check authentication
gh auth login     # If not logged in
```

---

## Customization

### Clone Destination
Edit `gity.sh`:
```bash
REPO_DIR="$HOME/path/to/your/repos"
```

### Scan Directories
Edit the `find` commands in `gity.sh`:
```bash
find "$HOME/Work" "$HOME/Plugins" ... -maxdepth 4
```

### Recent Repos Limit
In `repo_actions()`, change:
```bash
head -n 10   # default is 10
```
