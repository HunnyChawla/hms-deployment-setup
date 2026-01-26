#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Docker Deployment Orchestrator for Windows
.DESCRIPTION
    Main menu-driven interface for managing HMS Docker deployment.
    Provides one-click access to all deployment, backup, and management functions.
#>

# Script location detection
$script:WindowsDir = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent $WindowsDir
$script:ScriptsDir = Join-Path $WindowsDir "scripts"

# Source common functions
. (Join-Path $ScriptsDir "common.ps1")

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   HMS Docker Deployment - Windows Setup" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Project: $script:ProjectRoot" -ForegroundColor DarkGray
    Write-Host ""
}

function Show-MainMenu {
    Write-Host "  Select an option:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Full Setup (First Time)"
    Write-Host "      - Initialize directories" -ForegroundColor DarkGray
    Write-Host "      - Pull images & start services" -ForegroundColor DarkGray
    Write-Host "      - Setup auto-start service (NSSM)" -ForegroundColor DarkGray
    Write-Host "      - Configure daily backups (2 AM)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Deploy/Update Services"
    Write-Host "      - Pull latest images" -ForegroundColor DarkGray
    Write-Host "      - Restart all containers" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] " -NoNewline -ForegroundColor Yellow
    Write-Host "Backup Database Now"
    Write-Host ""
    Write-Host "  [4] " -NoNewline -ForegroundColor Yellow
    Write-Host "Restore Database"
    Write-Host ""
    Write-Host "  [5] " -NoNewline -ForegroundColor Yellow
    Write-Host "Docker Cleanup"
    Write-Host ""
    Write-Host "  [6] " -NoNewline -ForegroundColor Yellow
    Write-Host "Service Management (NSSM)"
    Write-Host "      - Install/Start/Stop/Remove" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [7] " -NoNewline -ForegroundColor Yellow
    Write-Host "View Status & Logs"
    Write-Host ""
    Write-Host "  [8] " -NoNewline -ForegroundColor Yellow
    Write-Host "Stop/Remove Containers"
    Write-Host ""
    Write-Host "  [0] " -NoNewline -ForegroundColor Red
    Write-Host "Exit"
    Write-Host ""
}

function Show-ServiceMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   NSSM Service Management" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Install Service"
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Start Service"
    Write-Host "  [3] " -NoNewline -ForegroundColor Yellow
    Write-Host "Stop Service"
    Write-Host "  [4] " -NoNewline -ForegroundColor Yellow
    Write-Host "Restart Service"
    Write-Host "  [5] " -NoNewline -ForegroundColor Yellow
    Write-Host "Remove Service"
    Write-Host "  [6] " -NoNewline -ForegroundColor Yellow
    Write-Host "Check Status"
    Write-Host ""
    Write-Host "  [0] " -NoNewline -ForegroundColor Red
    Write-Host "Back to Main Menu"
    Write-Host ""
}

function Show-CleanupMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Docker Cleanup" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Minimal Cleanup"
    Write-Host "      - Remove stopped containers" -ForegroundColor DarkGray
    Write-Host "      - Remove dangling images" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Standard Cleanup"
    Write-Host "      - All of minimal cleanup" -ForegroundColor DarkGray
    Write-Host "      - Remove unused networks" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] " -NoNewline -ForegroundColor Yellow
    Write-Host "Aggressive Cleanup (Caution!)"
    Write-Host "      - Remove all unused images" -ForegroundColor DarkGray
    Write-Host "      - Remove build cache" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [4] " -NoNewline -ForegroundColor Yellow
    Write-Host "Dry Run (Preview only)"
    Write-Host ""
    Write-Host "  [0] " -NoNewline -ForegroundColor Red
    Write-Host "Back to Main Menu"
    Write-Host ""
}

function Invoke-FullSetup {
    Write-Host "`n  Running Full Setup..." -ForegroundColor Cyan
    Write-Host "  ======================" -ForegroundColor Cyan

    # Step 1: Initialize directories
    Write-Host "`n  [Step 1/4] Initializing directories..." -ForegroundColor Yellow
    & (Join-Path $ScriptsDir "init-directories.ps1")

    # Step 2: Deploy services
    Write-Host "`n  [Step 2/4] Deploying services..." -ForegroundColor Yellow
    & (Join-Path $ScriptsDir "deploy.ps1")

    # Step 3: Install NSSM service (optional)
    Write-Host "`n  [Step 3/4] NSSM Service Setup" -ForegroundColor Yellow
    $installNssm = Read-Host "  Install auto-start service? (y/n)"
    if ($installNssm -eq 'y') {
        & (Join-Path $ScriptsDir "install-service.ps1") -Action install
    } else {
        Write-Host "  Skipped NSSM installation." -ForegroundColor DarkGray
    }

    # Step 4: Setup backup schedule (optional)
    Write-Host "`n  [Step 4/4] Backup Schedule Setup" -ForegroundColor Yellow
    $setupBackup = Read-Host "  Setup daily 2 AM backups? (y/n)"
    if ($setupBackup -eq 'y') {
        & (Join-Path $ScriptsDir "setup-backup-schedule.ps1")
    } else {
        Write-Host "  Skipped backup schedule." -ForegroundColor DarkGray
    }

    Write-Host "`n  Full Setup Complete!" -ForegroundColor Green
    Write-Host ""
    Pause-ForUser
}

