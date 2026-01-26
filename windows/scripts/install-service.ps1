#Requires -Version 5.1
<#
.SYNOPSIS
    Install and manage HMS Docker service using NSSM
.DESCRIPTION
    Creates a Windows service that automatically starts HMS Docker containers
    on system boot using NSSM (Non-Sucking Service Manager).
.PARAMETER Action
    Action to perform: install, start, stop, restart, remove, status
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("install", "start", "stop", "restart", "remove", "status")]
    [string]$Action
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$ServiceName = "HMSDocker"
$ProjectRoot = Get-ProjectRoot
$DeployScript = Join-Path $PSScriptRoot "deploy.ps1"
$LogDir = Join-Path $ProjectRoot "data\logs"
$NssmExe = Get-NssmPath

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Service Management (NSSM)" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Service Name: $ServiceName" -ForegroundColor DarkGray
Write-Host "  Action:       $Action" -ForegroundColor DarkGray
Write-Host ""

# Check NSSM is installed
if (-not (Test-NssmInstalled)) {
    Write-Host (Get-NssmInstallInstructions) -ForegroundColor Yellow
    exit 1
}

# Check for Admin rights for install/remove
if ($Action -in @("install", "remove")) {
    if (-not (Test-IsAdmin)) {
        Write-Log "This action requires Administrator privileges." -Level ERROR
        Write-Host ""
        Write-Host "  Please run as Administrator:" -ForegroundColor Yellow
        Write-Host "    1. Right-click on hms-setup.bat" -ForegroundColor DarkGray
        Write-Host "    2. Select 'Run as administrator'" -ForegroundColor DarkGray
        Write-Host ""
        exit 1
    }
}

function Install-HmsService {
    Write-Step "Installing $ServiceName service"

    # Check if already installed
    $existingStatus = & $NssmExe status $ServiceName 2>&1
    if ($existingStatus -notmatch "Can't open service") {
        Write-Log "Service already exists. Remove it first or use 'restart'." -Level WARN
        return
    }

    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    # Install service pointing to PowerShell running deploy.ps1 with NoPull flag
    # (We don't want to pull on every startup, just restart containers)
    Write-SubStep "Registering service..."
    & $NssmExe install $ServiceName "powershell.exe"

    Write-SubStep "Configuring service parameters..."
    & $NssmExe set $ServiceName AppParameters "-ExecutionPolicy Bypass -NoProfile -File `"$DeployScript`" -NoPull"
    & $NssmExe set $ServiceName AppDirectory $PSScriptRoot

    Write-SubStep "Setting service properties..."
    & $NssmExe set $ServiceName DisplayName "HMS Docker Deployment Service"
    & $NssmExe set $ServiceName Description "Starts HMS Docker containers on system boot"
    & $NssmExe set $ServiceName Start SERVICE_AUTO_START
    & $NssmExe set $ServiceName ObjectName LocalSystem

    # Exit/restart behavior
    & $NssmExe set $ServiceName AppExit Default Exit
    & $NssmExe set $ServiceName AppRestartDelay 60000

    # Logging
    Write-SubStep "Configuring logging..."
    $stdoutLog = Join-Path $LogDir "service-stdout.log"
    $stderrLog = Join-Path $LogDir "service-stderr.log"
    & $NssmExe set $ServiceName AppStdout $stdoutLog
    & $NssmExe set $ServiceName AppStderr $stderrLog
    & $NssmExe set $ServiceName AppRotateFiles 1
    & $NssmExe set $ServiceName AppRotateBytes 5242880

    Write-Host ""
    Write-Log "Service installed successfully" -Level SUCCESS
    Write-Host ""
    Write-Host "  The service is configured to:" -ForegroundColor Cyan
    Write-Host "    - Start automatically on system boot"
    Write-Host "    - Restart HMS containers (without pulling new images)"
    Write-Host "    - Log output to: $LogDir"
    Write-Host ""
    Write-Host "  To start the service now, run:" -ForegroundColor Yellow
    Write-Host "    .\install-service.ps1 -Action start" -ForegroundColor DarkGray
    Write-Host ""
}

function Remove-HmsService {
    Write-Step "Removing $ServiceName service"

    # Stop first if running
    Write-SubStep "Stopping service if running..."
    & $NssmExe stop $ServiceName 2>$null

    Write-SubStep "Removing service..."
    & $NssmExe remove $ServiceName confirm

    Write-Host ""
    Write-Log "Service removed" -Level SUCCESS
}

function Get-HmsServiceStatus {
    Write-Step "Checking $ServiceName service status"

    $status = & $NssmExe status $ServiceName 2>&1

    if ($status -match "Can't open service") {
        Write-Host ""
        Write-Host "  Status: " -NoNewline
        Write-Host "NOT INSTALLED" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  To install, run:" -ForegroundColor DarkGray
        Write-Host "    .\install-service.ps1 -Action install (as Administrator)" -ForegroundColor DarkGray
    } elseif ($status -match "SERVICE_RUNNING") {
        Write-Host ""
        Write-Host "  Status: " -NoNewline
        Write-Host "RUNNING" -ForegroundColor Green
    } elseif ($status -match "SERVICE_STOPPED") {
        Write-Host ""
        Write-Host "  Status: " -NoNewline
        Write-Host "STOPPED" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "  Status: $status" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Execute action
switch ($Action) {
    "install" {
        Install-HmsService
    }
    "start" {
        Write-Step "Starting $ServiceName service"
        & $NssmExe start $ServiceName
        Start-Sleep -Seconds 2
        Get-HmsServiceStatus
    }
    "stop" {
        Write-Step "Stopping $ServiceName service"
        & $NssmExe stop $ServiceName
        Start-Sleep -Seconds 2
        Get-HmsServiceStatus
    }
    "restart" {
        Write-Step "Restarting $ServiceName service"
        & $NssmExe restart $ServiceName
        Start-Sleep -Seconds 2
        Get-HmsServiceStatus
    }
    "remove" {
        Remove-HmsService
    }
    "status" {
        Get-HmsServiceStatus
    }
}
