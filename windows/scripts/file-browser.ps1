#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Interactive File Browser Utility
.DESCRIPTION
    Provides interactive file browsing and selection for both host machine
    and Docker containers. Supports Windows GUI dialogs, Out-GridView,
    and console-based browsing with history and bookmarks.
#>

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

# ============================================
# Configuration
# ============================================

$script:HistoryFile = Join-Path $env:TEMP "hms-file-history.json"
$script:BookmarksFile = Join-Path $env:TEMP "hms-bookmarks.json"
$script:MaxHistoryItems = 10

# Default bookmarks for containers
$script:DefaultContainerBookmarks = @{
    "hms-postgres" = @(
        @{ Name = "Data"; Path = "/var/lib/postgresql/data" }
        @{ Name = "PG Config"; Path = "/var/lib/postgresql/data/pgdata" }
        @{ Name = "Temp"; Path = "/tmp" }
    )
    "hms-platform-backend" = @(
        @{ Name = "App Root"; Path = "/app" }
        @{ Name = "HMS Module"; Path = "/app/hms" }
        @{ Name = "Config"; Path = "/app/hms/shared" }
        @{ Name = "Migrations"; Path = "/app/alembic/versions" }
        @{ Name = "Temp"; Path = "/tmp" }
    )
    "hospital-ui" = @(
        @{ Name = "App Root"; Path = "/app" }
        @{ Name = "Public"; Path = "/app/public" }
        @{ Name = "Temp"; Path = "/tmp" }
    )
}

# ============================================
# GUI Detection Functions
# ============================================

function Test-GuiAvailable {
    <#
    .SYNOPSIS
        Checks if Windows Forms GUI is available
    #>
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Test-OutGridViewAvailable {
    <#
    .SYNOPSIS
        Checks if Out-GridView is available
    #>
    try {
        Get-Command Out-GridView -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

# ============================================
# History and Bookmarks Management
# ============================================

function Get-RecentPaths {
    <#
    .SYNOPSIS
        Gets recent paths for a category
    #>
    param(
        [string]$Type = "HostFile"
    )

    if (-not (Test-Path $script:HistoryFile)) {
        return @()
    }

    try {
        $history = Get-Content $script:HistoryFile -Raw -ErrorAction Stop | ConvertFrom-Json
        $typeHistory = $history.$Type
        if ($typeHistory) {
            return @($typeHistory)
        }
    } catch {
        # Corrupted file, ignore
    }

    return @()
}

function Add-RecentPath {
    <#
    .SYNOPSIS
        Adds a path to recent history
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$Type = "HostFile"
    )

    $history = @{}
    if (Test-Path $script:HistoryFile) {
        try {
            $content = Get-Content $script:HistoryFile -Raw -ErrorAction Stop
            if ($content) {
                $history = $content | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            }
        } catch {
            $history = @{}
        }
    }

    if (-not $history.ContainsKey($Type)) {
        $history[$Type] = @()
    }

    # Remove if already exists, add to front
    $existing = @($history[$Type]) | Where-Object { $_ -ne $Path }
    $history[$Type] = @($Path) + $existing | Select-Object -First $script:MaxHistoryItems

    $history | ConvertTo-Json -Depth 5 | Set-Content $script:HistoryFile -Force
}

function Get-HostBookmarks {
    <#
    .SYNOPSIS
        Gets default host machine bookmarks
    #>
    $projectRoot = Get-ProjectRoot

    return @(
        @{ Name = "Project Root"; Path = $projectRoot }
        @{ Name = "Backups"; Path = (Join-Path $projectRoot "backups") }
        @{ Name = "Data"; Path = (Join-Path $projectRoot "data") }
        @{ Name = "Scripts"; Path = (Join-Path $projectRoot "windows\scripts") }
        @{ Name = "Desktop"; Path = [Environment]::GetFolderPath("Desktop") }
        @{ Name = "Documents"; Path = [Environment]::GetFolderPath("MyDocuments") }
    )
}

function Get-ContainerBookmarks {
    <#
    .SYNOPSIS
        Gets bookmarks for a specific container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if ($script:DefaultContainerBookmarks.ContainsKey($ContainerName)) {
        return $script:DefaultContainerBookmarks[$ContainerName]
    }

    # Default bookmarks for unknown containers
    return @(
        @{ Name = "Root"; Path = "/" }
        @{ Name = "Temp"; Path = "/tmp" }
    )
}

# ============================================
# Windows Forms Dialogs
# ============================================

function Invoke-OpenFileDialog {
    <#
    .SYNOPSIS
        Shows Windows OpenFileDialog
    #>
    param(
        [string]$Title = "Select File",
        [string]$Filter = "All Files|*.*",
        [string]$InitialDirectory
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    $dialog.Multiselect = $false

    if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $dialog.InitialDirectory = $InitialDirectory
    }

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }

    return $null
}

function Invoke-FolderBrowserDialog {
    <#
    .SYNOPSIS
        Shows Windows FolderBrowserDialog
    #>
    param(
        [string]$Title = "Select Folder",
        [string]$InitialDirectory
    )

    Add-Type -AssemblyName System.Windows.Forms

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Title
    $dialog.ShowNewFolderButton = $false

    if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $dialog.SelectedPath = $InitialDirectory
    }

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }

    return $null
}

