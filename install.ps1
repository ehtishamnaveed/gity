# Gity Windows Installer
# One-command setup for Windows users
# Downloads everything via curl - no winget needed
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

# ============================================================
# CURL SETUP
# ============================================================

function Get-CurlPath {
    # Check System32 first (Windows 10/11 has curl.exe here)
    $systemCurl = Join-Path $env:SystemRoot "System32\curl.exe"
    if (Test-Path $systemCurl) { return $systemCurl }
    
    # Check PATH
    $pathCurl = Get-Command "curl.exe" -ErrorAction SilentlyContinue
    if ($pathCurl) { return $pathCurl.Source }
    
    # Check our bin dir
    $binCurl = Join-Path $BinDir "curl.exe"
    if (Test-Path $binCurl) { return $binCurl }
    
    return $null
}

function Setup-Curl {
    $curlPath = Get-CurlPath
    if ($curlPath) {
        Write-Success "curl.exe found at $curlPath"
        return $true
    }
    
    Write-Step "Downloading curl.exe..."
    
    if (!(Test-Path $BinDir)) {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
    }
    
    # Download curl from official source
    $curlUrl = "https://curl.se/windows/latest.cgi?p=win64-mingw"
    $tempZip = Join-Path $env:TEMP "curl-win64.zip"
    $tempDir = Join-Path $env:TEMP "curl-extract"
    
    try {
        # Use PowerShell's built-in download (only for curl itself)
        Invoke-WebRequest -Uri $curlUrl -UseBasicParsing -OutFile $tempZip
        
        if (!(Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }
        Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
        
        # Find curl.exe in extracted files
        $curlExe = Get-ChildItem -Path $tempDir -Recurse -Filter "curl.exe" | Select-Object -First 1
        if ($curlExe) {
            Copy-Item $curlExe.FullName (Join-Path $BinDir "curl.exe") -Force
            Add-ToPath $BinDir
            Write-Success "curl.exe installed to $BinDir"
            return $true
        }
    } catch {
        Write-Err "Failed to download curl: $_"
    } finally {
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force -ErrorAction SilentlyContinue }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    
    return $false
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutputPath
    )
    
    $curlPath = Get-CurlPath
    if ($curlPath) {
        $result = & $curlPath -sSL --retry 3 --connect-timeout 10 -o $OutputPath $Url 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath)) {
            return $true
        }
        Write-Warn "curl failed (exit code: $LASTEXITCODE), falling back..."
    }
    
    # Fallback to PowerShell
    try {
        Invoke-WebRequest -Uri $Url -UseBasicParsing -OutFile $OutputPath
        return $true
    } catch {
        Write-Err "Download failed: $_"
        return $false
    }
}

function Get-RemoteContent {
    param([string]$Url)
    
    $curlPath = Get-CurlPath
    if ($curlPath) {
        $result = & $curlPath -sSL $Url 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $result
        }
    }
    
    # Fallback
    try {
        return (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content
    } catch {
        return $null
    }
}

# ============================================================
# PATH MANAGEMENT
# ============================================================

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

# ============================================================
# TOOL INSTALLERS (via curl direct download)
# ============================================================

