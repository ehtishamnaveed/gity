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
    
    local revs
    revs=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
    ahead=$(echo "$revs" | awk '{print $1}')
    behind=$(echo "$revs" | awk '{print $2}')
    
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

get_repo_details() {
    local repo="$1"
    cd "$repo" || return ""
    
    local has_changes=0
    local ahead=0
    local behind=0
    
    [ -n "$(git status --porcelain 2>/dev/null)" ] && has_changes=1
    
    local revs
    revs=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
    ahead=$(echo "$revs" | awk '{print $1}')
    behind=$(echo "$revs" | awk '{print $2}')
    
    local details=""
    [ "$has_changes" -eq 1 ] && details="Has uncommitted changes"
    [ "$ahead" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${ahead} commit(s) ahead"
    [ "$behind" -gt 0 ] && [ -n "$details" ] && details="$details, " && details="${details}${behind} commit(s) behind"
    [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ] && [ -z "$details" ] && details="${ahead} commit(s) ahead"
    [ "$behind" -gt 0 ] && [ "$ahead" -eq 0 ] && [ -z "$details" ] && details="${behind} commit(s) behind"
    [ -z "$details" ] && details="All synced"
    
    echo "$details"
}

# ============================================================
# FEATURE 1: Search Across Repos
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
    
    local temp_results
    temp_results=$(mktemp)
    local found=0
    
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local name
            name=$(basename "$repo")
            local results
            results=$(git -C "$repo" grep -n --heading --line-number --column "$query" 2>/dev/null || true)
            if [ -n "$results" ]; then
                echo "$name|$repo" >> "$temp_results"
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
    selected=$(cat "$temp_results" | while IFS='|' read -r name path; do
        echo "$name  ${DIM}$path${NC}"
    done | fzf --height 80% --border --header="Results for: $query" --prompt="Select > " || true)
    
    rm -f "$temp_results"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repo_name
    repo_name=$(echo "$selected" | awk '{print $1}')
    local repo_path
    repo_path=$(grep "/${repo_name}$" "$CACHE_FILE" | head -1)
    
    if [ -n "$repo_path" ] && [ -d "$repo_path" ]; then
        repo_actions "$repo_path"
    fi
}

# ============================================================
# FEATURE 2: Bulk Actions
# ============================================================

bulk_actions() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    
    local formatted
    formatted=$(mktemp)
    while IFS= read -r repo; do
        if [ -d "$repo/.git" ]; then
            local status
            status=$(get_repo_status "$repo")
            local name
            name=$(basename "$repo")
            echo "$status $name  ${DIM}$repo${NC}"
        fi
    done <<< "$all_repos" > "$formatted"
    
    local selected
    selected=$(cat "$formatted" | fzf --height 70% --border --header="Select repos (TAB for multi-select)" --prompt="Select > " --multi || true)
    rm -f "$formatted"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repos=""
    while IFS= read -r line; do
        local name
        name=$(echo "$line" | sed 's/^[^*↓↑↕✎●]*[^*↓↑↕✎●][[:space:]]*//' | awk '{print $1}')
        if [ -n "$name" ]; then
            local repo_path
            repo_path=$(grep "/${name}$" "$CACHE_FILE" | head -1)
            [ -n "$repo_path" ] && repos="$repos
