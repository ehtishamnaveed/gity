import os
import sys
import subprocess
import shutil
import platform
from pathlib import Path

# Color constants
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
NC = "\033[0m"

def print_color(text, color):
    print(f"{color}{text}{NC}")

def get_install_paths():
    home = Path.home()
    if platform.system() == "Windows":
        install_dir = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local")) / "Gity"
        bin_dir = install_dir
    else:
        install_dir = home / ".local" / "share" / "gity"
        bin_dir = home / ".local" / "bin"
    return install_dir, bin_dir

def setup_path_unix(bin_dir):
    shell = os.environ.get("SHELL", "")
    home = Path.home()
    rc_files = []
    
    if "zsh" in shell:
        rc_files.append(home / ".zshrc")
    elif "bash" in shell:
        rc_files.append(home / ".bashrc")
        rc_files.append(home / ".bash_profile")
    
    path_line = f'\nexport PATH="$PATH:{bin_dir}"\n'
    
    for rc in rc_files:
        if rc.exists():
            with open(rc, "r") as f:
                content = f.read()
            if str(bin_dir) not in content:
                with open(rc, "a") as f:
                    f.write(path_line)
                print_color(f"✓ Added {bin_dir} to {rc.name}", GREEN)
                return True
    return False

def setup_path_windows(bin_dir):
    try:
        # Use PowerShell to update User PATH permanently
        cmd = f'[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";{bin_dir}", "User")'
        subprocess.run(["powershell", "-Command", cmd], check=True)
        print_color(f"✓ Added {bin_dir} to Windows User PATH", GREEN)
        return True
    except Exception as e:
        print_color(f"✗ Failed to update Windows PATH: {e}", RED)
        return False

def install():
    print_color("=== Gity Python Installer ===", BLUE)
    
    install_dir, bin_dir = get_install_paths()
    install_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)
    
    # 1. Download gity.py to internal install dir
    print_color("Downloading gity.py...", BLUE)
    url = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/gity.py"
    try:
        subprocess.run(["curl", "-sSL", url, "-o", str(install_dir / "gity.py")], check=True)
    except subprocess.CalledProcessError as e:
        print_color(f"✗ Failed to download gity.py: {e}", RED)
        sys.exit(1)
    
    # 2. Create the global 'gity' keyword
    if platform.system() == "Windows":
        executable = bin_dir / "gity.bat"
        with open(executable, "w") as f:
            f.write(f'@echo off\npython "{install_dir / "gity.py"}" %*')
        setup_path_windows(bin_dir)
    else:
        executable = bin_dir / "gity"
        with open(executable, "w") as f:
            f.write(f'#!/usr/bin/env bash\npython3 "{install_dir / "gity.py"}" "$@"')
        executable.chmod(0o755)
        setup_path_unix(bin_dir)

    print_color("\nInstallation Complete!", GREEN)
    print_color(f"Gity is installed at: {install_dir}", DIM := "\033[2m")
    print_color("\nNext Steps:", BLUE)
    print("1. Restart your terminal (or source your .rc file)")
    print("2. Type 'gity' to start")

if __name__ == "__main__":
    try:
        install()
    except KeyboardInterrupt:
        print("\nInstallation cancelled.")
        sys.exit(1)
    except Exception as e:
        print(f"\nError during installation: {e}")
        sys.exit(1)
# Cache buster: Wed Apr  1 11:09:48 PM PKT 2026
