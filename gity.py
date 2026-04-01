import os
import subprocess
import shutil
import sys
import time
import json
import threading
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

VERSION = "1.1.0"

# Global state for background PR fetching
pr_counts = {}
pr_fetching_active = False

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
            res = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str))
            return res.returncode
    except Exception:
        return "" if capture else 1

def run_fzf(options, header="Select an option", multi=False, preview=None, height='60%'):
    """Run fzf with given options and return selection."""
    cmd = ['fzf', '--ansi', '--layout=reverse', '--header', header, '--height', height, '--border']
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

# ============================================================
# GITHUB PR LOGIC
# ============================================================

def get_repo_pr_count(repo_path):
    """Fetch open PR count for a repository using gh CLI."""
    if not shutil.which("gh"):
        return 0
    try:
        remote = run_command(["git", "remote", "get-url", "origin"], cwd=repo_path)
        if not remote or "github.com" not in remote:
            return 0
            
        prs_json = run_command(["gh", "pr", "list", "--limit", "50", "--json", "number"], cwd=repo_path)
        if prs_json:
            prs = json.loads(prs_json)
            return len(prs)
    except Exception:
        pass
    return 0

def fetch_pr_counts_background():
    """Background task to fetch PR counts for all repos."""
    global pr_counts, pr_fetching_active
    if pr_fetching_active:
        return
    
    pr_fetching_active = True
    try:
        if not CACHE_FILE.exists():
            return
        with open(CACHE_FILE, "r") as f:
            repos = f.read().splitlines()
        
        for repo in repos:
            if os.path.isdir(os.path.join(repo, ".git")):
                count = get_repo_pr_count(repo)
                if count > 0:
                    pr_counts[repo] = count
    finally:
        pr_fetching_active = False

def start_pr_fetch():
    thread = threading.Thread(target=fetch_pr_counts_background, daemon=True)
    thread.start()

def get_pr_diff_colored(repo_path, pr_number):
    """Get PR diff and apply basic terminal colors."""
    diff = run_command(["gh", "pr", "diff", str(pr_number)], cwd=repo_path)
    colored_diff = ""
    for line in diff.splitlines():
        if line.startswith('+'):
            colored_diff += f"{GREEN}{line}{NC}\n"
        elif line.startswith('-'):
            colored_diff += f"{RED}{line}{NC}\n"
        elif line.startswith('@@'):
            colored_diff += f"{CYAN}{line}{NC}\n"
        elif line.startswith('diff --git'):
            colored_diff += f"{BOLD}{WHITE}{line}{NC}\n"
        else:
            colored_diff += f"{line}\n"
    return colored_diff

def pr_detail_view(repo_path, pr_info):
    """View PR diff and perform actions."""
    pr_number = pr_info['number']
    title = pr_info['title']
    author = pr_info['author']['login']
    
    while True:
        clear_screen()
        print(f"{BLUE}╔{box_draw(60, '═')}╗{NC}")
        print(f"{BLUE}║{NC} {BOLD}PR #{pr_number}:{NC} {title[:45]}")
        print(f"{BLUE}║{NC} {DIM}Author: {author}{NC}")
        print(f"{BLUE}╚{box_draw(60, '═')}╝{NC}\n")
        
        action_opts = [
            "🔍 View Diff (Colored)",
            "✅ Accept & Merge",
            "💬 Send Message (Comment)",
            "❌ Close Pull Request",
            "🔙 Back"
        ]
        
        choice = run_fzf(action_opts, header="Choose Action", height='20%')
        
        if not choice or "Back" in choice:
            break
        elif "View Diff" in choice:
            clear_screen()
            print(f"{BOLD}--- DIFF FOR PR #{pr_number} ---{NC}\n")
            print(get_pr_diff_colored(repo_path, pr_number))
            print(f"\n{DIM}Press Enter to return...{NC}")
            input()
        elif "Accept & Merge" in choice:
            print(f"{BLUE}Merging PR #{pr_number}...{NC}")
            res = subprocess.run(["gh", "pr", "merge", str(pr_number), "--merge"], cwd=repo_path)
            if res.returncode == 0:
                print(f"{GREEN}✓ PR merged successfully!{NC}")
                time.sleep(2)
                break
        elif "Send Message" in choice:
            msg = input("Enter comment: ").strip()
            if msg:
                subprocess.run(["gh", "pr", "comment", str(pr_number), "--body", msg], cwd=repo_path)
                print(f"{GREEN}✓ Comment added.{NC}")
                time.sleep(1)
        elif "Close" in choice:
            confirm = input(f"Are you sure you want to close PR #{pr_number}? (y/N): ")
            if confirm.lower() == 'y':
                subprocess.run(["gh", "pr", "close", str(pr_number)], cwd=repo_path)
                print(f"{RED}PR closed.{NC}")
                time.sleep(2)
                break

