#Requires -Version 5.1
<#
.SYNOPSIS
    Common utility functions for HMS deployment scripts
.DESCRIPTION
    Shared functions used across all HMS PowerShell scripts including
    logging, Docker checks, environment variable handling, and path utilities.
#>

# ============================================
# Path Utilities
# ============================================

function Get-ProjectRoot {
    <#
    .SYNOPSIS
        Returns the project root directory (where docker-compose.yml is located)
    #>
    $scriptsDir = $PSScriptRoot
    $windowsDir = Split-Path -Parent $scriptsDir
    $projectRoot = Split-Path -Parent $windowsDir
    return $projectRoot
}

function Get-EnvFilePath {
    return Join-Path (Get-ProjectRoot) ".env"
}

function Get-ComposeFilePath {
    return Join-Path (Get-ProjectRoot) "docker-compose.yml"
}

# ============================================
# Logging Functions
# ============================================

function Write-Log {
    <#
    .SYNOPSIS
        Writes a timestamped log message with color coding
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "White" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
    }

    Write-Host "  [$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Level] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Write-Step {
    <#
    .SYNOPSIS
        Writes a step indicator for multi-step processes
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "  >> $Message" -ForegroundColor Cyan
}

function Write-SubStep {
    <#
    .SYNOPSIS
        Writes a sub-step indicator
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "     - $Message" -ForegroundColor DarkGray
}

# ============================================
# Docker Utilities
# ============================================

function Test-DockerRunning {
    <#
    .SYNOPSIS
        Checks if Docker daemon is running
    .OUTPUTS
        Boolean - True if Docker is running
    #>
    try {
        $null = docker info 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-DockerComposeExists {
    <#
    .SYNOPSIS
        Checks if docker-compose.yml exists in project root
    #>
    return Test-Path (Get-ComposeFilePath)
}

function Get-ContainerStatus {
    <#
    .SYNOPSIS
        Gets the status of a container by name
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    try {
        $status = docker inspect --format='{{.State.Status}}' $ContainerName 2>$null
        return $status
    } catch {
        return "not found"
    }
}

function Get-ContainerHealth {
    <#
    .SYNOPSIS
        Gets the health status of a container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    try {
        $health = docker inspect --format='{{.State.Health.Status}}' $ContainerName 2>$null
        if ($health) {
            return $health
        }
        return "no healthcheck"
    } catch {
        return "unknown"
    }
}

function Wait-ForHealthy {
    <#
    .SYNOPSIS
        Waits for a container to become healthy
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$TimeoutSeconds = 120,
        [int]$CheckIntervalSeconds = 5
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $health = Get-ContainerHealth -ContainerName $ContainerName
        if ($health -eq "healthy") {
            return $true
        }
        Start-Sleep -Seconds $CheckIntervalSeconds
        $elapsed += $CheckIntervalSeconds
        Write-Host "." -NoNewline
    }
    Write-Host ""
    return $false
}

# ============================================
# Environment Variable Utilities
# ============================================

function Get-EnvValue {
    <#
    .SYNOPSIS
        Gets a value from the .env file or returns default
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$Default = ""
    )

    $envFile = Get-EnvFilePath
    if (Test-Path $envFile) {
        $content = Get-Content $envFile -ErrorAction SilentlyContinue
        foreach ($line in $content) {
            if ($line -match "^$Key=(.*)$") {
                return $Matches[1]
            }
        }
    }
    return $Default
}

function Get-HmsContainerNames {
    <#
    .SYNOPSIS
        Returns the container names from .env or defaults
    #>
    return @{
        Postgres = Get-EnvValue -Key "POSTGRES_CONTAINER_NAME" -Default "hms-postgres"
        Backend  = Get-EnvValue -Key "BACKEND_CONTAINER_NAME" -Default "hms-backend"
        Frontend = Get-EnvValue -Key "FRONTEND_CONTAINER_NAME" -Default "hospital-ui"
    }
}

# ============================================
# Validation Functions
# ============================================

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Validates all prerequisites are met for deployment
    .OUTPUTS
        Boolean - True if all prerequisites pass
    #>
    param(
        [switch]$Quiet
    )

    $allPassed = $true

    # Check Docker
    if (-not (Test-DockerRunning)) {
        if (-not $Quiet) {
            Write-Log "Docker is not running. Please start Docker Desktop." -Level ERROR
        }
        $allPassed = $false
    } elseif (-not $Quiet) {
        Write-Log "Docker is running" -Level SUCCESS
    }

    # Check docker-compose.yml
    if (-not (Test-DockerComposeExists)) {
        if (-not $Quiet) {
            Write-Log "docker-compose.yml not found at: $(Get-ComposeFilePath)" -Level ERROR
        }
        $allPassed = $false
    } elseif (-not $Quiet) {
        Write-Log "docker-compose.yml found" -Level SUCCESS
    }

    # Check .env file (warning only)
    if (-not (Test-Path (Get-EnvFilePath))) {
        if (-not $Quiet) {
            Write-Log ".env file not found. Using defaults." -Level WARN
        }
    } elseif (-not $Quiet) {
        Write-Log ".env file found" -Level SUCCESS
    }

    return $allPassed
}

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if script is running with Administrator privileges
    #>
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    <#
    .SYNOPSIS
        Exits with error if not running as Administrator
    #>
    if (-not (Test-IsAdmin)) {
        Write-Log "This operation requires Administrator privileges." -Level ERROR
        Write-Log "Please run as Administrator." -Level ERROR
        exit 1
    }
}

