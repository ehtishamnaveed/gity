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

def find_python():
    """Return the exact Python executable running this installer."""
    return sys.executable

def create_launcher_windows(bin_dir, install_dir):
    """Create a .cmd launcher for Windows (more reliable than .bat)."""
    python_exe = find_python()
    gity_path = install_dir / "gity.py"
    launcher = bin_dir / "gity.cmd"

    # \r\n line endings are required for Windows batch files
    content = f'@echo off\r\n"{python_exe}" "{gity_path}" %*\r\n'

    with open(launcher, "w", newline="") as f:
        f.write(content)

    print_color(f"Created Windows launcher: {launcher}", GREEN)
    return launcher

def create_launcher_unix(bin_dir, install_dir):
    """Create a shell launcher for Linux/macOS."""
    gity_path = install_dir / "gity.py"
    launcher = bin_dir / "gity"

    with open(launcher, "w") as f:
        f.write(f'#!/usr/bin/env bash\nexec python3 "{gity_path}" "$@"\n')

    launcher.chmod(0o755)
    print_color(f"Created launcher: {launcher}", GREEN)
    return launcher

def add_to_path(bin_dir):
    """Add bin_dir to PATH for current and future sessions."""
    system = platform.system()

    if system == "Windows":
        try:
            cmd = f'[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";{bin_dir}", "User")'
            subprocess.run(["powershell", "-Command", cmd], check=True, capture_output=True)
            os.environ["PATH"] = f"{os.environ.get('PATH', '')};{bin_dir}"
            print_color(f"Added {bin_dir} to Windows PATH", GREEN)
            return True
        except Exception as e:
            print_color(f"Failed to update Windows PATH: {e}", RED)
            return False
    else:
        shell = os.environ.get("SHELL", "")
        home = Path.home()
        rc_files = []

        if "zsh" in shell:
            rc_files.append(home / ".zshrc")
        if "bash" in shell:
            rc_files.extend([home / ".bashrc", home / ".bash_profile"])
        if not rc_files:
            rc_files.extend([home / ".bashrc", home / ".zshrc"])

        path_line = f'\nexport PATH="$PATH:{bin_dir}"\n'
        added = False
        for rc in rc_files:
            if rc.exists():
                with open(rc, "r") as f:
                    content = f.read()
                if str(bin_dir) not in content:
                    with open(rc, "a") as f:
                        f.write(path_line)
                    print_color(f"Added {bin_dir} to {rc.name}", GREEN)
                    added = True
        return added

def download_gity_py(install_dir):
    """Download gity.py from GitHub using only the stdlib."""
    url = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/gity.py"
    dest = install_dir / "gity.py"

    try:
        import urllib.request
        urllib.request.urlretrieve(url, dest)
        print_color(f"Downloaded gity.py to {dest}", GREEN)
        return True
    except Exception as e:
        print_color(f"Failed to download gity.py: {e}", RED)
        return False

def install():
    print_color("=== Gity Installer ===", BLUE)

    install_dir, bin_dir = get_install_paths()
    install_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)

    system = platform.system()

    if not download_gity_py(install_dir):
        sys.exit(1)

    if system == "Windows":
        create_launcher_windows(bin_dir, install_dir)
    else:
        create_launcher_unix(bin_dir, install_dir)

    add_to_path(bin_dir)

    print_color("\nInstallation Complete!", GREEN)
    print_color(f"Installed at: {install_dir}", "\033[2m")

    if system == "Windows":
        print_color("\nIMPORTANT: Close and reopen your terminal, then type 'gity'", YELLOW)
    else:
        print_color("\nRun: source ~/.bashrc  (or ~/.zshrc), then type 'gity'", YELLOW)

if __name__ == "__main__":
    try:
        install()
    except KeyboardInterrupt:
        print("\nInstallation cancelled.")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)
