#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Container Debug Utility
.DESCRIPTION
    Provides tools for debugging failing containers including log inspection,
    debug mode with entrypoint override, container inspection, and recovery options.
#>

[CmdletBinding()]
param()

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

# ============================================
# Debug Functions
# ============================================

function Get-ContainerStartupLogs {
    <#
    .SYNOPSIS
        Gets container logs with error highlighting
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [int]$TailLines = 200
    )

    Write-Host ""
    Write-Host "  Logs for $ContainerName (last $TailLines lines):" -ForegroundColor Yellow
    Write-Host "  ========================================" -ForegroundColor DarkGray

    try {
        $logs = docker logs $ContainerName --tail $TailLines 2>&1

        foreach ($line in $logs) {
            if ($line -match "error|exception|failed|fatal|critical" -and $line -notmatch "no error") {
                Write-Host "  $line" -ForegroundColor Red
            } elseif ($line -match "warn|warning") {
                Write-Host "  $line" -ForegroundColor Yellow
            } else {
                Write-Host "  $line"
            }
        }
    } catch {
        Write-Log "Error reading logs: $_" -Level ERROR
    }

    Write-Host "  ========================================" -ForegroundColor DarkGray
}

function Get-ContainerInspection {
    <#
    .SYNOPSIS
        Gets detailed container inspection information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' not found" -Level ERROR
        return
    }

    Write-Host ""
    Write-Host "  Container Inspection: $ContainerName" -ForegroundColor Yellow
    Write-Host "  ========================================" -ForegroundColor DarkGray

    # Get state info
    $state = docker inspect --format='{{.State.Status}}' $ContainerName 2>$null
    $health = docker inspect --format='{{.State.Health.Status}}' $ContainerName 2>$null
    $startedAt = docker inspect --format='{{.State.StartedAt}}' $ContainerName 2>$null
    $exitCode = docker inspect --format='{{.State.ExitCode}}' $ContainerName 2>$null
    $error = docker inspect --format='{{.State.Error}}' $ContainerName 2>$null
    $restartCount = docker inspect --format='{{.RestartCount}}' $ContainerName 2>$null

    Write-Host ""
    Write-Host "  State:" -ForegroundColor Cyan
    Write-Host "    Status: " -NoNewline
    if ($state -eq "running") {
        Write-Host $state -ForegroundColor Green
    } else {
        Write-Host $state -ForegroundColor Red
    }

    if ($health) {
        Write-Host "    Health: " -NoNewline
        if ($health -eq "healthy") {
            Write-Host $health -ForegroundColor Green
        } elseif ($health -eq "unhealthy") {
            Write-Host $health -ForegroundColor Red
        } else {
            Write-Host $health -ForegroundColor Yellow
        }
    }

    Write-Host "    Started: $startedAt"
    Write-Host "    Exit Code: $exitCode"
    Write-Host "    Restart Count: $restartCount"

    if ($error) {
        Write-Host "    Error: $error" -ForegroundColor Red
    }

    # Get image info
    $image = docker inspect --format='{{.Config.Image}}' $ContainerName 2>$null
    $cmd = docker inspect --format='{{.Config.Cmd}}' $ContainerName 2>$null
    $entrypoint = docker inspect --format='{{.Config.Entrypoint}}' $ContainerName 2>$null
    $workdir = docker inspect --format='{{.Config.WorkingDir}}' $ContainerName 2>$null

    Write-Host ""
    Write-Host "  Configuration:" -ForegroundColor Cyan
    Write-Host "    Image: $image"
    Write-Host "    Entrypoint: $entrypoint"
    Write-Host "    Command: $cmd"
    Write-Host "    Working Dir: $workdir"

    # Get mount info
    Write-Host ""
    Write-Host "  Mounts:" -ForegroundColor Cyan
    $mounts = docker inspect --format='{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}}{{println}}{{end}}' $ContainerName 2>$null
    if ($mounts) {
        $mounts.Split("`n") | Where-Object { $_ } | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "    (none)"
    }

    # Get port mappings
    Write-Host ""
    Write-Host "  Ports:" -ForegroundColor Cyan
    $ports = docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{$p}} -> {{(index $conf 0).HostPort}}{{println}}{{end}}' $ContainerName 2>$null
    if ($ports) {
        $ports.Split("`n") | Where-Object { $_ } | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "    (none mapped)"
    }

    # Get health check details if unhealthy
    if ($health -eq "unhealthy") {
        Write-Host ""
        Write-Host "  Health Check Details:" -ForegroundColor Red
        $healthLogs = docker inspect --format='{{range .State.Health.Log}}{{.ExitCode}}: {{.Output}}{{println}}{{end}}' $ContainerName 2>$null
        if ($healthLogs) {
            $healthLogs.Split("`n") | Select-Object -First 5 | ForEach-Object {
                if ($_) { Write-Host "    $_" -ForegroundColor Yellow }
            }
        }
    }

    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor DarkGray
}

