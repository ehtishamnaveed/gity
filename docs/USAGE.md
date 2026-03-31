# Gity — Usage Guide

## Quick Start

```bash
gity
```

## First Time Setup

Gity will automatically scan your system on first run. This may take a few seconds depending on how many directories you have. The results are cached for faster subsequent launches.

### Scan Locations

Gity searches these directories by default:
- `~/Work`
- `~/Plugins`
- `~/Documents`
- `~/Desktop`
- `~/Luminor`
- General `~` (excluding cache directories)

---

## Main Menu Options

### Browse All Repositories
Opens a searchable list of all discovered Git repos with **status indicators**. Recent repos appear at the top. Use fuzzy search to filter by name or path.

### Search Across Repos
Search for any text or file across all your repositories at once. Enter your search query and Gity will grep through every repo. Results show the file path and matching line number. Select a result to open that repo directly.

### Bulk Actions
Select multiple repos and perform actions on all of them at once:
- **Pull All** — Run `git pull` on each selected repo
- **Push All** — Run `git push` on each selected repo
- **Status All** — View git status of all selected repos
- **Commit All** — Add all changes and commit with a single message
- **Custom Command** — Run any shell command on each repo (use `{repo}` for the path)

Use **Tab** to select multiple repos.

### GitHub Repos
Browse and clone repositories from your GitHub account directly. Requires the `gh` CLI to be installed and authenticated.

### Clone Repository
Prompts for a Git URL (HTTPS or SSH). Clones into `~/Documents/Github/<repo-name>`. After cloning, you'll be taken to the repo actions menu.

### Create New Repository
Prompts for a name. Creates the directory, initializes a Git repo, adds a blank `README.md`, and makes an initial commit. Then takes you to the repo actions menu.

### Refresh Cache
Rescans your home directory for new Git repositories and updates the cache.

### Exit
Quits Gity.

---

## Status Indicators

| Indicator | Meaning |
|---|---|
| `●` (green) | Clean — no uncommitted changes |
| `✎` (yellow) | Has uncommitted changes |
| `↑` (cyan) | Ahead of remote — commits to push |
| `↓` (red) | Behind remote — commits to pull |
| `↕` (magenta) | Diverged — both ahead and behind |

---

## Repository Actions

After selecting a repo (either by browsing or after clone/create), you can:

### Open in Lazygit (TUI)
Launches `lazygit` pointed at that repository. This is the main workflow — browse commits, stage files, resolve merge conflicts, and more.

### Browse Files (fzf)
Opens a fuzzy-searchable file browser for the repository. Use arrow keys to navigate, press **Enter** to preview a file, and **Escape** to go back. This shows ALL files in the repo, regardless of whether there are uncommitted changes.

### Open in Default Editor
Opens the repository using your system's default editor. Uses `$EDITOR` if set, otherwise falls back to your platform's default:
- Linux: `xdg-open`
- macOS: `open`
- Windows (WSL/Git Bash): `wslview`, `explorer.exe`, or `start`

### Open in File Manager
Opens the repository folder in your system's default file browser (uses `xdg-open`).

### Copy Path to Clipboard
Copies the full path of the repository. Requires a clipboard tool (`xclip`, `xsel`, or `wl-copy` on Wayland). If none are available, this option is hidden.

---

## Cache Management

Gity caches the list of repos in `~/.cache/lazygit_repos`. The cache is automatically refreshed when:
- The cache file is empty or missing
- A new repo is cloned or created through Gity
- You select "Refresh Cache" from the menu

To force a rescan, simply delete the cache file:

```bash
rm ~/.cache/lazygit_repos
```

The next time you run Gity, it will rescan.

---

## GitHub Integration

To use GitHub features, install the GitHub CLI:

```bash
# Arch
sudo pacman -S github-cli

# Ubuntu/Debian
sudo apt install gh

# macOS
brew install gh

# Windows (in WSL)
sudo apt install gh
```

Then authenticate:

```bash
gh auth login
```

---

## Customization

### Clone Destination
By default, cloned repos go to `~/Documents/Github`. Change this by editing the `REPO_DIR` variable in `gity.sh`:

```bash
REPO_DIR="$HOME/path/to/your/repos"
```

### Repo Scan Locations
To add or remove directories from the scan, edit `gity.sh`:

```bash
find "$HOME/Work" "$HOME/Plugins" "$HOME/Documents" ... -maxdepth 4 -name ".git" -type d
```

### Number of Recent Repos
Recent repos are limited to 10 by default. Change this in `repo_actions()`:

```bash
head -n 10   # change 10 to desired number
```

---

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `↑` / `↓` or `j` / `k` | Navigate options |
| `Enter` | Select |
| `Escape` | Go back / Cancel |
| `Tab` | Multi-select (in Bulk Actions) |
| `Ctrl+C` | Exit |
| Type | Fuzzy search filter |

---

## Troubleshooting

### "lazygit not found"
Gity requires lazygit to be installed. Install it via your package manager:

```bash
# Arch
sudo pacman -S lazygit

# Ubuntu/Debian
sudo apt install lazygit

# Fedora
sudo dnf install lazygit
```

### "fzf not found"
Same as above — `fzf` is required. Install it with your package manager.

### Clipboard not working
If the "Copy Path" option is missing or not working, install one of:
- `xclip` (X11)
- `xsel` (X11 alternative)
- `wl-copy` (Wayland)

### GitHub Repos not working
Make sure `gh` CLI is installed and you're authenticated:
```bash
gh auth status
```

### Gity not found after install
Make sure `~/.local/bin` is in your PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add this to `~/.bashrc` or `~/.zshrc` to make it permanent.
