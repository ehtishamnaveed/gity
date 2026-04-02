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

VERSION = "1.2.0"

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

def run_fzf(options, header="Select an option", multi=False, preview=None, height='60%', reverse=False):
    """Run fzf with given options and return selection."""
    cmd = ['fzf', '--ansi', '--header', header, '--height', height, '--border']
    if reverse:
        cmd.append('--layout=reverse')
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
            res = run_command(["gh", "pr", "merge", str(pr_number), "--merge"], cwd=repo_path, capture=False)
            if res == 0:
                print(f"{GREEN}✓ PR merged successfully!{NC}")
            else:
                print(f"{RED}✗ Failed to merge PR{NC}")
            time.sleep(2)
            break
        elif "Send Message" in choice:
            msg = input("Enter comment: ").strip()
            if msg:
                res = run_command(["gh", "pr", "comment", str(pr_number), "--body", msg], cwd=repo_path, capture=False)
                if res == 0:
                    print(f"{GREEN}✓ Comment added.{NC}")
                else:
                    print(f"{RED}✗ Failed to add comment{NC}")
                time.sleep(1)
        elif "Close" in choice:
            confirm = input(f"Are you sure you want to close PR #{pr_number}? (y/N): ")
            if confirm.lower() == 'y':
                res = run_command(["gh", "pr", "close", str(pr_number)], cwd=repo_path, capture=False)
                if res == 0:
                    print(f"{GREEN}✓ PR closed.{NC}")
                else:
                    print(f"{RED}✗ Failed to close PR{NC}")
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
    actions = ["🚀 Open in Lazygit (TUI)", "📁 Browse Files (fzf)", "📝 Open in Default Editor", "📂 Open in File Manager", "🔀 Sync with GitHub (Pull/Push)", "📥 Create Pull Request", "🌿 Branch Manager", "🗑️ Delete Repository", "🔙 Back to Gity"]
    while True:
        clear_screen()
        status = get_repo_status_simple(repo_path)
        print(f"====================================================\n  {BOLD}{name}{NC}  {status}\n  PATH: {repo_path}\n====================================================\n")
        choice = run_fzf(actions, header=f"Select Action", height='20%')
        if not choice or "Back" in choice: break
        elif "Lazygit" in choice: subprocess.run(['lazygit', '-p', repo_path])
        elif "Browse" in choice:
            git_ls = subprocess.Popen(["git", "ls-files"], cwd=repo_path, stdout=subprocess.PIPE, text=True)
            subprocess.run(['fzf', '--height', '100%', '--border', '--preview', f'cat {repo_path}/{{}}'], stdin=git_ls.stdout)
        elif "Editor" in choice: open_in_editor(repo_path)
        elif "Branch" in choice:
            branch_menu(repo_path)
        elif "Manager" in choice:
            if sys.platform == 'darwin': subprocess.run(['open', repo_path])
            elif sys.platform == 'win32': os.startfile(repo_path)
            else: subprocess.run(['xdg-open', repo_path])
        elif "Sync" in choice:
            sync_menu(repo_path)
        elif "Create" in choice:
            create_pr_menu(repo_path)
        elif "Branch" in choice:
            branch_menu(repo_path)
        elif "Delete" in choice:
            confirm = input(f"Delete '{name}'? This will remove ALL local files. Type 'yes' to confirm: ")
            if confirm.lower() == 'yes':
                shutil.rmtree(repo_path)
                with open(CACHE_FILE, "r") as f:
                    repos = f.read().splitlines()
                repos = [r for r in repos if r != repo_path]
                with open(CACHE_FILE, "w") as f:
                    f.write("\n".join(repos))
                print(f"{GREEN}✓ Repository deleted.{NC}")
                time.sleep(1)
                break
            else:
                print(f"{YELLOW}Cancelled.{NC}")
                time.sleep(1)

