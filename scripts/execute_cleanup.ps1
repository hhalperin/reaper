<#
.SYNOPSIS
    REAPER - Windows Service Cleanup Executor
    
.DESCRIPTION
    Disables services and startup items with full audit logging and automatic rollback.
    Creates restore point, logs all changes, generates undo script.
    
.PARAMETER DryRun
    Preview changes without applying.
    
.PARAMETER Execute
    Apply changes (requires Admin).
    
.PARAMETER Level
    Aggressiveness: light, moderate, aggressive
    
.PARAMETER AutoRollbackOnError
    Automatically undo all changes if any error occurs.
    
.EXAMPLE
    .\execute_cleanup.ps1 -DryRun
    .\execute_cleanup.ps1 -Execute -Level moderate
    .\execute_cleanup.ps1 -Execute -AutoRollbackOnError
#>

param(
    [switch]$DryRun,
    [switch]$Execute,
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level = "moderate",
    [switch]$SkipRestorePoint,
    [switch]$AutoRollbackOnError
)

# ============================================================================
# CONFIGURATION
# ============================================================================

$ErrorActionPreference = "Stop"
$script:ErrorCount = 0
$script:SuccessCount = 0
$script:RollbackCommands = @()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logsDir = Join-Path $projectRoot "data\audit_logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Ensure logs directory
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

$logFile = Join-Path $logsDir "${timestamp}_execution.log"
$rollbackFile = Join-Path $logsDir "${timestamp}_rollback.ps1"
$summaryFile = Join-Path $logsDir "${timestamp}_summary.txt"

# ============================================================================
# LOGGING - Clean, structured output
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "ERROR", "WARN", "DRYRUN", "HEADER")]
        [string]$Level = "INFO"
    )
    
    $ts = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "HEADER"  { "═══" }
        "SUCCESS" { " ✓ " }
        "ERROR"   { " ✗ " }
        "WARN"    { " ⚠ " }
        "DRYRUN"  { " → " }
        default   { "   " }
    }
    
    $color = switch ($Level) {
        "HEADER"  { "Cyan" }
        "SUCCESS" { "Green" }
        "ERROR"   { "Red" }
        "WARN"    { "Yellow" }
        "DRYRUN"  { "DarkCyan" }
        default   { "Gray" }
    }
    
    $logLine = "[$ts] $prefix $Message"
    Add-Content -Path $logFile -Value $logLine
    Write-Host $logLine -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Log "═══════════════════════════════════════════════════════" "HEADER"
    Write-Log $Title "HEADER"
    Write-Log "═══════════════════════════════════════════════════════" "HEADER"
}

# ============================================================================
# ROLLBACK SYSTEM
# ============================================================================

function Initialize-Rollback {
    $header = @"
# REAPER Rollback Script
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# Session: $timestamp
#
# This script reverses ALL changes from the cleanup session.
# Run as Administrator.

Set-StrictMode -Version Latest
`$ErrorActionPreference = "Continue"

Write-Host "REAPER Rollback - Restoring previous state..." -ForegroundColor Cyan
Write-Host ""

"@
    Set-Content -Path $rollbackFile -Value $header
}

function Add-RollbackCommand {
    param(
        [string]$Description,
        [string]$Command
    )
    
    $script:RollbackCommands += @{
        Description = $Description
        Command = $Command
    }
    
    $block = @"

# $Description
try {
    $Command
    Write-Host "  [OK] $Description" -ForegroundColor Green
} catch {
    Write-Host "  [FAIL] $Description - `$_" -ForegroundColor Red
}
"@
    Add-Content -Path $rollbackFile -Value $block
}

function Invoke-Rollback {
    Write-Section "AUTO-ROLLBACK TRIGGERED"
    Write-Log "Errors detected. Rolling back all changes..." "WARN"
    
    foreach ($cmd in $script:RollbackCommands) {
        try {
            Write-Log "Reverting: $($cmd.Description)" "INFO"
            Invoke-Expression $cmd.Command
            Write-Log "Reverted: $($cmd.Description)" "SUCCESS"
        } catch {
            Write-Log "Failed to revert: $($cmd.Description) - $_" "ERROR"
        }
    }
    
    Write-Log "Rollback complete." "INFO"
}

