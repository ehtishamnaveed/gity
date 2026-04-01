# Gity - TUI Git Hub for Windows
# Native PowerShell implementation

# ============================================================
# CONFIG & PATHS
# ============================================================

$GityVersion = "1.0.0"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$HomeDir = $env:USERPROFILE
$RepoDir = Join-Path $HomeDir "Documents\Github"
$CacheDir = Join-Path $env:APPDATA "gity"
$CacheFile = Join-Path $CacheDir "repos.txt"
$RecentFile = Join-Path $CacheDir "recent.txt"
$VersionFile = Join-Path $CacheDir "VERSION"

$UpdateUrl = "https://raw.githubusercontent.com/ehtishamnaveed/Gity/master"

if (!(Test-Path $RepoDir)) { New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null }
if (!(Test-Path $CacheDir)) { New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null }
if (!(Test-Path $RecentFile)) { New-Item -ItemType File -Path $RecentFile -Force | Out-Null }

# ============================================================
# COLORS & OUTPUT
# ============================================================

function Write-Banner {
    param([string]$Text)
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor White
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Status {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Blue
}

function Write-Success {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Green
}

function Write-Warning {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Text)
    Write-Host $Text -ForegroundColor Red
}

# ============================================================
# DEPENDENCY CHECK & AUTO-INSTALL
# ============================================================

function Check-Command {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Install-Dependency {
    param(
        [string]$Name,
        [string]$WingetId
    )
    
    if (Check-Command $Name) { return $true }
    
    Write-Warning "$Name not found. Attempting to install..."
    
    if (!(Check-Command "winget")) {
        Write-Error "winget not found. Please install $Name manually."
        return $false
    }
    
    $process = Start-Process -FilePath "winget" -ArgumentList "install", "-e", "--id", $WingetId, "--silent", "--accept-source-agreements" -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -eq 0) {
        Write-Success "$Name installed successfully!"
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
        return $true
    } else {
        Write-Error "Failed to install $Name. Please install manually."
        return $false
    }
}

function Check-Dependencies {
    $deps = @(
        @{Name = "git"; WingetId = "Git.Git"},
        @{Name = "fzf"; WingetId = "junegunn.fzf"},
        @{Name = "gh"; WingetId = "GitHub.cli"},
        @{Name = "lazygit"; WingetId = "JesseDuffield.lazygit"}
    )
    
    $allOk = $true
    foreach ($dep in $deps) {
        if (!(Install-Dependency -Name $dep.Name -WingetId $dep.WingetId)) {
            $allOk = $false
        }
    }
    
    return $allOk
}

# ============================================================
# VERSION & UPDATE
# ============================================================

function Get-LatestVersion {
    try {
        $response = Invoke-WebRequest -Uri "$UpdateUrl/VERSION" -UseBasicParsing -TimeoutSec 5
        return $response.Content.Trim()
    } catch {
        return $null
    }
}

function Check-ForUpdate {
    $localVersion = if (Test-Path $VersionFile) { Get-Content $VersionFile -Raw } else { "1.0.0" }
    $latestVersion = Get-LatestVersion
    
    if ($latestVersion -and $localVersion -ne $latestVersion) {
        return @{Available = $true; Latest = $latestVersion; Current = $localVersion}
    }
    return @{Available = $false; Current = $localVersion}
}

function Update-Gity {
    Write-Status "Updating Gity..."
    
    $tempFile = Join-Path $env:TEMP "gity-update.ps1"
    try {
        Invoke-WebRequest -Uri "$UpdateUrl/gity.ps1" -UseBasicParsing -OutFile $tempFile
        $installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        Copy-Item $tempFile (Join-Path $installDir "gity.ps1") -Force
        Remove-Item $tempFile -Force
        
        $latestVersion = Get-LatestVersion
        if ($latestVersion) {
            Set-Content -Path $VersionFile -Value $latestVersion -Force
        }
        
        Write-Success "Updated to v$latestVersion! Please restart Gity."
        Start-Sleep -Seconds 2
    } catch {
        Write-Error "Update failed. Please try again."
        Start-Sleep -Seconds 2
    }
}

# ============================================================
# REPO DISCOVERY
# ============================================================