def sync_menu(repo_path):
    """Sync with GitHub - pull and push."""
    name = os.path.basename(repo_path)
    remote = run_command(["git", "remote", "get-url", "origin"], cwd=repo_path)
    
    if not remote or "github.com" not in remote:
        print(f"{RED}No GitHub remote found.{NC}")
        time.sleep(2)
        return
    
    while True:
        clear_screen()
        print(f"====================================================\n  {BOLD}Sync: {name}{NC}\n  Remote: {remote[:50]}...\n====================================================\n")
        
        action_opts = ["⬇️ Pull from Remote", "⬆️ Push to Remote", "⬇️⬆️ Pull & Push", "🔙 Back"]
        choice = run_fzf(action_opts, header="Sync Options", height='30%')
        
        if not choice or "Back" in choice:
            break
        elif "Pull" in choice and "Push" not in choice:
            print(f"{BLUE}Pulling from remote...{NC}")
            res = run_command(["git", "pull"], cwd=repo_path, capture=False)
            if res == 0:
                print(f"{GREEN}✓ Pull successful.{NC}")
            else:
                print(f"{RED}✗ Pull failed.{NC}")
            time.sleep(2)
        elif "Push" in choice and "Pull" not in choice:
            print(f"{BLUE}Pushing to remote...{NC}")
            res = run_command(["git", "push"], cwd=repo_path, capture=False)
            if res == 0:
                print(f"{GREEN}✓ Push successful.{NC}")
            else:
                print(f"{RED}✗ Push failed.{NC}")
            time.sleep(2)
        elif "Pull & Push" in choice:
            print(f"{BLUE}Pulling and pushing...{NC}")
            res1 = run_command(["git", "pull"], cwd=repo_path, capture=False)
            res2 = run_command(["git", "push"], cwd=repo_path, capture=False)
            if res1 == 0 and res2 == 0:
                print(f"{GREEN}✓ Sync successful.{NC}")
            else:
                print(f"{RED}✗ Sync failed.{NC}")
            time.sleep(2)

def create_pr_menu(repo_path):
    """Create a pull request from current branch."""
    name = os.path.basename(repo_path)
    remote = run_command(["git", "remote", "get-url", "origin"], cwd=repo_path)
    
    if not remote or "github.com" not in remote:
        print(f"{RED}No GitHub remote found.{NC}")
        time.sleep(2)
        return
    
    branches = run_command(["git", "branch", "-a"], cwd=repo_path)
    if not branches:
        print(f"{RED}No branches found.{NC}")
        time.sleep(2)
        return
    
    branch_list = [b.strip() for b in branches.splitlines() if b.strip() and not b.startswith("remotes/")]
    current_branch = run_command(["git", "branch", "--show-current"], cwd=repo_path)
    
    selected = run_fzf(branch_list, header="Select branch to create PR from", height='60%')
    if not selected:
        return
    
    target = run_fzf(["main", "master"], header="Select target branch", height='20%')
    if not target:
        target = "main"
    
    print(f"\n{BLUE}Creating PR from '{selected}' to '{target}'...{NC}")
    
    title = input("PR Title: ").strip()
    if not title:
        print(f"{YELLOW}Title required.{NC}")
        time.sleep(1)
        return
    
    body = input("PR Description (optional): ").strip()
    
    cmd = ["gh", "pr", "create", "--base", target, "--head", selected, "--title", title]
    if body:
        cmd.extend(["--body", body])
    
    res = run_command(cmd, cwd=repo_path, capture=False)
    if res == 0:
        print(f"{GREEN}✓ Pull Request created!{NC}")
    else:
        print(f"{RED}✗ Failed to create PR.{NC}")
    time.sleep(2)