# ============================================
# Grid View Browser
# ============================================

function Show-GridViewFileBrowser {
    <#
    .SYNOPSIS
        Uses Out-GridView for file selection
    #>
    param(
        [string]$InitialDirectory,
        [string]$FileFilter = "*"
    )

    $currentPath = if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $InitialDirectory
    } else {
        Get-Location
    }

    do {
        $items = @()

        # Parent directory
        $parent = Split-Path $currentPath -Parent
        if ($parent) {
            $items += [PSCustomObject]@{
                Type = "[UP]"
                Name = ".."
                Size = ""
                Path = $parent
            }
        }

        # Directories
        Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
            $items += [PSCustomObject]@{
                Type = "[DIR]"
                Name = $_.Name
                Size = ""
                Path = $_.FullName
            }
        }

        # Files
        Get-ChildItem -Path $currentPath -File -Filter $FileFilter -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
            $sizeStr = if ($_.Length -gt 1MB) { "{0:N1} MB" -f ($_.Length / 1MB) } else { "{0:N1} KB" -f ($_.Length / 1KB) }
            $items += [PSCustomObject]@{
                Type = "[FILE]"
                Name = $_.Name
                Size = $sizeStr
                Path = $_.FullName
            }
        }

        $selected = $items | Out-GridView -Title "Browse: $currentPath (Double-click to select)" -PassThru

        if (-not $selected) {
            return $null
        }

        if ($selected.Type -eq "[UP]" -or $selected.Type -eq "[DIR]") {
            $currentPath = $selected.Path
        } else {
            return $selected.Path
        }

    } while ($true)
}

# ============================================
# Console File Browser (Host)
# ============================================

