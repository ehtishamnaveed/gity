import os
import subprocess
import shutil
import sys
import time
from pathlib import Path
from datetime import datetime, timedelta

# Color constants for terminal output
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
CYAN = "\033[0;36m"
MAGENTA = "\033[0;35m"
WHITE = "\033[1;37m"
BOLD = "\033[1m"
DIM = "\033[2m"
NC = "\033[0m"

# Configuration
HOME = Path.home()
REPO_DIR = HOME / "Documents" / "Github"
CACHE_DIR = HOME / ".cache"
CACHE_FILE = CACHE_DIR / "lazygit_repos"
RECENT_FILE = CACHE_DIR / "lazygit_recent"
CONFIG_DIR = HOME / ".config" / "gity"
VERSION_FILE = CONFIG_DIR / "VERSION"

VERSION = "1.0.0"

# Ensure directories exist
REPO_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_DIR.mkdir(parents=True, exist_ok=True)
RECENT_FILE.touch(exist_ok=True)

def clear_screen():
    os.system('clear' if os.name == 'posix' else 'cls')

def run_command(cmd, cwd=None, capture=True):
    """Utility to run shell commands and return output."""
    try:
        if capture:
            result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, shell=isinstance(cmd, str))
            return result.stdout.strip()
        else:
            subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str))
            return ""
    except Exception:
        return ""

def run_fzf(options, header="Select an option", multi=False, preview=None, height='60%', layout='reverse'):
    """Run fzf with given options and return selection."""
    cmd = ['fzf', '--header', header, '--height', height, '--border']
    if layout:
        cmd.append(f'--layout={layout}')
    if multi:
        cmd.append('--multi')
    if preview:
        cmd.extend(['--preview', preview, '--preview-window', 'right:60%:wrap'])
    
    process = subprocess.Popen(
        cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True
    )
    stdout, _ = process.communicate(input='\n'.join(options))
    return stdout.strip()

def box_draw(width, char='='):
    return char * width

def get_repo_status(repo_path):
    """Get a simple status string for a repo."""
    if not (Path(repo_path) / ".git").exists():
        return "?"

    status_indicators = ""
    has_changes = False
    ahead = 0
    behind = 0
    dirty_files = 0

    # Check for changes
    changes = run_command(["git", "status", "--porcelain"], cwd=repo_path)
    if changes:
        has_changes = True
        dirty_files = len(changes.splitlines())

    # Check ahead/behind
    revs = run_command("git rev-list --left-right --count '@{upstream}...HEAD'", cwd=repo_path)
    if revs:
        try:
            parts = revs.split()
            if len(parts) == 2:
                behind, ahead = int(parts[0]), int(parts[1])
        except ValueError:
            pass

    if has_changes:
        status_indicators += f"{YELLOW}✎{NC}"
    else:
        status_indicators += f"{GREEN}●{NC}"

    if ahead > 0 and behind > 0:
        status_indicators += f"{MAGENTA}↕{NC}"
    elif ahead > 0:
        status_indicators += f"{CYAN}↑{NC}"
    elif behind > 0:
        status_indicators += f"{RED}↓{NC}"

    return {
        "status": status_indicators,
        "has_changes": has_changes,
        "ahead": ahead,
        "behind": behind,
        "dirty_files": dirty_files
    }

def get_repo_status_simple(repo_path):
    return get_repo_status(repo_path)["status"]

