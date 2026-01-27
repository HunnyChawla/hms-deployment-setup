#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Container Script Execution Utility
.DESCRIPTION
    Provides functionality to run SQL scripts in PostgreSQL container,
    Python scripts in the backend container, and Alembic migrations.
.PARAMETER Action
    The action to perform: SQL, Python, or Alembic
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("SQL", "Python", "Alembic")]
    [string]$Action
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")
. (Join-Path $PSScriptRoot "file-browser.ps1")

# ============================================
# SQL Script Execution
# ============================================

function Invoke-SqlScript {
    <#
    .SYNOPSIS
        Runs a SQL script in the PostgreSQL container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string]$Database,
        [switch]$DryRun
    )

    $containers = Get-HmsContainerNames
    $pgContainer = $containers.Postgres
    $pgUser = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
    $pgDb = if ($Database) { $Database } else { Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db" }

    # Validate container is running
    if (-not (Test-ContainerRunning -ContainerName $pgContainer)) {
        Write-Log "PostgreSQL container '$pgContainer' is not running" -Level ERROR
        return $false
    }

    # Validate script file exists
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "SQL script not found: $ScriptPath" -Level ERROR
        return $false
    }

    # Show preview
    Write-Host ""
    Write-Host "  SQL Script Preview (first 20 lines):" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Get-Content $ScriptPath -Head 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $lineCount = (Get-Content $ScriptPath | Measure-Object -Line).Lines
    if ($lineCount -gt 20) {
        Write-Host "  ... ($($lineCount - 20) more lines)" -ForegroundColor DarkGray
    }
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    if ($DryRun) {
        Write-Log "Dry run - would execute: docker exec -i $pgContainer psql -U $pgUser -d $pgDb < $ScriptPath" -Level INFO
        return $true
    }

    # Confirm execution
    $confirm = Read-Host "  Execute this script against database '$pgDb'? (y/n)"
    if ($confirm -ne 'y') {
        Write-Log "Operation cancelled" -Level WARN
        return $false
    }

    Write-Step "Executing SQL script..."
    try {
        $scriptContent = Get-Content $ScriptPath -Raw
        $result = $scriptContent | docker exec -i $pgContainer psql -U $pgUser -d $pgDb 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Log "SQL script executed successfully" -Level SUCCESS
            Write-Host ""
            Write-Host "  Output:" -ForegroundColor Yellow
            Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
            $result | ForEach-Object { Write-Host "  $_" }
            Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
            return $true
        } else {
            Write-Log "SQL script execution failed" -Level ERROR
            Write-Host "  $result" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Log "Error executing SQL script: $_" -Level ERROR
        return $false
    }
}

function Invoke-SqlCommand {
    <#
    .SYNOPSIS
        Runs a single SQL command in the PostgreSQL container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlCommand,

        [string]$Database
    )

    $containers = Get-HmsContainerNames
    $pgContainer = $containers.Postgres
    $pgUser = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
    $pgDb = if ($Database) { $Database } else { Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db" }

    if (-not (Test-ContainerRunning -ContainerName $pgContainer)) {
        Write-Log "PostgreSQL container '$pgContainer' is not running" -Level ERROR
        return $null
    }

    try {
        $result = docker exec $pgContainer psql -U $pgUser -d $pgDb -c "$SqlCommand" 2>&1
        if ($LASTEXITCODE -eq 0) {
            return $result
        } else {
            Write-Log "SQL command failed: $result" -Level ERROR
            return $null
        }
    } catch {
        Write-Log "Error executing SQL command: $_" -Level ERROR
        return $null
    }
}