function Show-HostFileBrowser {
    <#
    .SYNOPSIS
        Console-based file browser for host machine
    #>
    param(
        [string]$InitialDirectory,
        [ValidateSet("File", "Folder")]
        [string]$SelectMode = "File",
        [string]$FileFilter = "*"
    )

    $currentPath = if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $InitialDirectory
    } else {
        (Get-Location).Path
    }

    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host "   File Browser - Host Machine" -ForegroundColor Cyan
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Current: $currentPath" -ForegroundColor Yellow
        Write-Host "  Mode: Select $SelectMode" -ForegroundColor DarkGray
        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

        $items = @()
        $index = 1

        # Parent directory
        $parent = Split-Path $currentPath -Parent
        if ($parent) {
            Write-Host "  [..] [D] .." -ForegroundColor Cyan
        }

        # Get directories
        $dirs = Get-ChildItem -Path $currentPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name
        foreach ($dir in $dirs) {
            $items += @{
                Index = $index
                Name = $dir.Name
                Type = "DIR"
                FullPath = $dir.FullName
            }
            Write-Host "  [$index] [D] $($dir.Name)" -ForegroundColor Cyan
            $index++
        }

        # Get files (only if selecting files)
        if ($SelectMode -eq "File") {
            $files = Get-ChildItem -Path $currentPath -File -Filter $FileFilter -ErrorAction SilentlyContinue | Sort-Object Name
            foreach ($file in $files) {
                $sizeStr = if ($file.Length -gt 1MB) {
                    "{0:N1} MB" -f ($file.Length / 1MB)
                } elseif ($file.Length -gt 1KB) {
                    "{0:N1} KB" -f ($file.Length / 1KB)
                } else {
                    "$($file.Length) B"
                }

                $items += @{
                    Index = $index
                    Name = $file.Name
                    Type = "FILE"
                    Size = $sizeStr
                    FullPath = $file.FullName
                }
                Write-Host "  [$index] [F] $($file.Name) ($sizeStr)" -ForegroundColor White
                $index++
            }
        }

        if ($items.Count -eq 0 -and -not $parent) {
            Write-Host "  (empty or inaccessible)" -ForegroundColor DarkGray
        }

        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Commands:" -ForegroundColor Yellow
        Write-Host "    <number> - Navigate to directory or select file"
        Write-Host "    ..       - Go up one directory"
        Write-Host "    /search  - Search in current directory"
        if ($SelectMode -eq "Folder") {
            Write-Host "    .        - Select current folder"
        }
        Write-Host "    q        - Cancel"
        Write-Host ""

        $input = Read-Host "  Enter choice"

        if ($input -eq "q" -or $input -eq "quit") {
            return $null
        }

        if ($input -eq ".") {
            if ($SelectMode -eq "Folder") {
                return $currentPath
            }
            continue
        }

        if ($input -eq "..") {
            if ($parent) {
                $currentPath = $parent
            }
            continue
        }

        if ($input -match "^/(.+)$") {
            # Search mode
            $searchPattern = $Matches[1]
            Write-Host ""
            Write-Host "  Searching for '$searchPattern'..." -ForegroundColor Yellow
            $searchResults = Get-ChildItem -Path $currentPath -Recurse -Filter "*$searchPattern*" -ErrorAction SilentlyContinue | Select-Object -First 15

            if ($searchResults.Count -gt 0) {
                Write-Host "  Results:" -ForegroundColor Yellow
                $searchIndex = 1
                $searchItems = @()
                foreach ($result in $searchResults) {
                    $relPath = $result.FullName.Replace($currentPath, "").TrimStart("\", "/")
                    $typeStr = if ($result.PSIsContainer) { "[D]" } else { "[F]" }
                    Write-Host "    [$searchIndex] $typeStr $relPath"
                    $searchItems += $result
                    $searchIndex++
                }
                Write-Host ""
                $searchChoice = Read-Host "  Select result (or Enter to cancel)"
                if ($searchChoice -match "^\d+$") {
                    $resultIndex = [int]$searchChoice - 1
                    if ($resultIndex -ge 0 -and $resultIndex -lt $searchItems.Count) {
                        $selected = $searchItems[$resultIndex]
                        if ($selected.PSIsContainer) {
                            $currentPath = $selected.FullName
                        } else {
                            if ($SelectMode -eq "File") {
                                return $selected.FullName
                            }
                        }
                    }
                }
            } else {
                Write-Host "  No results found" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
            continue
        }

        if ($input -match "^\d+$") {
            $selectedIndex = [int]$input
            $selectedItem = $items | Where-Object { $_.Index -eq $selectedIndex }

            if ($selectedItem) {
                if ($selectedItem.Type -eq "DIR") {
                    $currentPath = $selectedItem.FullPath
                } else {
                    if ($SelectMode -eq "File") {
                        return $selectedItem.FullPath
                    }
                }
            }
        }

    } while ($true)
}

# ============================================
# Host File/Folder Selection
# ============================================

