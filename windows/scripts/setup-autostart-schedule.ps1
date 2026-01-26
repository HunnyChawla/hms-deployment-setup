#Requires -Version 5.1
<#
.SYNOPSIS
    Setup auto-start for HMS Docker containers using Windows Task Scheduler
.DESCRIPTION
    Creates a Windows Scheduled Task that runs on system startup to:
    - Start Docker Desktop if not running
    - Pull latest images and start HMS containers
.PARAMETER Remove
    Remove the scheduled task instead of creating it
#>

[CmdletBinding()]
param(
    [switch]$Remove
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$TaskName = "HMS-DockerAutoStart"
$DeployScript = Join-Path $PSScriptRoot "deploy.ps1"

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Auto-Start Setup (Task Scheduler)" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Task Name: $TaskName" -ForegroundColor DarkGray
Write-Host ""

# Check for Admin rights
if (-not (Test-IsAdmin)) {
    Write-Log "This action requires Administrator privileges." -Level ERROR
    Write-Host ""
    Write-Host "  Please run as Administrator:" -ForegroundColor Yellow
    Write-Host "    1. Right-click on hms-setup.bat" -ForegroundColor DarkGray
    Write-Host "    2. Select 'Run as administrator'" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

if ($Remove) {
    # Remove the scheduled task
    Write-Step "Removing scheduled task"

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Log "Scheduled task removed" -Level SUCCESS
    } else {
        Write-Log "Scheduled task not found" -Level WARN
    }
    exit 0
}

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Log "Scheduled task already exists. Updating..." -Level INFO
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Write-Step "Creating scheduled task"

try {
    # Create the action (run PowerShell with deploy script)
    # The deploy script will handle starting Docker Desktop if needed
    Write-SubStep "Configuring action..."
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$DeployScript`""

    # Create the trigger (at system startup with delay to allow Docker Desktop to initialize)
    Write-SubStep "Setting trigger for system startup..."
    $trigger = New-ScheduledTaskTrigger -AtStartup
    # Add 60 second delay to allow system to fully boot
    $trigger.Delay = "PT60S"

    # Create settings
    Write-SubStep "Configuring task settings..."
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1)

    # Create principal (run as SYSTEM with highest privileges)
    Write-SubStep "Setting security principal..."
    $principal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    # Register the task
    Write-SubStep "Registering task..."
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Starts HMS Docker containers on system boot (pulls latest images)"

    Write-Host ""
    Write-Log "Scheduled task created successfully" -Level SUCCESS
    Write-Host ""
    Write-Host "  The auto-start task is configured to:" -ForegroundColor Cyan
    Write-Host "    - Run at system startup (60 sec delay)"
    Write-Host "    - Pull latest Docker images (pull_policy: always)"
    Write-Host "    - Start all HMS containers"
    Write-Host "    - Retry up to 3 times if failed"
    Write-Host ""
    Write-Host "  To verify the task:" -ForegroundColor Yellow
    Write-Host "    1. Open Task Scheduler (taskschd.msc)"
    Write-Host "    2. Look for '$TaskName' in the task list"
    Write-Host ""
    Write-Host "  To test the task now:" -ForegroundColor Yellow
    Write-Host "    Start-ScheduledTask -TaskName '$TaskName'"
    Write-Host ""
    Write-Host "  To remove this task later:" -ForegroundColor DarkGray
    Write-Host "    .\setup-autostart-schedule.ps1 -Remove" -ForegroundColor DarkGray
    Write-Host ""

} catch {
    Write-Log "Failed to create scheduled task: $_" -Level ERROR
    exit 1
}
