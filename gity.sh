#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

REQUIRED_DEPS="git fzf lazygit"
CLIPBOARD_DEPS="xclip xsel wl-copy clip.exe clip"

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
        clip.exe|clip)
            echo -n "$1" | clip
            ;;
    esac
    return 0
}

is_windows() {
    case "$(uname -s)" in
        *Msys*|*MINGW*|*CYGWIN*) return 0 ;;
        Linux)
            grep -qi microsoft /proc/version 2>/dev/null && return 0
            ;;
    esac
    return 1
}

open_in_editor() {
    local dir="$1"
    if [ -n "$EDITOR" ]; then
        (cd "$dir" && $EDITOR .)
    elif is_windows; then
        if command -v wslview &>/dev/null; then
            wslview "$dir"
        elif command -v explorer.exe &>/dev/null; then
            explorer.exe "$dir"
        elif command -v start &>/dev/null; then
            start "$dir"
        fi
    elif command -v open &>/dev/null; then
        open "$dir"
    else
        xdg-open "$dir"
    fi
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
        echo -e "${RED}  Missing dependencies:$missing${NC}"
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

# ============================================================
# FEATURE 1: Repo Status Overview
# ============================================================

get_repo_status() {
    local repo="$1"
    local status=""
    local has_changes=0
    local ahead=0
    local behind=0
    
    if [ ! -d "$repo/.git" ]; then
        echo "?"
        return
    fi
    
    cd "$repo" || return
    
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        has_changes=1
    fi
    
    if command -v git &>/dev/null; then
        local revs=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
        ahead=$(echo "$revs" | awk '{print $1}')
        behind=$(echo "$revs" | awk '{print $2}')
    fi
    
    if [ "$has_changes" -eq 1 ]; then
        status="${YELLOW}✎${NC}"
    else
        status="${GREEN}●${NC}"
    fi
    
    if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
        status="$status${MAGENTA}↕${NC}"
    elif [ "$ahead" -gt 0 ]; then
        status="$status${CYAN}↑${NC}"
    elif [ "$behind" -gt 0 ]; then
        status="$status${RED}↓${NC}"
    fi
    
    echo "$status"
}

format_repos_with_status() {
    local repos_file="$1"
    local temp_file=$(mktemp)
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local status
            status=$(get_repo_status "$repo")
            local name
            name=$(basename "$repo")
            local rel_path
            rel_path="${repo#$HOME/}"
            echo "${status} ${BOLD}${name}${NC}  ${BLUE}~/${rel_path}${NC}" >> "$temp_file"
        fi
    done < "$repos_file"
    
    cat "$temp_file"
    rm -f "$temp_file"
}

# ============================================================
# FEATURE 2: Search Across Repos
# ============================================================

search_repos() {
    echo -n "Enter search query: "
    read -r query
    
    if [ -z "$query" ]; then
        return
    fi
    
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local count
    count=$(echo "$all_repos" | wc -l)
    
    echo -e "${BLUE}Searching $count repos for: $query${NC}"
    echo ""
    
    local temp_results
    temp_results=$(mktemp)
    
    local found=0
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local results
            results=$(git -C "$repo" grep -n --heading --line-number --column "$query" 2>/dev/null || true)
            if [ -n "$results" ]; then
                local name
                name=$(basename "$repo")
                echo -e "${CYAN}${name}${NC}:" >> "$temp_results"
                echo "$results" | sed "s/^/  /" >> "$temp_results"
                echo "" >> "$temp_results"
                found=$((found + 1))
            fi
        fi
    done <<< "$all_repos"
    
    if [ "$found" -eq 0 ]; then
        echo -e "${YELLOW}No results found for: $query${NC}"
        rm -f "$temp_results"
        sleep 2
        return
    fi
    
    local selected
    selected=$(cat "$temp_results" | fzf --height 80% --border --header="Search results for: $query" --prompt="Select result > " || true)
    rm -f "$temp_results"
    
    if [ -n "$selected" ]; then
        local repo_name
        repo_name=$(echo "$selected" | head -1 | sed 's/:$//' | tr -d '[:space:]')
        local repo_path
        repo_path=$(grep -r "$repo_name$" "$CACHE_FILE" | head -1)
        if [ -n "$repo_path" ]; then
            repo_actions "$repo_path"
        fi
    fi
}

# ============================================================
# FEATURE 3: Bulk Actions
# ============================================================

bulk_actions() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local count
    count=$(echo "$all_repos" | wc -l)
    
    echo -e "${BLUE}Select repositories for bulk action (TAB to multi-select):${NC}"
    echo ""
    
    local formatted
    formatted=$(format_repos_with_status <(echo "$all_repos"))
    
    local selected
    selected=$(echo "$formatted" | fzf --height 70% --border --header="Select repos (TAB for multi-select)" --prompt="Select > " --multi || true)
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repos
    while IFS= read -r line; do
        local name
        name=$(echo "$line" | sed 's/^[^*↓↑↕✎●]*\s\+//' | awk '{print $1}')
        if [ -n "$name" ]; then
            local repo_path
            repo_path=$(grep "/${name}$" "$CACHE_FILE" | head -1)
            if [ -n "$repo_path" ]; then
                repos="$repos
$repo_path"
            fi
        fi
    done <<< "$selected"
    
    echo ""
    echo -e "${BLUE}Choose bulk action:${NC}"
    echo ""
    
    local action
    action=$(echo -e "⬇️  Pull All\n⬆️  Push All\n📊 Status All\n💬 Commit All\n🔍 Custom Command (per repo)" | fzf --height 25% --border --prompt="Action > " || true)
    
    local success=0
    local failed=0
    
    case "$action" in
        "⬇️  Pull All")
            echo -e "${BLUE}Pulling all repos...${NC}"
            while IFS= read -r repo; do
                if [ -n "$repo" ]; then
                    echo -e "${CYAN}Pulling: $(basename "$repo")${NC}"
                    if git -C "$repo" pull 2>&1 | tail -2; then
                        success=$((success + 1))
                    else
                        failed=$((failed + 1))
                    fi
                fi
            done <<< "$repos"
            ;;
        "⬆️  Push All")
            echo -e "${BLUE}Pushing all repos...${NC}"
            while IFS= read -r repo; do
                if [ -n "$repo" ]; then
                    echo -e "${CYAN}Pushing: $(basename "$repo")${NC}"
                    if git -C "$repo" push 2>&1 | tail -2; then
                        success=$((success + 1))
                    else
                        failed=$((failed + 1))
                    fi
                fi
            done <<< "$repos"
            ;;
        "📊 Status All")
            while IFS= read -r repo; do
                if [ -n "$repo" ]; then
                    echo -e "${BOLD}=== $(basename "$repo") ===${NC}"
                    git -C "$repo" status --short
                    echo ""
                fi
            done <<< "$repos"
            echo "Press Enter to continue..."
            read -r
            ;;
        "💬 Commit All")
            echo -n "Enter commit message: "
            read -r msg
            if [ -n "$msg" ]; then
                while IFS= read -r repo; do
                    if [ -n "$repo" ]; then
                        echo -e "${CYAN}Committing: $(basename "$repo")${NC}"
                        git -C "$repo" add -A && git -C "$repo" commit -m "$msg" 2>&1 | tail -3
                    fi
                done <<< "$repos"
            fi
            ;;
        "🔍 Custom Command (per repo)")
            echo -n "Enter command (use {repo} for repo path): "
            read -r cmd
            if [ -n "$cmd" ]; then
                while IFS= read -r repo; do
                    if [ -n "$repo" ]; then
                        echo -e "${CYAN}Running in: $(basename "$repo")${NC}"
                        local actual_cmd
                        actual_cmd=$(echo "$cmd" | sed "s|{repo}|$repo|g")
                        eval "$actual_cmd"
                    fi
                done <<< "$repos"
            fi
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}Done! $success succeeded, $failed failed${NC}"
    sleep 2
}