function Select-HostFile {
    <#
    .SYNOPSIS
        Interactive file selection from host machine
    .PARAMETER Title
        Dialog title
    .PARAMETER Filter
        File type filter (e.g., "SQL Files|*.sql")
    .PARAMETER InitialDirectory
        Starting directory
    .OUTPUTS
        String - Selected file path, or $null if cancelled
    #>
    [CmdletBinding()]
    param(
        [string]$Title = "Select File",
        [string]$Filter = "All Files|*.*",
        [string]$InitialDirectory
    )

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    $options = @()
    $optionNum = 1

    Write-Host "  Selection method:" -ForegroundColor Yellow

    if (Test-GuiAvailable) {
        Write-Host "  [$optionNum] Windows File Dialog (GUI)"
        $options += "gui"
        $optionNum++
    }

    if (Test-OutGridViewAvailable) {
        Write-Host "  [$optionNum] Grid View Browser"
        $options += "gridview"
        $optionNum++
    }

    Write-Host "  [$optionNum] Console File Browser"
    $options += "console"
    $optionNum++

    Write-Host "  [$optionNum] Enter path manually"
    $options += "manual"

    # Show recent paths
    $recentPaths = Get-RecentPaths -Type "HostFile"
    if ($recentPaths.Count -gt 0) {
        Write-Host ""
        Write-Host "  Recent files:" -ForegroundColor Yellow
        $recentNum = 1
        foreach ($path in $recentPaths | Select-Object -First 5) {
            $shortPath = if ($path.Length -gt 60) { "..." + $path.Substring($path.Length - 57) } else { $path }
            Write-Host "    [R$recentNum] $shortPath" -ForegroundColor DarkGray
            $recentNum++
        }
    }

    # Show bookmarks
    $bookmarks = Get-HostBookmarks
    Write-Host ""
    Write-Host "  Bookmarks:" -ForegroundColor Yellow
    $bmNum = 1
    foreach ($bm in $bookmarks | Select-Object -First 5) {
        Write-Host "    [B$bmNum] $($bm.Name)" -ForegroundColor DarkGray
        $bmNum++
    }

    Write-Host ""
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    # Handle recent path selection
    if ($choice -match "^[Rr](\d+)$") {
        $recentIndex = [int]$Matches[1] - 1
        if ($recentIndex -ge 0 -and $recentIndex -lt $recentPaths.Count) {
            $selectedPath = $recentPaths[$recentIndex]
            if (Test-Path $selectedPath) {
                return $selectedPath
            } else {
                Write-Log "File no longer exists: $selectedPath" -Level WARN
            }
        }
    }

    # Handle bookmark selection (start browsing from bookmark)
    if ($choice -match "^[Bb](\d+)$") {
        $bmIndex = [int]$Matches[1] - 1
        if ($bmIndex -ge 0 -and $bmIndex -lt $bookmarks.Count) {
            $InitialDirectory = $bookmarks[$bmIndex].Path
            $choice = "console"
            $options = @("console")
        }
    }

    if ($choice -eq "0") { return $null }

    $choiceIndex = [int]$choice - 1
    if ($choiceIndex -lt 0 -or $choiceIndex -ge $options.Count) {
        # If not a valid number, try matching the method name
        if ($choice -notin @("gui", "gridview", "console", "manual")) {
            Write-Log "Invalid choice" -Level ERROR
            return $null
        }
        $method = $choice
    } else {
        $method = $options[$choiceIndex]
    }

    $selectedPath = $null

    switch ($method) {
        "gui" {
            $selectedPath = Invoke-OpenFileDialog -Title $Title -Filter $Filter -InitialDirectory $InitialDirectory
        }
        "gridview" {
            # Extract pattern from filter
            $filterPattern = "*"
            if ($Filter -match "\|\*\.(\w+)") {
                $filterPattern = "*.$($Matches[1])"
            }
            $selectedPath = Show-GridViewFileBrowser -InitialDirectory $InitialDirectory -FileFilter $filterPattern
        }
        "console" {
            $filterPattern = "*"
            if ($Filter -match "\|\*\.(\w+)") {
                $filterPattern = "*.$($Matches[1])"
            }
            $selectedPath = Show-HostFileBrowser -InitialDirectory $InitialDirectory -SelectMode "File" -FileFilter $filterPattern
        }
        "manual" {
            Write-Host ""
            $inputPath = Read-Host "  Enter file path"
            $inputPath = $inputPath.Trim('"', "'")
            if (Test-Path $inputPath -PathType Leaf) {
                $selectedPath = $inputPath
            } else {
                Write-Log "File not found: $inputPath" -Level ERROR
            }
        }
    }

    if ($selectedPath) {
        Add-RecentPath -Path $selectedPath -Type "HostFile"
    }

    return $selectedPath
}

