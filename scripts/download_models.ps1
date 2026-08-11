```powershell
# Download the Gemma 3 270M IT Q4_K_M model for mndict

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$Repository = "mnsky-tyan/mndict"
$ReleaseTag = "v0.1.0"

$FileName = "gemma-3-270m-it-Q4_K_M.gguf"

$ModelDirectory = Join-Path $PSScriptRoot "..\test_model"
$ModelDirectory = [System.IO.Path]::GetFullPath($ModelDirectory)

$DownloadUrl = "https://github.com/$Repository/releases/download/$ReleaseTag/$FileName"
$Destination = Join-Path $ModelDirectory $FileName

# ------------------------------------------------------------
# Create test_model directory
# ------------------------------------------------------------

if (-not (Test-Path $ModelDirectory)) {
    Write-Host "Creating model directory..."
    New-Item -ItemType Directory -Path $ModelDirectory -Force | Out-Null
}

# ------------------------------------------------------------
# Check if model already exists
# ------------------------------------------------------------

if (Test-Path $Destination) {
    Write-Host ""
    Write-Host "Model already exists:"
    Write-Host "  $Destination"
    Write-Host ""

    $Overwrite = Read-Host "Download again and overwrite it? (y/N)"

    if ($Overwrite -ne "y" -and $Overwrite -ne "Y") {
        Write-Host "Download cancelled."
        exit 0
    }
}

# ------------------------------------------------------------
# Download
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Gemma 3 270M IT Q4_K_M..."
Write-Host ""
Write-Host "From:"
Write-Host "  $DownloadUrl"
Write-Host ""
Write-Host "To:"
Write-Host "  $Destination"
Write-Host ""

try {
    Invoke-WebRequest `
        -Uri $DownloadUrl `
        -OutFile $Destination `
        -UseBasicParsing
}
catch {
    Write-Error "Failed to download the model."
    
    if (Test-Path $Destination) {
        Remove-Item $Destination -Force
    }

    exit 1
}

# ------------------------------------------------------------
# Finished
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host "Model download complete!"
Write-Host ""
Write-Host "Model:"
Write-Host "  $Destination"
Write-Host "========================================"
```
