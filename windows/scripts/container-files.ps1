#Requires -Version 5.1
<#
.SYNOPSIS
    HMS Container File Management Utility
.DESCRIPTION
    Provides functionality to copy, delete, edit, and browse files
    inside Docker containers without rebuilding images.
.PARAMETER Action
    The action to perform: Copy, Delete, Edit, or Browse
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Copy", "Delete", "Edit", "Browse")]
    [string]$Action
)

# Source common functions
. (Join-Path $PSScriptRoot "common.ps1")
. (Join-Path $PSScriptRoot "file-browser.ps1")

# ============================================
# File Copy Functions
# ============================================

function Copy-ToContainer {
    <#
    .SYNOPSIS
        Copies a file from host to container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    # Validate source exists
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Source file not found: $SourcePath" -Level ERROR
        return $false
    }

    # Validate container is running
    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $false
    }

    Write-Step "Copying file to container..."
    Write-SubStep "Source: $SourcePath"
    Write-SubStep "Destination: ${ContainerName}:${DestinationPath}"

    try {
        docker cp "$SourcePath" "${ContainerName}:${DestinationPath}" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "File copied successfully" -Level SUCCESS
            return $true
        } else {
            Write-Log "Failed to copy file" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "Error copying file: $_" -Level ERROR
        return $false
    }
}

function Copy-FromContainer {
    <#
    .SYNOPSIS
        Copies a file from container to host
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    # Validate container is running
    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $false
    }

    Write-Step "Copying file from container..."
    Write-SubStep "Source: ${ContainerName}:${SourcePath}"
    Write-SubStep "Destination: $DestinationPath"

    try {
        docker cp "${ContainerName}:${SourcePath}" "$DestinationPath" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "File copied successfully" -Level SUCCESS
            return $true
        } else {
            Write-Log "Failed to copy file" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "Error copying file: $_" -Level ERROR
        return $false
    }
}

function Show-CopyMenu {
    <#
    .SYNOPSIS
        Interactive menu for file copy operations with file browser support
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Copy Files To/From Container" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "  Direction:" -ForegroundColor Yellow
    Write-Host "  [1] Copy file TO container (host -> container)"
    Write-Host "  [2] Copy file FROM container (container -> host)"
    Write-Host "  [0] Cancel"
    Write-Host ""

    $direction = Read-Host "  Enter choice"

    if ($direction -eq "0") {
        Write-Log "Operation cancelled" -Level WARN
        return
    }

    if ($direction -notin @("1", "2")) {
        Write-Log "Invalid choice" -Level ERROR
        return
    }

    # Select container
    $container = Select-Container
    if (-not $container) {
        Write-Log "No container selected" -Level WARN
        return
    }

    if ($direction -eq "1") {
        # Copy TO container - use interactive file browser
        $sourcePath = Select-HostFile -Title "Select file to copy to container"

        if (-not $sourcePath) {
            Write-Log "No file selected" -Level WARN
            return
        }

        # Validate the file
        $validation = Test-FileOperation -Operation "Copy" -SourcePath $sourcePath
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
        Show-FilePreview -FilePath $sourcePath -MaxLines 10

        # Select destination in container
        Write-Host ""
        $destPath = Select-ContainerPath -ContainerName $container

        if (-not $destPath) {
            Write-Log "No destination selected" -Level WARN
            return
        }

        Write-Host ""
        Write-Host "  Summary:" -ForegroundColor Yellow
        Write-Host "    Source: $sourcePath" -ForegroundColor DarkGray
        Write-Host "    Destination: ${container}:${destPath}" -ForegroundColor DarkGray
        Write-Host ""
        $confirm = Read-Host "  Proceed with copy? (y/n)"
        if ($confirm -eq 'y') {
            Copy-ToContainer -ContainerName $container -SourcePath $sourcePath -DestinationPath $destPath

            # Ask about restart
            Write-Host ""
            $restart = Read-Host "  Restart the container to apply changes? (y/n)"
            if ($restart -eq 'y') {
                $serviceName = Get-ServiceNameFromContainer -ContainerName $container
                if ($serviceName) {
                    $projectRoot = Get-ProjectRoot
                    Push-Location $projectRoot
                    docker-compose restart $serviceName
                    Pop-Location
                    Write-Log "Container restarted" -Level SUCCESS
                }
            }
        }
    } else {
        # Copy FROM container - use interactive container browser
        $sourcePath = Select-ContainerFile -ContainerName $container

        if (-not $sourcePath) {
            Write-Log "No file selected" -Level WARN
            return
        }

        # Show file preview
        Show-FilePreview -ContainerName $container -FilePath $sourcePath -MaxLines 10

        # Select destination on host
        Write-Host ""
        $destPath = Select-HostFolder -Title "Select destination folder"

        if (-not $destPath) {
            Write-Log "No destination selected" -Level WARN
            return
        }

        Write-Host ""
        Write-Host "  Summary:" -ForegroundColor Yellow
        Write-Host "    Source: ${container}:${sourcePath}" -ForegroundColor DarkGray
        Write-Host "    Destination: $destPath" -ForegroundColor DarkGray
        Write-Host ""
        $confirm = Read-Host "  Proceed with copy? (y/n)"
        if ($confirm -eq 'y') {
            Copy-FromContainer -ContainerName $container -SourcePath $sourcePath -DestinationPath $destPath
        }
    }
}