function Show-SqlMenu {
    <#
    .SYNOPSIS
        Interactive menu for SQL script execution
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Run SQL Script in PostgreSQL" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check container
    $containers = Get-HmsContainerNames
    if (-not (Test-ContainerRunning -ContainerName $containers.Postgres)) {
        Write-Log "PostgreSQL container is not running. Please start it first." -Level ERROR
        return
    }

    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "  [1] Run SQL file from disk (interactive browser)"
    Write-Host "  [2] Run SQL command directly"
    Write-Host "  [3] Open interactive psql session"
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    switch ($choice) {
        "1" {
            Write-Host ""
            # Use interactive file selection
            $scriptPath = Select-HostFile -Title "Select SQL Script" -Filter "SQL Files|*.sql"

            if (-not $scriptPath) {
                Write-Log "No file selected" -Level WARN
                return
            }

            # Validate the file operation
            $validation = Test-FileOperation -Operation "Read" -SourcePath $scriptPath
            if (-not $validation.IsValid) {
                foreach ($err in $validation.Errors) {
                    Write-Log $err -Level ERROR
                }
                return
            }
            foreach ($warn in $validation.Warnings) {
                Write-Log $warn -Level WARN
            }

            # Show file preview
            Write-Host ""
            Show-FilePreview -FilePath $scriptPath -MaxLines 20
            Write-Host ""

            # Invoke the SQL script
            Invoke-SqlScript -ScriptPath $scriptPath
        }
        "2" {
            Write-Host ""
            Write-Host "  Enter SQL command (single line):" -ForegroundColor Yellow
            $sqlCmd = Read-Host "  SQL"
            if ($sqlCmd) {
                Write-Host ""
                $result = Invoke-SqlCommand -SqlCommand $sqlCmd
                if ($result) {
                    Write-Host "  Result:" -ForegroundColor Yellow
                    $result | ForEach-Object { Write-Host "  $_" }
                }
            }
        }
        "3" {
            Write-Host ""
            Write-Host "  Starting interactive psql session..." -ForegroundColor Yellow
            Write-Host "  Type '\q' to exit" -ForegroundColor DarkGray
            Write-Host ""
            $pgUser = Get-EnvValue -Key "POSTGRES_USER" -Default "postgres"
            $pgDb = Get-EnvValue -Key "POSTGRES_DB" -Default "hms_db"
            docker exec -it $containers.Postgres psql -U $pgUser -d $pgDb
        }
        "0" {
            Write-Log "Operation cancelled" -Level WARN
        }
    }
}

# ============================================
# Python Script Execution
# ============================================

function Invoke-PythonScript {
    <#
    .SYNOPSIS
        Runs a Python script in the backend container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,

        [string[]]$Arguments
    )

    $containers = Get-HmsContainerNames
    $backendContainer = $containers.Backend

    # Validate container is running
    if (-not (Test-ContainerRunning -ContainerName $backendContainer)) {
        Write-Log "Backend container '$backendContainer' is not running" -Level ERROR
        return $false
    }

    # Validate script file exists
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Python script not found: $ScriptPath" -Level ERROR
        return $false
    }

    $scriptName = Split-Path -Leaf $ScriptPath
    $containerScriptPath = "/tmp/$scriptName"

    # Show preview
    Write-Host ""
    Write-Host "  Python Script Preview (first 30 lines):" -ForegroundColor Yellow
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Get-Content $ScriptPath -Head 30 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $lineCount = (Get-Content $ScriptPath | Measure-Object -Line).Lines
    if ($lineCount -gt 30) {
        Write-Host "  ... ($($lineCount - 30) more lines)" -ForegroundColor DarkGray
    }
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    # Confirm execution
    $argsDisplay = if ($Arguments) { $Arguments -join " " } else { "(none)" }
    Write-Host "  Script: $scriptName" -ForegroundColor DarkGray
    Write-Host "  Arguments: $argsDisplay" -ForegroundColor DarkGray
    Write-Host ""
    $confirm = Read-Host "  Execute this script in backend container? (y/n)"
    if ($confirm -ne 'y') {
        Write-Log "Operation cancelled" -Level WARN
        return $false
    }

    Write-Step "Copying script to container..."
    try {
        # Copy script to container
        docker cp $ScriptPath "${backendContainer}:${containerScriptPath}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to copy script to container" -Level ERROR
            return $false
        }
        Write-SubStep "Script copied to $containerScriptPath"

        # Execute script
        Write-Step "Executing Python script..."
        $pythonCmd = "python $containerScriptPath"
        if ($Arguments) {
            $pythonCmd += " " + ($Arguments -join " ")
        }

        # Run with output streaming
        docker exec $backendContainer sh -c $pythonCmd
        $exitCode = $LASTEXITCODE

        # Cleanup
        Write-Step "Cleaning up..."
        docker exec $backendContainer rm -f $containerScriptPath 2>$null
        Write-SubStep "Temporary script removed"

        if ($exitCode -eq 0) {
            Write-Log "Python script executed successfully" -Level SUCCESS
            return $true
        } else {
            Write-Log "Python script exited with code $exitCode" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "Error executing Python script: $_" -Level ERROR
        # Attempt cleanup
        docker exec $backendContainer rm -f $containerScriptPath 2>$null
        return $false
    }
}