def refresh_cache():
    """Scan filesystem for git repositories."""
    print(f"{BLUE}Scanning for repositories in {HOME}...{NC}")
    repos = []
    
    search_paths = [HOME / "Work", HOME / "Plugins", HOME / "Documents", HOME / "Desktop", HOME / "Luminor"]
    valid_paths = [p for p in search_paths if p.exists()]
    
    def scan_dir(start_dir, max_depth=4):
        start_dir = str(start_dir)
        start_depth = start_dir.count(os.sep)
        for root, dirs, files in os.walk(start_dir):
            current_depth = root.count(os.sep)
            if current_depth - start_depth > max_depth:
                dirs[:] = []
                continue
            
            if '.git' in dirs:
                repos.append(root)
                dirs.remove('.git')
                
            dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['node_modules', 'venv', 'target', 'build']]

    for p in valid_paths:
        scan_dir(p)
    
    scan_dir(HOME, max_depth=3)

    unique_repos = list(set(repos))
    unique_repos.sort()

    with open(CACHE_FILE, "w") as f:
        f.write("\n".join(unique_repos))
    
    print(f"{GREEN}Scan complete. Found {len(unique_repos)} repositories.{NC}")
    time.sleep(1)
    return unique_repos

def get_clipboard_tool():
    tools = ["xclip", "xsel", "wl-copy", "clip.exe", "clip"]
    for t in tools:
        if shutil.which(t):
            return t
    return None

def copy_path(path):
    tool = get_clipboard_tool()
    if not tool:
        return False
    
    try:
        if tool == "xclip":
            subprocess.run(["xclip", "-selection", "clipboard"], input=path, text=True)
        elif tool == "xsel":
            subprocess.run(["xsel", "--clipboard"], input=path, text=True)
        elif tool == "wl-copy":
            subprocess.run(["wl-copy"], input=path, text=True)
        else:
            subprocess.run([tool], input=path, text=True)
        return True
    except Exception:
        return False

def open_in_editor(repo_path):
    editor = os.environ.get('EDITOR')
    if editor:
        subprocess.run([editor, "."], cwd=repo_path)
    elif sys.platform == 'win32':
        os.startfile(repo_path)
    elif sys.platform == 'darwin':
        subprocess.run(["open", repo_path])
    else:
        if shutil.which("wslview"):
            subprocess.run(["wslview", repo_path])
        else:
            subprocess.run(["xdg-open", repo_path])

def repo_actions(repo_path):
    """Menu for actions on a specific repository."""
    try:
        with open(RECENT_FILE, "r") as f:
            recent = f.read().splitlines()
    except FileNotFoundError:
        recent = []
        
    if repo_path in recent:
        recent.remove(repo_path)
    recent.insert(0, repo_path)
    with open(RECENT_FILE, "w") as f:
        f.write("\n".join(recent[:10]))
        
    name = os.path.basename(repo_path)
    status = get_repo_status_simple(repo_path)
    has_clip = get_clipboard_tool() is not None
    
    actions = [
        "🚀 Open in Lazygit (TUI)",
        "📁 Browse Files (fzf)",
        "📝 Open in Default Editor",
        "📂 Open in File Manager"
    ]
    if has_clip:
        actions.append("📋 Copy Path to Clipboard")
    actions.append("🔙 Back to Gity")
    
    while True:
        clear_screen()
        print(f"====================================================")
        print(f"  {BOLD}{name}{NC}  {status}")
        print(f"  PATH: {repo_path}")
        print(f"====================================================\n")
        print(f"{YELLOW}  Tip: Use 'Browse Files' to see all repo files{NC}\n")
        
        choice = run_fzf(actions, header=f"Select Action >", height='20%', layout='reverse')
        
        if not choice or "🔙" in choice:
            break
        elif "🚀" in choice:
            subprocess.run(['lazygit', '-p', repo_path])
        elif "📁" in choice:
            git_ls = subprocess.Popen(["git", "ls-files"], cwd=repo_path, stdout=subprocess.PIPE, text=True)
            fzf_cmd = ['fzf', '--height', '100%', '--border', '--header', f"Files in {name}", '--preview', f'cat {repo_path}/{{}}', '--preview-window', 'right:60%:wrap']
            fzf_proc = subprocess.Popen(fzf_cmd, cwd=repo_path, stdin=git_ls.stdout, stdout=subprocess.PIPE, text=True)
            git_ls.stdout.close()
            fzf_proc.communicate()
        elif "📝" in choice:
            open_in_editor(repo_path)
        elif "📂" in choice:
            if sys.platform == 'darwin':
                subprocess.run(['open', repo_path])
            elif sys.platform == 'win32':
                os.startfile(repo_path)
            else:
                subprocess.run(['xdg-open', repo_path])
        elif "📋" in choice:
            if copy_path(repo_path):
                print("Path copied!")
                time.sleep(1)

