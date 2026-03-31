#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

REQUIRED_DEPS="git fzf lazygit"
CLIPBOARD_DEPS="xclip xsel wl-copy"

REPO_DIR="$HOME/Documents/Github"
CACHE_FILE="$HOME/.cache/lazygit_repos"
RECENT_FILE="$HOME/.cache/lazygit_recent"
mkdir -p "$REPO_DIR" "$(dirname "$CACHE_FILE")"
touch "$RECENT_FILE"

CLIPBOARD_TOOL=""
copy_path() {
    if [ -z "$CLIPBOARD_TOOL" ]; then
        return 1
    fi
    case "$CLIPBOARD_TOOL" in
        xclip)
            echo -n "$1" | xclip -selection clipboard
            ;;
        xsel)
            echo -n "$1" | xsel --clipboard
            ;;
        wl-copy)
            echo -n "$1" | wl-copy
            ;;
    esac
    return 0
}

detect_clipboard() {
    for tool in $CLIPBOARD_DEPS; do
        if command -v "$tool" &>/dev/null; then
            echo "$tool"
            return 0
        fi
    done
    echo ""
}

check_deps() {
    local missing=""
    for dep in $REQUIRED_DEPS; do
        if ! command -v "$dep" &>/dev/null; then
            missing="$missing $dep"
        fi
    done

    if [ -n "$missing" ]; then
        echo -e "${RED}============================================${NC}"
        echo -e "${RED}  ✗ Missing dependencies:$missing${NC}"
        echo -e "${RED}============================================${NC}"
        echo ""
        echo -e "${YELLOW}  Please install the missing tools and try again.${NC}"
        echo ""
        echo -e "${BLUE}  Quick install (run one of these):${NC}"
        echo -e "${BLUE}  • Arch:       sudo pacman -S$missing${NC}"
        echo -e "${BLUE}  • Debian/Ub:  sudo apt install$missing${NC}"
        echo -e "${BLUE}  • Fedora:     sudo dnf install$missing${NC}"
        echo -e "${BLUE}  • macOS:      brew install$missing${NC}"
        echo ""
        echo -e "${YELLOW}  Or use the installer:${NC}"
        echo -e "${GREEN}  bash <(curl -sL https://github.com/ehtishamnaveed/gity/install.sh)${NC}"
        echo ""
        exit 1
    fi
}

check_deps

CLIPBOARD_TOOL=$(detect_clipboard)

refresh_cache() {
    echo -e "${BLUE}Scanning for Git repositories in $HOME...${NC}"

    find "$HOME/Work" "$HOME/Plugins" "$HOME/Documents" "$HOME/Desktop" "$HOME/Luminor" -maxdepth 4 -name ".git" -type d 2>/dev/null > "$CACHE_FILE.tmp"

    find "$HOME" -maxdepth 4 -name ".git" -type d \
        -not -path "$HOME/.cache/*" \
        -not -path "$HOME/.local/share/*" \
        -not -path "$HOME/.npm/*" \
        -not -path "$HOME/.cargo/*" \
        -not -path "$HOME/.rustup/*" \
        2>/dev/null >> "$CACHE_FILE.tmp"

    cat "$CACHE_FILE.tmp" | rev | cut -d'/' -f2- | rev | sort | uniq > "$CACHE_FILE"
    rm -f "$CACHE_FILE.tmp"

    local count
    count=$(wc -l < "$CACHE_FILE")
    echo -e "${GREEN}Scan complete. Found $count repositories.${NC}"
    sleep 1
}

clone_repo() {
    echo -n "Enter Repository URL (HTTPS or SSH): "
    read -r url
    if [ -n "$url" ]; then
        repo_name=$(basename "$url" .git)
        dest="$REPO_DIR/$repo_name"
        if [ ! -d "$dest" ]; then
            echo -e "${BLUE}Cloning into $dest...${NC}"
            git clone "$url" "$dest" && repo_actions "$dest"
        else
            echo "Error: Directory already exists at $dest"
            sleep 2
        fi
    fi
}

repo_actions() {
    local repo_path="$1"

    grep -v "^$repo_path$" "$RECENT_FILE" > "$RECENT_FILE.tmp" 2>/dev/null
    printf '%s\n' "$repo_path" | cat - "$RECENT_FILE.tmp" | head -n 10 > "$RECENT_FILE"
    rm -f "$RECENT_FILE.tmp"

    local actions="🚀 Open in Lazygit (TUI)
💻 Open in VSCode
📂 Open in File Manager"

    if [ -n "$CLIPBOARD_TOOL" ]; then
        actions="$actions
📋 Copy Path to Clipboard"
    fi
    actions="$actions
🔙 Back to Gity"

    while true; do
        clear
        echo "===================================================="
        echo "  REPO: $(basename "$repo_path")"
        echo "  PATH: $repo_path"
        echo "===================================================="
        echo ""

        action=$(echo -e "$actions" | fzf --height 20% --layout=reverse --border --prompt="Select Action > ")

        case "$action" in
            "🚀 Open in Lazygit (TUI)")
                lazygit -p "$repo_path"
                ;;
            "💻 Open in VSCode")
                code "$repo_path"
                ;;
            "📂 Open in File Manager")
                xdg-open "$repo_path"
                ;;
            "📋 Copy Path to Clipboard")
                if copy_path "$repo_path"; then
                    echo "Path copied!"
                    sleep 1
                fi
                ;;
            *)
                break
                ;;
        esac
    done
}

open_existing() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi

    local selected
    selected=$( (cat "$RECENT_FILE"; cat "$CACHE_FILE") | awk 'NF && !x[$0]++' | fzf --height 60% --border --header="Select Repository (Recent at top)" --prompt="Search > ")

    if [ -n "$selected" ]; then
        repo_actions "$selected"
    fi
}

while true; do
    clear
    echo "=============================================="
    echo "              GITY (TUI EDITION)            "
    echo "=============================================="
    echo ""

    choice=$(echo -e "📂 Browse All Repositories
🔗 Clone Repository
✨ Create New Repository
❌ Exit" | fzf --height 15% --layout=reverse --border --prompt="Main Menu > ")

    case "$choice" in
        "📂 Browse All Repositories")
            open_existing
            ;;
        "🔗 Clone Repository")
            clone_repo
            ;;
        "✨ Create New Repository")
            echo -n "Enter new repository name: "
            read -r name
            if [ -n "$name" ]; then
                dest="$REPO_DIR/$name"
                mkdir -p "$dest"
                cd "$dest" && git init && touch README.md && git add . && git commit -m "Initial commit"
                repo_actions "$dest"
            fi
            ;;
        *)
            exit 0
            ;;
    esac
done
