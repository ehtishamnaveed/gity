#!/usr/bin/env bash

set -e

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="gity"
OS=""
REPO_URL="https://raw.githubusercontent.com/ehtishamnaveed/Gity/master"

# ============================================================
# DETECT OS
# ============================================================

detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            ;;
        Linux*)
            if grep -qi microsoft /proc/version 2>/dev/null || [[ "$OSTYPE" == *"msys"* ]] || [[ "$OSTYPE" == *"cygwin"* ]]; then
                OS="windows"
            else
                OS="linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            OS="windows"
            ;;
        *)
            OS="unknown"
            ;;
    esac
}

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

install_deps() {
    local deps="git fzf lazygit"
    
    case "$OS" in
        macos)
            echo "==> Detected macOS"
            
            # Check for Homebrew
            if ! command -v brew &>/dev/null; then
                echo ""
                echo "Homebrew not found. Installing..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            
            echo "==> Installing dependencies via Homebrew..."
            for dep in $deps; do
                if ! command -v "$dep" &>/dev/null; then
                    echo "    Installing $dep..."
                    brew install "$dep"
                else
                    echo "    [OK] $dep already installed"
                fi
            done
            
            # Optional: gh CLI
            if ! command -v gh &>/dev/null; then
                echo "    Installing gh CLI (optional)..."
                brew install gh
            fi
            ;;
        
        linux)
            echo "==> Detected Linux"
            
            if command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm $deps 2>/dev/null || true
            elif command -v apt-get &>/dev/null; then
                sudo apt-get update -qq && sudo apt-get install -y $deps 2>/dev/null || true
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y $deps 2>/dev/null || true
            elif command -v yum &>/dev/null; then
                sudo yum install -y $deps 2>/dev/null || true
            elif command -v zypper &>/dev/null; then
                sudo zypper install -y $deps 2>/dev/null || true
            fi
            
            # Install missing deps manually
            for dep in $deps; do
                if ! command -v "$dep" &>/dev/null; then
                    echo "    [WARN] $dep not installed. Please install manually."
                fi
            done
            ;;
        
        windows)
            echo "==> Detected Windows (Git Bash / WSL)"
            echo "    For Windows, please use the PowerShell installer instead:"
            echo ""
            echo "    irm https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.ps1 | iex"
            echo ""
            echo "    This will install all dependencies natively on Windows."
            echo ""
            ;;
    esac
}

# ============================================================
# DOWNLOAD & INSTALL GITY
# ============================================================

install_gity() {
    if [ "$OS" = "windows" ]; then
        echo "==> Skipping Gity installation for Windows (use PowerShell installer)"
        return
    fi
    
    echo "==> Installing Gity..."
    mkdir -p "$INSTALL_DIR"
    
    if [ -f "./gity.sh" ]; then
        cp ./gity.sh "$INSTALL_DIR/$SCRIPT_NAME"
    else
        curl -sSL "$REPO_URL/gity.sh" -o "$INSTALL_DIR/$SCRIPT_NAME"
    fi
    
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    echo "==> Installed to $INSTALL_DIR/$SCRIPT_NAME"
}

# ============================================================
# SETUP PATH
# ============================================================

setup_path() {
    if [ "$OS" = "windows" ]; then
        return
    fi
    
    local shell_rc=""
    case "$SHELL" in
        */bash)
            shell_rc="$HOME/.bashrc"
            ;;
        */zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        */fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
    esac
    
    if [ -n "$shell_rc" ] && [ -f "$shell_rc" ]; then
        if ! grep -q "$INSTALL_DIR" "$shell_rc" 2>/dev/null; then
            echo "" >> "$shell_rc"
            echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$shell_rc"
            echo "==> Added $INSTALL_DIR to PATH in $shell_rc"
            echo "    Please restart your terminal or run: source $shell_rc"
        else
            echo "==> $INSTALL_DIR already in PATH"
        fi
    fi
}

# ============================================================
# MAIN
# ============================================================

echo ""
echo "========================================"
echo "  GITY - Installer v1.0.0"
echo "========================================"
echo ""

detect_os
install_deps
install_gity
setup_path

echo ""
echo "========================================"
echo "  INSTALLATION COMPLETE"
echo "========================================"
echo ""
echo "To run Gity:"
echo "  gity"
echo ""
