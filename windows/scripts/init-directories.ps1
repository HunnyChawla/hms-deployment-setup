#Requires -Version 5.1
<#
.SYNOPSIS
    Initialize directory structure for HMS Docker deployment
.DESCRIPTION
    Creates all required directories for bind mounts and backups.
    Safe to run multiple times - will not overwrite existing data.
#>

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$ProjectRoot = Get-ProjectRoot

Write-Step "Initializing directory structure"

# Directory structure to create
$directories = @(
    "data\postgres",
    "data\uploads",
    "data\logs",
    "backups",
    "linux"
)

foreach ($dir in $directories) {
    $fullPath = Join-Path $ProjectRoot $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
        Write-SubStep "Created: $dir"
    } else {
        Write-SubStep "Exists:  $dir"
    }
}

# Create .gitkeep files to preserve directories in git
$gitkeepLocations = @(
    "backups\.gitkeep",
    "linux\.gitkeep"
)

foreach ($gitkeep in $gitkeepLocations) {
    $fullPath = Join-Path $ProjectRoot $gitkeep
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType File -Path $fullPath -Force | Out-Null
    }
}

Write-Log "Directory initialization complete" -Level SUCCESS