def open_existing():
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    try:
        with open(RECENT_FILE, "r") as f:
            recent = f.read().splitlines()
    except FileNotFoundError:
        recent = []
        
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        all_repos = []
        
    combined = []
    seen = set()
    for r in recent + all_repos:
        if r and r not in seen:
            combined.append(r)
            seen.add(r)
            
    selected = run_fzf(combined, header="Select Repository (Recent at top)", height='60%', layout=None)
    if selected:
        repo_actions(selected)

def show_dashboard():
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    print(f"{BLUE}Scanning repos for status...{NC}")
    
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        return
        
    critical = []
    warning = []
    healthy = []
    
    for repo in all_repos:
        if not (Path(repo) / ".git").exists():
            continue
            
        s = get_repo_status(repo)
        name = os.path.basename(repo)
        
        line = f'{s["status"]} {BOLD}{name}{NC}'
        
        if s["has_changes"] or (s["ahead"] > 0 and s["behind"] > 0):
            details = []
            if s["has_changes"]: details.append(f"{s['dirty_files']} file(s) changed")
            if s["ahead"] > 0: details.append(f"{s['ahead']}↑")
            if s["behind"] > 0: details.append(f"{s['behind']}↓")
            line += f"  {DIM}{', '.join(details)}{NC}"
            critical.append(line)
        elif s["ahead"] > 0 or s["behind"] > 0:
            details = []
            if s["ahead"] > 0: details.append(f"{s['ahead']} ahead")
            if s["behind"] > 0: details.append(f"{s['behind']} behind")
            line += f"  {DIM}{', '.join(details)}{NC}"
            warning.append(line)
        else:
            line += f"  {DIM}All synced{NC}"
            healthy.append(line)
            
    clear_screen()
    print(f"\n{BLUE}╔════════════════════════════════════════╗{NC}")
    print(f"{BLUE}║{NC}        {BOLD}📊 DASHBOARD{NC}                    {BLUE}║{NC}")
    print(f"{BLUE}╚════════════════════════════════════════╝{NC}\n")
    print(f"  Total repos scanned: {len(all_repos)}\n")
    
    if critical:
        print(f"  {RED}🔴 NEED ATTENTION ({len(critical)} repos){NC}")
        for c in critical: print(f"    {c}")
        print("")
        
    if warning:
        print(f"  {YELLOW}🟡 NEED SYNC ({len(warning)} repos){NC}")
        for w in warning: print(f"    {w}")
        print("")
        
    if healthy:
        print(f"  {GREEN}🟢 ALL SYNCED ({len(healthy)} repos){NC}\n")
        
    print(f"{DIM}  Legend: {GREEN}●{NC} Clean  {YELLOW}✎{NC} Changes  {CYAN}↑{NC} Ahead  {RED}↓{NC} Behind  {MAGENTA}↕{NC} Diverged{NC}\n")
    print(f"{DIM}  Press Enter to return to menu...{NC}")
    input()