# ============================================================================
# SERVICE OPERATIONS
# ============================================================================

function Disable-ServiceSafe {
    param(
        [string]$Name,
        [string]$Reason,
        [bool]$IsDryRun
    )
    
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Log "Service not found: $Name" "WARN"
        return $false
    }
    
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $beforeType = if ($wmiSvc) { $wmiSvc.StartMode } else { "Unknown" }
    $beforeStatus = $svc.Status
    
    if ($IsDryRun) {
        Write-Log "WOULD DISABLE: $Name ($Reason)" "DRYRUN"
        Write-Log "  Current: $beforeType, $beforeStatus" "DRYRUN"
        return $true
    }
    
    try {
        # Stop if running
        if ($svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        
        # Disable
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        
        Write-Log "DISABLED: $Name" "SUCCESS"
        Write-Log "  Was: $beforeType, $beforeStatus → Now: Disabled, Stopped" "INFO"
        
        # Add rollback
        Add-RollbackCommand "Re-enable $Name" "Set-Service -Name '$Name' -StartupType $beforeType; if ('$beforeStatus' -eq 'Running') { Start-Service -Name '$Name' -ErrorAction SilentlyContinue }"
        
        $script:SuccessCount++
        return $true
    }
    catch {
        Write-Log "FAILED: $Name - $_" "ERROR"
        $script:ErrorCount++
        return $false
    }
}

# ============================================================================
# REGISTRY OPERATIONS
# ============================================================================

