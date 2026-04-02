```
  ██████╗ ██╗████████╗██╗   ██╗
 ██╔════╝ ██║╚══██╔══╝╚██╗ ██╔╝
 ██║  ███╗██║   ██║    ╚████╔╝ 
 ██║   ██║██║   ██║     ╚██╔╝  
 ╚██████╔╝██║   ██║      ██║   
  ╚═════╝ ╚═╝   ╚═╝      ╚═╝  
  ```
**A powerful, keyboard-driven TUI hub for managing all your Git repositories in one place.**

No more hunting for repos across your filesystem. Gity automatically discovers all your Git repositories and brings them together with beautiful visualizations, status indicators, cross-repo search, bulk actions, and GitHub integration.

**Built entirely in Python for universal, native performance on Linux, macOS, and Windows.**

![Gity Screenshot](docs/screenshot.png)

## Quick Install (Universal)

Open your terminal (CMD/PowerShell on Windows, or Bash/Zsh on Mac/Linux) and run:

```bash
python -c "import urllib.request; exec(urllib.request.urlopen('https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.py').read())"
```

That's it. One command works on **Windows, macOS, and Linux**. Everything installs and sets up your PATH automatically.

- **Windows**: Installs `windows.py` (with built-in dependency checker that verifies git, fzf, gh, and lazygit before running)
- **Linux/macOS**: Installs `gity.py` (universal version)

---

## Features

### Visualization Dashboard
- **📊 Repos Needing Attention** — See at a glance which repos need work, color-coded by severity

### Core Features
- **Auto-Discovery** — Scans your home directory and finds all Git repos automatically
- **Repo Status Overview** — See which repos have changes, need pushing, or need pulling
- **Fuzzy Search** — Instantly filter through hundreds of repos with fzf
- **Bulk Actions** — Pull, push, commit, or run custom commands on multiple repos at once
- **GitHub Integration** — Browse and clone repos from your GitHub account (with organization support)
- **🔀 Merge Branches** — Merge branches in any repo with preview and confirmation
- **Recent First** — Your most-used repos always appear at the top
- **Quick Actions** — Open in Lazygit, your default editor, or your file manager
- **Universal & Native** — Runs natively on Windows (no WSL needed), macOS, and Linux
- **Zero Config** — Works out of the box

## Requirements

Gity requires **Python 3.6+** and two external TUI tools:

1.  **git**
2.  **fzf** (Fuzzy Finder)
3.  **lazygit** (Optional but recommended)
4.  **gh CLI** (Optional, for GitHub integration)

> **Windows users**: The installer automatically downloads `windows.py` which includes a built-in dependency checker. If any tools are missing, it will offer to install them via winget or Chocolatey.

## Installation

### The Easy Way (Automated)

Run the Python installer:

```bash
python3 -c "$(curl -fsSL https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.py)"
```

The installer will:
1. Detect your OS (Windows/Linux/macOS)
2. Download the correct version (`windows.py` for Windows, `gity.py` for others)
3. Create a dedicated folder in your local AppData (Windows) or .local/share (Linux/Mac)
4. Install the `gity` command to your PATH
5. Handle all OS-specific configuration automatically

### The Manual Way

**Windows:**
1.  Download `windows.py` to a folder of your choice.
2.  Add that folder to your system PATH.
3.  (Optional) Create a `gity.cmd` file: `@echo off && python "path\to\windows.py" %*`

**Linux/macOS:**
1.  Download `gity.py` to a folder of your choice.
2.  Add that folder to your system PATH.
3.  (Optional) Create an alias: `alias gity='python3 path/to/gity.py'`

## Usage

Run Gity from any terminal:

```bash
gity
```

### Keyboard Navigation

- Use **arrow keys** or **vim-style (j/k)** to navigate
- Press **Enter** to select
- Press **Escape** or select empty to go back
- Type to **fuzzy search** filter the list
- **Tab** to multi-select in Bulk Actions

## Contributing

Contributions are welcome! Since Gity is now written entirely in Python, it's easier than ever to contribute cross-platform features.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- [lazygit](https://github.com/jesseduffield/lazygit) by Jesse Duffield
- [fzf](https://github.com/junegunn/fzf) by Junegunn Choi
test change
more changes
testing sync feature