def pull_requests_menu():
    """Main PR menu showing repos with open PRs."""
    if not shutil.which("gh"):
        print(f"{RED}gh CLI is required for Pull Requests.{NC}")
        time.sleep(2)
        return

    if not CACHE_FILE.exists():
        refresh_cache()
        
    with open(CACHE_FILE, "r") as f:
        repos = f.read().splitlines()
    
    print(f"{BLUE}Scanning repositories for open Pull Requests...{NC}")
    repo_with_prs = []
    for repo in repos:
        if os.path.isdir(os.path.join(repo, ".git")):
            prs_json = run_command(["gh", "pr", "list", "--json", "number,title,author"], cwd=repo)
            if prs_json:
                prs = json.loads(prs_json)
                if prs:
                    repo_with_prs.append((repo, prs))
    
    if not repo_with_prs:
        clear_screen()
        print(f"\n{YELLOW}No open Pull Requests found in your cached repositories.{NC}")
        time.sleep(2)
        return

    repo_opts = [f"{len(prs)} PRs | {os.path.basename(path)}  ({path})" for path, prs in repo_with_prs]
    selected_repo_str = run_fzf(repo_opts, header="Select Repository with PRs", height='60%')
    
    if not selected_repo_str:
        return
        
    repo_path = selected_repo_str.split("  (")[-1].rstrip(")")
    prs = next(p for path, p in repo_with_prs if path == repo_path)
    
    pr_opts = [f"#{p['number']} | {p['title']} ({p['author']['login']})" for p in prs]
    selected_pr_str = run_fzf(pr_opts, header=f"PRs in {os.path.basename(repo_path)}", height='60%')
    
    if selected_pr_str:
        pr_number = int(selected_pr_str.split(" | ")[0].lstrip("#"))
        pr_info = next(p for p in prs if p['number'] == pr_number)
        pr_detail_view(repo_path, pr_info)

# ============================================================
# REPO SCANNING & STATUS
# ============================================================

def get_repo_status(repo_path):
    if not (Path(repo_path) / ".git").exists():
        return {"status": "?", "has_changes": False, "ahead": 0, "behind": 0, "dirty_files": 0}

    status_indicators = ""
    has_changes = False
    ahead = 0
    behind = 0
    dirty_files = 0

    changes = run_command(["git", "status", "--porcelain"], cwd=repo_path)
    if changes:
        has_changes = True
        dirty_files = len(changes.splitlines())

    revs = run_command("git rev-list --left-right --count '@{upstream}...HEAD'", cwd=repo_path)
    if revs:
        try:
            parts = revs.split()
            if len(parts) == 2:
                behind, ahead = int(parts[0]), int(parts[1])
        except ValueError:
            pass

    if has_changes: status_indicators += f"{YELLOW}✎{NC}"
    else: status_indicators += f"{GREEN}●{NC}"

    if ahead > 0 and behind > 0: status_indicators += f"{MAGENTA}↕{NC}"
    elif ahead > 0: status_indicators += f"{CYAN}↑{NC}"
    elif behind > 0: status_indicators += f"{RED}↓{NC}"

    return {"status": status_indicators, "has_changes": has_changes, "ahead": ahead, "behind": behind, "dirty_files": dirty_files}

def get_repo_status_simple(repo_path):
    return get_repo_status(repo_path)["status"]

def refresh_cache():
    print(f"{BLUE}Scanning for repositories in {HOME}...{NC}")
    repos = []
    search_paths = [HOME / "Work", HOME / "Plugins", HOME / "Documents", HOME / "Desktop"]
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

    for p in valid_paths: scan_dir(p)
    scan_dir(HOME, max_depth=3)
    unique_repos = sorted(list(set(repos)))
    with open(CACHE_FILE, "w") as f: f.write("\n".join(unique_repos))
    print(f"{GREEN}Scan complete. Found {len(unique_repos)} repositories.{NC}")
    time.sleep(1)
    return unique_repos

# ============================================================
# ACTIONS
# ============================================================

def open_in_editor(repo_path):
    editor = os.environ.get('EDITOR', 'vi')
    if sys.platform == 'win32': os.startfile(repo_path)
    elif sys.platform == 'darwin': subprocess.run(["open", repo_path])
    else: subprocess.run(["xdg-open", repo_path])

