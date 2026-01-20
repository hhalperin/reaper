<#
.SYNOPSIS
    REAPER - Windows Service Cleanup Executor
    
.DESCRIPTION
    Disables services and startup items with full audit logging and automatic rollback.
    
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

$ErrorActionPreference = "Continue"
$script:ErrorCount = 0
$script:SuccessCount = 0
$script:RollbackCommands = @()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logsDir = Join-Path $projectRoot "data\audit_logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Ensure logs directory
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

$logFile = Join-Path $logsDir "$($timestamp)_execution.log"
$rollbackFile = Join-Path $logsDir "$($timestamp)_rollback.ps1"
$summaryFile = Join-Path $logsDir "$($timestamp)_summary.txt"

# ============================================================================
# LOGGING
# ============================================================================

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "SUCCESS", "ERROR", "WARN", "DRYRUN", "HEADER")]
        [string]$Level = "INFO"
    )
    
    $ts = Get-Date -Format "HH:mm:ss"
    $prefix = switch ($Level) {
        "HEADER"  { "===" }
        "SUCCESS" { " [OK] " }
        "ERROR"   { " [FAIL] " }
        "WARN"    { " [WARN] " }
        "DRYRUN"  { " [->] " }
        default   { "      " }
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
    Add-Content -Path $logFile -Value $logLine -Encoding UTF8
    Write-Host $logLine -ForegroundColor $color
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Log ("=" * 60) "HEADER"
    Write-Log $Title "HEADER"
    Write-Log ("=" * 60) "HEADER"
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
# Run as Administrator to undo all changes.

Write-Host "REAPER Rollback - Restoring previous state..." -ForegroundColor Cyan
Write-Host ""

"@
    Set-Content -Path $rollbackFile -Value $header -Encoding UTF8
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
    Write-Host "  [FAIL] $Description" -ForegroundColor Red
}
"@
    Add-Content -Path $rollbackFile -Value $block -Encoding UTF8
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
            Write-Log "Failed to revert: $($cmd.Description)" "ERROR"
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
        return $false
    }
    
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    $beforeType = if ($wmiSvc) { $wmiSvc.StartMode } else { "Unknown" }
    $beforeStatus = $svc.Status
    
    if ($IsDryRun) {
        Write-Log "WOULD DISABLE: $Name" "DRYRUN"
        Write-Log "  Reason: $Reason" "DRYRUN"
        Write-Log "  Current: $beforeType, $beforeStatus" "DRYRUN"
        return $true
    }
    
    try {
        if ($svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        
        Write-Log "DISABLED: $Name" "SUCCESS"
        Write-Log "  Was: $beforeType -> Now: Disabled" "INFO"
        
        Add-RollbackCommand "Re-enable $Name" "Set-Service -Name '$Name' -StartupType $beforeType"
        
        $script:SuccessCount++
        return $true
    }
    catch {
        Write-Log "FAILED to disable $Name : $($_.Exception.Message)" "ERROR"
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
    
    if ($IsDryRun) {
        Write-Log "WOULD SET: $Path\$Name = $Value" "DRYRUN"
        Write-Log "  Reason: $Description" "DRYRUN"
        return $true
    }
    
    try {
        $currentValue = $null
        $existed = $false
        if (Test-Path $Path) {
            try {
                $currentValue = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction SilentlyContinue
                $existed = $true
            } catch {}
        } else {
            New-Item -Path $Path -Force | Out-Null
        }
        
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force
        
        Write-Log "SET: $Path\$Name = $Value" "SUCCESS"
        
        if ($existed -and $null -ne $currentValue) {
            Add-RollbackCommand "Restore $Name" "Set-ItemProperty -Path '$Path' -Name '$Name' -Value $currentValue -Type DWord"
        } else {
            Add-RollbackCommand "Remove $Name" "Remove-ItemProperty -Path '$Path' -Name '$Name' -ErrorAction SilentlyContinue"
        }
        
        $script:SuccessCount++
        return $true
    }
    catch {
        Write-Log "FAILED to set $Path\$Name : $($_.Exception.Message)" "ERROR"
        $script:ErrorCount++
        return $false
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

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
Write-Host ""
Write-Host "  REAPER - Windows Cleanup" -ForegroundColor Red
Write-Host "  ========================" -ForegroundColor Red
Write-Host ""

$mode = if ($DryRun) { "DRY RUN (Preview)" } else { "EXECUTE" }
Write-Host "  Mode: $mode" -ForegroundColor $(if ($DryRun) { "Cyan" } else { "Yellow" })
Write-Host "  Level: $Level" -ForegroundColor White
Write-Host "  Log: $logFile" -ForegroundColor DarkGray
Write-Host ""

Write-Log "Session started - Mode: $mode, Level: $Level" "INFO"

if (-not $DryRun) {
    Initialize-Rollback
    
    if (-not $SkipRestorePoint) {
        Write-Section "CREATING RESTORE POINT"
        try {
            Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
            Checkpoint-Computer -Description "REAPER $timestamp" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
            Write-Log "Restore point created" "SUCCESS"
        }
        catch {
            Write-Log "Could not create restore point: $($_.Exception.Message)" "WARN"
        }
    }
    
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
    @{Name="DiagTrack"; Reason="Telemetry - sends usage data to Microsoft"}
    @{Name="dmwappushservice"; Reason="Telemetry - WAP push messages"}
    @{Name="XblAuthManager"; Reason="Xbox - not used by Steam/Epic games"}
    @{Name="XblGameSave"; Reason="Xbox cloud saves - Steam has its own"}
    @{Name="XboxGipSvc"; Reason="Xbox accessories - standard gamepads work without"}
    @{Name="XboxNetApiSvc"; Reason="Xbox networking - not used by Steam/Epic"}
    @{Name="edgeupdate"; Reason="Edge updater - updates via Windows Update anyway"}
    @{Name="edgeupdatem"; Reason="Edge updater"}
    @{Name="gupdate"; Reason="Google updater - Chrome updates when launched"}
    @{Name="gupdatem"; Reason="Google updater"}
    @{Name="Razer Chroma SDK Service"; Reason="RGB sync - mouse works without this"}
    @{Name="Razer Chroma SDK Server"; Reason="RGB sync"}
    @{Name="Razer Chroma Stream Server"; Reason="RGB streaming"}
    @{Name="ArmouryCrateService"; Reason="ASUS bloat - hardware works via BIOS"}
    @{Name="ROG Live Service"; Reason="ASUS bloat"}
    @{Name="asComSvc"; Reason="ASUS service"}
    @{Name="LGHUBUpdaterService"; Reason="Logitech updater"}
)

if ($Level -in @("moderate", "aggressive")) {
    $services += @(
        @{Name="CortexLauncherService"; Reason="Razer Cortex - no real performance benefit"}
        @{Name="Razer Game Manager Service 3"; Reason="Razer game detection"}
        @{Name="RzActionSvc"; Reason="Razer macros - only if you use complex macros"}
        @{Name="Steam Client Service"; Reason="Starts on-demand when needed"}
        @{Name="ClickToRunSvc"; Reason="Office starts this on-demand"}
        @{Name="Apple Mobile Device Service"; Reason="Only when syncing iPhone"}
        @{Name="Bonjour Service"; Reason="iTunes network discovery"}
    )
}

if ($Level -eq "aggressive") {
    $services += @(
        @{Name="AsusFanControlService"; Reason="BIOS handles fans - only keep for custom curves"}
        @{Name="AsusCertService"; Reason="ASUS certificates"}
        @{Name="FileSyncHelper"; Reason="OneDrive sync - only if actively using"}
        @{Name="AUEPLauncher"; Reason="ASUS utility"}
    )
}

$foundServices = 0
$notFoundServices = @()

foreach ($svc in $services) {
    $result = Disable-ServiceSafe -Name $svc.Name -Reason $svc.Reason -IsDryRun $DryRun
    if ($result) {
        $foundServices++
    } else {
        $notFoundServices += $svc.Name
    }
}

Write-Host ""
Write-Log "Services found: $foundServices / $($services.Count)" "INFO"
if ($notFoundServices.Count -gt 0) {
    Write-Log "Not installed: $($notFoundServices -join ', ')" "INFO"
}

# ============================================================================
# REGISTRY
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
# SUMMARY
# ============================================================================

Write-Section "SUMMARY"

$summaryText = @"
REAPER Execution Summary
========================
Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Mode: $mode
Level: $Level

Results:
  Services processed: $foundServices
  Registry keys: $($regKeys.Count)
  Successful: $($script:SuccessCount)
  Failed: $($script:ErrorCount)

Log file: $logFile
"@

if (-not $DryRun) {
    $summaryText += "`nRollback: $rollbackFile"
}

Write-Host $summaryText
Set-Content -Path $summaryFile -Value $summaryText -Encoding UTF8

# Auto-rollback
if ($AutoRollbackOnError -and $script:ErrorCount -gt 0 -and -not $DryRun) {
    Invoke-Rollback
}

# Finalize
if (-not $DryRun) {
    Add-Content -Path $rollbackFile -Value @"

Write-Host ""
Write-Host "Rollback complete. Restart may be needed." -ForegroundColor Green
"@ -Encoding UTF8
}

Write-Host ""
if ($script:ErrorCount -eq 0) {
    Write-Host "  Complete! No errors." -ForegroundColor Green
} else {
    Write-Host "  Complete with $($script:ErrorCount) errors." -ForegroundColor Yellow
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "  To undo: .\$rollbackFile" -ForegroundColor Cyan
}

Write-Host ""
