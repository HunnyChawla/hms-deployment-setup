#Requires -Version 5.1
<#
.SYNOPSIS
    Backup PostgreSQL database from HMS Docker container
.DESCRIPTION
    Creates a compressed backup of the HMS database using pg_dump.
    Automatically cleans up old backups based on retention policy.
.PARAMETER RetentionDays
    Number of days to keep backups (default: 30, or from BACKUP_RETENTION_DAYS in .env)
#>

[CmdletBinding()]
param(
    [int]$RetentionDays = 0
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$ProjectRoot = Get-ProjectRoot
$BackupDir = Join-Path $ProjectRoot "backups"

# Get configuration from .env or defaults
$POSTGRES_USER = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
$POSTGRES_DB = Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db"
$POSTGRES_CONTAINER = Get-EnvValue -Key "POSTGRES_CONTAINER_NAME" -Default "hms-postgres"

# Retention days: parameter > .env > default (30)
if ($RetentionDays -eq 0) {
    $RetentionDays = [int](Get-EnvValue -Key "BACKUP_RETENTION_DAYS" -Default "30")
}

# Generate backup filename with timestamp
$Timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$BackupFile = "hms_backup_$Timestamp.sql"
$BackupPath = Join-Path $BackupDir $BackupFile

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Database Backup" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Timestamp:  $Timestamp" -ForegroundColor DarkGray
Write-Host "  Container:  $POSTGRES_CONTAINER" -ForegroundColor DarkGray
Write-Host "  Database:   $POSTGRES_DB" -ForegroundColor DarkGray
Write-Host "  Backup to:  $BackupPath" -ForegroundColor DarkGray
Write-Host "  Retention:  $RetentionDays days" -ForegroundColor DarkGray
Write-Host ""

# Check Docker is running
if (-not (Test-DockerRunning)) {
    Write-Log "Docker is not running. Please start Docker Desktop." -Level ERROR
    exit 1
}

# Ensure backup directory exists
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    Write-Log "Created backup directory: $BackupDir" -Level INFO
}

# Check container is running
$containerStatus = Get-ContainerStatus -ContainerName $POSTGRES_CONTAINER
if ($containerStatus -ne "running") {
    Write-Log "Container $POSTGRES_CONTAINER is not running (status: $containerStatus)" -Level ERROR
    exit 1
}

# Perform backup using pg_dump inside container
Write-Step "Creating backup"

try {
    # Run pg_dump and save directly (no gzip in alpine by default)
    docker exec $POSTGRES_CONTAINER pg_dump -U $POSTGRES_USER -d $POSTGRES_DB > $BackupPath

    if ($LASTEXITCODE -eq 0 -and (Test-Path $BackupPath)) {
        $fileInfo = Get-Item $BackupPath
        $sizeMB = [math]::Round($fileInfo.Length / 1MB, 2)

        if ($sizeMB -gt 0) {
            Write-Log "Backup successful: $sizeMB MB" -Level SUCCESS
        } else {
            Write-Log "Warning: Backup file is empty. Database may be empty." -Level WARN
        }
    } else {
        throw "pg_dump command failed"
    }
} catch {
    Write-Log "Backup failed: $_" -Level ERROR
    # Clean up partial backup file
    if (Test-Path $BackupPath) {
        Remove-Item $BackupPath -Force
    }
    exit 1
}

# Cleanup old backups
Write-Step "Cleaning up old backups"

$cutoffDate = (Get-Date).AddDays(-$RetentionDays)
$oldBackups = Get-ChildItem -Path $BackupDir -Filter "hms_backup_*.sql*" |
    Where-Object { $_.LastWriteTime -lt $cutoffDate }

$removedCount = 0
foreach ($old in $oldBackups) {
    Remove-Item $old.FullName -Force
    Write-SubStep "Deleted: $($old.Name)"
    $removedCount++
}

if ($removedCount -eq 0) {
    Write-Log "No old backups to remove" -Level INFO
} else {
    Write-Log "Removed $removedCount old backup(s)" -Level SUCCESS
}

# List current backups
Write-Host ""
Write-Host "  Current Backups:" -ForegroundColor Cyan
Write-Host "  ----------------" -ForegroundColor Cyan

$allBackups = Get-ChildItem -Path $BackupDir -Filter "hms_backup_*.sql*" |
    Sort-Object LastWriteTime -Descending

foreach ($backup in $allBackups) {
    $sizeMB = [math]::Round($backup.Length / 1MB, 2)
    $age = [math]::Round(((Get-Date) - $backup.LastWriteTime).TotalDays, 1)
    Write-Host "    $($backup.Name)" -NoNewline
    Write-Host " ($sizeMB MB, $age days old)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Log "Backup complete" -Level SUCCESS
Write-Host ""