function Install-Git {
    if (Check-Command "git") {
        Write-Success "git already installed"
        return $true
    }
    
    Write-Step "Installing git..."
    
    # Detect architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { "64" } else { "32" }
    Write-Step "Detected architecture: ${arch}-bit"
    
    # Download Git for Windows portable (no installer needed)
    $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/PortableGit-${arch}-bit.7z.exe"
    $gitPortable = Join-Path $InstallDir "git"
    
    if (!(Test-Path $gitPortable)) {
        New-Item -ItemType Directory -Path $gitPortable -Force | Out-Null
    }
    
    $tempGit = Join-Path $env:TEMP "git-portable.exe"
    
    if (!(Download-File -Url $gitUrl -OutputPath $tempGit)) {
        Write-Err "Failed to download Git portable"
        Write-Warn "Please install Git manually from: https://git-scm.com/download/win"
        return $false
    }
    
    Write-Step "Extracting Git to $gitPortable..."
    
    try {
        # Git portable is a self-extracting 7z archive
        # Use 7z or PowerShell to extract
        Expand-Archive -Path $tempGit -DestinationPath $gitPortable -Force -ErrorAction Stop
        
        # Add git bin to PATH
        $gitBin = Join-Path $gitPortable "bin"
        if (Test-Path $gitBin) {
            Add-ToPath $gitBin
            $env:PATH = "$env:PATH;$gitBin"
        }
        
        Write-Success "Git installed successfully (portable)"
        return $true
    } catch {
        Write-Warn "Could not extract Git portable: $_"
        Write-Warn "Please install Git manually from: https://git-scm.com/download/win"
    } finally {
        if (Test-Path $tempGit) { Remove-Item $tempGit -Force -ErrorAction SilentlyContinue }
    }
    
    return $false
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
    
    # Download fzf binary
    $fzfUrl = "https://github.com/junegunn/fzf/releases/latest/download/fzf-0.70.0-windows_amd64.zip"
    $tempZip = Join-Path $env:TEMP "fzf.zip"
    
    if (!(Download-File -Url $fzfUrl -OutputPath $tempZip)) {
        Write-Err "Failed to download fzf"
        return $false
    }
    
    # Extract
    $tempDir = Join-Path $env:TEMP "fzf-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    
    # Copy fzf.exe to bin
    $fzfExe = Get-ChildItem -Path $tempDir -Recurse -Filter "fzf.exe" | Select-Object -First 1
    if ($fzfExe) {
        Copy-Item $fzfExe.FullName (Join-Path $BinDir "fzf.exe") -Force
        Add-ToPath $BinDir
        Write-Success "fzf installed to $BinDir"
    } else {
        Write-Err "Could not find fzf.exe in archive"
    }
    
    # Cleanup
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    
    return $true
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
    
    # Download gh binary
    $ghUrl = "https://github.com/cli/cli/releases/latest/download/gh_2.70.0_windows_amd64.zip"
    $tempZip = Join-Path $env:TEMP "gh.zip"
    
    if (!(Download-File -Url $ghUrl -OutputPath $tempZip)) {
        Write-Err "Failed to download gh CLI"
        return $false
    }
    
    # Extract
    $tempDir = Join-Path $env:TEMP "gh-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    
    # Copy gh.exe to bin
    $ghBinDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    if ($ghBinDir) {
        $ghExe = Join-Path $ghBinDir.FullName "bin\gh.exe"
        if (Test-Path $ghExe) {
            Copy-Item $ghExe (Join-Path $BinDir "gh.exe") -Force
            Add-ToPath $BinDir
            Write-Success "gh CLI installed to $BinDir"
        }
    }
    
    # Cleanup
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    
    return $true
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
    
    # Download lazygit binary
    $lazygitUrl = "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_0.59.0_Windows_x86_64.zip"
    $tempZip = Join-Path $env:TEMP "lazygit.zip"
    
    if (!(Download-File -Url $lazygitUrl -OutputPath $tempZip)) {
        Write-Err "Failed to download lazygit"
        return $false
    }
    
    # Extract
    $tempDir = Join-Path $env:TEMP "lazygit-extract"
    if (!(Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir -Force | Out-Null }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    
    # Copy lazygit.exe to bin
    $lazygitExe = Get-ChildItem -Path $tempDir -Recurse -Filter "lazygit.exe" | Select-Object -First 1
    if ($lazygitExe) {
        Copy-Item $lazygitExe.FullName (Join-Path $BinDir "lazygit.exe") -Force
        Add-ToPath $BinDir
        Write-Success "lazygit installed to $BinDir"
    } else {
        Write-Err "Could not find lazygit.exe in archive"
    }
    
    # Cleanup
    if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    
    return $true
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
Write-Host "  (curl-based, no winget needed)" -ForegroundColor Gray
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Setup curl first
Write-Step "Setting up curl..."
if (!(Setup-Curl)) {
    Write-Warn "curl setup failed, will use PowerShell fallback for downloads"
}

# Install dependencies via direct downloads
Write-Host ""
Write-Step "Installing dependencies..."
Write-Host ""

Install-Git
Install-Fzf
Install-Gh
Install-Lazygit

Write-Host ""

# Download Gity
if (!(Download-Gity)) {
    exit 1
}

# Add to PATH
Add-ToPath $InstallDir
Add-ToPath $BinDir

# Save version
Save-Version

# Success message
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  INSTALLATION COMPLETE" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installed to: $InstallDir" -ForegroundColor White
Write-Host "Binaries in: $BinDir" -ForegroundColor White
Write-Host ""
Write-Host "To run Gity:" -ForegroundColor Cyan
Write-Host "  1. Open a NEW terminal" -ForegroundColor Gray
Write-Host "  2. Type: gity" -ForegroundColor Yellow
Write-Host ""
Write-Host "Or run directly:" -ForegroundColor Cyan
Write-Host "  pwsh -File `"$InstallDir\gity.ps1`"" -ForegroundColor Yellow
Write-Host ""