function Refresh-Cache {
    Write-Status "Scanning for Git repositories..."
    
    $searchPaths = @(
        $HomeDir,
        "C:\Users\*\Documents\Github",
        "C:\Users\*\Desktop",
        "C:\Users\*\Work"
    )
    
    $repos = @()
    foreach ($path in $searchPaths) {
        $resolvedPaths = [System.IO.Directory]::GetDirectories((Split-Path $path), (Split-Path $path -Leaf), "AllDirectories") | Where-Object { $_ -match $path }
        $repos += $resolvedPaths
    }
    
    $gitDirs = Get-ChildItem -Path $HomeDir -Recurse -Directory -Filter ".git" -Depth 4 -ErrorAction SilentlyContinue | Where-Object {
        $_.FullName -notmatch "\\AppData\\|\\node_modules\\|\\.local\\|\\.npm\\|\\.cargo\\"
    }
    
    $repoPaths = $gitDirs | ForEach-Object { Split-Path $_.Parent.FullName } | Sort-Object | Get-Unique
    
    $repoPaths | Out-File -FilePath $CacheFile -Encoding utf8
    
    $count = ($repoPaths | Measure-Object).Count
    Write-Success "Scan complete. Found $count repositories."
    Start-Sleep -Seconds 1
}

# ============================================================
# REPO STATUS
# ============================================================

function Get-RepoStatus {
    param([string]$RepoPath)
    
    if (!(Test-Path (Join-Path $RepoPath ".git"))) { return "?" }
    
    $status = @{
        HasChanges = $false
        Ahead = 0
        Behind = 0
        DirtyFiles = 0
    }
    
    $porcelain = git -C $RepoPath status --porcelain 2>$null
    if ($porcelain) {
        $status.HasChanges = $true
        $status.DirtyFiles = ($porcelain | Measure-Object).Count
    }
    
    $revList = git -C $RepoPath rev-list --left-right --count '@{upstream}...HEAD' 2>$null
    if ($revList) {
        $parts = $revList -split '\s+'
        $status.Ahead = [int]$parts[0]
        $status.Behind = [int]$parts[1]
    }
    
    return $status
}

function Get-StatusIcon {
    param([hashtable]$Status)
    
    $icon = "●"
    $color = "Green"
    
    if ($Status.HasChanges) {
        $icon = "✎"
        $color = "Yellow"
    }
    
    if ($Status.Ahead -gt 0 -and $Status.Behind -gt 0) {
        $color = "Magenta"
        $icon += "↕"
    } elseif ($Status.Ahead -gt 0) {
        $color = "Cyan"
        $icon += "↑"
    } elseif ($Status.Behind -gt 0) {
        $color = "Red"
        $icon += "↓"
    }
    
    return @{Icon = $icon; Color = $color}
}

# ============================================================
# REPO ACTIONS
# ============================================================

function Repo-Actions {
    param([string]$RepoPath)
    
    $repoName = Split-Path $RepoPath -Leaf
    
    # Update recent
    if (Test-Path $RecentFile) {
        $recent = Get-Content $RecentFile | Where-Object { $_ -ne $RepoPath }
        $recent = @($RepoPath) + $recent | Select-Object -First 10
        $recent | Out-File -FilePath $RecentFile -Encoding utf8
    }
    
    while ($true) {
        Clear-Host
        Write-Banner "$repoName"
        Write-Host "  PATH: $RepoPath" -ForegroundColor Gray
        Write-Host ""
        
        $actions = @(
            "Open in Lazygit (TUI)",
            "Open in File Explorer",
            "Open in VS Code",
            "Copy Path",
            "Back to Gity"
        )
        
        $choice = $actions | fzf --height 20% --border --prompt="Select Action > " 2>$null
        
        switch ($choice) {
            "Open in Lazygit (TUI)" {
                lazygit -p $RepoPath
            }
            "Open in File Explorer" {
                Start-Process explorer.exe -ArgumentList $RepoPath
            }
            "Open in VS Code" {
                if (Check-Command "code") {
                    code $RepoPath
                } else {
                    Write-Warning "VS Code not found in PATH"
                    Start-Sleep -Seconds 2
                }
            }
            "Copy Path" {
                $RepoPath | Set-Clipboard
                Write-Success "Path copied to clipboard!"
                Start-Sleep -Seconds 1
            }
            default {
                return
            }
        }
    }
}