function Show-PythonMenu {
    <#
    .SYNOPSIS
        Interactive menu for Python script execution
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Run Python Script in Backend" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check container
    $containers = Get-HmsContainerNames
    if (-not (Test-ContainerRunning -ContainerName $containers.Backend)) {
        Write-Log "Backend container is not running. Please start it first." -Level ERROR
        return
    }

    Write-Host "  The script will run using the Poetry-managed Python environment" -ForegroundColor DarkGray
    Write-Host "  inside the backend container (/app/.venv/bin/python)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "  [1] Run Python file from disk (interactive browser)"
    Write-Host "  [2] Run Python command directly"
    Write-Host "  [3] Open interactive Python shell"
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    switch ($choice) {
        "1" {
            Write-Host ""
            # Use interactive file selection
            $scriptPath = Select-HostFile -Title "Select Python Script" -Filter "Python Files|*.py"

            if (-not $scriptPath) {
                Write-Log "No file selected" -Level WARN
                return
            }

            # Validate the file operation
            $validation = Test-FileOperation -Operation "Read" -SourcePath $scriptPath
            if (-not $validation.IsValid) {
                foreach ($err in $validation.Errors) {
                    Write-Log $err -Level ERROR
                }
                return
            }
            foreach ($warn in $validation.Warnings) {
                Write-Log $warn -Level WARN
            }

            # Show file preview
            Write-Host ""
            Show-FilePreview -FilePath $scriptPath -MaxLines 30
            Write-Host ""

            # Ask for arguments
            Write-Host "  Enter arguments (or press Enter for none):" -ForegroundColor Yellow
            $args = Read-Host "  Arguments"
            $argArray = if ($args) { $args -split " " } else { @() }

            # Invoke the Python script
            Invoke-PythonScript -ScriptPath $scriptPath -Arguments $argArray
        }
        "2" {
            Write-Host ""
            Write-Host "  Enter Python command:" -ForegroundColor Yellow
            $pyCmd = Read-Host "  python -c"
            if ($pyCmd) {
                Write-Host ""
                docker exec $containers.Backend python -c "$pyCmd"
            }
        }
        "3" {
            Write-Host ""
            Write-Host "  Starting interactive Python shell..." -ForegroundColor Yellow
            Write-Host "  Type 'exit()' to quit" -ForegroundColor DarkGray
            Write-Host ""
            docker exec -it $containers.Backend python
        }
        "0" {
            Write-Log "Operation cancelled" -Level WARN
        }
    }
}

# ============================================
# Alembic Migration Management
# ============================================

