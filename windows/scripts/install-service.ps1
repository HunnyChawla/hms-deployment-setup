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

# ------------------------------------------------------------------
# Source common functions
# ------------------------------------------------------------------
. (Join-Path $PSScriptRoot "common.ps1")

# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------
$ServiceName   = "HMSDocker"
$ProjectRoot  = Get-ProjectRoot
$DeployScript = Join-Path $PSScriptRoot "deploy.ps1"
$LogDir       = Join-Path $ProjectRoot "data\logs"
$NssmExe      = Get-NssmPath

$PowerShellExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$AppDir        = (Resolve-Path $PSScriptRoot).Path

# ------------------------------------------------------------------
# Banner
# ------------------------------------------------------------------
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Service Management (NSSM)" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Service Name: $ServiceName" -ForegroundColor DarkGray
Write-Host "  Action:       $Action" -ForegroundColor DarkGray
Write-Host ""

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
if (-not (Test-NssmInstalled)) {
    Write-Host (Get-NssmInstallInstructions) -ForegroundColor Yellow
    exit 1
}

if ($Action -in @("install", "remove")) {
    if (-not (Test-IsAdmin)) {
        Write-Log "Administrator privileges required." -Level ERROR
        exit 1
    }
}

if ($Action -eq "install" -and -not (Test-Path $DeployScript)) {
    Write-Log "deploy.ps1 not found at: $DeployScript" -Level ERROR
    exit 1
}

# ------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------

function Install-HmsService {
    Write-Step "Installing $ServiceName service"

    $existingStatus = & $NssmExe status $ServiceName 2>&1
    if ($existingStatus -notmatch "Can't open service") {
        Write-Log "Service already exists. Use 'remove' or 'restart'." -Level WARN
        return
    }

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }

    Write-SubStep "Registering service (non-interactive)..."
    & $NssmExe install $ServiceName `
        $PowerShellExe `
        "-ExecutionPolicy Bypass -NoProfile -File `"$DeployScript`" -NoPull"

    if ($LASTEXITCODE -ne 0) {
        Write-Log "NSSM install failed" -Level ERROR
        exit 1
    }

    Write-SubStep "Configuring service properties..."
    & $NssmExe set $ServiceName AppDirectory $AppDir
    & $NssmExe set $ServiceName DisplayName "HMS Docker Deployment Service"
    & $NssmExe set $ServiceName Description "Starts HMS Docker containers on system boot"
    & $NssmExe set $ServiceName Start SERVICE_AUTO_START
    & $NssmExe set $ServiceName ObjectName LocalSystem

    & $NssmExe set $ServiceName AppExit Default Exit
    & $NssmExe set $ServiceName AppRestartDelay 60000

    Write-SubStep "Configuring logging..."
    & $NssmExe set $ServiceName AppStdout (Join-Path $LogDir "service-stdout.log")
    & $NssmExe set $ServiceName AppStderr (Join-Path $LogDir "service-stderr.log")
    & $NssmExe set $ServiceName AppRotateFiles 1
    & $NssmExe set $ServiceName AppRotateBytes 5242880

    Write-Log "Service installed successfully" -Level SUCCESS
}

function Remove-HmsService {
    Write-Step "Removing $ServiceName service"
    & $NssmExe stop $ServiceName 2>$null
    & $NssmExe remove $ServiceName confirm
    Write-Log "Service removed" -Level SUCCESS
}

function Get-HmsServiceStatus {
    Write-Step "Checking $ServiceName service status"

    $status = & $NssmExe status $ServiceName 2>&1

    if ($status -match "Can't open service") {
        Write-Host "  Status: NOT INSTALLED" -ForegroundColor Yellow
    } elseif ($status -match "SERVICE_RUNNING") {
        Write-Host "  Status: RUNNING" -ForegroundColor Green
    } elseif ($status -match "SERVICE_STOPPED") {
        Write-Host "  Status: STOPPED" -ForegroundColor Yellow
    } else {
        Write-Host "  Status: $status" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# ------------------------------------------------------------------
# Action dispatcher
# ------------------------------------------------------------------
switch ($Action) {
    "install"  { Install-HmsService }
    "start"    { & $NssmExe start $ServiceName;  Start-Sleep 2; Get-HmsServiceStatus }
    "stop"     { & $NssmExe stop  $ServiceName;  Start-Sleep 2; Get-HmsServiceStatus }
    "restart"  { & $NssmExe restart $ServiceName; Start-Sleep 2; Get-HmsServiceStatus }
    "remove"   { Remove-HmsService }
    "status"   { Get-HmsServiceStatus }
}