def show_activity_timeline(days=7):
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    print(f"{BLUE}Fetching activity for last {days} days...{NC}")
    
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        return
        
    commits_data = []
    
    for repo in all_repos:
        if not (Path(repo) / ".git").exists():
            continue
        name = os.path.basename(repo)
        
        logs = run_command(["git", "log", f"--since={days} days ago", "--format=%h|%s|%ai"], cwd=repo)
        if logs:
            for line in logs.splitlines():
                parts = line.split('|')
                if len(parts) >= 3:
                    hash_val, msg, date = parts[0], parts[1], parts[2]
                    day = date.split()[0]
                    commits_data.append((date, day, name, msg))
                    
    commits_data.sort(key=lambda x: x[0], reverse=True)
    
    clear_screen()
    width = 65
    print(f"{BLUE}╔{box_draw(width, '═')}╗{NC}")
    print(f"{BLUE}║{NC}" + " "*int((width - 24)/2 + 2) + f"{BOLD}📅 ACTIVITY TIMELINE{NC}" + " "*int((width - 24)/2 + 2) )
    print(f"{BLUE}║{NC}" + " "*int((width - 15)/2 + 2) + f"{DIM}(Last {days} days){NC}")
    print(f"{BLUE}╠{box_draw(width, '═')}╣{NC}")
    print(f"{BLUE}║{NC}  Total: {len(commits_data)} commits across all repos")
    print(f"{BLUE}╠{box_draw(width, '═')}╣{NC}")
    
    if not commits_data:
        print(f"{BLUE}║{NC}           {YELLOW}No recent activity{NC}")
    else:
        current_day = ""
        for date, day, repo, msg in commits_data:
            if day != current_day:
                current_day = day
                print(f"{BLUE}║{NC}{box_draw(width, ' ')}")
                print(f"{BLUE}║{NC}  {BOLD}{day}{NC}")
                print(f"{BLUE}║{NC}{box_draw(width, ' ')}")
            short_msg = msg[:45]
            print(f"{BLUE}║{NC}    {CYAN}{repo}{NC}  {short_msg}")
            
    print(f"{BLUE}╚{box_draw(width, '═')}╝{NC}")
    
    options = ["1 Day", "7 Days", "30 Days", "Exit"]
    selected = run_fzf(options, header="Timeline range > ", height='20%', layout=None)
    
    if selected == "1 Day": show_activity_timeline(1)
    elif selected == "7 Days": show_activity_timeline(7)
    elif selected == "30 Days": show_activity_timeline(30)

def search_repos():
    query = input("Enter search query: ").strip()
    if not query:
        return
        
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        return
        
    print(f"\n{BLUE}Searching {len(all_repos)} repos for: {query}{NC}\n")
    
    results_list = []
    
    for repo in all_repos:
        if not (Path(repo) / ".git").exists():
            continue
        
        name = os.path.basename(repo)
        res = run_command(["git", "grep", "-n", "--heading", "--line-number", "--column", query], cwd=repo)
        if res:
            for line in res.splitlines():
                if line:
                    results_list.append(f"{name}: {line}  ({repo})")
                    
    if not results_list:
        print(f"{YELLOW}No results found for: {query}{NC}")
        time.sleep(2)
        return
        
    selected = run_fzf(results_list, header=f"Search results for: {query}", height='80%', layout=None)
    if selected:
        repo_path = selected.split("  (")[-1].rstrip(")")
        repo_actions(repo_path)