function Invoke-AlembicCommand {
    <#
    .SYNOPSIS
        Runs an Alembic command in the backend container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("upgrade", "downgrade", "current", "history", "heads", "branches")]
        [string]$Command,

        [string]$Revision = "head"
    )

    $containers = Get-HmsContainerNames
    $backendContainer = $containers.Backend

    if (-not (Test-ContainerRunning -ContainerName $backendContainer)) {
        Write-Log "Backend container '$backendContainer' is not running" -Level ERROR
        return $false
    }

    $alembicCmd = switch ($Command) {
        "upgrade" { "alembic upgrade $Revision" }
        "downgrade" { "alembic downgrade $Revision" }
        "current" { "alembic current" }
        "history" { "alembic history --verbose" }
        "heads" { "alembic heads" }
        "branches" { "alembic branches" }
    }

    Write-Step "Running: $alembicCmd"
    try {
        docker exec $backendContainer sh -c "cd /app && $alembicCmd"
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Alembic command completed successfully" -Level SUCCESS
            return $true
        } else {
            Write-Log "Alembic command failed" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "Error running Alembic: $_" -Level ERROR
        return $false
    }
}

function Show-AlembicMenu {
    <#
    .SYNOPSIS
        Interactive menu for Alembic migrations
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Alembic Database Migrations" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Check container
    $containers = Get-HmsContainerNames
    if (-not (Test-ContainerRunning -ContainerName $containers.Backend)) {
        Write-Log "Backend container is not running. Please start it first." -Level ERROR
        return
    }

    # Show current status
    Write-Host "  Current migration status:" -ForegroundColor Yellow
    docker exec $containers.Backend sh -c "cd /app && alembic current" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    Write-Host ""

    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "  [1] Upgrade to latest (head)"
    Write-Host "  [2] Upgrade to specific revision"
    Write-Host "  [3] Downgrade by 1 revision"
    Write-Host "  [4] Downgrade to specific revision"
    Write-Host "  [5] Show migration history"
    Write-Host "  [6] Show current revision"
    Write-Host "  [7] Show available heads"
    Write-Host "  [0] Cancel"
    Write-Host ""

    $choice = Read-Host "  Enter choice"

    switch ($choice) {
        "1" {
            Write-Host ""
            $confirm = Read-Host "  Upgrade database to latest migration? (y/n)"
            if ($confirm -eq 'y') {
                Invoke-AlembicCommand -Command "upgrade" -Revision "head"
            }
        }
        "2" {
            Write-Host ""
            Write-Host "  Enter target revision (e.g., 'abc123' or '+2' for relative):" -ForegroundColor Yellow
            $revision = Read-Host "  Revision"
            if ($revision) {
                Invoke-AlembicCommand -Command "upgrade" -Revision $revision
            }
        }
        "3" {
            Write-Host ""
            if (Confirm-DestructiveAction -ActionDescription "This will downgrade the database by 1 migration revision." -ConfirmationWord "downgrade") {
                Invoke-AlembicCommand -Command "downgrade" -Revision "-1"
            }
        }
        "4" {
            Write-Host ""
            Write-Host "  Enter target revision (e.g., 'abc123' or '-2' for relative):" -ForegroundColor Yellow
            $revision = Read-Host "  Revision"
            if ($revision) {
                if (Confirm-DestructiveAction -ActionDescription "This will downgrade the database to revision: $revision" -ConfirmationWord "downgrade") {
                    Invoke-AlembicCommand -Command "downgrade" -Revision $revision
                }
            }
        }
        "5" {
            Invoke-AlembicCommand -Command "history"
        }
        "6" {
            Invoke-AlembicCommand -Command "current"
        }
        "7" {
            Invoke-AlembicCommand -Command "heads"
        }
        "0" {
            Write-Log "Operation cancelled" -Level WARN
        }
    }
}

# ============================================
# Main Execution
# ============================================

switch ($Action) {
    "SQL" {
        Show-SqlMenu
    }
    "Python" {
        Show-PythonMenu
    }
    "Alembic" {
        Show-AlembicMenu
    }
}
