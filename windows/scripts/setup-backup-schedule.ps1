#Requires -Version 5.1
<#
.SYNOPSIS
    Setup daily automated database backup using Windows Task Scheduler
.DESCRIPTION
    Creates a Windows Scheduled Task that runs the backup script daily at 2:00 AM.
    The task runs under the SYSTEM account and survives reboots.
.PARAMETER Remove
    Remove the scheduled task instead of creating it
.PARAMETER Time
    Time to run the backup (default: "02:00" = 2:00 AM)
#>

[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$Time = "02:00"
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$TaskName = "HMS-DatabaseBackup"
$BackupScript = Join-Path $PSScriptRoot "backup-database.ps1"

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Backup Schedule Setup" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Task Name:    $TaskName" -ForegroundColor DarkGray
Write-Host "  Backup Time:  $Time daily" -ForegroundColor DarkGray
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
    # Create the action (run PowerShell with backup script)
    Write-SubStep "Configuring action..."
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$BackupScript`""

    # Create the trigger (daily at specified time)
    Write-SubStep "Setting trigger for $Time daily..."
    $trigger = New-ScheduledTaskTrigger -Daily -At $Time

    # Create settings
    Write-SubStep "Configuring task settings..."
    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -DontStopIfGoingOnBatteries `
        -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    # Create principal (run as SYSTEM)
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
        -Description "Daily HMS PostgreSQL database backup at $Time"

    Write-Host ""
    Write-Log "Scheduled task created successfully" -Level SUCCESS
    Write-Host ""
    Write-Host "  The backup task is configured to:" -ForegroundColor Cyan
    Write-Host "    - Run daily at $Time"
    Write-Host "    - Run even if computer was asleep (catch-up)"
    Write-Host "    - Run under SYSTEM account"
    Write-Host "    - Store backups in: $(Join-Path (Get-ProjectRoot) 'backups')"
    Write-Host ""
    Write-Host "  To verify the task:" -ForegroundColor Yellow
    Write-Host "    1. Open Task Scheduler (taskschd.msc)"
    Write-Host "    2. Look for '$TaskName' in the task list"
    Write-Host ""
    Write-Host "  To remove this task later:" -ForegroundColor DarkGray
    Write-Host "    .\setup-backup-schedule.ps1 -Remove" -ForegroundColor DarkGray
    Write-Host ""

} catch {
    Write-Log "Failed to create scheduled task: $_" -Level ERROR
    exit 1
}