# ============================================
# File Delete Functions
# ============================================

function Remove-ContainerFile {
    <#
    .SYNOPSIS
        Deletes a file or directory from a container
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [switch]$Recursive
    )

    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $false
    }

    $rmCmd = if ($Recursive) { "rm -rf" } else { "rm -f" }

    Write-Step "Deleting file from container..."
    Write-SubStep "Target: ${ContainerName}:${FilePath}"

    try {
        docker exec $ContainerName sh -c "$rmCmd '$FilePath'" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "File deleted successfully" -Level SUCCESS
            return $true
        } else {
            Write-Log "Failed to delete file" -Level ERROR
            return $false
        }
    } catch {
        Write-Log "Error deleting file: $_" -Level ERROR
        return $false
    }
}

function Show-DeleteMenu {
    <#
    .SYNOPSIS
        Interactive menu for file delete operations with file browser support
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Delete Files From Container" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Select container
    $container = Select-Container
    if (-not $container) {
        Write-Log "No container selected" -Level WARN
        return
    }

    # Use interactive browser to select file
    $filePath = Select-ContainerFile -ContainerName $container

    if (-not $filePath) {
        Write-Log "No file selected" -Level WARN
        return
    }

    # Validate operation
    $validation = Test-FileOperation -Operation "Delete" -SourcePath $filePath -ContainerName $container
    foreach ($warn in $validation.Warnings) {
        Write-Log $warn -Level WARN
    }

    # Show file preview
    Show-FilePreview -ContainerName $container -FilePath $filePath -MaxLines 10

    Write-Host ""
    $recursive = Read-Host "  Delete recursively (for directories)? (y/n)"
    $isRecursive = ($recursive -eq 'y')

    Write-Host ""
    $actionDesc = if ($isRecursive) { "recursively delete '$filePath' from container '$container'" } else { "delete '$filePath' from container '$container'" }

    if (Confirm-DestructiveAction -ActionDescription "This will $actionDesc" -ConfirmationWord "delete") {
        Remove-ContainerFile -ContainerName $container -FilePath $filePath -Recursive:$isRecursive
    } else {
        Write-Log "Operation cancelled" -Level WARN
    }
}

# ============================================
# File Edit Functions
# ============================================

function Edit-ContainerFile {
    <#
    .SYNOPSIS
        Edits a file inside a container using local editor
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return $false
    }

    # Get temp path
    $tempDir = Get-TempEditPath
    $fileName = Split-Path -Leaf $FilePath
    $tempFile = Join-Path $tempDir $fileName
    $backupFile = Join-Path $tempDir "$fileName.backup"

    Write-Step "Preparing file for editing..."

    # Copy file from container
    Write-SubStep "Copying file from container..."
    docker cp "${ContainerName}:${FilePath}" $tempFile 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Failed to copy file from container. File may not exist." -Level ERROR
        return $false
    }

    # Create backup
    Copy-Item $tempFile $backupFile -Force

    # Get file info
    $originalContent = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
    $originalSize = (Get-Item $tempFile).Length

    Write-SubStep "File copied to: $tempFile"
    Write-Host ""
    Write-Host "  Opening file in editor..." -ForegroundColor Yellow
    Write-Host "  Close the editor when done to continue." -ForegroundColor DarkGray
    Write-Host ""

    # Determine editor
    $editor = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }

    # Open editor and wait
    $editorProcess = Start-Process $editor -ArgumentList "`"$tempFile`"" -PassThru -Wait

    # Check if file was modified
    $newContent = Get-Content $tempFile -Raw -ErrorAction SilentlyContinue
    $newSize = (Get-Item $tempFile).Length

    if ($originalContent -eq $newContent) {
        Write-Log "No changes detected" -Level INFO
        # Cleanup
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
        return $true
    }

    # Show diff summary
    Write-Host ""
    Write-Host "  Changes detected:" -ForegroundColor Yellow
    Write-Host "    Original size: $originalSize bytes" -ForegroundColor DarkGray
    Write-Host "    New size: $newSize bytes" -ForegroundColor DarkGray
    Write-Host ""

    $confirm = Read-Host "  Copy changes back to container? (y/n)"
    if ($confirm -ne 'y') {
        Write-Log "Changes discarded" -Level WARN
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Copy back to container
    Write-Step "Applying changes..."
    docker cp $tempFile "${ContainerName}:${FilePath}" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "File updated successfully" -Level SUCCESS

        # Ask about restart
        Write-Host ""
        $restart = Read-Host "  Restart the container to apply changes? (y/n)"
        if ($restart -eq 'y') {
            $serviceName = Get-ServiceNameFromContainer -ContainerName $ContainerName
            if ($serviceName) {
                $projectRoot = Get-ProjectRoot
                Push-Location $projectRoot
                docker-compose restart $serviceName
                Pop-Location
                Write-Log "Container restarted" -Level SUCCESS
            }
        }

        # Cleanup
        Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        Remove-Item $backupFile -Force -ErrorAction SilentlyContinue
        return $true
    } else {
        Write-Log "Failed to copy file back to container" -Level ERROR
        Write-Log "Backup saved at: $backupFile" -Level INFO
        return $false
    }
}

function Show-EditMenu {
    <#
    .SYNOPSIS
        Interactive menu for file edit operations with file browser support
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Edit File In Container" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  This will:" -ForegroundColor DarkGray
    Write-Host "    1. Copy the file to your local machine" -ForegroundColor DarkGray
    Write-Host "    2. Open it in your editor (notepad or `$env:EDITOR)" -ForegroundColor DarkGray
    Write-Host "    3. Copy it back after you save and close" -ForegroundColor DarkGray
    Write-Host ""

    # Select container
    $container = Select-Container
    if (-not $container) {
        Write-Log "No container selected" -Level WARN
        return
    }

    # Use interactive browser to select file
    $filePath = Select-ContainerFile -ContainerName $container

    if (-not $filePath) {
        Write-Log "No file selected" -Level WARN
        return
    }

    # Show file preview before editing
    Show-FilePreview -ContainerName $container -FilePath $filePath -MaxLines 15

    Write-Host ""
    $confirm = Read-Host "  Edit this file? (y/n)"
    if ($confirm -eq 'y') {
        Edit-ContainerFile -ContainerName $container -FilePath $filePath
    } else {
        Write-Log "Operation cancelled" -Level WARN
    }
}

