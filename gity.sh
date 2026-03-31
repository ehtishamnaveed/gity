#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
WHITE='\033[1;37m'
DIM='\033[2m'
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
# UTILITY FUNCTIONS
# ============================================================

box_draw() {
    local width="$1"
    local char="$2"
    printf "%${width}s" "" | tr ' ' "$char"
}

# ============================================================
# FEATURE 1: Repo Status Overview
# ============================================================

get_repo_status() {
    local repo="$1"
    local status=""
    local has_changes=0
    local ahead=0
    local behind=0
    local dirty_files=0
    
    if [ ! -d "$repo/.git" ]; then
        echo "?"
        return
    fi
    
    cd "$repo" || return
    
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        has_changes=1
        dirty_files=$(git status --porcelain 2>/dev/null | wc -l)
    fi
    
    if command -v git &>/dev/null; then
        local revs
        revs=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
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
    
    echo "$status|$has_changes|$ahead|$behind|$dirty_files"
}

get_repo_status_simple() {
    local repo="$1"
    local status_info
    status_info=$(get_repo_status "$repo")
    echo "$status_info" | cut -d'|' -f1
}

get_repo_details() {
    local repo="$1"
    local status_info="$2"
    local has_changes=$(echo "$status_info" | cut -d'|' -f2)
    local ahead=$(echo "$status_info" | cut -d'|' -f3)
    local behind=$(echo "$status_info" | cut -d'|' -f4)
    local dirty_files=$(echo "$status_info" | cut -d'|' -f5)
    
    local details=""
    if [ "$has_changes" -eq 1 ]; then
        details="$dirty_files file(s) changed"
    fi
    if [ "$ahead" -gt 0 ]; then
        [ -n "$details" ] && details="$details, "
        details="${details}${ahead} commit(s) ahead"
    fi
    if [ "$behind" -gt 0 ]; then
        [ -n "$details" ] && details="$details, "
        details="${details}${behind} commit(s) behind"
    fi
    
    echo "$details"
}