def bulk_actions():
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        return
        
    print(f"{BLUE}Select repositories for bulk action (TAB to multi-select):{NC}\n")
    
    options = []
    for r in all_repos:
        if (Path(r) / ".git").exists():
            options.append(f"~/{Path(r).relative_to(HOME, walk_up=True)}")
            
    selected_str = run_fzf(options, header="Select repos (TAB for multi-select)", multi=True, height='70%', layout=None)
    if not selected_str:
        return
        
    selected_repos = []
    for line in selected_str.splitlines():
        rel_path = line.replace("~/", "")
        repo_path = HOME / rel_path
        if repo_path.exists():
            selected_repos.append(str(repo_path))
            
    if not selected_repos:
        return
        
    print(f"\n{BLUE}Choose bulk action:{NC}\n")
    action_opts = [
        "⬇️  Pull All",
        "⬆️  Push All",
        "📊 Status All",
        "💬 Commit All",
        "🔍 Custom Command (per repo)"
    ]
    
    action = run_fzf(action_opts, header="Action > ", height='25%', layout=None)
    if not action:
        return
        
    success = 0
    failed = 0
    
    if "Pull All" in action:
        print(f"{BLUE}Pulling all repos...{NC}")
        for r in selected_repos:
            print(f"{CYAN}Pulling: {os.path.basename(r)}{NC}")
            res = subprocess.run(["git", "pull"], cwd=r, capture_output=True, text=True)
            if res.returncode == 0: success += 1
            else: failed += 1
            print(res.stdout.strip())
            print(res.stderr.strip())
            
    elif "Push All" in action:
        print(f"{BLUE}Pushing all repos...{NC}")
        for r in selected_repos:
            print(f"{CYAN}Pushing: {os.path.basename(r)}{NC}")
            res = subprocess.run(["git", "push"], cwd=r, capture_output=True, text=True)
            if res.returncode == 0: success += 1
            else: failed += 1
            print(res.stdout.strip())
            print(res.stderr.strip())
            
    elif "Status All" in action:
        for r in selected_repos:
            print(f"{BOLD}=== {os.path.basename(r)} ==={NC}")
            subprocess.run(["git", "status", "--short"], cwd=r)
            print("")
        input("Press Enter to continue...")
        return
        
    elif "Commit All" in action:
        msg = input("Enter commit message: ").strip()
        if msg:
            for r in selected_repos:
                print(f"{CYAN}Committing: {os.path.basename(r)}{NC}")
                subprocess.run(["git", "add", "-A"], cwd=r)
                subprocess.run(["git", "commit", "-m", msg], cwd=r)
                
    elif "Custom Command" in action:
        cmd = input("Enter command (use {repo} for repo path): ").strip()
        if cmd:
            for r in selected_repos:
                print(f"{CYAN}Running in: {os.path.basename(r)}{NC}")
                actual_cmd = cmd.replace("{repo}", r)
                subprocess.run(actual_cmd, shell=True, cwd=r)
                
    print(f"\n{GREEN}Done! {success} succeeded, {failed} failed{NC}")
    time.sleep(2)

