<#
.SYNOPSIS
    Windows Optimization Toolkit - Post-Update Check
    
.DESCRIPTION
    Checks if Windows Update has reverted any optimizations and reapplies them.
    Can be run manually or scheduled as a task.
    
.PARAMETER AutoReapply
    Automatically reapply changes without prompting.
    
.PARAMETER LogOnly
    Only log findings, don't make any changes.
    
.EXAMPLE
    .\post_update_check.ps1
    
.EXAMPLE
    .\post_update_check.ps1 -AutoReapply
#>

param(
    [switch]$AutoReapply,
    [switch]$LogOnly
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$logsDir = Join-Path $projectRoot "data\audit_logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Ensure logs directory exists
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logFile = Join-Path $logsDir "protection_${timestamp}.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "REVERT" { "Magenta" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$ExpectedValue
    )
    
    try {
        $value = Get-ItemPropertyValue -Path $Path -Name $Name -ErrorAction Stop
        return @{
            Exists = $true
            Value = $value
            Expected = $ExpectedValue
            Match = ($value -eq $ExpectedValue)
        }
    }
    catch {
        return @{
            Exists = $false
            Value = $null
            Expected = $ExpectedValue
            Match = $false
        }
    }
}

function Test-ServiceStartType {
    param(
        [string]$Name,
        [string]$ExpectedType
    )
    
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return @{
            Exists = $false
            CurrentType = $null
            Expected = $ExpectedType
            Match = $false
        }
    }
    
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$Name'"
    $currentType = $wmiSvc.StartMode
    
    return @{
        Exists = $true
        CurrentType = $currentType
        Expected = $ExpectedType
        Match = ($currentType -eq $ExpectedType)
    }
}

function Test-AppxInstalled {
    param([string]$PackageName)
    
    $pkg = Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue
    return ($null -ne $pkg)
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host " Windows Optimization Toolkit" -ForegroundColor Blue
Write-Host " Post-Update Protection Check" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

Write-Log "Post-update check started"

$issues = @()

# === Check Telemetry Settings ===
Write-Log "Checking telemetry settings..."

$diagTrack = Test-ServiceStartType -Name "DiagTrack" -ExpectedType "Disabled"
if ($diagTrack.Exists -and -not $diagTrack.Match) {
    Write-Log "DiagTrack service reverted to $($diagTrack.CurrentType)" "REVERT"
    $issues += @{Type = "Service"; Name = "DiagTrack"; Expected = "Disabled"; Current = $diagTrack.CurrentType}
}

$dmwappush = Test-ServiceStartType -Name "dmwappushservice" -ExpectedType "Disabled"
if ($dmwappush.Exists -and -not $dmwappush.Match) {
    Write-Log "dmwappushservice reverted to $($dmwappush.CurrentType)" "REVERT"
    $issues += @{Type = "Service"; Name = "dmwappushservice"; Expected = "Disabled"; Current = $dmwappush.CurrentType}
}

# === Check Copilot Settings ===
Write-Log "Checking Copilot settings..."

$copilotHKCU = Test-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ExpectedValue 1
if (-not $copilotHKCU.Match) {
    Write-Log "Copilot registry (HKCU) not set or reverted" "REVERT"
    $issues += @{Type = "Registry"; Path = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Expected = 1; Current = $copilotHKCU.Value}
}

$copilotHKLM = Test-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -ExpectedValue 1
if (-not $copilotHKLM.Match) {
    Write-Log "Copilot registry (HKLM) not set or reverted" "REVERT"
    $issues += @{Type = "Registry"; Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name = "TurnOffWindowsCopilot"; Expected = 1; Current = $copilotHKLM.Value}
}

# === Check Advertising ID ===
Write-Log "Checking advertising settings..."

$adId = Test-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -ExpectedValue 0
if (-not $adId.Match) {
    Write-Log "Advertising ID setting reverted" "REVERT"
    $issues += @{Type = "Registry"; Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name = "Enabled"; Expected = 0; Current = $adId.Value}
}

# === Check Copilot App Reinstalled ===
Write-Log "Checking for reinstalled apps..."

if (Test-AppxInstalled "Microsoft.Copilot") {
    Write-Log "Microsoft Copilot app was reinstalled" "REVERT"
    $issues += @{Type = "AppX"; Name = "Microsoft.Copilot"; Status = "Reinstalled"}
}

if (Test-AppxInstalled "Microsoft.Windows.Copilot") {
    Write-Log "Windows Copilot app was reinstalled" "REVERT"
    $issues += @{Type = "AppX"; Name = "Microsoft.Windows.Copilot"; Status = "Reinstalled"}
}

# === Summary ===
Write-Host ""
if ($issues.Count -eq 0) {
    Write-Log "All optimizations intact - no reverts detected" "SUCCESS"
} else {
    Write-Log "Found $($issues.Count) reverted settings" "WARNING"
    
    if ($LogOnly) {
        Write-Log "Log-only mode - no changes made"
    } elseif ($AutoReapply) {
        Write-Log "Auto-reapply mode - fixing issues..."
        
        foreach ($issue in $issues) {
            switch ($issue.Type) {
                "Service" {
                    try {
                        if ($issue.Expected -eq "Disabled") {
                            Set-Service -Name $issue.Name -StartupType Disabled -ErrorAction Stop
                            Stop-Service -Name $issue.Name -Force -ErrorAction SilentlyContinue
                        } else {
                            Set-Service -Name $issue.Name -StartupType $issue.Expected -ErrorAction Stop
                        }
                        Write-Log "Fixed service: $($issue.Name)" "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to fix service $($issue.Name): $_" "ERROR"
                    }
                }
                "Registry" {
                    try {
                        if (-not (Test-Path $issue.Path)) {
                            New-Item -Path $issue.Path -Force | Out-Null
                        }
                        Set-ItemProperty -Path $issue.Path -Name $issue.Name -Value $issue.Expected -Type DWord -Force
                        Write-Log "Fixed registry: $($issue.Path)\$($issue.Name)" "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to fix registry $($issue.Path)\$($issue.Name): $_" "ERROR"
                    }
                }
                "AppX" {
                    try {
                        Get-AppxPackage -AllUsers -Name "*$($issue.Name)*" | Remove-AppxPackage -AllUsers -ErrorAction Stop
                        Write-Log "Removed reinstalled app: $($issue.Name)" "SUCCESS"
                    }
                    catch {
                        Write-Log "Failed to remove app $($issue.Name): $_" "ERROR"
                    }
                }
            }
        }
    } else {
        Write-Host ""
        Write-Host "Issues found. Run with -AutoReapply to fix automatically." -ForegroundColor Yellow
        Write-Host "Or run execute_cleanup.ps1 to reapply all optimizations." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Log saved to: $logFile"
Write-Host ""
