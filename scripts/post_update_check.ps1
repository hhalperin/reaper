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

.PARAMETER Profile
    Optional profile name from config\profiles.json.
#>

param(
    [switch]$AutoReapply,
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level = "moderate",
    [string]$Profile
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logsDir = Join-Path $projectRoot "data\audit_logs"
$profilesPath = Join-Path $projectRoot "config\profiles.json"
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

function Get-ProfileData {
    param([string]$ProfileName)
    
    if (-not $ProfileName) { return $null }
    if (-not (Test-Path $profilesPath)) { return $null }
    
    try {
        $json = Get-Content -Path $profilesPath -Raw | ConvertFrom-Json
        if ($json.profiles) {
            foreach ($prop in $json.profiles.PSObject.Properties) {
                if ($prop.Name -eq $ProfileName) {
                    return $prop.Value
                }
            }
        }
    } catch {}
    
    return $null
}

function Normalize-Name {
    param([string]$Name)
    if ($null -eq $Name) { return "" }
    return $Name.ToLower()
}

Write-Log "REAPER Post-Update Check started"
Write-Log "Level: $Level"
if ($Profile) {
    Write-Log "Profile: $Profile"
}

$profileData = Get-ProfileData -ProfileName $Profile

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
        "CortexLauncherService", "ClickToRunSvc",
        "Apple Mobile Device Service", "Bonjour Service", "LGHUBUpdaterService"
    )
}

if ($profileData) {
    $keepSet = @{}
    foreach ($name in ($profileData.keep_services | Where-Object { $_ })) {
        $keepSet[(Normalize-Name $name)] = $true
    }
    
    $targetServices = $targetServices | Where-Object {
        -not $keepSet.ContainsKey((Normalize-Name $_))
    }
    
    foreach ($name in ($profileData.disable_services | Where-Object { $_ })) {
        if ($targetServices -notcontains $name) {
            $targetServices += $name
        }
    }
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

if ($profileData -and $profileData.registry) {
    foreach ($entry in $profileData.registry) {
        if (-not $entry.path -or -not $entry.name) { continue }
        if (-not (Test-Path $entry.path)) { continue }
        
        $expected = $entry.value
        $current = Get-ItemPropertyValue -Path $entry.path -Name $entry.name -ErrorAction SilentlyContinue
        if ($current -ne $expected) {
            Write-Log "DETECTED: $($entry.path)\$($entry.name) reverted"
            if ($AutoReapply) {
                try {
                    $type = if ($entry.type) { $entry.type } else { "DWord" }
                    if ($type -eq "String") {
                        Set-ItemProperty -Path $entry.path -Name $entry.name -Value $expected -Type String -Force
                    } else {
                        Set-ItemProperty -Path $entry.path -Name $entry.name -Value $expected -Type DWord -Force
                    }
                    Write-Log "FIXED: $($entry.path)\$($entry.name) restored"
                } catch {
                    Write-Log "ERROR: Could not restore $($entry.path)\$($entry.name) - $_"
                }
            }
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