# ============================================================
# DASHBOARD
# ============================================================

function Show-Dashboard {
    if (!(Test-Path $CacheFile) -or (Get-Item $CacheFile).Length -eq 0) {
        Write-Warning "No repos found. Run 'Refresh Cache' first."
        Start-Sleep -Seconds 2
        return
    }
    
    Write-Status "Scanning repos for status..."
    
    $repos = Get-Content $CacheFile
    $critical = @()
    $warning = @()
    $healthy = @()
    
    foreach ($repo in $repos) {
        if (!(Test-Path $repo)) { continue }
        if (!(Test-Path (Join-Path $repo ".git"))) { continue }
        
        $status = Get-RepoStatus $repo
        $statusIcon = Get-StatusIcon $status
        $name = Split-Path $repo -Leaf
        
        $line = "[$($statusIcon.Icon)] $name"
        
        if ($status.HasChanges -or ($status.Ahead -gt 0 -and $status.Behind -gt 0)) {
            $details = @()
            if ($status.HasChanges) { $details += "$($status.DirtyFiles) file(s) changed" }
            if ($status.Ahead -gt 0) { $details += "$($status.Ahead)↑" }
            if ($status.Behind -gt 0) { $details += "$($status.Behind)↓" }
            $critical += "$line - $($details -join ', ')"
        } elseif ($status.Ahead -gt 0 -or $status.Behind -gt 0) {
            $details = @()
            if ($status.Ahead -gt 0) { $details += "$($status.Ahead) ahead" }
            if ($status.Behind -gt 0) { $details += "$($status.Behind) behind" }
            $warning += "$line - $($details -join ', ')"
        } else {
            $healthy += "$line - All synced"
        }
    }
    
    Clear-Host
    Write-Banner "DASHBOARD"
    Write-Host "  Total repos scanned: $($repos.Count)" -ForegroundColor White
    Write-Host ""
    
    if ($critical.Count -gt 0) {
        Write-Host "  NEED ATTENTION ($($critical.Count) repos)" -ForegroundColor Red
        $critical | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        Write-Host ""
    }
    
    if ($warning.Count -gt 0) {
        Write-Host "  NEED SYNC ($($warning.Count) repos)" -ForegroundColor Yellow
        $warning | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        Write-Host ""
    }
    
    if ($healthy.Count -gt 0) {
        Write-Host "  ALL SYNCED ($($healthy.Count) repos)" -ForegroundColor Green
        $healthy | ForEach-Object { Write-Host "    $_" -ForegroundColor Green }
    }
    
    Write-Host ""
    Write-Host "  Press Enter to return to menu..." -ForegroundColor Gray
    $null = $Host.UI.ReadLine()
}

# ============================================================
# BROWSE REPOSITORIES
# ============================================================

function Browse-Repositories {
    if (!(Test-Path $CacheFile) -or (Get-Item $CacheFile).Length -eq 0) {
        Refresh-Cache
    }
    
    $repos = Get-Content $CacheFile
    $recent = @()
    if (Test-Path $RecentFile) {
        $recent = Get-Content $RecentFile -ErrorAction SilentlyContinue
    }
    
    $allRepos = @($recent) + @($repos | Where-Object { $_ -notin $recent }) | Where-Object { $_ -and (Test-Path $_) } | Get-Unique
    
    $selected = $allRepos | ForEach-Object {
        $relPath = $_.Replace($HomeDir, "~")
        $relPath
    } | fzf --height 60% --border --header="Select Repository (Recent at top)" --prompt="Search > " 2>$null
    
    if ($selected) {
        $fullPath = $selected.Replace("~", $HomeDir)
        Repo-Actions $fullPath
    }
}

# ============================================================
# BULK ACTIONS
# ============================================================