def github_repos():
    if not shutil.which("gh"):
        print(f"{YELLOW}GitHub CLI (gh) is not installed.{NC}")
        print(f"{BLUE}To install:{NC}")
        print(f"{GREEN}  Arch:       sudo pacman -S github-cli{NC}")
        print(f"{GREEN}  Ubuntu:     sudo apt install gh{NC}")
        print(f"{GREEN}  macOS:      brew install gh{NC}")
        print(f"{GREEN}  Windows:    winget install GitHub.cli{NC}")
        print(f"\n{BLUE}Or visit: https://cli.github.com{NC}")
        input("\nPress Enter to continue...")
        return
        
    status = subprocess.run(["gh", "auth", "status"], capture_output=True).returncode
    if status != 0:
        print(f"{YELLOW}Not authenticated with GitHub.{NC}")
        choice = run_fzf(["🔗 Connect to GitHub", "❌ Cancel"], header="Connect > ", height='15%', layout=None)
        if "Connect" in choice:
            subprocess.run(["gh", "auth", "login"])
            if subprocess.run(["gh", "auth", "status"], capture_output=True).returncode != 0:
                print(f"{RED}Authentication failed.{NC}")
                time.sleep(2)
                return
        else:
            return
            
    print(f"{BLUE}Fetching your GitHub information...{NC}")
    user = run_command(["gh", "api", "user", "--jq", ".login"])
    orgs_raw = run_command(["gh", "api", "user/orgs", "--jq", ".[].login"])
    orgs = orgs_raw.splitlines() if orgs_raw else []
    
    if not user:
        print(f"{RED}Failed to fetch user info.{NC}")
        time.sleep(2)
        return
        
    entity_options = [f"👤 Your Repositories ({user})"]
    for org in orgs:
        entity_options.append(f"🏢 {org}")
        
    selected_entity = run_fzf(entity_options, header="Select Organization or User", height='40%', layout=None)
    if not selected_entity:
        return
        
    if "👤" in selected_entity:
        entity_type = "user"
        entity_name = user
        print(f"{BLUE}Fetching your repositories...{NC}")
    else:
        entity_type = "org"
        entity_name = selected_entity.replace("🏢 ", "")
        print(f"{BLUE}Fetching {entity_name} repositories...{NC}")
        
    if entity_type == "user":
        repos_json = run_command(["gh", "repo", "list", entity_name, "--limit", "100", "--json", "name,owner,url"])
    else:
        repos_json = run_command(["gh", "api", f"orgs/{entity_name}/repos?per_page=100", "--jq", "[.[] | {name: .name, owner: {login: .owner.login}, url: .html_url}]"])
        
    import json
    try:
        repos_data = json.loads(repos_json)
    except Exception:
        print(f"{RED}Failed to parse GitHub repos.{NC}")
        time.sleep(2)
        return
        
    if not repos_data:
        print(f"{YELLOW}No repositories found.{NC}")
        time.sleep(2)
        return
        
    repo_options = [f"{r['owner']['login']}/{r['name']}" for r in repos_data]
    selected_repo = run_fzf(repo_options, header=f"Repositories in {entity_name}", height='70%', layout=None)
    
    if not selected_repo:
        return
        
    # Find the corresponding URL
    full_name = selected_repo
    url = next((r['url'] for r in repos_data if f"{r['owner']['login']}/{r['name']}" == full_name), None)
    
    if not url:
        print(f"{RED}Error: URL not found for selected repository.{NC}")
        time.sleep(2)
        return
        
    print(f"\n{BLUE}Selected: {full_name}{NC}")
    print(f"{BLUE}URL: {url}{NC}\n")
    
    action = run_fzf(["📥 Clone Repository", "🌐 Open in Browser", "📂 View on GitHub"], header="Action > ", height='20%', layout=None)
    
    if "Clone" in action:
        dest_name = full_name.replace("/", "-")
        dest = REPO_DIR / dest_name
        if dest.exists():
            print(f"{YELLOW}Repository already exists at: {dest}{NC}")
            repo_actions(str(dest))
        else:
            clone_mode = run_fzf(["Fetch Default Branch Only", "Fetch All Branches"], header="Clone mode > ", height='15%', layout=None)
            print(f"{BLUE}Cloning to: {dest}{NC}")
            if clone_mode == "Fetch All Branches":
                subprocess.run(["git", "clone", "--no-single-branch", url, str(dest)])
            else:
                subprocess.run(["git", "clone", url, str(dest)])
            repo_actions(str(dest))
    elif "Browser" in action or "View" in action:
        if sys.platform == 'darwin': subprocess.run(['open', url])
        elif sys.platform == 'win32': os.startfile(url)
        else: subprocess.run(['xdg-open', url])

def clone_repo():
    url = input("Enter Repository URL (HTTPS or SSH): ").strip()
    if url:
        name = url.split("/")[-1].replace(".git", "")
        dest = REPO_DIR / name
        if not dest.exists():
            print(f"{BLUE}Cloning into {dest}...{NC}")
            res = subprocess.run(["git", "clone", url, str(dest)])
            if res.returncode == 0:
                repo_actions(str(dest))
        else:
            print(f"{YELLOW}Error: Directory already exists at {dest}{NC}")
            time.sleep(2)

def create_new_repo():
    name = input("Enter new repository name: ").strip()
    if name:
        dest = REPO_DIR / name
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init"], cwd=dest)
        (dest / "README.md").touch()
        subprocess.run(["git", "add", "."], cwd=dest)
        subprocess.run(["git", "commit", "-m", "Initial commit"], cwd=dest)
        repo_actions(str(dest))

