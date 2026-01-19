# Pre-execution hook - runs before any system changes
# Validates environment and creates safety net

param(
    [switch]$SkipRestorePoint
)

$ErrorActionPreference = "Stop"

Write-Host "=== REAPER Pre-Execute Hook ===" -ForegroundColor Cyan

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Administrator privileges required. Run PowerShell as Admin."
    exit 1
}

# Check manifest exists
if (-not (Test-Path "config/manifest.yaml")) {
    Write-Error "manifest.yaml not found. Run analyze_suspects.py first."
    exit 1
}

# Create restore point
if (-not $SkipRestorePoint) {
    Write-Host "Creating system restore point..." -ForegroundColor Yellow
    try {
        Checkpoint-Computer -Description "REAPER pre-cleanup $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS
        Write-Host "Restore point created." -ForegroundColor Green
    } catch {
        Write-Warning "Could not create restore point: $_"
    }
}

Write-Host "Pre-execute checks passed." -ForegroundColor Green
exit 0