function Set-RegistrySafe {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    $regPath = $Path -replace "^HKCU:", "HKCU:\" -replace "^HKLM:", "HKLM:\"
    
    if ($IsDryRun) {
        Write-Log "WOULD SET: $Path\$Name = $Value ($Description)" "DRYRUN"
        return $true
    }
    
    try {
        # Get current value for rollback
        $currentValue = $null
        $existed = $false
        if (Test-Path $regPath) {
            try {
                $currentValue = Get-ItemPropertyValue -Path $regPath -Name $Name -ErrorAction SilentlyContinue
                $existed = $true
            } catch {}
        } else {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        Set-ItemProperty -Path $regPath -Name $Name -Value $Value -Type DWord -Force
        
        Write-Log "SET: $Path\$Name = $Value" "SUCCESS"
        
        # Add rollback
        if ($existed -and $null -ne $currentValue) {
            Add-RollbackCommand "Restore $Name" "Set-ItemProperty -Path '$regPath' -Name '$Name' -Value $currentValue -Type DWord"
        } else {
            Add-RollbackCommand "Remove $Name" "Remove-ItemProperty -Path '$regPath' -Name '$Name' -ErrorAction SilentlyContinue"
        }
        
        $script:SuccessCount++
        return $true
    }
    catch {
        Write-Log "FAILED: $Path\$Name - $_" "ERROR"
        $script:ErrorCount++
        return $false
    }
}

# ============================================================================
# APPX REMOVAL
# ============================================================================

function Remove-AppxSafe {
    param(
        [string]$PackageName,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    $packages = Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue
    
    if (-not $packages) {
        Write-Log "Package not found: $PackageName" "WARN"
        return $false
    }
    
    foreach ($pkg in $packages) {
        if ($IsDryRun) {
            Write-Log "WOULD REMOVE: $($pkg.Name)" "DRYRUN"
            continue
        }
        
        try {
            Get-AppxPackage -AllUsers -Name $pkg.Name | Remove-AppxPackage -AllUsers -ErrorAction Stop
            Write-Log "REMOVED: $($pkg.Name)" "SUCCESS"
            Add-RollbackCommand "Reinstall $PackageName" "# Manual: Reinstall from Microsoft Store"
            $script:SuccessCount++
        }
        catch {
            Write-Log "FAILED: $($pkg.Name) - $_" "ERROR"
            $script:ErrorCount++
        }
    }
    return $true
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($Execute -and -not $isAdmin) {
    Write-Host "ERROR: Run as Administrator" -ForegroundColor Red
    exit 1
}

if (-not $DryRun -and -not $Execute) {
    Write-Host "Usage: .\execute_cleanup.ps1 -DryRun | -Execute [-Level light|moderate|aggressive]" -ForegroundColor Yellow
    exit 1
}

# Header
Clear-Host
Write-Host ""
Write-Host "  ██████╗ ███████╗ █████╗ ██████╗ ███████╗██████╗ " -ForegroundColor Red
Write-Host "  ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗" -ForegroundColor Red
Write-Host "  ██████╔╝█████╗  ███████║██████╔╝█████╗  ██████╔╝" -ForegroundColor Red
Write-Host "  ██╔══██╗██╔══╝  ██╔══██║██╔═══╝ ██╔══╝  ██╔══██╗" -ForegroundColor Red
Write-Host "  ██║  ██║███████╗██║  ██║██║     ███████╗██║  ██║" -ForegroundColor Red
Write-Host "  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝" -ForegroundColor Red
Write-Host ""

$mode = if ($DryRun) { "DRY RUN (Preview)" } else { "EXECUTE" }
Write-Host "  Mode: $mode" -ForegroundColor $(if ($DryRun) { "Cyan" } else { "Yellow" })
Write-Host "  Level: $Level" -ForegroundColor White
Write-Host "  Log: $logFile" -ForegroundColor DarkGray
Write-Host ""

# Initialize
Write-Log "Session started - Mode: $mode, Level: $Level" "INFO"

if (-not $DryRun) {
    Initialize-Rollback
    
    # Create restore point
    if (-not $SkipRestorePoint) {
        Write-Section "CREATING RESTORE POINT"
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "REAPER $timestamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Log "Restore point created" "SUCCESS"
        }
        catch {
            Write-Log "Could not create restore point: $_" "WARN"
        }
    }
    
    # Confirmation
    Write-Host ""
    Write-Host "  This will modify system services and registry." -ForegroundColor Yellow
    $confirm = Read-Host "  Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Log "Cancelled by user" "INFO"
        exit 0
    }
}

# ============================================================================
# SERVICES TO DISABLE
# ============================================================================

Write-Section "SERVICES"

$services = @(
    # Telemetry
    @{Name="DiagTrack"; Reason="Telemetry"}
    @{Name="dmwappushservice"; Reason="Telemetry"}
    
    # Xbox (not needed for Steam/Epic)
    @{Name="XblAuthManager"; Reason="Xbox - Steam/Epic don't use this"}
    @{Name="XblGameSave"; Reason="Xbox cloud saves - Steam has its own"}
    @{Name="XboxGipSvc"; Reason="Xbox accessories - standard controllers work without"}
    @{Name="XboxNetApiSvc"; Reason="Xbox networking - not used by Steam/Epic"}
    
    # Updaters
    @{Name="edgeupdate"; Reason="Edge updater - updates via Windows Update"}
    @{Name="edgeupdatem"; Reason="Edge updater"}
    @{Name="gupdate"; Reason="Google updater"}
    @{Name="gupdatem"; Reason="Google updater"}
    
    # RGB/Hardware
    @{Name="Razer Chroma SDK Service"; Reason="RGB sync - devices work without"}
    @{Name="Razer Chroma SDK Server"; Reason="RGB sync"}
    @{Name="Razer Chroma Stream Server"; Reason="RGB streaming"}
    @{Name="ArmouryCrateService"; Reason="ASUS bloat - hardware works via BIOS"}
    @{Name="ROG Live Service"; Reason="ASUS bloat"}
    @{Name="asComSvc"; Reason="ASUS bloat"}
    @{Name="LGHUBUpdaterService"; Reason="Logitech updater"}
)

# Add moderate level services
if ($Level -in @("moderate", "aggressive")) {
    $services += @(
        @{Name="CortexLauncherService"; Reason="Razer Cortex - no real benefit"}
        @{Name="Razer Game Manager Service 3"; Reason="Razer game detection"}
        @{Name="RzActionSvc"; Reason="Razer macros"}
        @{Name="Steam Client Service"; Reason="Starts on-demand when needed"}
        @{Name="ClickToRunSvc"; Reason="Office starts this on-demand"}
        @{Name="Apple Mobile Device Service"; Reason="Only when syncing iPhone"}
        @{Name="Bonjour Service"; Reason="iTunes network discovery"}
    )
}

# Add aggressive level services
if ($Level -eq "aggressive") {
    $services += @(
        @{Name="AsusFanControlService"; Reason="BIOS handles fans"}
        @{Name="AsusCertService"; Reason="ASUS certs"}
        @{Name="FileSyncHelper"; Reason="OneDrive sync helper"}
    )
}

foreach ($svc in $services) {
    Disable-ServiceSafe -Name $svc.Name -Reason $svc.Reason -IsDryRun $DryRun
}

# ============================================================================
# REGISTRY - Disable telemetry and ads
# ============================================================================

Write-Section "REGISTRY"

$regKeys = @(
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; Value=0; Desc="Advertising ID"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338388Enabled"; Value=0; Desc="Start menu suggestions"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338389Enabled"; Value=0; Desc="App suggestions"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SoftLandingEnabled"; Value=0; Desc="Windows tips"}
)

if ($Level -in @("moderate", "aggressive")) {
    $regKeys += @(
        @{Path="HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name="TurnOffWindowsCopilot"; Value=1; Desc="Disable Copilot"}
        @{Path="HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"; Name="DisableAIDataAnalysis"; Value=1; Desc="Disable Recall"}
    )
}

foreach ($key in $regKeys) {
    Set-RegistrySafe -Path $key.Path -Name $key.Name -Value $key.Value -Description $key.Desc -IsDryRun $DryRun
}

# ============================================================================
# APPX PACKAGES (moderate+)
# ============================================================================

if ($Level -in @("moderate", "aggressive") -and -not $DryRun) {
    Write-Section "APPS"
    
    $apps = @(
        @{Name="Microsoft.549981C3F5F10"; Desc="Cortana"}
        @{Name="Microsoft.Copilot"; Desc="Copilot"}
        @{Name="Microsoft.WindowsFeedbackHub"; Desc="Feedback Hub"}
        @{Name="Microsoft.GetHelp"; Desc="Get Help"}
        @{Name="Microsoft.Getstarted"; Desc="Tips"}
    )
    
    foreach ($app in $apps) {
        Remove-AppxSafe -PackageName $app.Name -Description $app.Desc -IsDryRun $DryRun
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Section "SUMMARY"

$summary = @"
REAPER Execution Summary
========================
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Mode: $mode
Level: $Level

Results:
  Successful: $($script:SuccessCount)
  Failed: $($script:ErrorCount)

Files:
  Log: $logFile
  Rollback: $rollbackFile
"@

Write-Host $summary
Set-Content -Path $summaryFile -Value $summary

# Auto-rollback on error
if ($AutoRollbackOnError -and $script:ErrorCount -gt 0 -and -not $DryRun) {
    Invoke-Rollback
}

# Finalize rollback script
if (-not $DryRun) {
    Add-Content -Path $rollbackFile -Value @"

Write-Host ""
Write-Host "Rollback complete. $($script:RollbackCommands.Count) items restored." -ForegroundColor Green
Write-Host "You may need to restart for all changes to take effect."
"@
}

Write-Host ""
if ($script:ErrorCount -eq 0) {
    Write-Host "  ✓ Complete! No errors." -ForegroundColor Green
} else {
    Write-Host "  ⚠ Complete with $($script:ErrorCount) errors." -ForegroundColor Yellow
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "  To undo all changes:" -ForegroundColor DarkGray
    Write-Host "  .\$rollbackFile" -ForegroundColor Cyan
}

Write-Host ""
