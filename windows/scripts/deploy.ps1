#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy HMS Docker services
.DESCRIPTION
    Pulls latest Docker images and starts/restarts all HMS services.
    Handles graceful shutdown and health check verification.
.PARAMETER NoPull
    Skip pulling new images (use existing local images)
.PARAMETER Force
    Force recreate all containers even if unchanged
#>

[CmdletBinding()]
param(
    [switch]$NoPull,
    [switch]$Force
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

$ProjectRoot = Get-ProjectRoot

# Banner
Write-Host ""
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host "   HMS Docker Deployment" -ForegroundColor Cyan
Write-Host "  ========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Project Root: $ProjectRoot" -ForegroundColor DarkGray
Write-Host "  Timestamp:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
Write-Host ""

# Check prerequisites
Write-Step "Checking prerequisites"
if (-not (Test-Prerequisites)) {
    Write-Log "Prerequisites check failed. Please resolve issues above." -Level ERROR
    exit 1
}

# Initialize directories
Write-Step "Ensuring directories exist"
& (Join-Path $PSScriptRoot "init-directories.ps1")

# Change to project directory for docker-compose
Push-Location $ProjectRoot

try {
    # Pull latest images
    if (-not $NoPull) {
        Write-Step "Pulling latest images"
        docker-compose pull
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Image pull had issues. Continuing with existing images..." -Level WARN
        } else {
            Write-Log "Images pulled successfully" -Level SUCCESS
        }
    } else {
        Write-Log "Skipping image pull (NoPull flag set)" -Level INFO
    }

    # Stop existing containers
    Write-Step "Stopping existing containers"
    docker-compose down --timeout 30
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Containers stopped gracefully" -Level SUCCESS
    }

    # Start services
    Write-Step "Starting services"
    $upArgs = @("up", "-d")
    if ($Force) {
        $upArgs += "--force-recreate"
    }
    docker-compose @upArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to start services" -Level ERROR
        exit 1
    }
    Write-Log "Services started" -Level SUCCESS

    # Wait for health checks
    Write-Step "Waiting for services to become healthy"
    $containers = Get-HmsContainerNames

    Write-Host "  Checking $($containers.Postgres)..." -NoNewline
    if (Wait-ForHealthy -ContainerName $containers.Postgres -TimeoutSeconds 60) {
        Write-Host " healthy" -ForegroundColor Green
    } else {
        Write-Host " timeout" -ForegroundColor Yellow
    }

    Write-Host "  Checking $($containers.Backend)..." -NoNewline
    if (Wait-ForHealthy -ContainerName $containers.Backend -TimeoutSeconds 120) {
        Write-Host " healthy" -ForegroundColor Green
    } else {
        Write-Host " timeout" -ForegroundColor Yellow
    }

    Write-Host "  Checking $($containers.Frontend)..." -NoNewline
    $frontendStatus = Get-ContainerStatus -ContainerName $containers.Frontend
    if ($frontendStatus -eq "running") {
        Write-Host " running" -ForegroundColor Green
    } else {
        Write-Host " $frontendStatus" -ForegroundColor Yellow
    }

    Write-Host "  Checking $($containers.TvLegacy)..." -NoNewline
    $tvLegacyStatus = Get-ContainerStatus -ContainerName $containers.TvLegacy
    if ($tvLegacyStatus -eq "running") {
        Write-Host " running" -ForegroundColor Green
    } else {
        Write-Host " $tvLegacyStatus" -ForegroundColor Yellow
    }

    # Final status
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host "   Deployment Complete!" -ForegroundColor Green
    Write-Host "  ========================================" -ForegroundColor Green
    Write-Host ""

    # Show container status
    docker-compose ps

    Write-Host ""
    Write-Host "  Access Points:" -ForegroundColor Cyan
    $frontendPort = Get-EnvValue -Key "FRONTEND_PORT" -Default "80"
    $backendPort = Get-EnvValue -Key "APP_PORT" -Default "8000"
    $tvLegacyPort = Get-EnvValue -Key "TV_LEGACY_PORT" -Default "5500"
    Write-Host "    Frontend:   http://localhost:$frontendPort"
    Write-Host "    Backend:    http://localhost:$backendPort"
    Write-Host "    API Docs:   http://localhost:$backendPort/docs"
    Write-Host "    TV Display: http://localhost:$tvLegacyPort"
    Write-Host ""

} finally {
    Pop-Location
}