def repo_actions(repo_path):
    name = os.path.basename(repo_path)
    actions = ["🚀 Open in Lazygit (TUI)", "📁 Browse Files (fzf)", "📝 Open in Default Editor", "📂 Open in File Manager", "🔙 Back to Gity"]
    while True:
        clear_screen()
        status = get_repo_status_simple(repo_path)
        print(f"====================================================\n  {BOLD}{name}{NC}  {status}\n  PATH: {repo_path}\n====================================================\n")
        choice = run_fzf(actions, header=f"Select Action", height='20%')
        if not choice or "Back" in choice: break
        elif "Lazygit" in choice: subprocess.run(['lazygit', '-p', repo_path])
        elif "Browse" in choice:
            git_ls = subprocess.Popen(["git", "ls-files"], cwd=repo_path, stdout=subprocess.PIPE, text=True)
            subprocess.run(['fzf', '--layout=reverse', '--height', '100%', '--border', '--preview', f'cat {repo_path}/{{}}'], stdin=git_ls.stdout)
        elif "Editor" in choice: open_in_editor(repo_path)
        elif "Manager" in choice:
            if sys.platform == 'darwin': subprocess.run(['open', repo_path])
            elif sys.platform == 'win32': os.startfile(repo_path)
            else: subprocess.run(['xdg-open', repo_path])

def open_existing():
    if not CACHE_FILE.exists(): refresh_cache()
    
    print(f"{BLUE}Searching repositories...{NC}")
    try:
        with open(RECENT_FILE, "r") as f: recent = f.read().splitlines()
    except FileNotFoundError: recent = []
    
    with open(CACHE_FILE, "r") as f: repos = f.read().splitlines()
    
    combined = []
    seen = set()
    for r in recent + repos:
        if r and r not in seen:
            combined.append(r)
            seen.add(r)
            
    options = []
    for r in combined:
        status = get_repo_status_simple(r)
        options.append(f"{status} {os.path.basename(r)}  ({r})")
        
    selected = run_fzf(options, header="Select Repository (Recent at top)", height='60%')
    if selected:
        repo_path = selected.split("  (")[-1].rstrip(")")
        repo_actions(repo_path)

def show_dashboard():
    if not CACHE_FILE.exists(): refresh_cache()
    print(f"{BLUE}Scanning repos for status...{NC}")
    with open(CACHE_FILE, "r") as f: repos = f.read().splitlines()
    critical, warning, healthy = [], [], []
    for repo in repos:
        if not os.path.exists(os.path.join(repo, ".git")): continue
        s = get_repo_status(repo)
        line = f'{s["status"]} {BOLD}{os.path.basename(repo)}{NC}'
        if s["has_changes"]: critical.append(line + f"  {DIM}{s['dirty_files']} files{NC}")
        elif s["ahead"] or s["behind"]: warning.append(line + f"  {DIM}{s['ahead']}↑ {s['behind']}↓{NC}")
        else: healthy.append(line)
    clear_screen()
    print(f"\n{BLUE}📊 DASHBOARD{NC}\n  Critical: {len(critical)} | Warning: {len(warning)} | Synced: {len(healthy)}\n")
    if critical:
        print(f"  {RED}🔴 NEED ATTENTION{NC}")
        for l in critical: print(f"    {l}")
    print(f"\n{DIM}Press Enter to return...{NC}")
    input()

def show_activity_timeline(days=7):
    if not CACHE_FILE.exists(): refresh_cache()
    with open(CACHE_FILE, "r") as f: repos = f.read().splitlines()
    commits = []
    for repo in repos:
        logs = run_command(["git", "log", f"--since={days} days ago", "--format=%ai|%s|%an"], cwd=repo)
        if logs:
            for line in logs.splitlines():
                parts = line.split('|')
                if len(parts) >= 3: commits.append((parts[0], os.path.basename(repo), parts[1]))
    commits.sort(reverse=True)
    clear_screen()
    print(f"{BLUE}📅 ACTIVITY TIMELINE (Last {days} days){NC}\n")
    for date, repo, msg in commits[:20]:
        print(f"  {CYAN}{repo}{NC} {DIM}{date[:10]}{NC} {msg[:50]}")
    print(f"\n{DIM}Press Enter to return...{NC}")
    input()

def search_repos():
    query = input("Enter search query: ").strip()
    if not query: return
    if not CACHE_FILE.exists(): refresh_cache()
    with open(CACHE_FILE, "r") as f: repos = f.read().splitlines()
    results = []
    for repo in repos:
        res = run_command(["git", "grep", "-n", query], cwd=repo)
        if res:
            for line in res.splitlines(): results.append(f"{os.path.basename(repo)}: {line} ({repo})")
    selected = run_fzf(results, header=f"Search: {query}", height='80%')
    if selected: repo_actions(selected.split(" (")[-1].rstrip(")"))