function Select-HostFolder {
    <#
    .SYNOPSIS
        Interactive folder selection from host machine
    #>
    param(
        [string]$Title = "Select Folder",
        [string]$InitialDirectory
    )

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   $Title" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    $options = @()
    $optionNum = 1

    Write-Host "  Selection method:" -ForegroundColor Yellow

    if (Test-GuiAvailable) {
        Write-Host "  [$optionNum] Windows Folder Dialog (GUI)"
        $options += "gui"
        $optionNum++
    }

    Write-Host "  [$optionNum] Console Folder Browser"
    $options += "console"
    $optionNum++

    Write-Host "  [$optionNum] Enter path manually"
    $options += "manual"

    # Show bookmarks
    $bookmarks = Get-HostBookmarks
    Write-Host ""
    Write-Host "  Bookmarks:" -ForegroundColor Yellow
    $bmNum = 1
    foreach ($bm in $bookmarks) {
        Write-Host "    [B$bmNum] $($bm.Name): $($bm.Path)" -ForegroundColor DarkGray
        $bmNum++
    }

    Write-Host ""
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    # Handle bookmark selection
    if ($choice -match "^[Bb](\d+)$") {
        $bmIndex = [int]$Matches[1] - 1
        if ($bmIndex -ge 0 -and $bmIndex -lt $bookmarks.Count) {
            $selectedPath = $bookmarks[$bmIndex].Path
            if (Test-Path $selectedPath -PathType Container) {
                return $selectedPath
            }
        }
    }

    if ($choice -eq "0") { return $null }

    $choiceIndex = [int]$choice - 1
    if ($choiceIndex -lt 0 -or $choiceIndex -ge $options.Count) {
        return $null
    }

    $method = $options[$choiceIndex]

    switch ($method) {
        "gui" {
            return Invoke-FolderBrowserDialog -Title $Title -InitialDirectory $InitialDirectory
        }
        "console" {
            return Show-HostFileBrowser -InitialDirectory $InitialDirectory -SelectMode "Folder"
        }
        "manual" {
            Write-Host ""
            $inputPath = Read-Host "  Enter folder path"
            $inputPath = $inputPath.Trim('"', "'")
            if (Test-Path $inputPath -PathType Container) {
                return $inputPath
            } else {
                Write-Log "Folder not found: $inputPath" -Level ERROR
                return $null
            }
        }
    }
}

# ============================================
# Container File Browser
# ============================================

