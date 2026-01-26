#Requires -Version 5.1
<#
.SYNOPSIS
    Restore PostgreSQL database from backup
.DESCRIPTION
    Restores the HMS database from a backup file.
    WARNING: This will REPLACE all existing data in the database!
.PARAMETER BackupFile
    Path to backup file (optional - will show list if not provided)
#>

[CmdletBinding()]
param(
    [string]$BackupFile
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$ProjectRoot = Get-ProjectRoot
$BackupDir = Join-Path $ProjectRoot "backups"

# Get configuration from .env or defaults
$POSTGRES_USER = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
$POSTGRES_DB = Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db"
$POSTGRES_CONTAINER = Get-EnvValue -Key "POSTGRES_CONTAINER_NAME" -Default "hms-postgres"

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Database Restore" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker is running
if (-not (Test-DockerRunning)) {
    Write-Log "Docker is not running. Please start Docker Desktop." -Level ERROR
    exit 1
}

# Check container is running
$containerStatus = Get-ContainerStatus -ContainerName $POSTGRES_CONTAINER
if ($containerStatus -ne "running") {
    Write-Log "Container $POSTGRES_CONTAINER is not running (status: $containerStatus)" -Level ERROR
    Write-Log "Start the services first with: .\scripts\deploy.ps1" -Level INFO
    exit 1
}

# If no backup specified, list available and prompt
if (-not $BackupFile) {
    # Get available backups
    $backups = Get-ChildItem -Path $BackupDir -Filter "hms_backup_*.sql*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($backups.Count -eq 0) {
        Write-Log "No backup files found in: $BackupDir" -Level ERROR
        exit 1
    }

    Write-Host "  Available Backups:" -ForegroundColor Cyan
    Write-Host "  ------------------" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt $backups.Count; $i++) {
        $backup = $backups[$i]
        $sizeMB = [math]::Round($backup.Length / 1MB, 2)
        $age = [math]::Round(((Get-Date) - $backup.LastWriteTime).TotalDays, 1)
        Write-Host "    [$i] " -NoNewline -ForegroundColor Yellow
        Write-Host "$($backup.Name)" -NoNewline
        Write-Host " ($sizeMB MB, $age days old)" -ForegroundColor DarkGray
    }

    Write-Host ""
    $selection = Read-Host "  Enter backup number to restore (or 'q' to cancel)"

    if ($selection -eq 'q') {
        Write-Log "Restore cancelled." -Level INFO
        exit 0
    }

    try {
        $index = [int]$selection
        if ($index -lt 0 -or $index -ge $backups.Count) {
            throw "Invalid selection"
        }
        $BackupFile = $backups[$index].FullName
    } catch {
        Write-Log "Invalid selection: $selection" -Level ERROR
        exit 1
    }
}

# Validate backup file exists
if (-not (Test-Path $BackupFile)) {
    Write-Log "Backup file not found: $BackupFile" -Level ERROR
    exit 1
}

$backupInfo = Get-Item $BackupFile
$sizeMB = [math]::Round($backupInfo.Length / 1MB, 2)

# Warning and confirmation
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Red
Write-Host "   WARNING: DATABASE RESTORE" -ForegroundColor Red
Write-Host "  ========================================" -ForegroundColor Red
Write-Host ""
Write-Host "  This will REPLACE ALL DATA in database: $POSTGRES_DB" -ForegroundColor Red
Write-Host ""
Write-Host "  Backup file:  $($backupInfo.Name)" -ForegroundColor Yellow
Write-Host "  Size:         $sizeMB MB" -ForegroundColor Yellow
Write-Host "  Created:      $($backupInfo.LastWriteTime)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  All existing data will be permanently lost!" -ForegroundColor Red
Write-Host ""

$confirm = Read-Host "  Type 'RESTORE' to confirm"
if ($confirm -ne "RESTORE") {
    Write-Log "Restore cancelled." -Level WARN
    exit 0
}

Write-Host ""
Write-Step "Restoring database"

try {
    # Step 1: Terminate existing connections
    Write-SubStep "Terminating existing connections..."
    $terminateQuery = "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$POSTGRES_DB' AND pid <> pg_backend_pid();"
    docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -c $terminateQuery 2>&1 | Out-Null

    # Step 2: Drop and recreate database
    Write-SubStep "Dropping existing database..."
    docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -c "DROP DATABASE IF EXISTS $POSTGRES_DB;" 2>&1 | Out-Null

    Write-SubStep "Creating fresh database..."
    docker exec $POSTGRES_CONTAINER psql -U $POSTGRES_USER -c "CREATE DATABASE $POSTGRES_DB;" 2>&1 | Out-Null

    # Step 3: Restore from backup
    Write-SubStep "Restoring from backup (this may take a while)..."

    # Read backup file and pipe to psql
    Get-Content $BackupFile -Raw | docker exec -i $POSTGRES_CONTAINER psql -U $POSTGRES_USER -d $POSTGRES_DB 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Log "Database restored successfully!" -Level SUCCESS
    } else {
        throw "Restore command failed"
    }

} catch {
    Write-Log "Restore failed: $_" -Level ERROR
    Write-Log "The database may be in an inconsistent state." -Level WARN
    Write-Log "You may need to re-run the restore or redeploy." -Level INFO
    exit 1
}

Write-Host ""
Write-Host "  Next Steps:" -ForegroundColor Cyan
Write-Host "    1. Restart the backend to reconnect to the database"
Write-Host "    2. Verify your data in the application"
Write-Host ""
Write-Host "  To restart services, run:" -ForegroundColor DarkGray
Write-Host "    .\scripts\deploy.ps1 -NoPull" -ForegroundColor DarkGray
Write-Host ""
