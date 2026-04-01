# Gity Windows Installer
# One-command setup for Windows users
# Uses PowerShell native commands - no curl, no winget
# Usage: irm https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.ps1 | iex

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Gity"
$BinDir = Join-Path $InstallDir "bin"
$CacheDir = Join-Path $env:APPDATA "gity"
$GityUrl = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master"

function Write-Step {
    param([string]$Text)
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "    [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "    [WARN] $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "    [FAIL] $Text" -ForegroundColor Red
}

function Check-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    try {
        # Use PowerShell native download
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $OutputPath
        return $true
    } catch {
        Write-Err "Download failed: $_"
        return $false
    }
}

function Add-ToPath {
    param([string]$PathToAdd)
    
    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    if ($currentPath -split ';' | Where-Object { $_ -eq $PathToAdd }) {
        Write-Success "Already in PATH: $PathToAdd"
        return $true
    }
    
    try {
        $newPath = "$currentPath;$PathToAdd"
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        $env:PATH = "$env:PATH;$PathToAdd"
        Write-Success "Added to PATH: $PathToAdd"
        return $true
    } catch {
        Write-Err "Failed to add to PATH: $_"
        return $false
    }
}

function Install-Git {
    if (Check-Command "git") {
        Write-Success "git already installed"
        return $true
    }
    
    Write-Step "Installing git..."
    
    $gitDir = Join-Path $InstallDir "git"
    if (!(Test-Path $gitDir)) {
        New-Item -ItemType Directory -Path $gitDir -Force | Out-Null
    }
    
    # Download Git portable
    $arch = if ([Environment]::Is64BitOperatingSystem) { "64" } else { "32" }
    $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/PortableGit-${arch}-bit.7z.exe"
    $tempGit = Join-Path $env:TEMP "git-portable.exe"
    
    if (!(Download-File -Url $gitUrl -OutputPath $tempGit)) {
        Write-Warn "Could not download Git. Please install manually from: https://git-scm.com/download/win"
        return $false
    }
    
    Write-Step "Extracting Git..."
    
    try {
        Expand-Archive -Path $tempGit -DestinationPath $gitDir -Force
        $gitBin = Join-Path $gitDir "bin"
        if (Test-Path $gitBin) {
            Add-ToPath $gitBin
            $env:PATH = "$env:PATH;$gitBin"
        }
        Write-Success "Git installed successfully"
        return $true
    } catch {
        Write-Err "Failed to extract Git: $_"
        Write-Warn "Please install Git manually from: https://git-scm.com/download/win"
        return $false
    } finally {
        if (Test-Path $tempGit) { Remove-Item $tempGit -Force -ErrorAction SilentlyContinue }
    }
}

function Install-Fzf {
    if (Check-Command "fzf") {
        Write-Success "fzf already installed"
        return $true
    }
    
    Write-Step "Installing fzf..."
    
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }
    
    $fzfUrl = "https://github.com/junegunn/fzf/releases/latest/download/fzf-0.70.0-windows_amd64.zip"
    $tempZip = Join-Path $env:TEMP "fzf.zip"
    
    if (!(Download-File -Url $fzfUrl -OutputPath $tempZip)) {
        Write-Warn "Could not download fzf. Please install manually: winget install junegunn.fzf"
        return $false
    }
    
    $tempDir = Join-Path $env:TEMP "fzf-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    
    try {
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        $fzfExe = Get-ChildItem -Path $tempDir -Recurse -Filter "fzf.exe" | Select-Object -First 1
        if ($fzfExe) {
            Copy-Item $fzfExe.FullName (Join-Path $BinDir "fzf.exe") -Force
            Add-ToPath $BinDir
            Write-Success "fzf installed"
            return $true
        }
    } catch {
        Write-Err "Failed to extract fzf: $_"
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    return $false
}

function Install-Gh {
    if (Check-Command "gh") {
        Write-Success "gh CLI already installed"
        return $true
    }
    
    Write-Step "Installing gh CLI..."
    
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }
    
    $ghUrl = "https://github.com/cli/cli/releases/latest/download/gh_2.70.0_windows_amd64.zip"
    $tempZip = Join-Path $env:TEMP "gh.zip"
    
    if (!(Download-File -Url $ghUrl -OutputPath $tempZip)) {
        Write-Warn "Could not download gh CLI. Please install manually: winget install GitHub.cli"
        return $false
    }
    
    $tempDir = Join-Path $env:TEMP "gh-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    
    try {
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        $ghBinDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
        if ($ghBinDir) {
            $ghExe = Join-Path $ghBinDir.FullName "bin\gh.exe"
            if (Test-Path $ghExe) {
                Copy-Item $ghExe (Join-Path $BinDir "gh.exe") -Force
                Add-ToPath $BinDir
                Write-Success "gh CLI installed"
                return $true
            }
        }
    } catch {
        Write-Err "Failed to extract gh CLI: $_"
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    return $false
}

function Install-Lazygit {
    if (Check-Command "lazygit") {
        Write-Success "lazygit already installed"
        return $true
    }
    
    Write-Step "Installing lazygit..."
    
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }
    
    $lazygitUrl = "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_0.59.0_Windows_x86_64.zip"
    $tempZip = Join-Path $env:TEMP "lazygit.zip"
    
    if (!(Download-File -Url $lazygitUrl -OutputPath $tempZip)) {
        Write-Warn "Could not download lazygit. Please install manually: winget install JesseDuffield.lazygit"
        return $false
    }
    
    $tempDir = Join-Path $env:TEMP "lazygit-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    
    try {
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        $lazygitExe = Get-ChildItem -Path $tempDir -Recurse -Filter "lazygit.exe" | Select-Object -First 1
        if ($lazygitExe) {
            Copy-Item $lazygitExe.FullName (Join-Path $BinDir "lazygit.exe") -Force
            Add-ToPath $BinDir
            Write-Success "lazygit installed"
            return $true
        }
    } catch {
        Write-Err "Failed to extract lazygit: $_"
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    return $false
}

function Download-Gity {
    Write-Step "Downloading Gity..."
    
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    
    $gityFile = Join-Path $InstallDir "gity.ps1"
    
    if (Download-File -Url "$GityUrl/gity.ps1" -OutputPath $gityFile) {
        Write-Success "Gity downloaded"
        return $true
    }
    return $false
}

function Save-Version {
    try {
        $version = (Invoke-WebRequest -Uri "$GityUrl/VERSION" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        if (!(Test-Path $CacheDir)) {
            New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        }
        Set-Content -Path (Join-Path $CacheDir "VERSION") -Value $version -Force
        Write-Success "Version saved: $version"
    } catch {
        Write-Warn "Could not fetch version info"
    }
}

# ============================================================
# MAIN INSTALL
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GITY - Windows Installer v1.0.0" -ForegroundColor White
Write-Host "  (PowerShell native - no winget/curl)" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Step "Installing dependencies..."
Write-Host ""

Install-Git
Install-Fzf
Install-Gh
Install-Lazygit

Write-Host ""

if (!(Download-Gity)) {
    exit 1
}

Add-ToPath $InstallDir
Add-ToPath $BinDir
Save-Version

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installed to: $InstallDir" -ForegroundColor White
Write-Host ""
Write-Host "To run Gity:" -ForegroundColor Cyan
Write-Host "  1. Open a NEW terminal" -ForegroundColor Gray
Write-Host "  2. Type: gity" -ForegroundColor Yellow
Write-Host ""
Write-Host "Or run directly:" -ForegroundColor Cyan
Write-Host "  pwsh -File `"$InstallDir\gity.ps1`"" -ForegroundColor Yellow
Write-Host ""