function Invoke-Deploy {
    Write-Host "`n  Deploying Services..." -ForegroundColor Cyan
    & (Join-Path $ScriptsDir "deploy.ps1")
    Pause-ForUser
}

function Invoke-Backup {
    Write-Host "`n  Creating Database Backup..." -ForegroundColor Cyan
    & (Join-Path $ScriptsDir "backup-database.ps1")
    Pause-ForUser
}

function Invoke-Restore {
    Write-Host "`n  Database Restore" -ForegroundColor Cyan
    & (Join-Path $ScriptsDir "restore-database.ps1")
    Pause-ForUser
}

function Invoke-CleanupMenu {
    do {
        Show-CleanupMenu
        $choice = Read-Host "  Enter choice [0-4]"

        switch ($choice) {
            "1" {
                & (Join-Path $ScriptsDir "cleanup.ps1") -Level minimal
                Pause-ForUser
            }
            "2" {
                & (Join-Path $ScriptsDir "cleanup.ps1") -Level standard
                Pause-ForUser
            }
            "3" {
                & (Join-Path $ScriptsDir "cleanup.ps1") -Level aggressive
                Pause-ForUser
            }
            "4" {
                & (Join-Path $ScriptsDir "cleanup.ps1") -Level standard -DryRun
                Pause-ForUser
            }
            "0" { return }
            default {
                Write-Host "  Invalid choice. Please try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Invoke-ServiceMenu {
    do {
        Show-ServiceMenu
        $choice = Read-Host "  Enter choice [0-6]"

        switch ($choice) {
            "1" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action install
                Pause-ForUser
            }
            "2" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action start
                Pause-ForUser
            }
            "3" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action stop
                Pause-ForUser
            }
            "4" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action restart
                Pause-ForUser
            }
            "5" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action remove
                Pause-ForUser
            }
            "6" {
                & (Join-Path $ScriptsDir "install-service.ps1") -Action status
                Pause-ForUser
            }
            "0" { return }
            default {
                Write-Host "  Invalid choice. Please try again." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

function Show-Status {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   HMS Status & Logs" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check Docker
    Write-Host "  Docker Status:" -ForegroundColor Yellow
    if (Test-DockerRunning) {
        Write-Host "    Docker is running" -ForegroundColor Green
    } else {
        Write-Host "    Docker is NOT running!" -ForegroundColor Red
        $startDocker = Read-Host "  Start Docker Desktop? (y/n)"
        if ($startDocker -eq 'y') {
            Start-DockerDesktop
        }
        Pause-ForUser
        return
    }

    # Get container names
    $containers = Get-HmsContainerNames
    $containerList = @($containers.Postgres, $containers.Backend, $containers.Frontend)

    Write-Host ""
    Write-Host "  Container Health Status:" -ForegroundColor Yellow
    Write-Host "  -------------------------" -ForegroundColor DarkGray

    $unhealthyContainers = @()
    $index = 1
    foreach ($containerName in $containerList) {
        $status = Get-ContainerStatus -ContainerName $containerName
        $health = Get-ContainerHealth -ContainerName $containerName

        Write-Host "    [$index] $containerName" -NoNewline

        if ($status -eq "running") {
            if ($health -eq "healthy") {
                Write-Host " - running (healthy)" -ForegroundColor Green
            } elseif ($health -eq "unhealthy") {
                Write-Host " - running (UNHEALTHY)" -ForegroundColor Red
                $unhealthyContainers += $containerName
            } else {
                Write-Host " - running ($health)" -ForegroundColor Yellow
            }
        } elseif ($status -eq "not found") {
            Write-Host " - not found" -ForegroundColor DarkGray
        } else {
            Write-Host " - $status" -ForegroundColor Yellow
        }
        $index++
    }

    # Show warning for unhealthy containers
    if ($unhealthyContainers.Count -gt 0) {
        Write-Host ""
        Write-Host "  WARNING: Unhealthy containers detected!" -ForegroundColor Red
        Write-Host "  View their logs to troubleshoot issues." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "  [1] View logs - hms-postgres"
    Write-Host "  [2] View logs - hms-backend"
    Write-Host "  [3] View logs - hospital-ui"
    Write-Host "  [4] View ALL logs (live, Ctrl+C to stop)"
    Write-Host "  [5] Save logs to file"
    Write-Host "  [0] Back to main menu"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    switch ($choice) {
        "1" {
            Show-ContainerLogs -ContainerName $containers.Postgres -TailLines 100
            Pause-ForUser
        }
        "2" {
            Show-ContainerLogs -ContainerName $containers.Backend -TailLines 100
            Pause-ForUser
        }
        "3" {
            Show-ContainerLogs -ContainerName $containers.Frontend -TailLines 100
            Pause-ForUser
        }
        "4" {
            Push-Location $script:ProjectRoot
            Write-Host ""
            Write-Host "  Showing live logs (Ctrl+C to stop)..." -ForegroundColor Yellow
            docker-compose logs -f --tail=50
            Pop-Location
        }
        "5" {
            Write-Host ""
            foreach ($containerName in $containerList) {
                $logFile = Show-ContainerLogs -ContainerName $containerName -TailLines 500 -SaveToFile
            }
            Write-Host ""
            Write-Log "Logs saved to: $(Join-Path $script:ProjectRoot 'data\logs')" -Level SUCCESS
            Pause-ForUser
        }
    }
}

function Show-StopMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Stop/Remove Containers" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] " -NoNewline -ForegroundColor Yellow
    Write-Host "Stop containers (keep data)"
    Write-Host "      - Gracefully stops all HMS containers" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [2] " -NoNewline -ForegroundColor Yellow
    Write-Host "Remove containers (keep data)"
    Write-Host "      - Stops and removes containers" -ForegroundColor DarkGray
    Write-Host "      - Data in ./data is preserved" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  [3] " -NoNewline -ForegroundColor Red
    Write-Host "Remove containers AND data (DANGER!)"
    Write-Host "      - Removes everything including database" -ForegroundColor Red
    Write-Host ""
    Write-Host "  [0] " -NoNewline -ForegroundColor DarkGray
    Write-Host "Back to main menu"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    switch ($choice) {
        "1" {
            Stop-HmsContainers
            Pause-ForUser
        }
        "2" {
            Remove-HmsContainers
            Pause-ForUser
        }
        "3" {
            Write-Host ""
            Write-Host "  ========================================" -ForegroundColor Red
            Write-Host "   WARNING: This will DELETE ALL DATA!" -ForegroundColor Red
            Write-Host "  ========================================" -ForegroundColor Red
            Write-Host ""
            Write-Host "  This includes:" -ForegroundColor Yellow
            Write-Host "    - Database (all records lost)" -ForegroundColor Yellow
            Write-Host "    - Uploaded files" -ForegroundColor Yellow
            Write-Host "    - Application logs" -ForegroundColor Yellow
            Write-Host ""
            $confirm = Read-Host "  Type 'DELETE' to confirm"
            if ($confirm -eq "DELETE") {
                Remove-HmsContainers
                $dataPath = Join-Path $script:ProjectRoot "data"
                if (Test-Path $dataPath) {
                    Remove-Item -Recurse -Force $dataPath
                    Write-Log "Data directory removed" -Level SUCCESS
                }
            } else {
                Write-Log "Operation cancelled" -Level WARN
            }
            Pause-ForUser
        }
    }
}

function Pause-ForUser {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# Check Docker at startup
Write-Host ""
Write-Host "  Checking Docker status..." -ForegroundColor DarkGray
if (-not (Test-DockerRunning)) {
    Write-Host ""
    Write-Host "  Docker is not running!" -ForegroundColor Red
    Write-Host ""
    $startDocker = Read-Host "  Start Docker Desktop automatically? (y/n)"
    if ($startDocker -eq 'y') {
        if (-not (Start-DockerDesktop -TimeoutSeconds 180)) {
            Write-Host ""
            Write-Host "  Failed to start Docker. Please start Docker Desktop manually and try again." -ForegroundColor Red
            Pause-ForUser
            exit 1
        }
    } else {
        Write-Host ""
        Write-Host "  Please start Docker Desktop and run this script again." -ForegroundColor Yellow
        Pause-ForUser
        exit 0
    }
}

# Main loop
do {
    Show-Banner
    Show-MainMenu

    $choice = Read-Host "  Enter choice [0-8]"

    switch ($choice) {
        "1" { Invoke-FullSetup }
        "2" { Invoke-Deploy }
        "3" { Invoke-Backup }
        "4" { Invoke-Restore }
        "5" { Invoke-CleanupMenu }
        "6" { Invoke-ServiceMenu }
        "7" { Show-Status }
        "8" { Show-StopMenu }
        "0" {
            Write-Host "`n  Goodbye!" -ForegroundColor Green
            exit 0
        }
        default {
            Write-Host "  Invalid choice. Please try again." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