# ============================================================
# FEATURE 4: GitHub Integration
# ============================================================

github_repos() {
    if ! command -v gh &>/dev/null; then
        echo -e "${YELLOW}GitHub CLI (gh) is not installed.${NC}"
        echo ""
        echo -e "${BLUE}To install, run:${NC}"
        echo -e "${GREEN}  Arch:       sudo pacman -S github-cli${NC}"
        echo -e "${GREEN}  Ubuntu:     sudo apt install gh${NC}"
        echo -e "${GREEN}  macOS:      brew install gh${NC}"
        echo -e "${GREEN}  Windows:    winget install GitHub.cli${NC}"
        echo ""
        echo -e "${BLUE}Or visit: https://cli.github.com${NC}"
        echo ""
        echo "Press Enter to continue..."
        read -r
        return
    fi
    
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}Not authenticated with GitHub.${NC}"
        echo ""
        echo -e "${BLUE}Run: gh auth login${NC}"
        echo ""
        echo "Press Enter to continue..."
        read -r
        return
    fi
    
    echo -e "${BLUE}Fetching your GitHub repositories...${NC}"
    
    local repos
    repos=$(gh repo list --limit 100 --json name,owner,url --jq '.[] | "\(.owner.login)/\(.name)|\(.url)"' 2>/dev/null)
    
    if [ -z "$repos" ]; then
        echo -e "${YELLOW}No repositories found or error fetching.${NC}"
        sleep 2
        return
    fi
    
    local temp_file
    temp_file=$(mktemp)
    while IFS='|' read -r name url; do
        echo "$name" >> "$temp_file"
    done <<< "$repos"
    
    local selected
    selected=$(cat "$temp_file" | fzf --height 70% --border --header="Your GitHub Repositories" --prompt="Select repo > " || true)
    rm -f "$temp_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local url
    url=$(echo "$repos" | grep "^$selected|" | cut -d'|' -f2)
    
    echo ""
    echo -e "${BLUE}Selected: $selected${NC}"
    echo -e "${BLUE}URL: $url${NC}"
    echo ""
    echo -e "${BLUE}Choose action:${NC}"
    
    local action
    action=$(echo -e "📥 Clone Repository\n🌐 Open in Browser\n📂 View on GitHub" | fzf --height 20% --border --prompt="Action > " || true)
    
    case "$action" in
        "📥 Clone Repository")
            local dest="$REPO_DIR/$(echo "$selected" | tr '/' '-')"
            if [ -d "$dest" ]; then
                echo -e "${YELLOW}Repository already exists at: $dest${NC}"
                repo_actions "$dest"
            else
                echo -e "${BLUE}Cloning to: $dest${NC}"
                git clone "$url" "$dest" && repo_actions "$dest"
            fi
            ;;
        "🌐 Open in Browser")
            if command -v xdg-open &>/dev/null; then
                xdg-open "$url"
            elif command -v open &>/dev/null; then
                open "$url"
            fi
            ;;
        "📂 View on GitHub")
            if command -v xdg-open &>/dev/null; then
                xdg-open "https://github.com/$selected"
            elif command -v open &>/dev/null; then
                open "https://github.com/$selected"
            fi
            ;;
    esac
}