function Show-ContainerFileBrowserEnhanced {
    <#
    .SYNOPSIS
        Enhanced interactive container file browser
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [string]$StartPath = "/",
        [string]$FileFilter,
        [ValidateSet("File", "Folder")]
        [string]$SelectMode = "File"
    )

    $currentPath = $StartPath

    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host "   Container File Browser" -ForegroundColor Cyan
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host "  Container: $ContainerName" -ForegroundColor DarkGray
        Write-Host "  Path: $currentPath" -ForegroundColor Yellow
        Write-Host "  Mode: Select $SelectMode" -ForegroundColor DarkGray
        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

        # Get listing with details
        $lsOutput = docker exec $ContainerName sh -c "ls -la '$currentPath' 2>/dev/null" 2>$null

        if (-not $lsOutput) {
            Write-Host "  Error: Cannot access path" -ForegroundColor Red
            $currentPath = "/"
            Start-Sleep -Seconds 1
            continue
        }

        $items = @()
        $index = 1

        # Add parent directory option
        if ($currentPath -ne "/") {
            Write-Host "  [..] [D] .." -ForegroundColor Cyan
        }

        foreach ($line in $lsOutput) {
            if ($line -match "^([drwx\-]+)\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\S+\s+\d+\s+[\d:]+)\s+(.+)$") {
                $permissions = $Matches[1]
                $size = $Matches[2]
                $name = $Matches[4]

                if ($name -eq "." -or $name -eq "..") { continue }

                $isDir = $permissions.StartsWith("d")

                # Apply file filter if specified (only for files)
                if ($FileFilter -and -not $isDir) {
                    if ($name -notmatch $FileFilter) { continue }
                }

                $sizeStr = if ($isDir) { "" } elseif ([long]$size -gt 1MB) {
                    "{0:N1}M" -f ([long]$size / 1MB)
                } elseif ([long]$size -gt 1KB) {
                    "{0:N1}K" -f ([long]$size / 1KB)
                } else {
                    "${size}B"
                }

                $items += @{
                    Index = $index
                    Name = $name
                    Type = if ($isDir) { "DIR" } else { "FILE" }
                    Size = $sizeStr
                    FullPath = "$currentPath/$name" -replace "//", "/"
                }

                $typeChar = if ($isDir) { "D" } else { "F" }
                $color = if ($isDir) { "Cyan" } else { "White" }
                $sizeDisplay = if ($sizeStr) { "($sizeStr)" } else { "" }
                Write-Host "  [$index] [$typeChar] $name $sizeDisplay" -ForegroundColor $color
                $index++
            }
        }

        if ($items.Count -eq 0) {
            Write-Host "  (empty directory)" -ForegroundColor DarkGray
        }

        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Commands:" -ForegroundColor Yellow
        Write-Host "    <num>    - Enter directory or select file"
        Write-Host "    ..       - Go up one directory"
        Write-Host "    cat <n>  - Preview file contents"
        Write-Host "    /text    - Search in current directory"
        if ($SelectMode -eq "Folder") {
            Write-Host "    .        - Select current folder"
        }
        Write-Host "    q        - Cancel selection"
        Write-Host ""

        $cmd = Read-Host "  Command"

        if ($cmd -eq "q" -or $cmd -eq "quit") {
            return $null
        }

        if ($cmd -eq ".") {
            if ($SelectMode -eq "Folder") {
                return $currentPath
            }
            continue
        }

        if ($cmd -eq "..") {
            if ($currentPath -ne "/") {
                $parent = Split-Path $currentPath -Parent
                $currentPath = if ($parent) { $parent } else { "/" }
            }
            continue
        }

        # Preview command
        if ($cmd -match "^cat\s+(\d+)$") {
            $catIndex = [int]$Matches[1]
            $catItem = $items | Where-Object { $_.Index -eq $catIndex -and $_.Type -eq "FILE" }
            if ($catItem) {
                Write-Host ""
                Write-Host "  Preview: $($catItem.FullPath)" -ForegroundColor Yellow
                Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
                docker exec $ContainerName sh -c "head -30 '$($catItem.FullPath)' 2>/dev/null"
                Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            continue
        }

        # Search command
        if ($cmd -match "^/(.+)$") {
            $searchPattern = $Matches[1]
            Write-Host ""
            Write-Host "  Searching for '$searchPattern'..." -ForegroundColor Yellow
            $searchResults = docker exec $ContainerName sh -c "find '$currentPath' -maxdepth 3 -name '*$searchPattern*' 2>/dev/null | head -15" 2>$null

            if ($searchResults) {
                Write-Host "  Results:" -ForegroundColor Yellow
                $searchIndex = 1
                $searchItems = @()
                foreach ($result in $searchResults -split "`n") {
                    if ($result) {
                        Write-Host "    [$searchIndex] $result"
                        $searchItems += $result
                        $searchIndex++
                    }
                }
                Write-Host ""
                $searchChoice = Read-Host "  Select result (or Enter to cancel)"
                if ($searchChoice -match "^\d+$") {
                    $sIndex = [int]$searchChoice - 1
                    if ($sIndex -ge 0 -and $sIndex -lt $searchItems.Count) {
                        $selectedResult = $searchItems[$sIndex]
                        $isResultDir = docker exec $ContainerName sh -c "[ -d '$selectedResult' ] && echo 'dir'" 2>$null
                        if ($isResultDir -eq "dir") {
                            $currentPath = $selectedResult
                        } else {
                            if ($SelectMode -eq "File") {
                                Add-RecentPath -Path $selectedResult -Type "Container:$ContainerName"
                                return $selectedResult
                            }
                        }
                    }
                }
            } else {
                Write-Host "  No results found" -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
            continue
        }

        # Number selection
        if ($cmd -match "^\d+$") {
            $selectedIndex = [int]$cmd
            $selectedItem = $items | Where-Object { $_.Index -eq $selectedIndex }

            if ($selectedItem) {
                if ($selectedItem.Type -eq "DIR") {
                    $currentPath = $selectedItem.FullPath
                } else {
                    if ($SelectMode -eq "File") {
                        Add-RecentPath -Path $selectedItem.FullPath -Type "Container:$ContainerName"
                        return $selectedItem.FullPath
                    }
                }
            }
        }

    } while ($true)
}