def branch_menu(repo_path):
    """Manage branches - delete, sync with remote."""
    name = os.path.basename(repo_path)
    remote = run_command(["git", "remote", "get-url", "origin"], cwd=repo_path)
    
    if not remote or "github.com" not in remote:
        print(f"{RED}No GitHub remote found.{NC}")
        time.sleep(2)
        return
    
    while True:
        clear_screen()
        print(f"====================================================\n  {BOLD}Branch Manager: {name}{NC}\n====================================================\n")
        
        action_opts = ["📋 List Branches", "🗑️ Delete Local Branch", "🗑️ Delete Remote Branch", "🔄 Delete Merged Branches", "🔙 Back"]
        choice = run_fzf(action_opts, header="Branch Actions", height='30%')
        
        if not choice or "Back" in choice:
            break
        elif "List" in choice:
            clear_screen()
            local = run_command(["git", "branch"], cwd=repo_path)
            remote_branches = run_command(["git", "branch", "-r"], cwd=repo_path)
            print(f"{BOLD}Local Branches:{NC}\n{local}\n")
            print(f"{BOLD}Remote Branches:{NC}\n{remote_branches}")
            print(f"\n{DIM}Press Enter to return...{NC}")
            input()
        elif "Delete Local" in choice:
            branches = run_command(["git", "branch"], cwd=repo_path)
            branch_list = [b.strip() for b in branches.splitlines() if b.strip()]
            selected = run_fzf(branch_list, header="Select branches to delete (TAB)", height='60%', multi=True)
            if not selected:
                continue
            to_delete = selected.splitlines()
            for branch in to_delete:
                if branch in ["main", "master"]:
                    print(f"{YELLOW}Skipping {branch} (main/master){NC}")
                    continue
                res = run_command(["git", "branch", "-d", branch], cwd=repo_path, capture=False)
                if res == 0:
                    print(f"{GREEN}✓ Deleted: {branch}{NC}")
                else:
                    print(f"{RED}✗ Failed to delete: {branch}{NC}")
            time.sleep(2)
        elif "Delete Remote" in choice:
            r_branches = run_command(["git", "branch", "-r"], cwd=repo_path)
            if not r_branches:
                print(f"{YELLOW}No remote branches found.{NC}")
                time.sleep(2)
                continue
            
            remote_list = [b.replace("origin/", "").strip() for b in r_branches.splitlines() if b.strip() and "origin/" in b]
            selected = run_fzf(remote_list, header="Select remote branches to delete (TAB)", height='60%', multi=True)
            if not selected:
                continue
            
            to_delete = selected.splitlines()
            for branch in to_delete:
                if branch in ["main", "master"]:
                    print(f"{YELLOW}Skipping {branch} (main/master){NC}")
                    continue
                res = run_command(["git", "push", "origin", "--delete", branch], cwd=repo_path, capture=False)
                if res == 0:
                    print(f"{GREEN}✓ Deleted remote: {branch}{NC}")
                else:
                    print(f"{RED}✗ Failed to delete: {branch}{NC}")
            time.sleep(2)
        elif "Delete Merged" in choice:
            print(f"{BLUE}Finding merged branches...{NC}")
            merged = run_command(["git", "branch", "--merged"], cwd=repo_path)
            if not merged:
                print(f"{YELLOW}No merged branches found.{NC}")
                time.sleep(2)
                continue
            
            branch_list = [b.strip() for b in merged.splitlines() if b.strip() and b.strip() not in ["main", "master"]]
            if not branch_list:
                print(f"{YELLOW}No mergeable branches found.{NC}")
                time.sleep(2)
                continue
            
            selected = run_fzf(branch_list, header="Select branches to delete (TAB)", multi=True, height='60%')
            if not selected:
                continue
            
            to_delete = selected.splitlines()
            for branch in to_delete:
                run_command(["git", "branch", "-d", branch], cwd=repo_path, capture=False)
            print(f"{GREEN}✓ Deleted {len(to_delete)} branch(es).{NC}")
            time.sleep(2)

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
        if r and r not in seen and os.path.isdir(r):
            combined.append(r)
            seen.add(r)
    
    if not combined:
        print(f"{YELLOW}No repositories found on disk.{NC}")
        time.sleep(2)
        return
            
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

def delete_github_repo():
    """Delete a repository from GitHub."""
    if not shutil.which("gh"):
        print(f"{RED}gh CLI is required.{NC}")
        time.sleep(2)
        return
    
    print(f"{BLUE}Fetching your repositories...{NC}")
    user = run_command(["gh", "api", "user", "--jq", ".login"])
    repos_json = run_command(["gh", "repo", "list", user, "--limit", "50", "--json", "name,owner"])
    if not repos_json:
        print(f"{RED}No repositories found.{NC}")
        time.sleep(2)
        return
    
    repos_data = json.loads(repos_json)
    repo_opts = [f"{r['owner']['login']}/{r['name']}" for r in repos_data]
    selected = run_fzf(repo_opts, header="Select repository to DELETE", height='60%')
    
    if not selected:
        return
    
    clear_screen()
    print(f"{RED}⚠️  WARNING: You are about to DELETE a repository!{NC}")
    print(f"{RED}This action is IRREVERSIBLE and will delete all data.{NC}\n")
    print(f"Repository: {RED}{selected}{NC}\n")
    
    confirm = input(f"Type '{selected}' to confirm deletion: ")
    
    if confirm != selected:
        print(f"{YELLOW}Deletion cancelled.{NC}")
        time.sleep(2)
        return
    
    print(f"{RED}Deleting repository...{NC}")
    res = run_command(["gh", "repo", "delete", selected, "--yes"], capture=False)
    
    if res == 0:
        print(f"{GREEN}✓ Repository '{selected}' deleted successfully.{NC}")
        with open(CACHE_FILE, "r") as f:
            repos = f.read().splitlines()
        repos = [r for r in repos if selected.split("/")[-1] not in r]
        with open(CACHE_FILE, "w") as f:
            f.write("\n".join(repos))
    else:
        print(f"{RED}✗ Failed to delete repository.{NC}")
        print(f"{YELLOW}Note: You need 'delete_repo' scope to delete repos.{NC}")
        print(f"{YELLOW}Run: gh auth refresh -h github.com -s delete_repo{NC}")
    time.sleep(3)