function Get-ContainerEnvironment {
    <#
    .SYNOPSIS
        Shows container environment variables
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName
    )

    if (-not (Test-ContainerExists -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' not found" -Level ERROR
        return
    }

    Write-Host ""
    Write-Host "  Environment Variables: $ContainerName" -ForegroundColor Yellow
    Write-Host "  ========================================" -ForegroundColor DarkGray

    $env = docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' $ContainerName 2>$null

    # Mask sensitive values
    $sensitiveKeys = @("PASSWORD", "SECRET", "KEY", "TOKEN")

    $env.Split("`n") | Where-Object { $_ } | ForEach-Object {
        $parts = $_ -split "=", 2
        $key = $parts[0]
        $value = if ($parts.Count -gt 1) { $parts[1] } else { "" }

        $isSensitive = $false
        foreach ($sensitiveKey in $sensitiveKeys) {
            if ($key -match $sensitiveKey) {
                $isSensitive = $true
                break
            }
        }

        if ($isSensitive -and $value.Length -gt 4) {
            $maskedValue = $value.Substring(0, 4) + "****"
            Write-Host "    $key=$maskedValue" -ForegroundColor DarkGray
        } else {
            Write-Host "    $_"
        }
    }

    Write-Host "  ========================================" -ForegroundColor DarkGray
}

function Start-ContainerDebugMode {
    <#
    .SYNOPSIS
        Starts a container in debug mode with shell access
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [string]$Shell = "/bin/sh"
    )

    $projectRoot = Get-ProjectRoot

    Write-Host ""
    Write-Host "  Starting debug mode for service: $ServiceName" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  This will:" -ForegroundColor DarkGray
    Write-Host "    1. Start a new container with the same image" -ForegroundColor DarkGray
    Write-Host "    2. Override the entrypoint to $Shell" -ForegroundColor DarkGray
    Write-Host "    3. Give you an interactive shell to debug" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Type 'exit' to leave the debug shell" -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Read-Host "  Start debug mode? (y/n)"
    if ($confirm -ne 'y') {
        Write-Log "Operation cancelled" -Level WARN
        return
    }

    Write-Step "Starting debug container..."

    Push-Location $projectRoot
    try {
        # Use docker-compose run with entrypoint override
        docker-compose run --rm --entrypoint $Shell $ServiceName
    } finally {
        Pop-Location
    }

    Write-Log "Debug session ended" -Level INFO
}

function Restart-SingleService {
    <#
    .SYNOPSIS
        Restarts a single service
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [switch]$ForceRecreate,
        [switch]$NoPull
    )

    $projectRoot = Get-ProjectRoot

    Write-Step "Restarting service: $ServiceName"

    Push-Location $projectRoot
    try {
        if ($ForceRecreate) {
            Write-SubStep "Force recreating container..."
            if (-not $NoPull) {
                docker-compose pull $ServiceName
            }
            docker-compose up -d --force-recreate $ServiceName
        } else {
            docker-compose restart $ServiceName
        }

        if ($LASTEXITCODE -eq 0) {
            Write-Log "Service restarted successfully" -Level SUCCESS
        } else {
            Write-Log "Failed to restart service" -Level ERROR
        }
    } finally {
        Pop-Location
    }
}

function Show-FailingContainers {
    <#
    .SYNOPSIS
        Shows containers that are not running or unhealthy
    #>
    $containers = Get-HmsContainerNames
    $containerList = @(
        @{ Name = $containers.Postgres; Service = "db"; Label = "PostgreSQL" }
        @{ Name = $containers.Backend; Service = "hms-backend"; Label = "Backend" }
        @{ Name = $containers.Frontend; Service = "hospital-ui"; Label = "Frontend" }
    )

    $failing = @()

    foreach ($c in $containerList) {
        $status = Get-ContainerStatus -ContainerName $c.Name
        $health = Get-ContainerHealth -ContainerName $c.Name

        $isFailing = $false
        $reason = ""

        if ($status -ne "running") {
            $isFailing = $true
            $reason = "Status: $status"
        } elseif ($health -eq "unhealthy") {
            $isFailing = $true
            $reason = "Health: unhealthy"
        }

        if ($isFailing) {
            $failing += @{
                Name = $c.Name
                Service = $c.Service
                Label = $c.Label
                Status = $status
                Health = $health
                Reason = $reason
            }
        }
    }

    return $failing
}

# ============================================
# Main Debug Menu
# ============================================

