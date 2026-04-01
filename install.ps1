# Gity Windows Installer
# One-command setup for Windows users
# Usage: irm https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.ps1 | iex

$ErrorActionPreference = "Stop"

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Gity"
$CacheDir = Join-Path $env:APPDATA "gity"
$GityUrl = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master"

function Write-Step {
    param([string]$Text)
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "    ✓ $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "    ! $Text" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Text)
    Write-Host "    ✗ $Text" -ForegroundColor Red
}

function Check-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    return $null -ne $winget
}

function Install-WithWinget {
    param(
        [string]$Name,
        [string]$WingetId
    )
    
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        Write-Success "$Name already installed"
        return $true
    }
    
    Write-Step "Installing $Name..."
    
    $process = Start-Process -FilePath "winget" -ArgumentList "install", "-e", "--id", $WingetId, "--silent", "--accept-source-agreements" -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Success "$Name installed successfully"
        return $true
    } else {
        Write-Err "Failed to install $Name (exit code: $($process.ExitCode))"
        return $false
    }
}

function Add-ToPath {
    param([string]$Path)
    
    $currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
    
    if ($currentPath -split ';' | Where-Object { $_ -eq $Path }) {
        return $true
    }
    
    try {
        $newPath = "$currentPath;$Path"
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        $env:PATH = "$env:PATH;$Path"
        return $true
    } catch {
        return $false
    }
}

function Download-Gity {
    Write-Step "Downloading Gity..."
    
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    
    $gityFile = Join-Path $InstallDir "gity.ps1"
    
    try {
        Invoke-WebRequest -Uri "$GityUrl/gity.ps1" -UseBasicParsing -OutFile $gityFile
        Write-Success "Gity downloaded to $InstallDir"
        return $true
    } catch {
        Write-Err "Failed to download Gity"
        return $false
    }
}

function Save-Version {
    try {
        $version = (Invoke-WebRequest -Uri "$GityUrl/VERSION" -UseBasicParsing -TimeoutSec 5).Content.Trim()
        if (!(Test-Path $CacheDir)) {
            New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        }
        Set-Content -Path (Join-Path $CacheDir "VERSION") -Value $version -Force
    } catch {
        Write-Warn "Could not fetch version info"
    }
}

# ============================================================
# MAIN INSTALL
# ============================================================

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   GITY - Windows Installer v1.0.0   ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (!(Check-Winget)) {
    Write-Err "winget not found! Please install winget first."
    Write-Host ""
    Write-Host "    Install winget from: https://aka.ms/getwinget" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

$allOk = $true

Write-Step "Checking dependencies..."
Write-Host ""

$deps = @(
    @{Name = "git"; WingetId = "Git.Git"},
    @{Name = "fzf"; WingetId = "junegunn.fzf"},
    @{Name = "gh"; WingetId = "GitHub.cli"},
    @{Name = "lazygit"; WingetId = "JesseDuffield.lazygit"}
)

foreach ($dep in $deps) {
    if (!(Install-WithWinget -Name $dep.Name -WingetId $dep.WingetId)) {
        $allOk = $false
    }
}

Write-Host ""

if (!$allOk) {
    Write-Warn "Some dependencies failed to install. You may need to run as Administrator."
    Write-Warn "Continuing with installation anyway..."
    Write-Host ""
}

if (!(Download-Gity)) {
    exit 1
}

if (!(Add-ToPath $InstallDir)) {
    Write-Err "Failed to add Gity to PATH"
    exit 1
}

Save-Version

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║          INSTALLATION COMPLETE       ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "    Gity is now installed at: $InstallDir" -ForegroundColor White
Write-Host "    Added to PATH: $InstallDir" -ForegroundColor White
Write-Host ""
Write-Host "    To run Gity, open a NEW terminal and type:" -ForegroundColor Cyan
Write-Host "        gity" -ForegroundColor Yellow
Write-Host ""
Write-Host "    Or run directly:" -ForegroundColor Cyan
Write-Host "        pwsh -File `"$InstallDir\gity.ps1`"" -ForegroundColor Yellow
Write-Host ""