function Bulk-Actions {
    if (!(Test-Path $CacheFile) -or (Get-Item $CacheFile).Length -eq 0) {
        Refresh-Cache
    }
    
    $repos = Get-Content $CacheFile | Where-Object { Test-Path $_ }
    
    Write-Status "Select repositories for bulk action (TAB to multi-select):"
    
    $selected = $repos | ForEach-Object {
        $_.Replace($HomeDir, "~")
    } | fzf --height 70% --border --header="Select repos (TAB for multi-select)" --prompt="Select > " --multi 2>$null
    
    if (!$selected) { return }
    
    $selectedPaths = $selected | ForEach-Object { $_.Replace("~", $HomeDir) }
    
    Write-Host ""
    Write-Status "Choose bulk action:"
    Write-Host ""
    
    $actions = @(
        "Pull All",
        "Push All",
        "Status All",
        "Commit All"
    )
    
    $action = $actions | fzf --height 25% --border --prompt="Action > " 2>$null
    
    $success = 0
    $failed = 0
    
    switch ($action) {
        "Pull All" {
            Write-Status "Pulling all repos..."
            foreach ($repo in $selectedPaths) {
                $name = Split-Path $repo -Leaf
                Write-Host "Pulling: $name" -ForegroundColor Cyan
                $output = git -C $repo pull 2>&1 | Select-Object -Last 2
                if ($LASTEXITCODE -eq 0) {
                    $success++
                } else {
                    $failed++
                }
            }
        }
        "Push All" {
            Write-Status "Pushing all repos..."
            foreach ($repo in $selectedPaths) {
                $name = Split-Path $repo -Leaf
                Write-Host "Pushing: $name" -ForegroundColor Cyan
                $output = git -C $repo push 2>&1 | Select-Object -Last 2
                if ($LASTEXITCODE -eq 0) {
                    $success++
                } else {
                    $failed++
                }
            }
        }
        "Status All" {
            foreach ($repo in $selectedPaths) {
                $name = Split-Path $repo -Leaf
                Write-Host "=== $name ===" -ForegroundColor White
                git -C $repo status --short
                Write-Host ""
            }
            Write-Host "Press Enter to continue..." -ForegroundColor Gray
            $null = $Host.UI.ReadLine()
        }
        "Commit All" {
            $msg = Read-Host "Enter commit message"
            if ($msg) {
                foreach ($repo in $selectedPaths) {
                    $name = Split-Path $repo -Leaf
                    Write-Host "Committing: $name" -ForegroundColor Cyan
                    git -C $repo add -A 2>$null
                    git -C $repo commit -m $msg 2>&1 | Select-Object -Last 3
                }
            }
        }
    }
    
    Write-Host ""
    Write-Success "Done! $success succeeded, $failed failed"
    Start-Sleep -Seconds 2
}

# ============================================================
# GITHUB INTEGRATION
# ============================================================