# ============================================
# File Browse Functions
# ============================================

function Get-ContainerFileListing {
    <#
    .SYNOPSIS
        Lists files in a container directory
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [string]$Path = "/",
        [switch]$Recursive
    )

    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Log "Container '$ContainerName' is not running" -Level ERROR
        return
    }

    $lsCmd = if ($Recursive) { "ls -laR" } else { "ls -la" }

    try {
        $result = docker exec $ContainerName sh -c "$lsCmd '$Path'" 2>&1
        return $result
    } catch {
        Write-Log "Error listing files: $_" -Level ERROR
        return $null
    }
}

function Show-BrowseMenu {
    <#
    .SYNOPSIS
        Interactive menu for browsing container files using enhanced browser
    #>
    Write-Host ""
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host "   Browse Container Files" -ForegroundColor Cyan
    Write-Host "  ========================================" -ForegroundColor Cyan
    Write-Host ""

    # Select container
    $container = Select-Container
    if (-not $container) {
        Write-Log "No container selected" -Level WARN
        return
    }

    $containers = Get-HmsContainerNames

    # Set default starting path based on container
    $startPath = "/"
    switch ($container) {
        $containers.Backend { $startPath = "/app" }
        $containers.Postgres { $startPath = "/var/lib/postgresql/data" }
        $containers.Frontend { $startPath = "/app" }
    }

    # Use the enhanced browser (browse mode, no file selection needed)
    $selectedFile = Show-ContainerFileBrowserEnhanced -ContainerName $container -StartPath $startPath -SelectMode "File"

    if ($selectedFile) {
        Write-Host ""
        Write-Host "  Selected: $selectedFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "  What would you like to do?" -ForegroundColor Yellow
        Write-Host "  [1] View full file contents"
        Write-Host "  [2] Edit this file"
        Write-Host "  [3] Copy to host"
        Write-Host "  [0] Nothing (close)"
        Write-Host ""

        $action = Read-Host "  Enter choice"

        switch ($action) {
            "1" {
                Write-Host ""
                Write-Host "  File contents:" -ForegroundColor Yellow
                Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
                docker exec $container sh -c "cat '$selectedFile' 2>&1"
                Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
            }
            "2" {
                Edit-ContainerFile -ContainerName $container -FilePath $selectedFile
            }
            "3" {
                $destPath = Select-HostFolder -Title "Select destination folder"
                if ($destPath) {
                    Copy-FromContainer -ContainerName $container -SourcePath $selectedFile -DestinationPath $destPath
                }
            }
        }
    }
}

# ============================================
# Main Execution
# ============================================

switch ($Action) {
    "Copy" {
        Show-CopyMenu
    }
    "Delete" {
        Show-DeleteMenu
    }
    "Edit" {
        Show-EditMenu
    }
    "Browse" {
        Show-BrowseMenu
    }
}