def github_repo_actions(repo_data):
    full_name = f"{repo_data['owner']['login']}/{repo_data['name']}"
    clone_url = f"https://github.com/{full_name}.git"

    while True:
        clear_screen()
        print(f"{BLUE}{'=' * 60}{NC}")
        print(f"  {BOLD}{full_name}{NC}")
        print(f"  {DIM}{repo_data.get('url', '')}{NC}")
        print(f"{BLUE}{'=' * 60}{NC}\n")

        actions = [
            "📥 Clone Repository",
            "🌐 Open in Browser",
            "📄 View README",
            "📋 View File Tree",
            "🔀 View Branches",
            "📦 View Releases",
            "📊 View Recent Commits",
            "🔙 Back",
        ]

        choice = run_fzf(actions, header=f"Actions for {full_name}", height='30%')

        if not choice or "Back" in choice:
            break
        elif "Clone" in choice:
            name = repo_data['name']
            dest = REPO_DIR / name
            print(f"{BLUE}Cloning to {dest}...{NC}")
            res = subprocess.run(["git", "clone", clone_url, str(dest)])
            if res.returncode == 0:
                print(f"{GREEN}✓ Cloned to {dest}{NC}")
            time.sleep(2)
        elif "Browser" in choice:
            browse_url = f"https://github.com/{full_name}"
            if sys.platform == 'win32':
                os.startfile(browse_url)
            elif sys.platform == 'darwin':
                subprocess.run(["open", browse_url])
            else:
                subprocess.run(["xdg-open", browse_url])
        elif "README" in choice:
            readme = run_command(["gh", "api", f"repos/{full_name}/readme", "--jq", ".content"])
            if readme:
                import base64
                try:
                    decoded = base64.b64decode(readme).decode('utf-8')
                    clear_screen()
                    print(f"{BOLD}--- README for {full_name} ---{NC}\n")
                    for line in decoded.splitlines()[:80]:
                        print(line)
                    print(f"\n{DIM}Press Enter to return...{NC}")
                    input()
                except Exception:
                    print(f"{RED}Could not decode README{NC}")
                    time.sleep(2)
            else:
                print(f"{YELLOW}No README found.{NC}")
                time.sleep(2)
        elif "File Tree" in choice:
            tree = run_command(["gh", "api", f"repos/{full_name}/git/trees/HEAD?recursive=1", "--jq", ".tree[].path"])
            if tree:
                files = tree.splitlines()
                selected = run_fzf(files, header=f"Files in {full_name}", height='80%')
                if selected:
                    browse_url = f"https://github.com/{full_name}/blob/HEAD/{selected}"
                    if sys.platform == 'win32':
                        os.startfile(browse_url)
                    elif sys.platform == 'darwin':
                        subprocess.run(["open", browse_url])
                    else:
                        subprocess.run(["xdg-open", browse_url])
            else:
                print(f"{YELLOW}Could not fetch file tree.{NC}")
                time.sleep(2)
        elif "Branches" in choice:
            branches = run_command(["gh", "api", f"repos/{full_name}/branches", "--jq", ".[].name"])
            if branches:
                branch_list = branches.splitlines()
                run_fzf(branch_list, header=f"Branches in {full_name}", height='60%')
            else:
                print(f"{YELLOW}Could not fetch branches.{NC}")
                time.sleep(2)
        elif "Releases" in choice:
            releases = run_command(["gh", "api", f"repos/{full_name}/releases", "--jq", ".[].tag_name"])
            if releases:
                run_fzf(releases.splitlines(), header=f"Releases for {full_name}", height='60%')
            else:
                print(f"{YELLOW}No releases found.{NC}")
                time.sleep(2)
        elif "Commits" in choice:
            commits = run_command(["gh", "api", f"repos/{full_name}/commits", "--jq", '.[] | .sha[:7] + " | " + .commit.message + " | " + .commit.author.name'])
            if commits:
                clear_screen()
                print(f"{BOLD}--- Recent Commits for {full_name} ---{NC}\n")
                for line in commits.splitlines()[:20]:
                    print(f"  {CYAN}{line}{NC}")
                print(f"\n{DIM}Press Enter to return...{NC}")
                input()
            else:
                print(f"{YELLOW}Could not fetch commits.{NC}")
                time.sleep(2)


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
    repos_json = run_command(["gh", "repo", "list", name, "--limit", "100", "--json", "name,owner,url,description,stargazerCount,forkCount,isPrivate,primaryLanguage,updatedAt"])
    repos_data = json.loads(repos_json)

    repo_names = [f"{r['owner']['login']}/{r['name']}" for r in repos_data]
    selected = run_fzf(repo_names, header=f"Repos in {name}")
    if selected:
        for i, rn in enumerate(repo_names):
            if rn == selected:
                github_repo_actions(repos_data[i])
                return