# ============================================================
# Core Functions
# ============================================================

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
    
    local status
    status=$(get_repo_status "$repo_path")
    
    local actions="🚀 Open in Lazygit (TUI)
📁 Browse Files (fzf)
📝 Open in Default Editor
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
        echo -e "  ${BOLD}$(basename "$repo_path")${NC}  $status"
        echo "  PATH: $repo_path"
        echo "===================================================="
        echo ""
        echo -e "${YELLOW}  Tip: Use 'Browse Files' to see all repo files${NC}"
        echo ""
        
        action=$(echo -e "$actions" | fzf --height 20% --layout=reverse --border --prompt="Select Action > " || true)
        
        case "$action" in
            "🚀 Open in Lazygit (TUI)")
                lazygit -p "$repo_path"
                ;;
            "📁 Browse Files (fzf)")
                (cd "$repo_path" && git ls-files | fzf --height 100% --border --header="Files in $(basename "$repo_path")" --preview="cat {}" --preview-window="right:60%:wrap" || true)
                ;;
            "📝 Open in Default Editor")
                open_in_editor "$repo_path"
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
    
    local all_repos
    all_repos=$( (cat "$RECENT_FILE"; cat "$CACHE_FILE") | awk 'NF && !x[$0]++')
    
    local formatted
    formatted=$(format_repos_with_status <(echo "$all_repos"))
    
    if [ -z "$formatted" ]; then
        echo -e "${YELLOW}No repositories found. Run 'Refresh' to rescan.${NC}"
        sleep 2
        return
    fi
    
    local selected
    selected=$(echo "$formatted" | fzf --height 70% --border --header="Status: ●Clean ✎Changes ↑Ahead ↓Behind ↕Diverged" --prompt="Search > " || true)
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local name
    name=$(echo "$selected" | sed 's/^[^*↓↑↕✎●]*\s\+//' | awk '{print $1}')
    
    local repo_path
    repo_path=$(grep "/${name}$" "$CACHE_FILE" | head -1)
    
    if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        repo_actions "$repo_path"
    fi
}

while true; do
    clear
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}           ${BOLD}GITY (TUI EDITION)${NC}${BLUE}            ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo ""
    echo -e "  ${BOLD}●${NC} ${GREEN}Clean${NC}    ${YELLOW}✎${NC} ${YELLOW}Changes${NC}    ${CYAN}↑${NC} ${CYAN}Ahead${NC}    ${RED}↓${NC} ${RED}Behind${NC}    ${MAGENTA}↕${NC} ${MAGENTA}Diverged${NC}"
    echo ""
    
    choice=$(echo -e "📂 Browse All Repositories
🔍 Search Across Repos
⚡ Bulk Actions
🐙 GitHub Repos
🔗 Clone Repository
✨ Create New Repository
🔄 Refresh Cache
❌ Exit" | fzf --height 30% --layout=reverse --border --prompt="Main Menu > " || true)
    
    case "$choice" in
        "📂 Browse All Repositories")
            open_existing
            ;;
        "🔍 Search Across Repos")
            search_repos
            ;;
        "⚡ Bulk Actions")
            bulk_actions
            ;;
        "🐙 GitHub Repos")
            github_repos
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
                git init "$dest" && touch "$dest/README.md" && git -C "$dest" add . && git -C "$dest" commit -m "Initial commit"
                repo_actions "$dest"
            fi
            ;;
        "🔄 Refresh Cache")
            refresh_cache
            ;;
        *)
            exit 0
            ;;
    esac
done