function Select-ContainerFile {
    <#
    .SYNOPSIS
        Interactive file selection from a Docker container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [string]$InitialPath,
        [string]$FileFilter
    )

    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $null
    }

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Select File from Container" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Container: $ContainerName" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Selection method:" -ForegroundColor Yellow
    Write-Host "  [1] Interactive browser"
    Write-Host "  [2] Enter path manually"

    # Show bookmarks for this container
    $bookmarks = Get-ContainerBookmarks -ContainerName $ContainerName
    if ($bookmarks.Count -gt 0) {
        Write-Host ""
        Write-Host "  Quick access:" -ForegroundColor Yellow
        $bmNum = 1
        foreach ($bm in $bookmarks) {
            Write-Host "    [B$bmNum] $($bm.Name): $($bm.Path)" -ForegroundColor DarkGray
            $bmNum++
        }
    }

    # Show recent paths
    $recentPaths = Get-RecentPaths -Type "Container:$ContainerName"
    if ($recentPaths.Count -gt 0) {
        Write-Host ""
        Write-Host "  Recent:" -ForegroundColor Yellow
        $recentNum = 1
        foreach ($path in $recentPaths | Select-Object -First 3) {
            Write-Host "    [R$recentNum] $path" -ForegroundColor DarkGray
            $recentNum++
        }
    }

    Write-Host ""
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    # Handle bookmark selection
    if ($choice -match "^[Bb](\d+)$") {
        $bmIndex = [int]$Matches[1] - 1
        if ($bmIndex -ge 0 -and $bmIndex -lt $bookmarks.Count) {
            $startPath = $bookmarks[$bmIndex].Path
            return Show-ContainerFileBrowserEnhanced -ContainerName $ContainerName -StartPath $startPath -FileFilter $FileFilter
        }
    }

    # Handle recent path selection
    if ($choice -match "^[Rr](\d+)$") {
        $recentIndex = [int]$Matches[1] - 1
        if ($recentIndex -ge 0 -and $recentIndex -lt $recentPaths.Count) {
            $selectedPath = $recentPaths[$recentIndex]
            $exists = docker exec $ContainerName sh -c "[ -e '$selectedPath' ] && echo 'exists'" 2>$null
            if ($exists -eq "exists") {
                return $selectedPath
            } else {
                Write-Log "File no longer exists in container" -Level WARN
            }
        }
    }

    if ($choice -eq "0") { return $null }

    switch ($choice) {
        "1" {
            $startPath = if ($InitialPath) { $InitialPath } else { "/" }
            return Show-ContainerFileBrowserEnhanced -ContainerName $ContainerName -StartPath $startPath -FileFilter $FileFilter
        }
        "2" {
            Write-Host ""
            $inputPath = Read-Host "  Enter file path in container"
            $exists = docker exec $ContainerName sh -c "[ -e '$inputPath' ] && echo 'exists'" 2>$null
            if ($exists -eq "exists") {
                Add-RecentPath -Path $inputPath -Type "Container:$ContainerName"
                return $inputPath
            } else {
                Write-Log "File not found in container: $inputPath" -Level ERROR
                return $null
            }
        }
        default {
            return $null
        }
    }
}

function Select-ContainerPath {
    <#
    .SYNOPSIS
        Select a path (folder) in a container for destination
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [string]$InitialPath
    )

    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $null
    }

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Select Destination in Container" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  Container: $ContainerName" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Selection method:" -ForegroundColor Yellow
    Write-Host "  [1] Interactive browser"
    Write-Host "  [2] Enter path manually"

    # Show bookmarks
    $bookmarks = Get-ContainerBookmarks -ContainerName $ContainerName
    if ($bookmarks.Count -gt 0) {
        Write-Host ""
        Write-Host "  Quick access:" -ForegroundColor Yellow
        $bmNum = 1
        foreach ($bm in $bookmarks) {
            Write-Host "    [B$bmNum] $($bm.Name): $($bm.Path)" -ForegroundColor DarkGray
            $bmNum++
        }
    }

    Write-Host ""
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    # Handle bookmark selection
    if ($choice -match "^[Bb](\d+)$") {
        $bmIndex = [int]$Matches[1] - 1
        if ($bmIndex -ge 0 -and $bmIndex -lt $bookmarks.Count) {
            return $bookmarks[$bmIndex].Path
        }
    }

    if ($choice -eq "0") { return $null }

    switch ($choice) {
        "1" {
            $startPath = if ($InitialPath) { $InitialPath } else { "/" }
            return Show-ContainerFileBrowserEnhanced -ContainerName $ContainerName -StartPath $startPath -SelectMode "Folder"
        }
        "2" {
            Write-Host ""
            $inputPath = Read-Host "  Enter destination path in container"
            return $inputPath
        }
        default {
            return $null
        }
    }
}