format_repos_with_status() {
    local repos_file="$1"
    local temp_file=$(mktemp)
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local status
            status=$(get_repo_status_simple "$repo")
            local name
            name=$(basename "$repo")
            local rel_path
            rel_path="${repo#$HOME/}"
            echo "${status} ${BOLD}${name}${NC}  ${DIM}~/${rel_path}${NC}" >> "$temp_file"
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
        repo_path=$(grep -F "/${repo_name}" "$CACHE_FILE" | awk -F/ '{if ($NF == "'"${repo_name}"'") print}' | head -1)
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
            repo_path=$(grep -F "/${name}" "$CACHE_FILE" | awk -F/ '{if ($NF == "'"${name}"'") print}' | head -1)
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
    url=$(echo "$repos" | grep -F "$selected|" | cut -d'|' -f2)
    
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
# FEATURE 5: Repos Needing Attention Dashboard
# ============================================================

show_dashboard() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    echo -e "${BLUE}Scanning repos for status...${NC}"
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local count
    count=$(echo "$all_repos" | wc -l)
    
    local critical_file=$(mktemp)
    local warning_file=$(mktemp)
    local healthy_file=$(mktemp)
    
    local critical_count=0
    local warning_count=0
    local healthy_count=0
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local status_info
            status_info=$(get_repo_status "$repo")
            local status=$(echo "$status_info" | cut -d'|' -f1)
            local has_changes=$(echo "$status_info" | cut -d'|' -f2)
            local ahead=$(echo "$status_info" | cut -d'|' -f3)
            local behind=$(echo "$status_info" | cut -d'|' -f4)
            local dirty_files=$(echo "$status_info" | cut -d'|' -f5)
            local name=$(basename "$repo")
            
            local category=""
            local line="${status} ${BOLD}${name}${NC}"
            
            if [ "$has_changes" -eq 1 ] || [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
                category="critical"
                local details=""
                [ "$has_changes" -eq 1 ] && details="${dirty_files} file(s) changed"
                [ "$ahead" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${ahead}↑"
                [ "$behind" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${behind}↓"
                [ -z "$details" ] && [ "$ahead" -gt 0 ] && details="${ahead} commit(s) ahead" && [ "$behind" -gt 0 ] && details="${details}, ${behind} commit(s) behind"
                line="$line  ${DIM}$details${NC}"
            elif [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
                category="warning"
                local details=""
                [ "$ahead" -gt 0 ] && details="${ahead} ahead"
                [ "$behind" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${behind} behind"
                [ "$ahead" -eq 0 ] && [ "$behind" -gt 0 ] && details="${behind} commit(s) behind"
                [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ] && details="${ahead} commit(s) ahead"
                line="$line  ${DIM}$details${NC}"
            else
                category="healthy"
                line="$line  ${DIM}All synced${NC}"
            fi
            
            case "$category" in
                critical)
                    echo "$line" >> "$critical_file"
                    critical_count=$((critical_count + 1))
                    ;;
                warning)
                    echo "$line" >> "$warning_file"
                    warning_count=$((warning_count + 1))
                    ;;
                healthy)
                    echo "$line" >> "$healthy_file"
                    healthy_count=$((healthy_count + 1))
                    ;;
            esac
        fi
    done <<< "$all_repos"
    
    clear
    local width=60
    echo -e "${BLUE}╔$(box_draw $width '═')╗${NC}"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 30) / 2)) "")${BOLD}📊 REPOS NEEDING ATTENTION${NC}$(printf "%*s" $(((width - 30) / 2)) "")"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    echo -e "${BLUE}║${NC}  Total: $count repos scanned"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    
    if [ "$critical_count" -gt 0 ]; then
        echo -e "${BLUE}║${NC}  ${RED}🔴 CRITICAL ($critical_count repos)${NC}$(printf "%*s" $((width - 30)) "")"
        echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
        while IFS= read -r line; do
            echo -e "${BLUE}║${NC}  $line$(printf "%*s" $((width - ${#line} - 2)) "")"
        done < "$critical_file"
        echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    fi
    
    if [ "$warning_count" -gt 0 ]; then
        echo -e "${BLUE}║${NC}  ${YELLOW}🟡 WARNINGS ($warning_count repos)${NC}$(printf "%*s" $((width - 30)) "")"
        echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
        while IFS= read -r line; do
            echo -e "${BLUE}║${NC}  $line$(printf "%*s" $((width - ${#line} - 2)) "")"
        done < "$warning_file"
        echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    fi
    
    if [ "$healthy_count" -gt 0 ]; then
        echo -e "${BLUE}║${NC}  ${GREEN}🟢 HEALTHY ($healthy_count repos)${NC}$(printf "%*s" $((width - 28)) "")"
        echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
        while IFS= read -r line; do
            echo -e "${BLUE}║${NC}  $line$(printf "%*s" $((width - ${#line} - 2)) "")"
        done < "$healthy_file"
    fi
    
    echo -e "${BLUE}╚$(box_draw $width '═')╝${NC}"
    echo ""
    echo -e "${DIM}  Legend: ${GREEN}●${NC} Clean  ${YELLOW}✎${NC} Changes  ${CYAN}↑${NC} Ahead  ${RED}↓${NC} Behind  ${MAGENTA}↕${NC} Diverged${NC}"
    
    rm -f "$critical_file" "$warning_file" "$healthy_file"
    
    local all_repos_file=$(mktemp)
    local critical_count2=0 warning_count2=0 healthy_count2=0
    
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        local name
        name=$(basename "$repo")
        echo "$name|$repo" >> "$all_repos_file"
    done <<< "$all_repos"
    
    local selected
    selected=$(cat "$all_repos_file" | while IFS='|' read -r name repo; do
        [ ! -d "$repo/.git" ] && continue
        local status_info
        status_info=$(get_repo_status "$repo")
        local status=$(echo "$status_info" | cut -d'|' -f1)
        local has_changes=$(echo "$status_info" | cut -d'|' -f2)
        local ahead=$(echo "$status_info" | cut -d'|' -f3)
        local behind=$(echo "$status_info" | cut -d'|' -f4)
        local dirty_files=$(echo "$status_info" | cut -d'|' -f5)
        local details=""
        if [ "$has_changes" -eq 1 ]; then
            details="${dirty_files} file(s) changed"
        fi
        [ "$ahead" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${ahead}↑"
        [ "$behind" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${behind}↓"
        [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ] && [ -z "$details" ] && details="${ahead} commit(s) ahead"
        [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ] && [ -z "$details" ] && details="${behind} commit(s) behind"
        [ -z "$details" ] && details="All synced"
        echo "$status ${BOLD}${name}${NC}  ${DIM}$details${NC}"
    done | fzf --height 80% --border --header="Dashboard - Select a repo" --prompt="> " || true)
    
    rm -f "$all_repos_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local name
    name=$(echo "$selected" | sed 's/^[^*↓↑↕✎●]*\s\+//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep -F "/${name}" "$CACHE_FILE" | awk -F/ '{if ($NF == "'"${name}"'") print}' | head -1)
    
    if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        repo_actions "$repo_path"
    fi
}

# ============================================================
# FEATURE 7: Branch Health Overview
# ============================================================

show_branch_health() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    
    echo -e "${BLUE}Analyzing branch health...${NC}"
    
    local temp_file=$(mktemp)
    local repo_count=0
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local name
            name=$(basename "$repo")
            
            local branch_count
            branch_count=$(git -C "$repo" branch -a 2>/dev/null | wc -l)
            
            local current_branch
            current_branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")
            
            local stale_branches=0
            local stale_list=$(git -C "$repo" for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:relative)' refs/heads 2>/dev/null | awk '$2 ~ /months|year/ {print $1}' | head -3)
            [ -n "$stale_list" ] && stale_branches=$(echo "$stale_list" | wc -l)
            
            local unmerged_count=0
            if [ -n "$current_branch" ] && [ "$current_branch" != "detached" ]; then
                unmerged_count=$(git -C "$repo" cherry -v 2>/dev/null | wc -l)
            fi
            
            local status="${GREEN}🟢${NC}"
            if [ "$stale_branches" -gt 2 ]; then
                status="${YELLOW}🟡${NC}"
            fi
            if [ "$stale_branches" -gt 5 ]; then
                status="${RED}🔴${NC}"
            fi
            
            local stale_info=""
            if [ "$stale_branches" -gt 0 ]; then
                stale_info=" • ${RED}$stale_branches stale${NC}"
            fi
            
            echo "$status ${BOLD}${name}${NC}  ${DIM}$branch_count branches${NC} • ${CYAN}$current_branch${NC}${stale_info}" >> "$temp_file"
            repo_count=$((repo_count + 1))
        fi
    done <<< "$all_repos"
    
    clear
    local width=65
    echo -e "${BLUE}╔$(box_draw $width '═')╗${NC}"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 18) / 2)) "")${BOLD}🌿 BRANCH HEALTH${NC}$(printf "%*s" $(((width - 18) / 2)) "")"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    
    if [ "$repo_count" -eq 0 ]; then
        echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 20) / 2)) "")${YELLOW}No repos found${NC}"
    else
        while IFS= read -r line; do
            echo -e "${BLUE}║${NC}  $line$(printf "%*s" $((width - ${#line} - 2)) "")"
        done < "$temp_file"
    fi
    
    rm -f "$temp_file"
    
    echo -e "${BLUE}╚$(box_draw $width '═')╝${NC}"
    echo ""
    echo -e "${DIM}  Legend: ${GREEN}🟢${NC} Healthy  ${YELLOW}🟡${NC} Needs cleanup  ${RED}🔴${NC} Needs attention${NC}"
    
    local selected
    selected=$(cat "$temp_file" | while IFS= read -r line; do
        echo "$line"
    done | fzf --height 80% --border --header="Branch Health - Select a repo" --prompt="> " || true)
    
    rm -f "$temp_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local name
    name=$(echo "$selected" | sed 's/^[^\s]*\s[[:space:]]*//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep -F "/${name}" "$CACHE_FILE" | awk -F/ '{if ($NF == "'"${name}"'") print}' | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# FEATURE 8: Activity Timeline
# ============================================================

show_activity_timeline() {
    local days=${1:-7}
    
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    
    echo -e "${BLUE}Fetching activity for last $days days...${NC}"
    
    local temp_file=$(mktemp)
    local commit_count=0
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local name
            name=$(basename "$repo")
            
            local commits
            commits=$(git -C "$repo" log --since="$days days ago" --format="|%h|%s|%ai|%an" 2>/dev/null || true)
            
            while IFS='|' read -r hash msg date author; do
                [ -z "$hash" ] && continue
                local day
                day=$(echo "$date" | awk '{print $1}')
                echo "$day|$name|$msg|$date" >> "$temp_file"
                commit_count=$((commit_count + 1))
            done <<< "$commits"
        fi
    done <<< "$all_repos"
    
    clear
    local width=65
    echo -e "${BLUE}╔$(box_draw $width '═')╗${NC}"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 24) / 2)) "")${BOLD}📅 ACTIVITY TIMELINE${NC}$(printf "%*s" $(((width - 24) / 2)) "")"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 24) / 2)) "")${DIM}(Last $days days)${NC}"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    echo -e "${BLUE}║${NC}  Total: $commit_count commits across all repos"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    
    if [ "$commit_count" -eq 0 ]; then
        echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 25) / 2)) "")${YELLOW}No recent activity${NC}"
    else
        local current_day=""
        while IFS='|' read -r day repo msg date; do
            if [ "$day" != "$current_day" ]; then
                current_day="$day"
                echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
                echo -e "${BLUE}║${NC}  ${BOLD}${day}${NC}$(printf "%*s" $((width - ${#day} - 2)) "")"
                echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
            fi
            local short_msg
            short_msg=$(echo "$msg" | cut -c1-45)
            echo -e "${BLUE}║${NC}    ${CYAN}$repo${NC}  $short_msg"
        done < <(sort -r "$temp_file")
    fi
    
    rm -f "$temp_file"
    
    echo -e "${BLUE}╚$(box_draw $width '═')╝${NC}"
    local selected
    selected=$(echo -e "1 Day\n7 Days\n30 Days\nExit" | fzf --height 20% --border --prompt="Timeline range > " || true)
    
    rm -f "$temp_file"
    
    case "$selected" in
        "1 Day")    show_activity_timeline 1 ;;
        "7 Days")   show_activity_timeline 7 ;;
        "30 Days")  show_activity_timeline 30 ;;
    esac
}

