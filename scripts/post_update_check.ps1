<#
.SYNOPSIS
    REAPER Post-Update Protection
    
.DESCRIPTION
    Runs after Windows Update to re-apply service settings.
    Installed as a scheduled task by setup.ps1
    
.PARAMETER AutoReapply
    Automatically re-disable services without prompting.
    
.PARAMETER Level
    Aggressiveness level to apply.
#>

param(
    [switch]$AutoReapply,
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level = "moderate"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logsDir = Join-Path $projectRoot "data\audit_logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = Join-Path $logsDir "${timestamp}_postupdate.log"

# Ensure logs directory
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

function Write-Log {
    param([string]$Message)
    $line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
    Add-Content -Path $logFile -Value $line
    Write-Host $line
}

Write-Log "REAPER Post-Update Check started"
Write-Log "Level: $Level"

# Services that should be disabled
$targetServices = @(
    "DiagTrack", "dmwappushservice",
    "XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc",
    "edgeupdate", "edgeupdatem",
    "Razer Chroma SDK Service", "Razer Chroma SDK Server",
    "ArmouryCrateService", "ROG Live Service"
)

if ($Level -in @("moderate", "aggressive")) {
    $targetServices += @(
        "CortexLauncherService", "Steam Client Service", "ClickToRunSvc",
        "Apple Mobile Device Service", "Bonjour Service", "LGHUBUpdaterService"
    )
}

$reverted = @()

foreach ($svcName in $targetServices) {
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if (-not $svc) { continue }
    
    $wmi = Get-WmiObject Win32_Service -Filter "Name='$svcName'" -ErrorAction SilentlyContinue
    if ($wmi -and $wmi.StartMode -ne "Disabled") {
        Write-Log "DETECTED: $svcName was re-enabled (currently: $($wmi.StartMode))"
        $reverted += $svcName
        
        if ($AutoReapply) {
            try {
                if ($svc.Status -eq "Running") {
                    Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
                }
                Set-Service -Name $svcName -StartupType Disabled
                Write-Log "FIXED: $svcName disabled again"
            }
            catch {
                Write-Log "ERROR: Could not disable $svcName - $_"
            }
        }
    }
}

# Check registry
$copilotPath = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
if (Test-Path $copilotPath) {
    $val = Get-ItemPropertyValue -Path $copilotPath -Name "TurnOffWindowsCopilot" -ErrorAction SilentlyContinue
    if ($val -ne 1) {
        Write-Log "DETECTED: Copilot registry was reverted"
        if ($AutoReapply) {
            Set-ItemProperty -Path $copilotPath -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -Force
            Write-Log "FIXED: Copilot disabled again"
        }
    }
}

# Summary
Write-Log "---"
if ($reverted.Count -eq 0) {
    Write-Log "All settings intact. No action needed."
} else {
    Write-Log "Found $($reverted.Count) reverted settings."
    if ($AutoReapply) {
        Write-Log "All settings re-applied."
    } else {
        Write-Log "Run with -AutoReapply to fix, or run setup.ps1 again."
    }
}

Write-Log "Post-update check complete."