function GitHub-Repos {
    if (!(Check-Command "gh")) {
        Write-Warning "GitHub CLI (gh) not found."
        $install = Read-Host "Install now? (y/n)"
        if ($install -eq "y") {
            Install-Dependency "gh" "GitHub.cli"
        } else {
            return
        }
    }
    
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Not authenticated with GitHub."
        $authChoice = "Connect to GitHub", "Cancel" | fzf --height 15% --border --prompt="Connect > " 2>$null
        
        if ($authChoice -eq "Connect to GitHub") {
            gh auth login
            $authStatus = gh auth status 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Error "Authentication failed."
                Start-Sleep -Seconds 2
                return
            }
        } else {
            return
        }
    }
    
    Write-Status "Fetching user info..."
    $user = gh api user --jq '.login' 2>$null
    
    $orgsFile = Join-Path $env:TEMP "gity-orgs.txt"
    gh api user/orgs --jq '.[].login' > $orgsFile 2>$null
    $orgs = Get-Content $orgsFile -ErrorAction SilentlyContinue
    Remove-Item $orgsFile -Force -ErrorAction SilentlyContinue
    
    $options = @("Your Repositories ($user)")
    if ($orgs) {
        $orgs | ForEach-Object { $options += "$_" }
    }
    
    $selectedEntity = $options | fzf --height 40% --border --header="Select Organization or User" --prompt="Select > " 2>$null
    
    if (!$selectedEntity) { return }
    
    $entityType = "user"
    $entityName = $user
    
    if ($selectedEntity -ne "Your Repositories ($user)") {
        $entityType = "org"
        $entityName = $selectedEntity
    }
    
    Write-Status "Fetching $entityName repositories..."
    
    $reposFile = Join-Path $env:TEMP "gity-repos.txt"
    if ($entityType -eq "user") {
        gh repo list $entityName --limit 100 --json name,owner,url --jq '.[] | "\(.owner.login)/\(.name)|\(.url)"' > $reposFile 2>$null
    } else {
        gh api "orgs/$entityName/repos?per_page=100" --jq '.[] | "\(.owner.login)/\(.name)|\(.html_url)"' > $reposFile 2>$null
    }
    
    $repos = Get-Content $reposFile -ErrorAction SilentlyContinue
    Remove-Item $reposFile -Force -ErrorAction SilentlyContinue
    
    if (!$repos) {
        Write-Warning "No repositories found."
        Start-Sleep -Seconds 2
        return
    }
    
    $repoNames = $repos | ForEach-Object { ($_ -split '\|')[0] }
    
    $selected = $repoNames | fzf --height 70% --border --header="Repositories in $entityName" --prompt="Select repo > " 2>$null
    
    if (!$selected) { return }
    
    $url = ($repos | Where-Object { $_ -match "^$selected\|" } | ForEach-Object { ($_ -split '\|')[1] })
    
    Write-Host ""
    Write-Status "Selected: $selected"
    Write-Status "URL: $url"
    Write-Host ""
    Write-Status "Choose action:"
    
    $actionChoice = "Clone Repository", "Open in Browser" | fzf --height 20% --border --prompt="Action > " 2>$null
    
    switch ($actionChoice) {
        "Clone Repository" {
            $dest = Join-Path $RepoDir ($selected -replace '/', '-')
            if (Test-Path $dest) {
                Write-Warning "Repository already exists at: $dest"
                Repo-Actions $dest
            } else {
                $cloneMode = "Fetch Default Branch Only", "Fetch All Branches" | fzf --height 15% --border --prompt="Clone mode > " 2>$null
                Write-Status "Cloning to: $dest"
                
                if ($cloneMode -eq "Fetch All Branches") {
                    git clone --no-single-branch $url $dest
                } else {
                    git clone $url $dest
                }
                
                if ($LASTEXITCODE -eq 0) {
                    Repo-Actions $dest
                }
            }
        }
        "Open in Browser" {
            Start-Process $url
        }
    }
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {
    $updateInfo = Check-ForUpdate
    
    Clear-Host
    Write-Banner "GITY - TUI Git Hub v$($updateInfo.Current)"
    
    if ($updateInfo.Available) {
        Write-Warning "  Update available! v$($updateInfo.Latest) - Select 'Update Gity' to upgrade."
        Write-Host ""
    }
    
    Write-Host "  Status: ● Clean  ✎ Changes  ↑ Ahead  ↓ Behind  ↕ Diverged" -ForegroundColor Gray
    Write-Host ""
    
    $choices = @(
        "Dashboard (Repos Needing Work)",
        "Browse All Repositories",
        "Bulk Actions",
        "GitHub Repos",
        "Refresh Cache",
        "Update Gity",
        "Exit"
    )
    
    $choice = $choices | fzf --height 50% --layout=reverse --border --prompt="Main Menu > " 2>$null
    
    return $choice
}

# ============================================================
# ENTRY POINT
# ============================================================

Check-Dependencies

if (!(Test-Path $CacheFile) -or (Get-Item $CacheFile).Length -eq 0) {
    Write-Status "First run - scanning for repositories..."
    Refresh-Cache
}

while ($true) {
    $choice = Show-MainMenu
    
    switch ($choice) {
        "Dashboard (Repos Needing Work)" {
            Show-Dashboard
        }
        "Browse All Repositories" {
            Browse-Repositories
        }
        "Bulk Actions" {
            Bulk-Actions
        }
        "GitHub Repos" {
            GitHub-Repos
        }
        "Refresh Cache" {
            Refresh-Cache
        }
        "Update Gity" {
            Update-Gity
        }
        default {
            exit
        }
    }
}
