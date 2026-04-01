# Gity Windows Installer
# One-command setup for Windows users
# Usage: irm https://raw.githubusercontent.com/ehtishamnaveed/Gity/master/install.ps1 | iex

$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\Gity"
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

# ============================================================
# CURL SETUP - Windows has curl.exe in System32
# ============================================================

function Setup-Curl {
    # Check for curl.exe explicitly (not PowerShell's curl alias)
    $curlPath = Join-Path $env:SystemRoot "System32\curl.exe"
    
    if (Test-Path $curlPath) {
        Write-Success "curl.exe found at $curlPath"
        return $true
    }
    
    # Also check if curl.exe is in PATH
    $curlInPath = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($curlInPath) {
        Write-Success "curl.exe found in PATH"
        return $true
    }
    
    Write-Warn "curl.exe not found. Installing..."
    
    # Try winget first
    if (Check-Command "winget") {
        Write-Step "Installing curl via winget..."
        winget install -e --id curl.curl --silent --accept-source-agreements 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "curl installed successfully"
            return $true
        }
    }
    
    # Fallback: Download curl manually
    Write-Warn "winget failed. Downloading curl manually..."
    
    $curlUrl = "https://curl.se/windows/dl-8.7.1_7/curl-8.7.1-win64-mingw.zip"
    $tempZip = Join-Path $env:TEMP "curl-win64.zip"
    $curlExtractDir = Join-Path $env:TEMP "curl-extract"
    
    try {
        # Use PowerShell's built-in download
        Invoke-WebRequest -Uri $curlUrl -UseBasicParsing -OutFile $tempZip
        
        # Extract
        if (!(Test-Path $curlExtractDir)) {
            New-Item -ItemType Directory -Path $curlExtractDir -Force | Out-Null
        }
        Expand-Archive -Path $tempZip -DestinationPath $curlExtractDir -Force
        
        # Copy curl.exe to a known location
        $curlBinDir = Join-Path $InstallDir "bin"
        if (!(Test-Path $curlBinDir)) {
            New-Item -ItemType Directory -Path $curlBinDir -Force | Out-Null
        }
        
        $curlExe = Get-ChildItem -Path $curlExtractDir -Recurse -Filter "curl.exe" | Select-Object -First 1
        if ($curlExe) {
            Copy-Item $curlExe.FullName (Join-Path $curlBinDir "curl.exe") -Force
            Add-ToPath $curlBinDir
            Write-Success "curl installed to $curlBinDir"
            return $true
        }
    } catch {
        Write-Err "Failed to download curl: $_"
    } finally {
        # Cleanup
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $curlExtractDir) { Remove-Item $curlExtractDir -Recurse -Force }
    }
    
    Write-Err "Could not install curl. Please install manually:"
    Write-Host "  winget install curl.curl" -ForegroundColor Gray
    return $false
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    # Use curl.exe for downloads (native Windows binary)
    $result = & curl.exe -sSL -o $OutputPath $Url 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        return $true
    } else {
        Write-Warn "curl failed (exit code: $LASTEXITCODE), falling back to Invoke-WebRequest..."
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $OutputPath
            return $true
        } catch {
            Write-Err "Download failed: $_"
            return $false
        }
    }
}

function Get-RemoteContent {
    param([string]$Url)
    
    # Use curl.exe to fetch content
    $result = & curl.exe -sSL $Url 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        return $result
    } else {
        Write-Warn "curl failed, falling back to Invoke-WebRequest..."
        try {
            return (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
        } catch {
            Write-Err "Failed to fetch content: $_"
            return $null
        }
    }
}

# ============================================================
# WINGET INSTALLER
# ============================================================

function Install-WithWinget {
    param(
        [string]$Name,
        [string]$WingetId
    )
    
    if (Check-Command $Name) {
        Write-Success "$Name already installed"
        return $true
    }
    
    Write-Step "Installing $Name via winget..."
    
    try {
        $result = winget install -e --id $WingetId --silent --accept-source-agreements 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$Name installed successfully"
            # Refresh PATH
            $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
            return $true
        } else {
            Write-Warn "winget install failed for $Name (exit code: $LASTEXITCODE)"
            return $false
        }
    } catch {
        Write-Warn "winget error: $_"
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

function Download-Gity {
    Write-Step "Downloading Gity..."
    
    if (!(Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    
    $gityFile = Join-Path $InstallDir "gity.ps1"
    
    if (Download-File -Url "$GityUrl/gity.ps1" -OutputPath $gityFile) {
        Write-Success "Gity downloaded to $InstallDir"
        return $true
    }
    return $false
}

function Save-Version {
    $version = Get-RemoteContent -Url "$GityUrl/VERSION"
    if ($version) {
        $version = $version.Trim()
        if (!(Test-Path $CacheDir)) {
            New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
        }
        Set-Content -Path (Join-Path $CacheDir "VERSION") -Value $version -Force
        Write-Success "Version saved: $version"
    } else {
        Write-Warn "Could not fetch version info (will use default)"
    }
}

# ============================================================
# MAIN INSTALL
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  GITY - Windows Installer v1.0.0" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Setup curl first
Write-Step "Setting up curl..."
if (!(Setup-Curl)) {
    Write-Warn "curl setup failed, will use PowerShell fallback for downloads"
}

# Check winget
Write-Step "Checking winget..."
if (!(Check-Command "winget")) {
    Write-Err "winget not found!"
    Write-Host ""
    Write-Host "Please install winget first:" -ForegroundColor Yellow
    Write-Host "  1. Open Microsoft Store" -ForegroundColor Gray
    Write-Host "  2. Search for 'App Installer'" -ForegroundColor Gray
    Write-Host "  3. Install it" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or download from: https://aka.ms/getwinget" -ForegroundColor Gray
    Write-Host ""
    exit 1
}
Write-Success "winget found"

# Install dependencies
Write-Host ""
Write-Step "Checking dependencies..."
Write-Host ""

$deps = @(
    @{Name = "git"; WingetId = "Git.Git"},
    @{Name = "fzf"; WingetId = "junegunn.fzf"},
    @{Name = "gh"; WingetId = "GitHub.cli"},
    @{Name = "lazygit"; WingetId = "JesseDuffield.lazygit"}
)

$failedDeps = @()

foreach ($dep in $deps) {
    if (!(Install-WithWinget -Name $dep.Name -WingetId $dep.WingetId)) {
        $failedDeps += $dep
    }
}

Write-Host ""

if ($failedDeps.Count -gt 0) {
    Write-Host ""
    Write-Warn "Some dependencies failed to install:"
    foreach ($dep in $failedDeps) {
        Write-Host "    - $($dep.Name)" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Try these steps:" -ForegroundColor Yellow
    Write-Host "  1. Run PowerShell as Administrator" -ForegroundColor Gray
    Write-Host "  2. Run: winget source reset --force" -ForegroundColor Gray
    Write-Host "  3. Run this installer again" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Or install manually:" -ForegroundColor Yellow
    foreach ($dep in $failedDeps) {
        Write-Host "    winget install -e --id $($dep.WingetId)" -ForegroundColor Gray
    }
    Write-Host ""
}

# Download Gity
if (!(Download-Gity)) {
    exit 1
}

# Add to PATH
Add-ToPath $InstallDir

# Save version
Save-Version

# Success message
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