def bulk_actions():
    if not CACHE_FILE.exists(): refresh_cache()
    with open(CACHE_FILE, "r") as f: repos = f.read().splitlines()
    selected_str = run_fzf(repos, header="Select repos (TAB)", multi=True, height='70%')
    if not selected_str: return
    selected_repos = selected_str.splitlines()
    action = run_fzf(["⬇️ Pull All", "⬆️ Push All", "📊 Status All"], header="Action", height='25%')
    if not action: return
    for r in selected_repos:
        print(f"{CYAN}Processing: {os.path.basename(r)}{NC}")
        if "Pull" in action: subprocess.run(["git", "pull"], cwd=r)
        elif "Push" in action: subprocess.run(["git", "push"], cwd=r)
        elif "Status" in action: subprocess.run(["git", "status", "-s"], cwd=r)
    input("\nDone. Press Enter...")

def github_repos():
    if not shutil.which("gh"): print("gh CLI missing"); return
    
    print(f"{BLUE}Searching organizations or your repos...{NC}")
    user = run_command(["gh", "api", "user", "--jq", ".login"])
    orgs = run_command(["gh", "api", "user/orgs", "--jq", ".[].login"]).splitlines()
    options = [f"👤 {user}"] + [f"🏢 {o}" for o in orgs]
    ent = run_fzf(options, header="Select User/Org", height='40%')
    if not ent: return
    
    name = ent.split(" ")[1]
    print(f"{BLUE}Fetching repositories for {name}...{NC}")
    repos_json = run_command(["gh", "repo", "list", name, "--limit", "50", "--json", "name,owner,url"])
    repos_data = json.loads(repos_json)
    selected = run_fzf([f"{r['owner']['login']}/{r['name']}" for r in repos_data], header=f"Repos in {name}")
    if selected:
        url = next(r['url'] for r in repos_data if f"{r['owner']['login']}/{r['name']}" == selected)
        action = run_fzf(["📥 Clone", "🌐 Browser"], header="Action")
        if "Clone" in action: subprocess.run(["git", "clone", url, str(REPO_DIR / selected.split("/")[-1])])

def clone_repo():
    url = input("URL: ").strip()
    if url: subprocess.run(["git", "clone", url], cwd=REPO_DIR)

def create_new_repo():
    name = input("Name: ").strip()
    if name:
        dest = REPO_DIR / name
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init"], cwd=dest)

def main_menu():
    start_pr_fetch()
    while True:
        clear_screen()
        total_prs = sum(pr_counts.values())
        pr_notifier = f" {RED}● {total_prs} PRs{NC}" if total_prs > 0 else ""
        
        print(f"""{BLUE}
 ██████╗ ██╗████████╗██╗   ██╗
██╔════╝ ██║╚══██╔══╝╚██╗ ██╔╝
██║  ███╗██║   ██║    ╚████╔╝ 
██║   ██║██║   ██║     ╚██╔╝  
╚██████╔╝██║   ██║      ██║   
 ╚═════╝ ╚═╝   ╚═╝      ╚═╝   
{NC}
        {DIM}— Universal Git Hub v{VERSION} —{NC}
        """)
        
        print(f"  {BOLD}Indicators:{NC} {GREEN}●{NC} Clean {YELLOW}✎{NC} Changes {CYAN}↑{NC} Ahead {RED}↓{NC} Behind\n")
        options = ["📊 Dashboard", f"📥 Pull Requests{pr_notifier}", "📂 Browse Repos", "📅 Activity", "⚡ Bulk Actions", "🔍 Search", "🐙 GitHub Repos", "🔗 Clone", "✨ New Repo", "🔄 Refresh Cache", "❌ Exit"]
        choice = run_fzf(options, header="MAIN MENU", height='50%')
        if not choice or "❌" in choice: sys.exit(0)
        elif "Dashboard" in choice: show_dashboard()
        elif "Pull Requests" in choice: pull_requests_menu(); start_pr_fetch()
        elif "Browse Repos" in choice: open_existing()
        elif "Activity" in choice: show_activity_timeline()
        elif "Bulk" in choice: bulk_actions()
        elif "Search" in choice: search_repos()
        elif "GitHub" in choice: github_repos()
        elif "Clone" in choice: clone_repo()
        elif "New Repo" in choice: create_new_repo()
        elif "Refresh" in choice: refresh_cache()

if __name__ == "__main__":
    if not shutil.which("fzf") or not shutil.which("git"):
        print("Error: git and fzf required")
        sys.exit(1)
    main_menu()