$repo_path"
        fi
    done <<< "$selected"
    
    local action
    action=$(echo -e "Pull All\nPush All\nStatus All\nCommit All\nCustom Command" | fzf --height 25% --border --prompt="Action > " || true)
    
    local success=0
    local failed=0
    
    case "$action" in
        "Pull All")
            while IFS= read -r repo; do
                [ -z "$repo" ] && continue
                echo -e "${CYAN}Pulling: $(basename "$repo")${NC}"
                git -C "$repo" pull 2>&1 | tail -1 && success=$((success + 1)) || failed=$((failed + 1))
            done <<< "$repos"
            ;;
        "Push All")
            while IFS= read -r repo; do
                [ -z "$repo" ] && continue
                echo -e "${CYAN}Pushing: $(basename "$repo")${NC}"
                git -C "$repo" push 2>&1 | tail -1 && success=$((success + 1)) || failed=$((failed + 1))
            done <<< "$repos"
            ;;
        "Status All")
            while IFS= read -r repo; do
                [ -z "$repo" ] && continue
                echo -e "${BOLD}=== $(basename "$repo") ===${NC}"
                git -C "$repo" status --short
                echo ""
            done <<< "$repos"
            echo "Press Enter to continue..."
            read -r
            ;;
        "Commit All")
            echo -n "Enter commit message: "
            read -r msg
            if [ -n "$msg" ]; then
                while IFS= read -r repo; do
                    [ -z "$repo" ] && continue
                    echo -e "${CYAN}Committing: $(basename "$repo")${NC}"
                    git -C "$repo" add -A && git -C "$repo" commit -m "$msg" 2>&1 | tail -2
                done <<< "$repos"
            fi
            ;;
        "Custom Command")
            echo -n "Enter command: "
            read -r cmd
            if [ -n "$cmd" ]; then
                while IFS= read -r repo; do
                    [ -z "$repo" ] && continue
                    echo -e "${CYAN}Running in: $(basename "$repo")${NC}"
                    eval "$(echo "$cmd" | sed "s|{repo}|$repo|g")"
                done <<< "$repos"
            fi
            ;;
    esac
    
    echo -e "${GREEN}Done! $success succeeded, $failed failed${NC}"
    sleep 2
}

# ============================================================
# FEATURE 3: GitHub Integration
# ============================================================

github_repos() {
    if ! command -v gh &>/dev/null; then
        echo -e "${YELLOW}GitHub CLI (gh) is not installed.${NC}"
        echo ""
        echo -e "${BLUE}Install: sudo apt install gh (Ubuntu) / brew install gh (macOS)${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi
    
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}Not authenticated. Run: gh auth login${NC}"
        echo "Press Enter to continue..."
        read -r
        return
    fi
    
    echo -e "${BLUE}Fetching GitHub repositories...${NC}"
    
    local repos
    repos=$(gh repo list --limit 100 --json name,owner,url --jq '.[] | "\(.owner.login)/\(.name)|\(.url)"' 2>/dev/null)
    
    if [ -z "$repos" ]; then
        echo -e "${YELLOW}No repositories found.${NC}"
        sleep 2
        return
    fi
    
    local selected
    selected=$(echo "$repos" | while IFS='|' read -r name url; do
        echo "$name"
    done | fzf --height 70% --border --header="Your GitHub Repositories" --prompt="Select > " || true)
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local url
    url=$(echo "$repos" | grep "^$selected|" | cut -d'|' -f2)
    
    local action
    action=$(echo -e "Clone Repository\nOpen in Browser\nView on GitHub" | fzf --height 20% --border --prompt="Action > " || true)
    
    case "$action" in
        "Clone Repository")
            local dest="$REPO_DIR/$(echo "$selected" | tr '/' '-')"
            if [ -d "$dest" ]; then
                echo -e "${YELLOW}Already exists: $dest${NC}"
                repo_actions "$dest"
            else
                git clone "$url" "$dest" && repo_actions "$dest"
            fi
            ;;
        "Open in Browser")
            xdg-open "$url" 2>/dev/null || open "$url" 2>/dev/null
            ;;
        "View on GitHub")
            xdg-open "https://github.com/$selected" 2>/dev/null || open "https://github.com/$selected" 2>/dev/null
            ;;
    esac
}

# ============================================================
# VISUALIZATION: Dashboard (Repos Needing Work)
# ============================================================

