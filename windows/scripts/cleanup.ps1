#Requires -Version 5.1
<#
.SYNOPSIS
    Docker cleanup script with safety checks
.DESCRIPTION
    Cleans unused Docker resources while protecting HMS containers and data.
    Three cleanup levels available: minimal, standard, aggressive.
.PARAMETER Level
    Cleanup level: minimal, standard, aggressive
.PARAMETER DryRun
    Show what would be cleaned without executing
#>

[CmdletBinding()]
param(
    [ValidateSet("minimal", "standard", "aggressive")]
    [string]$Level = "standard",

    [switch]$DryRun
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

function Show-DiskUsage {
    Write-Host ""
    Write-Host "  Docker Disk Usage:" -ForegroundColor Cyan
    docker system df
    Write-Host ""
}

function Invoke-CleanupCommand {
    param(
        [string]$Command,
        [string]$Description
    )

    Write-Step $Description
    if ($DryRun) {
        Write-Host "    [DRY RUN] Would execute: $Command" -ForegroundColor DarkGray
    } else {
        Invoke-Expression $Command
    }
}

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   Docker Cleanup - Level: $Level" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "  [DRY RUN MODE - No changes will be made]" -ForegroundColor Magenta
}

# Check Docker is running
if (-not (Test-DockerRunning)) {
    Write-Log "Docker is not running. Please start Docker Desktop." -Level ERROR
    exit 1
}

# Show current disk usage
Show-DiskUsage

# Show HMS container status
$containers = Get-HmsContainerNames
$runningContainers = docker ps --format "{{.Names}}"

Write-Host "  HMS Container Status:" -ForegroundColor Cyan
foreach ($key in $containers.Keys) {
    $containerName = $containers[$key]
    if ($runningContainers -contains $containerName) {
        Write-Host "    $containerName : " -NoNewline
        Write-Host "RUNNING (protected)" -ForegroundColor Green
    } else {
        Write-Host "    $containerName : " -NoNewline
        Write-Host "NOT RUNNING" -ForegroundColor Yellow
    }
}
Write-Host ""

# Perform cleanup based on level
switch ($Level) {
    "minimal" {
        Invoke-CleanupCommand "docker container prune -f" "Removing stopped containers"
        Invoke-CleanupCommand "docker image prune -f" "Removing dangling images"
    }

    "standard" {
        Invoke-CleanupCommand "docker container prune -f" "Removing stopped containers"
        Invoke-CleanupCommand "docker image prune -f" "Removing dangling images"
        Invoke-CleanupCommand "docker network prune -f" "Removing unused networks"
    }

    "aggressive" {
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Red
        Write-Host "   WARNING: Aggressive Cleanup" -ForegroundColor Red
        Write-Host "  ========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "  This will remove:" -ForegroundColor Yellow
        Write-Host "    - All stopped containers" -ForegroundColor Yellow
        Write-Host "    - All unused images (not just dangling)" -ForegroundColor Yellow
        Write-Host "    - All unused networks" -ForegroundColor Yellow
        Write-Host "    - Build cache" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  This will NOT remove:" -ForegroundColor Green
        Write-Host "    - Running containers" -ForegroundColor Green
        Write-Host "    - Data volumes (./data directory)" -ForegroundColor Green
        Write-Host "    - Backup files (./backups directory)" -ForegroundColor Green
        Write-Host ""

        if (-not $DryRun) {
            $confirm = Read-Host "  Type 'yes' to proceed"
            if ($confirm -ne "yes") {
                Write-Host ""
                Write-Log "Cleanup cancelled." -Level WARN
                exit 0
            }
        }

        Invoke-CleanupCommand "docker system prune -af" "Running aggressive cleanup"
    }
}

# Show final disk usage
Write-Host ""
Write-Host "  Cleanup Results:" -ForegroundColor Cyan
Show-DiskUsage

Write-Log "Cleanup complete" -Level SUCCESS

# Safety reminder
Write-Host ""
Write-Host "  Note: Your HMS data in ./data and ./backups is always preserved." -ForegroundColor DarkGray
Write-Host ""