def merge_branch():
    if not CACHE_FILE.exists() or os.path.getsize(CACHE_FILE) == 0:
        refresh_cache()
        
    try:
        with open(CACHE_FILE, "r") as f:
            all_repos = f.read().splitlines()
    except FileNotFoundError:
        return
        
    options = [f"{os.path.basename(r)}  ({r})" for r in all_repos if (Path(r) / ".git").exists()]
            
    selected_repo_str = run_fzf(options, header="Select repository to merge branches", height='60%', layout=None)
    if not selected_repo_str:
        return
        
    repo_path = selected_repo_str.split("  (")[-1].rstrip(")")
    
    branches = run_command(["git", "branch", "--format=%(refname:short)"], cwd=repo_path).splitlines()
    if len(branches) <= 1:
        print(f"{YELLOW}Only one branch exists. Nothing to merge.{NC}")
        time.sleep(2)
        return
        
    target = run_fzf(branches, header="STEP 1: Select branch to merge INTO", height='60%', layout=None)
    if not target: return
    
    source = run_fzf([b for b in branches if b != target], header="STEP 2: Select branch to merge (source)", height='60%', layout=None)
    if not source: return
    
    print(f"\n{BLUE}Merging {source} into {target}...{NC}")
    subprocess.run(["git", "checkout", target], cwd=repo_path)
    res = subprocess.run(["git", "merge", source, "--no-edit"], cwd=repo_path)
    if res.returncode == 0:
        print(f"\n{GREEN}✅ Merge successful!{NC}")
    else:
        print(f"\n{RED}❌ Merge failed - conflicts detected!{NC}")
    input("\nPress Enter to continue...")

def main_menu():
    """Main application loop."""
    while True:
        clear_screen()
        print(f"{BLUE}╔═══════════════════════════════════════════════════╗{NC}")
        print(f"{BLUE}║{NC}           {BOLD}{WHITE}GITY{NC} {DIM}-{NC} {BOLD}Python TUI Hub{NC} {DIM}v{VERSION}{NC}             {BLUE}║{NC}")
        print(f"{BLUE}╚═══════════════════════════════════════════════════╝{NC}\n")
        print(f"  {BOLD}Status Indicators:{NC}  {GREEN}●{NC} Clean  {YELLOW}✎{NC} Changes  {CYAN}↑{NC} Ahead  {RED}↓{NC} Behind  {MAGENTA}↕{NC} Diverged\n")
        
        options = [
            "📊 Dashboard (Repos Needing Work)",
            "📂 Browse All Repositories",
            "📅 Activity Timeline",
            "⚡ Bulk Actions",
            "🔍 Search Across Repos",
            "🐙 GitHub Repos",
            "🔀 Merge Branch",
            "🔗 Clone Repository",
            "✨ Create New Repository",
            "🔄 Refresh Cache",
            "↻ Update Gity",
            "❌ Exit"
        ]
        
        choice = run_fzf(options, header="Main Menu", height='50%', layout='reverse')
        
        if not choice or "❌" in choice:
            sys.exit(0)
        elif "📊" in choice: show_dashboard()
        elif "📂" in choice: open_existing()
        elif "📅" in choice: show_activity_timeline()
        elif "⚡" in choice: bulk_actions()
        elif "🔍" in choice: search_repos()
        elif "🐙" in choice: github_repos()
        elif "🔀" in choice: merge_branch()
        elif "🔗" in choice: clone_repo()
        elif "✨" in choice: create_new_repo()
        elif "🔄" in choice: refresh_cache()
        elif "↻" in choice:
            print(f"{BLUE}Update Gity is handled by your system package manager or install script.{NC}")
            time.sleep(2)

if __name__ == "__main__":
    if not shutil.which("fzf") or not shutil.which("git"):
        print(f"{RED}Error: 'git' and 'fzf' are required to run Gity.{NC}")
        sys.exit(1)
    main_menu()