show_dashboard() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    echo -e "${BLUE}Scanning repos...${NC}"
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    
    local critical_file=$(mktemp)
    local warning_file=$(mktemp)
    local healthy_file=$(mktemp)
    local all_repos_file=$(mktemp)
    
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        
        local status
        status=$(get_repo_status "$repo")
        local name
        name=$(basename "$repo")
        local details
        details=$(get_repo_details "$repo")
        
        local line="$status $name  ${DIM}$details${NC}"
        echo "$name|$repo|$status" >> "$all_repos_file"
        
        local has_changes=0
        local ahead=0
        local behind=0
        
        cd "$repo" || continue
        [ -n "$(git status --porcelain 2>/dev/null)" ] && has_changes=1
        local revs
        revs=$(git rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null || echo "0 0")
        ahead=$(echo "$revs" | awk '{print $1}')
        behind=$(echo "$revs" | awk '{print $2}')
        
        if [ "$has_changes" -eq 1 ] || { [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; }; then
            echo "$line" >> "$critical_file"
        elif [ "$ahead" -gt 0 ] || [ "$behind" -gt 0 ]; then
            echo "$line" >> "$warning_file"
        else
            echo "$line" >> "$healthy_file"
        fi
    done <<< "$all_repos"
    
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}         ${BOLD}📊 REPOS NEEDING ATTENTION${NC}                       ${BLUE}║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    
    [ -s "$critical_file" ] && echo -e "${BLUE}║${NC}  ${RED}🔴 CRITICAL (needs immediate attention)${NC}" && echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    [ -s "$critical_file" ] && cat "$critical_file" | while IFS= read -r line; do echo -e "${BLUE}║${NC}  $line"; done
    
    [ -s "$warning_file" ] && echo -e "${BLUE}║${NC}  ${YELLOW}🟡 WARNINGS (sync needed)${NC}" && echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    [ -s "$warning_file" ] && cat "$warning_file" | while IFS= read -r line; do echo -e "${BLUE}║${NC}  $line"; done
    
    [ -s "$healthy_file" ] && echo -e "${BLUE}║${NC}  ${GREEN}🟢 HEALTHY (all synced)${NC}" && echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
    [ -s "$healthy_file" ] && cat "$healthy_file" | while IFS= read -r line; do echo -e "${BLUE}║${NC}  $line"; done
    
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    local selected
    selected=$(cat "$all_repos_file" | while IFS='|' read -r name repo status; do
        echo "$status $name  ${DIM}$repo${NC}"
    done | fzf --height 80% --border --header="Select a repo to open" --prompt="> " || true)
    
    rm -f "$critical_file" "$warning_file" "$healthy_file" "$all_repos_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repo_name
    repo_name=$(echo "$selected" | sed 's/^[^*↓↑↕✎●]*[^*↓↑↕✎●][[:space:]]*//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep "/${repo_name}$" "$CACHE_FILE" | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# VISUALIZATION: Stale Repo Finder
# ============================================================

show_stale_repos() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    echo -e "${BLUE}Checking repo activity...${NC}"
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local temp_file=$(mktemp)
    local stale_count=0
    
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        
        local name
        name=$(basename "$repo")
        local last_date
        last_date=$(git -C "$repo" log -1 --format="%ai" 2>/dev/null | awk '{print $1}')
        local days_since=0
        
        if [ -n "$last_date" ]; then
            days_since=$(python3 -c "from datetime import datetime; print((datetime.now() - datetime.strptime('$last_date', '%Y-%m-%d')).days)" 2>/dev/null || echo "0")
        fi
        
        local last_msg
        last_msg=$(git -C "$repo" log -1 --format="%s" 2>/dev/null | cut -c1-30)
        [ -z "$last_msg" ] && last_msg="No commits"
        
        local indicator="🟢"
        local urgency="recent"
        
        if [ "$days_since" -eq 0 ]; then
            indicator="🟢"
            urgency="recent"
        elif [ "$days_since" -lt 30 ]; then
            indicator="🟢"
            urgency="recent"
        elif [ "$days_since" -lt 60 ]; then
            indicator="🟡"
            urgency="stale"
            stale_count=$((stale_count + 1))
        elif [ "$days_since" -lt 90 ]; then
            indicator="🔴"
            urgency="very_stale"
            stale_count=$((stale_count + 1))
        else
            indicator="⚠️"
            urgency="abandoned"
            stale_count=$((stale_count + 1))
        fi
        
        if [ "$urgency" != "recent" ]; then
            echo "$indicator|$days_since|$name|$last_msg|$repo" >> "$temp_file"
        fi
    done <<< "$all_repos"
    
    if [ "$stale_count" -eq 0 ]; then
        echo -e "${GREEN}All repos are active! No stale repos found.${NC}"
        rm -f "$temp_file"
        sleep 2
        return
    fi
    
    local selected
    selected=$(cat "$temp_file" | sort -t'|' -k2 -rn | while IFS='|' read -r indicator days name msg repo; do
        echo "$indicator $name  ${DIM}($days days) $msg${NC}"
    done | fzf --height 80% --border --header="Stale Repos - Select to open" --prompt="> " || true)
    
    rm -f "$temp_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repo_name
    repo_name=$(echo "$selected" | sed 's/^[^\s]*\s[[:space:]]*//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep "/${repo_name}$" "$CACHE_FILE" | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# VISUALIZATION: Branch Health
# ============================================================

show_branch_health() {
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    echo -e "${BLUE}Analyzing branch health...${NC}"
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local temp_file=$(mktemp)
    local count=0
    
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        
        local name
        name=$(basename "$repo")
        local branch_count
        branch_count=$(git -C "$repo" branch -a 2>/dev/null | wc -l)
        local current_branch
        current_branch=$(git -C "$repo" branch --show-current 2>/dev/null || echo "detached")
        
        local stale_branches
        stale_branches=$(git -C "$repo" for-each-ref --sort=-committerdate --format='%(refname:short) %(committerdate:relative)' refs/heads 2>/dev/null | awk '$2 ~ /months|year/ {print $1}' | wc -l)
        
        local indicator="🟢"
        [ "$stale_branches" -gt 2 ] && indicator="🟡"
        [ "$stale_branches" -gt 5 ] && indicator="🔴"
        
        local stale_info=""
        [ "$stale_branches" -gt 0 ] && stale_info=" • ${RED}$stale_branches stale${NC}"
        
        echo "$indicator|$name|$branch_count|$current_branch|$stale_info|$repo" >> "$temp_file"
        count=$((count + 1))
    done <<< "$all_repos"
    
    local selected
    selected=$(cat "$temp_file" | while IFS='|' read -r indicator name branches current stale info repo; do
        echo "$indicator $name  ${DIM}($branches branches) • $current${stale}${NC}"
    done | fzf --height 80% --border --header="Branch Health - Select a repo" --prompt="> " || true)
    
    rm -f "$temp_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repo_name
    repo_name=$(echo "$selected" | sed 's/^[^\s]*\s[[:space:]]*//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep "/${repo_name}$" "$CACHE_FILE" | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# VISUALIZATION: Activity Timeline
# ============================================================

show_activity_timeline() {
    local days=${1:-7}
    
    if [ ! -s "$CACHE_FILE" ]; then
        refresh_cache
    fi
    
    echo -e "${BLUE}Fetching activity for last $days days...${NC}"
    
    local all_repos
    all_repos=$(cat "$CACHE_FILE")
    local temp_file=$(mktemp)
    local commit_count=0
    
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        
        local name
        name=$(basename "$repo")
        
        git -C "$repo" log --since="$days days ago" --format="|%h|%s|%ai|%an" 2>/dev/null | grep '|' | while IFS='|' read -r hash msg date author; do
            [ -z "$hash" ] && continue
            local day
            day=$(echo "$date" | awk '{print $1}')
            echo "$day|$name|$msg" >> "$temp_file"
            commit_count=$((commit_count + 1))
        done
    done <<< "$all_repos"
    
    if [ "$commit_count" -eq 0 ]; then
        echo -e "${YELLOW}No activity in the last $days days.${NC}"
        rm -f "$temp_file"
        sleep 2
        return
    fi
    
    local selected
    selected=$(cat "$temp_file" | sort -r | while IFS='|' read -r day name msg; do
        echo "${CYAN}$day${NC}  ${BOLD}$name${NC}  $msg"
    done | fzf --height 80% --border --header="Activity Timeline (Last $days days) - Select to open repo" --prompt="> " || true)
    
    rm -f "$temp_file"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local repo_name
    repo_name=$(echo "$selected" | sed 's/^[^\s]*\s[[:space:]]*//' | awk '{print $1}')
    local repo_path
    repo_path=$(grep "/${repo_name}$" "$CACHE_FILE" | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# Core Functions
# ============================================================

refresh_cache() {
    echo -e "${BLUE}Scanning for Git repositories...${NC}"
    
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
    echo -e "${GREEN}Found $count repositories.${NC}"
    sleep 1
}

clone_repo() {
    echo -n "Enter Repository URL: "
    read -r url
    if [ -n "$url" ]; then
        local repo_name
        repo_name=$(basename "$url" .git)
        local dest="$REPO_DIR/$repo_name"
        if [ ! -d "$dest" ]; then
            echo -e "${BLUE}Cloning into $dest...${NC}"
            git clone "$url" "$dest" && repo_actions "$dest"
        else
            echo -e "${YELLOW}Directory already exists.${NC}"
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
    local details
    details=$(get_repo_details "$repo_path")
    
    local actions="🚀 Open in Lazygit (TUI)
📁 Browse Files (fzf)
📝 Open in Default Editor
📂 Open in File Manager"
    
    [ -n "$CLIPBOARD_TOOL" ] && actions="$actions
📋 Copy Path to Clipboard"
    actions="$actions
🔙 Back to Gity"
    
    while true; do
        clear
        echo "===================================================="
        echo -e "  ${BOLD}$(basename "$repo_path")${NC}  $status"
        echo "  PATH: $repo_path"
        echo "  STATUS: $details"
        echo "===================================================="
        echo ""
        
        local action
        action=$(echo -e "$actions" | fzf --height 25% --layout=reverse --border --prompt="Select Action > " || true)
        
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
                copy_path "$repo_path" && echo "Path copied!" && sleep 1
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
    
    local formatted=$(mktemp)
    while IFS= read -r repo; do
        [ ! -d "$repo/.git" ] && continue
        local status
        status=$(get_repo_status "$repo")
        local name
        name=$(basename "$repo")
        local details
        details=$(get_repo_details "$repo")
        echo "$status $name  ${DIM}$details${NC}"
    done <<< "$all_repos" > "$formatted"
    
    if [ ! -s "$formatted" ]; then
        echo -e "${YELLOW}No repositories found. Run Refresh to rescan.${NC}"
        rm -f "$formatted"
        sleep 2
        return
    fi
    
    local selected
    selected=$(cat "$formatted" | fzf --height 80% --border --header="Select Repository - ●Clean ✎Changes ↑Ahead ↓Behind ↕Diverged" --prompt="Search > " || true)
    rm -f "$formatted"
    
    if [ -z "$selected" ]; then
        return
    fi
    
    local name
    name=$(echo "$selected" | sed 's/^[^*↓↑↕✎●]*[^*↓↑↕✎●][[:space:]]*//' | awk '{print $1}')
    
    local repo_path
    repo_path=$(grep "/${name}$" "$CACHE_FILE" | head -1)
    
    [ -n "$repo_path" ] && [ -d "$repo_path" ] && repo_actions "$repo_path"
}

# ============================================================
# MAIN MENU
# ============================================================

show_main_menu() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}              ${BOLD}${WHITE}GITY${NC} ${DIM}-${NC} ${BOLD}TUI Git Hub${NC}               ${BLUE}║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Status:${NC}  ${GREEN}●${NC} Clean  ${YELLOW}✎${NC} Changes  ${CYAN}↑${NC} Ahead  ${RED}↓${NC} Behind  ${MAGENTA}↕${NC} Diverged"
    echo ""
    
    local choice
    while true; do
    choice=$(echo -e "📊 Dashboard (Repos Needing Work)
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
❌ Exit" | fzf --height 50% --layout=reverse --border --prompt="Main Menu > " || true)
    
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
        "🕰️ Stale Repos")
            show_stale_repos
            ;;
        "🌿 Branch Health")
            show_branch_health
            ;;
        "⚡ Bulk Actions")
            bulk_actions
            ;;
        "🔍 Search Across Repos")
            search_across_repos
            ;;
        "🐙 GitHub Repos")
            browse_github_repos
            ;;
        "🔗 Clone Repository")
            clone_repo
            ;;
        "✨ Create New Repository")
            echo -n "Enter repository name: "
            read -r name
            if [ -n "$name" ]; then
                local dest="$REPO_DIR/$name"
                mkdir -p "$dest"
                git init "$dest" && touch "$dest/README.md" && git -C "$dest" add . && git -C "$dest" commit -m "Initial commit"
                repo_actions "$dest"
            fi
            ;;
        "🔄 Refresh Cache")
            refresh_cache
            ;;
        *)
            return 1
            ;;
    esac
    done
}
show_main_menu