# ============================================
# File Preview and Validation
# ============================================

function Show-FilePreview {
    <#
    .SYNOPSIS
        Shows preview of file contents before operations
    #>
    param(
        [string]$ContainerName,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [int]$MaxLines = 20
    )

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   File Preview" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "  File: $FilePath" -ForegroundColor DarkGray
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    if ($ContainerName) {
        # Container file
        $fileInfo = docker exec $ContainerName sh -c "stat -c '%s bytes, modified: %y' '$FilePath' 2>/dev/null" 2>$null
        if ($fileInfo) {
            Write-Host "  Info: $fileInfo" -ForegroundColor DarkGray
        }
        Write-Host ""

        docker exec $ContainerName sh -c "head -$MaxLines '$FilePath' 2>/dev/null" 2>$null | ForEach-Object {
            Write-Host "  $_"
        }
    } else {
        # Host file
        if (Test-Path $FilePath) {
            $fileInfo = Get-Item $FilePath
            Write-Host "  Size: $($fileInfo.Length) bytes" -ForegroundColor DarkGray
            Write-Host "  Modified: $($fileInfo.LastWriteTime)" -ForegroundColor DarkGray
            Write-Host ""

            try {
                Get-Content $FilePath -Head $MaxLines -ErrorAction Stop | ForEach-Object {
                    Write-Host "  $_"
                }
            } catch {
                Write-Host "  (Cannot preview file contents)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  File not found" -ForegroundColor Red
        }
    }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
}

function Test-FileOperation {
    <#
    .SYNOPSIS
        Validates a file operation before execution
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Copy", "Delete", "Edit", "Execute")]
        [string]$Operation,

        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$ContainerName
    )

    $result = @{
        IsValid = $true
        Warnings = @()
        Errors = @()
    }

    switch ($Operation) {
        "Copy" {
            if ($ContainerName) {
                # Source is container path
                $exists = docker exec $ContainerName sh -c "[ -e '$SourcePath' ] && echo 'exists'" 2>$null
                if ($exists -ne "exists") {
                    $result.Errors += "Source file does not exist in container: $SourcePath"
                    $result.IsValid = $false
                }
            } else {
                if (-not (Test-Path $SourcePath)) {
                    $result.Errors += "Source file does not exist: $SourcePath"
                    $result.IsValid = $false
                } else {
                    $fileSize = (Get-Item $SourcePath).Length
                    if ($fileSize -gt 100MB) {
                        $result.Warnings += "Large file ($([math]::Round($fileSize/1MB, 1)) MB) - copy may take time"
                    }
                }
            }
        }
        "Delete" {
            $systemPaths = @("/bin", "/sbin", "/usr", "/etc", "/lib", "/var/lib")
            foreach ($sysPath in $systemPaths) {
                if ($SourcePath.StartsWith($sysPath)) {
                    $result.Warnings += "WARNING: Path is in system directory: $sysPath"
                    break
                }
            }
        }
        "Execute" {
            if (-not (Test-Path $SourcePath)) {
                $result.Errors += "Script file not found: $SourcePath"
                $result.IsValid = $false
            } else {
                $ext = [System.IO.Path]::GetExtension($SourcePath).ToLower()
                $validExtensions = @(".sql", ".py", ".sh", ".ps1")
                if ($ext -notin $validExtensions) {
                    $result.Warnings += "Unusual file extension: $ext"
                }
            }
        }
    }

    return $result
}

# ============================================
# File Type Filters
# ============================================

function Get-FileFilter {
    <#
    .SYNOPSIS
        Gets file filter string for common file types
    #>
    param(
        [ValidateSet("SQL", "Python", "Config", "Backup", "All")]
        [string]$Type = "All"
    )

    switch ($Type) {
        "SQL" { return "SQL Files|*.sql|All Files|*.*" }
        "Python" { return "Python Files|*.py|All Files|*.*" }
        "Config" { return "Config Files|*.json;*.yaml;*.yml;*.ini;*.conf;*.env|All Files|*.*" }
        "Backup" { return "Backup Files|*.sql;*.dump;*.bak|All Files|*.*" }
        "All" { return "All Files|*.*" }
    }
}