function Show-DebugMenu {
    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Container Debug & Recovery" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check Docker
    if (-not (Test-DockerRunning)) {
        Write-Log "Docker is not running. Please start Docker Desktop." -Level ERROR
        return
    }

    # Show failing containers
    $failing = Show-FailingContainers
    $containers = Get-HmsContainerNames
    $containerList = @($containers.Postgres, $containers.Backend, $containers.Frontend)

    Write-Host "  Container Status:" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    foreach ($name in $containerList) {
        $status = Get-ContainerStatus -ContainerName $name
        $health = Get-ContainerHealth -ContainerName $name

        Write-Host "    $name : " -NoNewline
        if ($status -eq "running") {
            if ($health -eq "healthy") {
                Write-Host "running (healthy)" -ForegroundColor Green
            } elseif ($health -eq "unhealthy") {
                Write-Host "running (UNHEALTHY)" -ForegroundColor Red
            } else {
                Write-Host "running ($health)" -ForegroundColor Yellow
            }
        } elseif ($status -eq "not found") {
            Write-Host "not found" -ForegroundColor DarkGray
        } else {
            Write-Host "$status" -ForegroundColor Red
        }
    }

    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    if ($failing.Count -gt 0) {
        Write-Host ""
        Write-Host "  Issues detected:" -ForegroundColor Red
        foreach ($f in $failing) {
            Write-Host "    - $($f.Label): $($f.Reason)" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "  All containers are healthy" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  Select a container to debug:" -ForegroundColor Yellow
    Write-Host "  [1] $($containers.Postgres) (PostgreSQL)"
    Write-Host "  [2] $($containers.Backend) (Backend/FastAPI)"
    Write-Host "  [3] $($containers.Frontend) (Frontend/Next.js)"
    Write-Host "  [0] Back"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    $selectedContainer = $null
    $selectedService = $null

    switch ($choice) {
        "1" { $selectedContainer = $containers.Postgres; $selectedService = "db" }
        "2" { $selectedContainer = $containers.Backend; $selectedService = "hms-backend" }
        "3" { $selectedContainer = $containers.Frontend; $selectedService = "hospital-ui" }
        "0" { return }
        default { return }
    }

    if ($selectedContainer) {
        Show-ContainerDebugOptions -ContainerName $selectedContainer -ServiceName $selectedService
    }
}

function Show-ContainerDebugOptions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    do {
        Clear-Host
        Write-Host ""
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host "   Debug: $ContainerName" -ForegroundColor Cyan
        Write-Host "  ========================================" -ForegroundColor Cyan
        Write-Host ""

        $status = Get-ContainerStatus -ContainerName $ContainerName
        $health = Get-ContainerHealth -ContainerName $ContainerName

        Write-Host "  Status: " -NoNewline
        if ($status -eq "running") {
            Write-Host "$status ($health)" -ForegroundColor $(if ($health -eq "healthy") { "Green" } else { "Yellow" })
        } else {
            Write-Host $status -ForegroundColor Red
        }
        Write-Host ""

        Write-Host "  Debug Options:" -ForegroundColor Yellow
        Write-Host "  [1] View logs (last 200 lines)"
        Write-Host "  [2] View more logs (last 500 lines)"
        Write-Host "  [3] Inspect container (state, mounts, ports)"
        Write-Host "  [4] View environment variables"
        Write-Host ""
        Write-Host "  Recovery Options:" -ForegroundColor Yellow
        Write-Host "  [5] Restart service"
        Write-Host "  [6] Force recreate (pull + recreate)"
        Write-Host "  [7] Start debug mode (shell access)"
        Write-Host ""
        Write-Host "  [0] Back"
        Write-Host ""

        $action = Read-Host "  Enter choice"

        switch ($action) {
            "1" {
                Get-ContainerStartupLogs -ContainerName $ContainerName -TailLines 200
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "2" {
                Get-ContainerStartupLogs -ContainerName $ContainerName -TailLines 500
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "3" {
                Get-ContainerInspection -ContainerName $ContainerName
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "4" {
                Get-ContainerEnvironment -ContainerName $ContainerName
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "5" {
                Write-Host ""
                $confirm = Read-Host "  Restart service '$ServiceName'? (y/n)"
                if ($confirm -eq 'y') {
                    Restart-SingleService -ServiceName $ServiceName
                }
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "6" {
                Write-Host ""
                $confirm = Read-Host "  Force recreate service '$ServiceName' (will pull latest image)? (y/n)"
                if ($confirm -eq 'y') {
                    Restart-SingleService -ServiceName $ServiceName -ForceRecreate
                }
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "7" {
                Start-ContainerDebugMode -ServiceName $ServiceName
                Write-Host ""
                Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            "0" { return }
        }
    } while ($true)
}

# ============================================
# Main Execution
# ============================================

Show-DebugMenu
