#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Environment Diagnostics and Health Check Utility
.DESCRIPTION
    Provides comprehensive environment validation, health checks, and diagnostics
    for the HMS Docker deployment including port availability, disk usage,
    container health, and configuration validation.
#>

[CmdletBinding()]
param(
    [ValidateSet("full", "quick", "export")]
    [string]$Mode = "full",

    [string]$ExportPath
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")

# ============================================
# Diagnostics Functions
# ============================================

function Test-PortAvailability {
    <#
    .SYNOPSIS
        Checks if a port is available or in use
    #>
    param(
        [Parameter(Mandatory = $true)]
        [int]$Port
    )

    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        if ($connections) {
            $process = Get-Process -Id $connections[0].OwningProcess -ErrorAction SilentlyContinue
            return @{
                Available = $false
                Port = $Port
                ProcessName = if ($process) { $process.ProcessName } else { "Unknown" }
                ProcessId = $connections[0].OwningProcess
            }
        }
        return @{
            Available = $true
            Port = $Port
            ProcessName = $null
            ProcessId = $null
        }
    } catch {
        return @{
            Available = $true
            Port = $Port
            ProcessName = $null
            ProcessId = $null
        }
    }
}

function Get-DockerDiskUsage {
    <#
    .SYNOPSIS
        Gets Docker disk usage statistics
    #>
    try {
        $dfOutput = docker system df --format "{{.Type}}\t{{.Size}}\t{{.Reclaimable}}" 2>$null
        $result = @{}

        foreach ($line in $dfOutput) {
            $parts = $line -split "\t"
            if ($parts.Count -ge 3) {
                $result[$parts[0]] = @{
                    Size = $parts[1]
                    Reclaimable = $parts[2]
                }
            }
        }
        return $result
    } catch {
        return $null
    }
}

function Get-HostDiskUsage {
    <#
    .SYNOPSIS
        Gets disk usage for HMS data directories
    #>
    $projectRoot = Get-ProjectRoot
    $directories = @(
        @{ Name = "data/postgres"; Path = Join-Path $projectRoot "data\postgres" }
        @{ Name = "data/uploads"; Path = Join-Path $projectRoot "data\uploads" }
        @{ Name = "data/logs"; Path = Join-Path $projectRoot "data\logs" }
        @{ Name = "backups"; Path = Join-Path $projectRoot "backups" }
    )

    $result = @()
    foreach ($dir in $directories) {
        if (Test-Path $dir.Path) {
            $size = (Get-ChildItem -Path $dir.Path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            $sizeFormatted = if ($size -gt 1GB) {
                "{0:N2} GB" -f ($size / 1GB)
            } elseif ($size -gt 1MB) {
                "{0:N2} MB" -f ($size / 1MB)
            } else {
                "{0:N2} KB" -f ($size / 1KB)
            }
            $result += @{
                Name = $dir.Name
                Path = $dir.Path
                Size = $sizeFormatted
                SizeBytes = $size
            }
        } else {
            $result += @{
                Name = $dir.Name
                Path = $dir.Path
                Size = "Not found"
                SizeBytes = 0
            }
        }
    }
    return $result
}

function Get-ContainerResourceUsage {
    <#
    .SYNOPSIS
        Gets resource usage for HMS containers
    #>
    $containers = Get-HmsContainerNames
    $containerList = @($containers.Postgres, $containers.Backend, $containers.Frontend)
    $result = @()

    foreach ($container in $containerList) {
        if (Test-ContainerRunning -ContainerName $container) {
            $stats = docker stats $container --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>$null
            if ($stats) {
                $parts = $stats -split "\t"
                $result += @{
                    Container = $container
                    Running = $true
                    CPU = if ($parts.Count -gt 0) { $parts[0] } else { "N/A" }
                    Memory = if ($parts.Count -gt 1) { $parts[1] } else { "N/A" }
                    NetworkIO = if ($parts.Count -gt 2) { $parts[2] } else { "N/A" }
                }
            }
        } else {
            $result += @{
                Container = $container
                Running = $false
                CPU = "N/A"
                Memory = "N/A"
                NetworkIO = "N/A"
            }
        }
    }
    return $result
}

function Test-DatabaseConnection {
    <#
    .SYNOPSIS
        Tests database connectivity
    #>
    $containers = Get-HmsContainerNames
    $pgContainer = $containers.Postgres
    $pgUser = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
    $pgDb = Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db"

    if (-not (Test-ContainerRunning -ContainerName $pgContainer)) {
        return @{
            Success = $false
            Message = "PostgreSQL container is not running"
        }
    }

    $result = docker exec $pgContainer pg_isready -U $pgUser -d $pgDb 2>&1
    return @{
        Success = ($LASTEXITCODE -eq 0)
        Message = $result
    }
}

function Test-BackendHealth {
    <#
    .SYNOPSIS
        Tests backend health endpoint
    #>
    $appPort = Get-EnvValue -Key "APP_PORT" -Default "8155"
    $healthUrl = "http://localhost:$appPort/health"

    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return @{
            Success = ($response.StatusCode -eq 200)
            StatusCode = $response.StatusCode
            Message = "Health endpoint responded successfully"
        }
    } catch {
        return @{
            Success = $false
            StatusCode = $null
            Message = $_.Exception.Message
        }
    }
}