# ============================================
# NSSM Utilities (Bundled)
# ============================================

function Get-NssmPath {
    <#
    .SYNOPSIS
        Returns the path to bundled NSSM executable
    #>
    $scriptsDir = $PSScriptRoot
    $windowsDir = Split-Path -Parent $scriptsDir
    $nssmPath = Join-Path $windowsDir "dependencies\nssm\nssm.exe"
    return $nssmPath
}

function Test-NssmInstalled {
    <#
    .SYNOPSIS
        Checks if bundled NSSM exists
    #>
    $nssmPath = Get-NssmPath
    return Test-Path $nssmPath
}

function Invoke-Nssm {
    <#
    .SYNOPSIS
        Invokes the bundled NSSM with given arguments
    .OUTPUTS
        Returns the exit code from NSSM
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $nssmPath = Get-NssmPath
    & $nssmPath @Arguments
    return $LASTEXITCODE
}

function Get-NssmInstallInstructions {
    return @"

NSSM executable not found at expected location.

Expected path: $(Get-NssmPath)

Please ensure the dependencies folder contains nssm.exe:
  windows/dependencies/nssm/nssm.exe

"@
}

# ============================================
# Docker Desktop Auto-Start
# ============================================

function Start-DockerDesktop {
    <#
    .SYNOPSIS
        Starts Docker Desktop if not running
    .OUTPUTS
        Boolean - True if Docker is running after attempt
    #>
    param(
        [int]$TimeoutSeconds = 120
    )

    # Check if already running
    if (Test-DockerRunning) {
        return $true
    }

    Write-Log "Docker is not running. Attempting to start Docker Desktop..." -Level WARN

    # Find Docker Desktop executable
    $dockerDesktopPaths = @(
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe"
    )

    $dockerExe = $null
    foreach ($path in $dockerDesktopPaths) {
        if (Test-Path $path) {
            $dockerExe = $path
            break
        }
    }

    if (-not $dockerExe) {
        Write-Log "Docker Desktop not found. Please install from https://www.docker.com/products/docker-desktop" -Level ERROR
        return $false
    }

    # Start Docker Desktop
    Write-Log "Starting Docker Desktop..." -Level INFO
    Start-Process $dockerExe

    # Wait for Docker to be ready
    Write-Host "  Waiting for Docker to start" -NoNewline
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host "." -NoNewline

        if (Test-DockerRunning) {
            Write-Host ""
            Write-Log "Docker Desktop started successfully" -Level SUCCESS
            return $true
        }
    }

    Write-Host ""
    Write-Log "Timeout waiting for Docker Desktop to start" -Level ERROR
    return $false
}

function Stop-HmsContainers {
    <#
    .SYNOPSIS
        Stops all HMS containers gracefully
    #>
    $projectRoot = Get-ProjectRoot
    Push-Location $projectRoot

    try {
        Write-Step "Stopping HMS containers"
        docker-compose stop --timeout 30
        Write-Log "Containers stopped" -Level SUCCESS
    } finally {
        Pop-Location
    }
}

function Remove-HmsContainers {
    <#
    .SYNOPSIS
        Stops and removes all HMS containers (preserves data)
    #>
    $projectRoot = Get-ProjectRoot
    Push-Location $projectRoot

    try {
        Write-Step "Removing HMS containers"
        docker-compose down --timeout 30
        Write-Log "Containers removed (data preserved)" -Level SUCCESS
    } finally {
        Pop-Location
    }
}

function Show-ContainerLogs {
    <#
    .SYNOPSIS
        Shows logs for a specific container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$TailLines = 100,
        [switch]$Follow,
        [switch]$SaveToFile
    )

    $projectRoot = Get-ProjectRoot
    $logDir = Join-Path $projectRoot "data\logs"

    # Ensure log directory exists
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    if ($SaveToFile) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $logFile = Join-Path $logDir "$ContainerName-$timestamp.log"

        Write-Log "Saving logs to: $logFile" -Level INFO
        docker logs $ContainerName --tail $TailLines 2>&1 | Out-File -FilePath $logFile -Encoding UTF8
        Write-Log "Logs saved successfully" -Level SUCCESS
        return $logFile
    }

    if ($Follow) {
        Write-Host ""
        Write-Host "  Showing live logs for $ContainerName (Ctrl+C to stop)" -ForegroundColor Yellow
        Write-Host "  ================================================" -ForegroundColor DarkGray
        docker logs $ContainerName --tail $TailLines -f
    } else {
        Write-Host ""
        Write-Host "  Last $TailLines lines from $ContainerName" -ForegroundColor Yellow
        Write-Host "  ================================================" -ForegroundColor DarkGray
        docker logs $ContainerName --tail $TailLines
    }
}
