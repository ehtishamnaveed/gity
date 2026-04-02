# Gity — Usage Guide

## Quick Start

```bash
gity
```

## Platform-Specific Versions

Gity ships with two versions:

- **`gity.py`** — Universal version for Linux/macOS
- **`windows.py`** — Windows-optimized version with built-in dependency checker

The installer automatically detects your OS and installs the correct version. Both are launched with the same `gity` command.

### Windows Dependency Checker

When you run `gity` on Windows for the first time, it checks for required tools:

- **git** (required)
- **fzf** (required)
- **gh CLI** (required for GitHub features)
- **lazygit** (optional)

If anything is missing, you'll be prompted to install it via:
1. **winget** (recommended, built into Windows 10/11)
2. **Chocolatey** (alternative package manager)
3. **Manual download links**

## Main Menu Overview

Gity's main menu provides quick access to all features:

```
╔═══════════════════════════════════════════════════╗
║           GITY - TUI Git Hub                      ║
╚═══════════════════════════════════════════════════╝

📊 Dashboard (Repos Needing Work)
📂 Browse All Repositories
📅 Activity Timeline
⚡ Bulk Actions
🔍 Search Across Repos
🐙 GitHub Repos
🔀 Merge Branch
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
📊 DASHBOARD

  Total repos scanned: 12

🔴 NEED ATTENTION (2 repos)
    ● gity
    ● wordpress-manager

🟡 NEED SYNC (1 repos)
    ✎ plugins  3 file(s) changed

🟢 ALL SYNCED (9 repos)

Legend: ●Clean ✎Changes ↑Ahead ↓Behind ↕Diverged

Press [Enter] to return to menu...
```

**Legend:**
- `●` Clean — nothing to commit
- `✎` Changes — uncommitted changes
- `↑` Ahead — commits to push
- `↓` Behind — commits to pull
- `↕` Diverged — both ahead and behind

---

### 📅 Activity Timeline

View your recent work across all repos. Choose timeframe with fzf: 1 Day, 7 Days, or 30 Days.

```
📅 ACTIVITY TIMELINE (Last 7 days)
  Total: 15 commits across all repos

2024-03-25
    gity          fix: menu mismatch
    gity          add: bulk actions feature
    dynamicleo    Enhancement: Hero animations

2024-03-24
    wordpress     add: plugin installer
    plugins-repo  chore: update deps
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

### 🔀 Merge Branch

Merge branches in any repository with a step-by-step wizard:

1. **Select repository** — Choose the repo to work with
2. **Select target branch** — Choose the branch to merge INTO
3. **Select source branch** — Choose the branch to merge
4. **Preview** — See merge stats (commits ahead/behind, divergence warning)
5. **Confirm** — Yes, Merge or Cancel

The merge preview shows:
- Repository name
- Source and target branches
- Commit counts
- Divergence warning if branches have diverged
- Recent commits from the source branch

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