function Test-FrontendHealth {
    <#
    .SYNOPSIS
        Tests frontend availability
    #>
    $frontendPort = Get-EnvValue -Key "FRONTEND_PORT" -Default "8154"
    $frontendUrl = "http://localhost:$frontendPort"

    try {
        $response = Invoke-WebRequest -Uri $frontendUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return @{
            Success = ($response.StatusCode -eq 200)
            StatusCode = $response.StatusCode
            Message = "Frontend responded successfully"
        }
    } catch {
        return @{
            Success = $false
            StatusCode = $null
            Message = $_.Exception.Message
        }
    }
}

function Get-EnvValidation {
    <#
    .SYNOPSIS
        Validates .env file against .env.example and checks for security issues
    #>
    $projectRoot = Get-ProjectRoot
    $envPath = Join-Path $projectRoot ".env"
    $examplePath = Join-Path $projectRoot ".env.example"

    $result = @{
        EnvExists = Test-Path $envPath
        ExampleExists = Test-Path $examplePath
        MissingVars = @()
        SecurityWarnings = @()
        AllVars = @{}
    }

    if (-not $result.EnvExists) {
        return $result
    }

    # Read current .env
    $envContent = Get-Content $envPath -ErrorAction SilentlyContinue
    foreach ($line in $envContent) {
        if ($line -match "^([^#=]+)=(.*)$") {
            $result.AllVars[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }

    # Check for security issues
    $securityVars = @("JWT_SECRET_KEY", "LICENSE_ENCRYPTION_KEY", "POSTGRES_PASSWORD")
    $defaultValues = @(
        "CHANGE_THIS_GENERATE_RANDOM_STRING_MIN_32_CHARS",
        "your-secret-key-min-32-chars",
        "postgres"
    )

    foreach ($var in $securityVars) {
        $value = $result.AllVars[$var]
        if ($value) {
            foreach ($defaultVal in $defaultValues) {
                if ($value -eq $defaultVal -or $value -match "CHANGE_THIS" -or $value -match "your-secret") {
                    $result.SecurityWarnings += "$var uses default/placeholder value"
                    break
                }
            }
            if ($var -ne "POSTGRES_PASSWORD" -and $value.Length -lt 32) {
                $result.SecurityWarnings += "$var should be at least 32 characters"
            }
        }
    }

    # Compare with example if exists
    if ($result.ExampleExists) {
        $exampleContent = Get-Content $examplePath -ErrorAction SilentlyContinue
        foreach ($line in $exampleContent) {
            if ($line -match "^([^#=]+)=") {
                $varName = $Matches[1].Trim()
                if (-not $result.AllVars.ContainsKey($varName)) {
                    $result.MissingVars += $varName
                }
            }
        }
    }

    return $result
}

function Get-DockerVersion {
    <#
    .SYNOPSIS
        Gets Docker and Docker Compose versions
    #>
    try {
        $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
        $composeVersion = docker-compose version --short 2>$null
        return @{
            Docker = if ($dockerVersion) { $dockerVersion } else { "Unknown" }
            Compose = if ($composeVersion) { $composeVersion } else { "Unknown" }
        }
    } catch {
        return @{
            Docker = "Error"
            Compose = "Error"
        }
    }
}

# ============================================
# Report Generation
# ============================================

function Show-DiagnosticsReport {
    <#
    .SYNOPSIS
        Displays comprehensive diagnostics report
    #>
    param(
        [switch]$Quick
    )

    Clear-Host
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   HMS Environment Diagnostics Report" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host ""

    # Docker Status
    Write-Host "  [Docker Status]" -ForegroundColor Yellow
    $versions = Get-DockerVersion
    if (Test-DockerRunning) {
        Write-Host "    Docker Engine: " -NoNewline; Write-Host "Running (v$($versions.Docker))" -ForegroundColor Green
        Write-Host "    Docker Compose: v$($versions.Compose)" -ForegroundColor DarkGray
    } else {
        Write-Host "    Docker Engine: " -NoNewline; Write-Host "NOT Running" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Please start Docker Desktop and try again." -ForegroundColor Yellow
        return
    }
    Write-Host ""

    # Container Status
    Write-Host "  [Container Status]" -ForegroundColor Yellow
    $containers = Get-HmsContainerNames
    $containerList = @(
        @{ Name = $containers.Postgres; Label = "PostgreSQL" }
        @{ Name = $containers.Backend; Label = "Backend/FastAPI" }
        @{ Name = $containers.Frontend; Label = "Frontend/Next.js" }
    )

    foreach ($c in $containerList) {
        $status = Get-ContainerStatus -ContainerName $c.Name
        $health = Get-ContainerHealth -ContainerName $c.Name
        Write-Host "    $($c.Name): " -NoNewline

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
            Write-Host "$status" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    # Port Availability
    Write-Host "  [Port Status]" -ForegroundColor Yellow
    $ports = @(
        @{ Port = [int](Get-EnvValue -Key "POSTGRES_PORT" -Default "5444"); Service = "PostgreSQL" }
        @{ Port = [int](Get-EnvValue -Key "APP_PORT" -Default "8155"); Service = "Backend" }
        @{ Port = [int](Get-EnvValue -Key "FRONTEND_PORT" -Default "8154"); Service = "Frontend" }
    )

    foreach ($p in $ports) {
        $portStatus = Test-PortAvailability -Port $p.Port
        Write-Host "    $($p.Port) ($($p.Service)): " -NoNewline
        if ($portStatus.Available) {
            Write-Host "Available" -ForegroundColor Green
        } else {
            Write-Host "In use by $($portStatus.ProcessName) (PID: $($portStatus.ProcessId))" -ForegroundColor Yellow
        }
    }
    Write-Host ""

    if (-not $Quick) {
        # Resource Usage
        Write-Host "  [Resource Usage]" -ForegroundColor Yellow
        $resources = Get-ContainerResourceUsage
        Write-Host "    Container                    CPU      Memory           Network I/O" -ForegroundColor DarkGray
        Write-Host "    -------------------------------------------------------------------------" -ForegroundColor DarkGray
        foreach ($r in $resources) {
            if ($r.Running) {
                $containerPadded = $r.Container.PadRight(28)
                $cpuPadded = $r.CPU.PadRight(8)
                $memPadded = $r.Memory.PadRight(16)
                Write-Host "    $containerPadded $cpuPadded $memPadded $($r.NetworkIO)"
            } else {
                Write-Host "    $($r.Container.PadRight(28)) " -NoNewline
                Write-Host "Not running" -ForegroundColor DarkGray
            }
        }
        Write-Host ""

        # Disk Usage
        Write-Host "  [Disk Usage]" -ForegroundColor Yellow
        Write-Host "    Docker:" -ForegroundColor DarkGray
        $dockerDisk = Get-DockerDiskUsage
        if ($dockerDisk) {
            foreach ($key in $dockerDisk.Keys) {
                Write-Host "      $($key): $($dockerDisk[$key].Size) (Reclaimable: $($dockerDisk[$key].Reclaimable))"
            }
        }
        Write-Host ""
        Write-Host "    Host Directories:" -ForegroundColor DarkGray
        $hostDisk = Get-HostDiskUsage
        foreach ($dir in $hostDisk) {
            Write-Host "      $($dir.Name): $($dir.Size)"
        }
        Write-Host ""

        # Connectivity Tests
        Write-Host "  [Connectivity Tests]" -ForegroundColor Yellow
        $dbTest = Test-DatabaseConnection
        Write-Host "    Database: " -NoNewline
        if ($dbTest.Success) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "FAILED - $($dbTest.Message)" -ForegroundColor Red
        }

        $backendTest = Test-BackendHealth
        Write-Host "    Backend /health: " -NoNewline
        if ($backendTest.Success) {
            Write-Host "OK ($($backendTest.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "FAILED" -ForegroundColor Red
        }

        $frontendTest = Test-FrontendHealth
        Write-Host "    Frontend: " -NoNewline
        if ($frontendTest.Success) {
            Write-Host "OK ($($frontendTest.StatusCode))" -ForegroundColor Green
        } else {
            Write-Host "FAILED" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Environment Validation
    Write-Host "  [Environment Validation]" -ForegroundColor Yellow
    $envValidation = Get-EnvValidation
    Write-Host "    .env file: " -NoNewline
    if ($envValidation.EnvExists) {
        Write-Host "Found" -ForegroundColor Green
    } else {
        Write-Host "NOT FOUND" -ForegroundColor Red
    }

    if ($envValidation.MissingVars.Count -gt 0) {
        Write-Host "    Missing variables:" -ForegroundColor Yellow
        foreach ($var in $envValidation.MissingVars) {
            Write-Host "      - $var" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    Required variables: All present" -ForegroundColor DarkGray
    }

    if ($envValidation.SecurityWarnings.Count -gt 0) {
        Write-Host ""
        Write-Host "    Security warnings:" -ForegroundColor Red
        foreach ($warning in $envValidation.SecurityWarnings) {
            Write-Host "      - $warning" -ForegroundColor Red
        }
    }
    Write-Host ""

    # Recommendations
    $recommendations = @()
    if ($envValidation.SecurityWarnings.Count -gt 0) {
        $recommendations += "Change default security keys in .env"
    }
    $dockerDisk = Get-DockerDiskUsage
    if ($dockerDisk -and $dockerDisk["Build Cache"]) {
        $reclaimable = $dockerDisk["Build Cache"].Reclaimable
        if ($reclaimable -and $reclaimable -ne "0B") {
            $recommendations += "Consider cleanup - $reclaimable build cache available"
        }
    }

    if ($recommendations.Count -gt 0) {
        Write-Host "  [Recommendations]" -ForegroundColor Yellow
        $i = 1
        foreach ($rec in $recommendations) {
            Write-Host "    $i. $rec"
            $i++
        }
        Write-Host ""
    }

    Write-Host "  ========================================" -ForegroundColor Cyan
}

function Export-DiagnosticsReport {
    <#
    .SYNOPSIS
        Exports diagnostics report to a file
    #>
    param(
        [string]$OutputPath
    )

    $projectRoot = Get-ProjectRoot
    if (-not $OutputPath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $OutputPath = Join-Path $projectRoot "data\logs\diagnostics_$timestamp.txt"
    }

    # Ensure directory exists
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Capture output
    $report = @()
    $report += "HMS Environment Diagnostics Report"
    $report += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report += "=" * 50
    $report += ""

    # Docker Status
    $versions = Get-DockerVersion
    $report += "[Docker Status]"
    $report += "  Docker Engine: $(if (Test-DockerRunning) { "Running (v$($versions.Docker))" } else { "NOT Running" })"
    $report += "  Docker Compose: v$($versions.Compose)"
    $report += ""

    # Container Status
    $report += "[Container Status]"
    $containers = Get-HmsContainerNames
    foreach ($name in @($containers.Postgres, $containers.Backend, $containers.Frontend)) {
        $status = Get-ContainerStatus -ContainerName $name
        $health = Get-ContainerHealth -ContainerName $name
        $report += "  $name : $status ($health)"
    }
    $report += ""

    # Port Status
    $report += "[Port Status]"
    $ports = @(
        @{ Port = [int](Get-EnvValue -Key "POSTGRES_PORT" -Default "5444"); Service = "PostgreSQL" }
        @{ Port = [int](Get-EnvValue -Key "APP_PORT" -Default "8155"); Service = "Backend" }
        @{ Port = [int](Get-EnvValue -Key "FRONTEND_PORT" -Default "8154"); Service = "Frontend" }
    )
    foreach ($p in $ports) {
        $portStatus = Test-PortAvailability -Port $p.Port
        $status = if ($portStatus.Available) { "Available" } else { "In use by $($portStatus.ProcessName)" }
        $report += "  $($p.Port) ($($p.Service)): $status"
    }
    $report += ""

    # Resource Usage
    $report += "[Resource Usage]"
    $resources = Get-ContainerResourceUsage
    foreach ($r in $resources) {
        if ($r.Running) {
            $report += "  $($r.Container): CPU=$($r.CPU), Memory=$($r.Memory), Network=$($r.NetworkIO)"
        } else {
            $report += "  $($r.Container): Not running"
        }
    }
    $report += ""

    # Disk Usage
    $report += "[Disk Usage - Docker]"
    $dockerDisk = Get-DockerDiskUsage
    if ($dockerDisk) {
        foreach ($key in $dockerDisk.Keys) {
            $report += "  $key : $($dockerDisk[$key].Size) (Reclaimable: $($dockerDisk[$key].Reclaimable))"
        }
    }
    $report += ""

    $report += "[Disk Usage - Host]"
    $hostDisk = Get-HostDiskUsage
    foreach ($dir in $hostDisk) {
        $report += "  $($dir.Name): $($dir.Size)"
    }
    $report += ""

    # Connectivity Tests
    $report += "[Connectivity Tests]"
    $dbTest = Test-DatabaseConnection
    $report += "  Database: $(if ($dbTest.Success) { 'OK' } else { "FAILED - $($dbTest.Message)" })"
    $backendTest = Test-BackendHealth
    $report += "  Backend /health: $(if ($backendTest.Success) { "OK ($($backendTest.StatusCode))" } else { 'FAILED' })"
    $frontendTest = Test-FrontendHealth
    $report += "  Frontend: $(if ($frontendTest.Success) { "OK ($($frontendTest.StatusCode))" } else { 'FAILED' })"
    $report += ""

    # Environment Validation
    $report += "[Environment Validation]"
    $envValidation = Get-EnvValidation
    $report += "  .env file: $(if ($envValidation.EnvExists) { 'Found' } else { 'NOT FOUND' })"
    if ($envValidation.SecurityWarnings.Count -gt 0) {
        $report += "  Security warnings:"
        foreach ($warning in $envValidation.SecurityWarnings) {
            $report += "    - $warning"
        }
    }
    $report += ""

    # Write to file
    $report | Out-File -FilePath $OutputPath -Encoding UTF8

    Write-Log "Diagnostics report exported to: $OutputPath" -Level SUCCESS
    return $OutputPath
}

# ============================================
# Main Execution
# ============================================

switch ($Mode) {
    "full" {
        Show-DiagnosticsReport
    }
    "quick" {
        Show-DiagnosticsReport -Quick
    }
    "export" {
        Export-DiagnosticsReport -OutputPath $ExportPath
    }
}