# ============================================================
# FEATURE 9: Work Session Summary
# ============================================================

show_work_summary() {
    local hours=${1:-24}
    
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    
    echo -e "${BLUE}Calculating work summary...${NC}"
    
    local temp_file=$(mktemp)
    local total_commits=0
    local total_lines_added=0
    local total_lines_deleted=0
    local repos_touched=0
    declare -A commit_counts
    declare -A file_counts
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local name
            name=$(basename "$repo")
            
            local commits
            commits=$(git -C "$repo" log --since="$hours hours ago" --format="|%H" 2>/dev/null || true)
            
            local repo_commits=0
            while IFS='|' read -r hash; do
                [ -z "$hash" ] && continue
                ((repo_commits++))
                
                local diff_stats
                diff_stats=$(git -C "$repo" show "$hash" --stat --format="" 2>/dev/null | tail -1)
                local added
                added=$(echo "$diff_stats" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
                local deleted
                deleted=$(echo "$diff_stats" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")
                
                total_lines_added=$((total_lines_added + added))
                total_lines_deleted=$((total_lines_deleted + deleted))
                
                local files_changed
                files_changed=$(echo "$diff_stats" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
                file_counts["$name"]=$((${file_counts["$name"]:-0} + files_changed))
            done <<< "$commits"
            
            if [ "$repo_commits" -gt 0 ]; then
                commit_counts["$name"]=$repo_commits
                total_commits=$((total_commits + repo_commits))
                repos_touched=$((repos_touched + 1))
                echo "$name|$repo_commits|${file_counts["$name"]:-0}" >> "$temp_file"
            fi
        fi
    done <<< "$all_repos"
    
    clear
    local width=60
    echo -e "${BLUE}╔$(box_draw $width '═')╗${NC}"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 26) / 2)) "")${BOLD}📊 WORK SUMMARY${NC}$(printf "%*s" $(((width - 26) / 2)) "")"
    echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 20) / 2)) "")${DIM}(Last $hours hours)${NC}"
    echo -e "${BLUE}╠$(box_draw $width '═')╣${NC}"
    echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
    echo -e "${BLUE}║${NC}   ${BOLD}$repos_touched repos touched${NC}  •  ${BOLD}$total_commits commits${NC}  •  ${GREEN}+$total_lines_added${NC} / ${RED}-$total_lines_deleted lines"
    echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
    
    if [ "$repos_touched" -gt 0 ]; then
        echo -e "${BLUE}║${NC}  ${BOLD}Most Active Repos:${NC}$(printf "%*s" $((width - 24)) "")"
        echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
        
        while IFS='|' read -r name commits files; do
            local bar_width=20
            local max_commits=10
            local filled=$((commits * bar_width / max_commits))
            [ "$filled" -gt "$bar_width" ] && filled=$bar_width
            local bar=$(printf "%${filled}s" "" | tr ' ' '█')
            local remaining=$((bar_width - filled))
            [ "$remaining" -lt 0 ] && remaining=0
            bar="$bar$(printf "%${remaining}s" "" | tr ' ' '░')"
            echo -e "${BLUE}║${NC}    ${CYAN}$name${NC}  ${GREEN}$bar${NC}  $commits commits"
        done < <(sort -t'|' -k2 -rn "$temp_file")
    else
        echo -e "${BLUE}║${NC}$(printf "%*s" $(((width + 15) / 2)) "")${YELLOW}No commits yet${NC}"
    fi
    
    rm -f "$temp_file"
    
    echo -e "${BLUE}║${NC}$(box_draw $width ' ')"
    echo -e "${BLUE}╚$(box_draw $width '═')╝${NC}"
    echo ""
    echo -e "${DIM}  [1] Last hour  [24] Last 24h  [168] Last week  [Q] Quit${NC}"
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
    
    grep -vF "$repo_path" "$RECENT_FILE" > "$RECENT_FILE.tmp" 2>/dev/null || true
    printf '%s\n' "$repo_path" | cat - "$RECENT_FILE.tmp" | head -n 10 > "$RECENT_FILE"
    rm -f "$RECENT_FILE.tmp"
    
    local status
    status=$(get_repo_status_simple "$repo_path")
    
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

    local selected
    selected=$( (cat "$RECENT_FILE"; cat "$CACHE_FILE") | awk 'NF && !x[$0]++' | fzf --height 60% --border --header="Select Repository (Recent at top)" --prompt="Search > " || true)

    if [ -n "$selected" ]; then
        repo_actions "$selected"
    fi
}

while true; do
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}           ${BOLD}${WHITE}GITY${NC} ${DIM}-${NC} ${BOLD}TUI Git Hub${NC}               ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Status Indicators:${NC}  ${GREEN}●${NC} Clean  ${YELLOW}✎${NC} Changes  ${CYAN}↑${NC} Ahead  ${RED}↓${NC} Behind  ${MAGENTA}↕${NC} Diverged"
    echo ""
    
    choice=$(echo -e "📊 Dashboard (Repos Needing Work)
📂 Browse All Repositories
📅 Activity Timeline
⚡ Bulk Actions
🔍 Search Across Repos
🐙 GitHub Repos
🔗 Clone Repository
✨ Create New Repository
🔄 Refresh Cache
❌ Exit" | fzf --height 45% --layout=reverse --border --prompt="Main Menu > " || true)
    
    case "$choice" in
        "📊 Dashboard (Repos Needing Work)")
            show_dashboard
            ;;
        "📂 Browse All Repositories")
            open_existing
            ;;
        "📅 Activity Timeline")
            show_activity_timeline 7
            ;;
        "⚡ Bulk Actions")
            bulk_actions
            ;;
        "🔍 Search Across Repos")
            search_repos
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