def clone_repo():
    url = input("URL: ").strip()
    if url: subprocess.run(["git", "clone", url], cwd=REPO_DIR)

def create_new_repo():
    name = input("Name: ").strip()
    if name:
        dest = REPO_DIR / name
        dest.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "init"], cwd=dest)

def check_gh_auth():
    """Check if user is logged in to GitHub CLI, prompt login if not."""
    if not shutil.which("gh"):
        print(f"{RED}gh CLI is not installed.{NC}")
        print(f"{YELLOW}Installing gh CLI...{NC}")
        if sys.platform == "linux":
            run_command(["sudo", "apt", "install", "gh"], capture=False)
        elif sys.platform == "darwin":
            run_command(["brew", "install", "gh"], capture=False)
        else:
            print(f"{YELLOW}Please install gh from: https://github.com/cli/cli{NC}")
            time.sleep(3)
            return False
    
    result = run_command(["gh", "auth", "status"])
    if "Logged in" in result:
        if "delete_repo" in result:
            print(f"{GREEN}✓ Logged into GitHub (with delete permission){NC}")
        else:
            print(f"{GREEN}✓ Logged into GitHub{NC}")
            print(f"{YELLOW}Requesting delete_repo permission...{NC}")
            res = run_command(["gh", "auth", "refresh", "-h", "github.com", "-s", "delete_repo"], capture=False)
            if res == 0:
                print(f"{GREEN}✓ Delete permission granted!{NC}")
            else:
                print(f"{YELLOW}⚠ Could not add delete permission automatically")
                print(f"  You can still delete repos manually on GitHub web")
        time.sleep(2)
        return True
    
    print(f"{YELLOW}You are not logged into GitHub.{NC}")
    print(f"{BLUE}Starting GitHub login...{NC}\n")
    print(f"{DIM}Note: You'll need to re-authenticate to add delete_repo permission after initial login.{NC}\n")
    
    run_command(["gh", "auth", "login", "-h", "github.com", "-s", "repo", "-s", "read:org", "-w"], capture=False)
    
    result = run_command(["gh", "auth", "status"])
    if "Logged in" in result:
        print(f"{GREEN}✓ Login successful!{NC}")
        time.sleep(2)
        return True
    else:
        print(f"{RED}Login failed or cancelled.{NC}")
        time.sleep(2)
        return False

UPDATE_URL = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/gity.py"
INSTALLER_URL = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.py"

def get_install_dir():
    if platform.system() == "Windows":
        return Path(os.environ.get("LOCALAPPDATA", HOME / "AppData" / "Local")) / "Gity"
    return HOME / ".local" / "share" / "gity"

def get_bin_dir():
    if platform.system() == "Windows":
        return get_install_dir()
    return HOME / ".local" / "bin"

def check_for_update():
    """Check if a newer version of gity.py is available."""
    try:
        import urllib.request
        remote = urllib.request.urlopen(INSTALLER_URL, timeout=5).read().decode()
        for line in remote.splitlines():
            if line.startswith("VERSION = "):
                remote_version = line.split('"')[1]
                if remote_version != VERSION:
                    return True, remote_version
                return False, VERSION
    except Exception:
        pass
    return False, VERSION

def update_gity():
    """Download and apply the latest gity.py and launcher."""
    clear_screen()
    print(f"{BLUE}Checking for updates...{NC}")

    has_update, remote_ver = check_for_update()
    if not has_update:
        print(f"\n{GREEN}✓ Gity is already up to date (v{VERSION}){NC}")
        time.sleep(2)
        return

    print(f"\n{YELLOW}New version available: v{remote_ver} (current: v{VERSION}){NC}")
    confirm = input(f"\nUpdate now? (y/N): ").strip().lower()
    if confirm != 'y':
        return

    install_dir = get_install_dir()
    bin_dir = get_bin_dir()

    try:
        import urllib.request

        print(f"\n{BLUE}Downloading latest gity.py...{NC}")
        urllib.request.urlretrieve(UPDATE_URL, install_dir / "gity.py")

        print(f"{BLUE}Downloading latest installer...{NC}")
        installer_content = urllib.request.urlopen(INSTALLER_URL).read().decode()

        if platform.system() == "Windows":
            python_exe = sys.executable
            gity_path = install_dir / "gity.py"
            launcher = bin_dir / "gity.cmd"
            content = f'@echo off\r\n"{python_exe}" "{gity_path}" %*\r\n'
            with open(launcher, "w", newline="") as f:
                f.write(content)
        else:
            launcher = bin_dir / "gity"
            with open(launcher, "w") as f:
                f.write(f'#!/usr/bin/env bash\nexec python3 "{install_dir / "gity.py"}" "$@"\n')
            launcher.chmod(0o755)

        print(f"\n{GREEN}✓ Updated to v{remote_ver}!{NC}")
        print(f"{YELLOW}Restart Gity to apply changes.{NC}")
        time.sleep(3)
        sys.exit(0)
    except Exception as e:
        print(f"\n{RED}✗ Update failed: {e}{NC}")
        time.sleep(3)

def main_menu():
    check_gh_auth()
    start_pr_fetch()

    has_update, remote_ver = check_for_update()

    while True:
        clear_screen()
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

        if has_update:
            print(f"  {YELLOW}⚠ Update available: v{remote_ver}{NC}\n")
        else:
            print()

        print(f"  {BOLD}Indicators:{NC} {GREEN}●{NC} Clean {YELLOW}✎{NC} Changes {CYAN}↑{NC} Ahead {RED}↓{NC} Behind\n")
        options = ["📊 Dashboard", "📥 Pull Requests", "📂 Browse Repos", "📅 Activity", "⚡ Bulk Actions", "🔍 Search", "🐙 GitHub Repos", "🔗 Clone", "✨ New Repo", "☠️ DELETE GitHub REPO", "🔄 Refresh Cache"]
        if has_update:
            options.append(f"🔼 Update to v{remote_ver}")
        options.append("❌ Exit")

        choice = run_fzf(options, header="MAIN MENU", height='50%', reverse=True)
        if not choice or "❌" in choice: sys.exit(0)
        elif "Dashboard" in choice: show_dashboard()
        elif "Pull Requests" in choice: pull_requests_menu()
        elif "Browse Repos" in choice: open_existing()
        elif "Activity" in choice: show_activity_timeline()
        elif "Bulk" in choice: bulk_actions()
        elif "Search" in choice: search_repos()
        elif "GitHub Repos" in choice: github_repos()
        elif "Clone" in choice: clone_repo()
        elif "New Repo" in choice: create_new_repo()
        elif "DELETE GitHub" in choice: delete_github_repo()
        elif "Refresh" in choice: refresh_cache()
        elif "Update" in choice: update_gity(); return

if __name__ == "__main__":
    if not shutil.which("fzf") or not shutil.which("git"):
        print("Error: git and fzf required")
        sys.exit(1)
    main_menu()
