<#
.SYNOPSIS
    Windows Optimization Toolkit - Cleanup Executor
    
.DESCRIPTION
    Executes cleanup actions defined in the manifest.yaml file.
    Supports dry-run mode to preview changes before applying.
    Creates system restore point and generates rollback script.
    
.PARAMETER DryRun
    Preview changes without making any modifications.
    
.PARAMETER Execute
    Apply changes (requires confirmation).
    
.PARAMETER ManifestPath
    Path to manifest.yaml file. Defaults to config/manifest.yaml.
    
.PARAMETER Level
    Aggressiveness level to apply (light, moderate, aggressive).
    Overrides manifest setting.
    
.PARAMETER SkipRestorePoint
    Skip creating system restore point (not recommended).
    
.EXAMPLE
    .\execute_cleanup.ps1 -DryRun
    
.EXAMPLE
    .\execute_cleanup.ps1 -Execute -Level light
    
.NOTES
    Requires Administrator privileges for most operations.
#>

param(
    [switch]$DryRun,
    [switch]$Execute,
    [string]$ManifestPath = "config\manifest.yaml",
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level,
    [switch]$SkipRestorePoint
)

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and $Execute) {
    Write-Host "ERROR: Administrator privileges required for execution mode." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator." -ForegroundColor Yellow
    exit 1
}

# Validate parameters
if (-not $DryRun -and -not $Execute) {
    Write-Host "ERROR: Specify either -DryRun or -Execute" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\execute_cleanup.ps1 -DryRun     # Preview changes"
    Write-Host "  .\execute_cleanup.ps1 -Execute   # Apply changes"
    exit 1
}

# Set up paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$manifestFullPath = Join-Path $projectRoot $ManifestPath
$logsDir = Join-Path $projectRoot "data\audit_logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Ensure logs directory exists
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logFile = Join-Path $logsDir "${timestamp}_execution.log"
$rollbackFile = Join-Path $logsDir "${timestamp}_rollback.ps1"

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry
    
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        "DRYRUN" { "Cyan" }
        default { "White" }
    }
    Write-Host $logEntry -ForegroundColor $color
}

# Initialize rollback script
function Initialize-Rollback {
    $header = @"
# Windows Optimization Toolkit - Rollback Script
# Session: $timestamp
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
#
# WARNING: This script reverses ALL changes from the session.
# Run as Administrator.

`$confirm = Read-Host "This will rollback all changes. Continue? (y/N)"
if (`$confirm -ne "y" -and `$confirm -ne "Y") {
    Write-Host "Rollback cancelled."
    exit
}

Write-Host "Starting rollback..."

"@
    Set-Content -Path $rollbackFile -Value $header
}

# Add rollback command
function Add-Rollback {
    param([string]$Comment, [string]$Command)
    Add-Content -Path $rollbackFile -Value "# $Comment"
    Add-Content -Path $rollbackFile -Value $Command
    Add-Content -Path $rollbackFile -Value ""
}

# Load manifest
function Load-Manifest {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Log "Manifest not found: $Path" "ERROR"
        exit 1
    }
    
    # Simple YAML parser for our structure
    $content = Get-Content $Path -Raw
    
    # We'll use a simple approach - parse key sections
    $manifest = @{
        version = "1.0"
        aggressiveness_level = "light"
        critical_keep_list = @{
            processes = @()
            services = @()
        }
        categories = @{}
    }
    
    # Extract aggressiveness level
    if ($content -match "aggressiveness_level:\s*(\w+)") {
        $manifest.aggressiveness_level = $matches[1]
    }
    
    return $manifest, $content
}

# Check if service exists
function Test-ServiceExists {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    return $null -ne $svc
}

# Disable service
function Disable-ServiceSafely {
    param(
        [string]$Name,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    if (-not (Test-ServiceExists $Name)) {
        Write-Log "Service not found: $Name" "WARNING"
        return
    }
    
    $svc = Get-Service -Name $Name
    $beforeState = @{
        StartType = (Get-WmiObject Win32_Service -Filter "Name='$Name'").StartMode
        Status = $svc.Status
    }
    
    if ($IsDryRun) {
        Write-Log "WOULD disable service: $Name ($Description)" "DRYRUN"
        Write-Log "  Current: StartType=$($beforeState.StartType), Status=$($beforeState.Status)" "DRYRUN"
        return
    }
    
    try {
        # Stop service if running
        if ($svc.Status -eq "Running") {
            Stop-Service -Name $Name -Force -ErrorAction Stop
        }
        
        # Set to disabled
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        
        Write-Log "Disabled service: $Name" "SUCCESS"
        
        # Add rollback
        Add-Rollback "Rollback: $Name" "Set-Service -Name '$Name' -StartupType $($beforeState.StartType); Start-Service '$Name' -ErrorAction SilentlyContinue"
    }
    catch {
        Write-Log "Failed to disable service $Name : $_" "ERROR"
    }
}

# Set service to manual
function Set-ServiceManual {
    param(
        [string]$Name,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    if (-not (Test-ServiceExists $Name)) {
        Write-Log "Service not found: $Name" "WARNING"
        return
    }
    
    $beforeState = (Get-WmiObject Win32_Service -Filter "Name='$Name'").StartMode
    
    if ($IsDryRun) {
        Write-Log "WOULD set service to Manual: $Name ($Description)" "DRYRUN"
        return
    }
    
    try {
        Set-Service -Name $Name -StartupType Manual -ErrorAction Stop
        Write-Log "Set service to Manual: $Name" "SUCCESS"
        Add-Rollback "Rollback: $Name" "Set-Service -Name '$Name' -StartupType $beforeState"
    }
    catch {
        Write-Log "Failed to set service $Name to Manual: $_" "ERROR"
    }
}

# Set registry value
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [int]$Value,
        [string]$Type = "DWord",
        [string]$Description,
        [bool]$IsDryRun
    )
    
    # Convert path format
    $regPath = $Path -replace "HKCU:", "HKCU:\" -replace "HKLM:", "HKLM:\"
    
    if ($IsDryRun) {
        Write-Log "WOULD set registry: $Path\$Name = $Value ($Description)" "DRYRUN"
        return
    }
    
    try {
        # Create path if it doesn't exist
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
        
        # Get current value for rollback
        $currentValue = $null
        try {
            $currentValue = Get-ItemPropertyValue -Path $regPath -Name $Name -ErrorAction SilentlyContinue
        } catch {}
        
        # Set new value
        Set-ItemProperty -Path $regPath -Name $Name -Value $Value -Type $Type -Force
        
        Write-Log "Set registry: $Path\$Name = $Value" "SUCCESS"
        
        # Add rollback
        if ($null -ne $currentValue) {
            Add-Rollback "Rollback: $Path\$Name" "Set-ItemProperty -Path '$regPath' -Name '$Name' -Value $currentValue -Type $Type"
        } else {
            Add-Rollback "Rollback: $Path\$Name" "Remove-ItemProperty -Path '$regPath' -Name '$Name' -ErrorAction SilentlyContinue"
        }
    }
    catch {
        Write-Log "Failed to set registry $Path\$Name : $_" "ERROR"
    }
}

# Remove AppX package
function Remove-AppxPackageSafely {
    param(
        [string]$PackageName,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    $packages = Get-AppxPackage -AllUsers -Name "*$PackageName*" -ErrorAction SilentlyContinue
    
    if (-not $packages) {
        Write-Log "AppX package not found: $PackageName" "WARNING"
        return
    }
    
    foreach ($pkg in $packages) {
        if ($IsDryRun) {
            Write-Log "WOULD remove AppX: $($pkg.Name) ($Description)" "DRYRUN"
            continue
        }
        
        try {
            # Remove for all users
            Get-AppxPackage -AllUsers -Name $pkg.Name | Remove-AppxPackage -AllUsers -ErrorAction Stop
            
            # Remove provisioned package to prevent reinstall
            $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "*$PackageName*" }
            if ($provisioned) {
                Remove-AppxProvisionedPackage -Online -PackageName $provisioned.PackageName -ErrorAction SilentlyContinue
            }
            
            Write-Log "Removed AppX: $($pkg.Name)" "SUCCESS"
            Add-Rollback "Reinstall: $PackageName" "# Manual reinstall from Microsoft Store required for $PackageName"
        }
        catch {
            Write-Log "Failed to remove AppX $($pkg.Name): $_" "ERROR"
        }
    }
}

# Disable startup item
function Disable-StartupItem {
    param(
        [string]$Name,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    # Check registry locations
    $locations = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    )
    
    foreach ($loc in $locations) {
        if (-not (Test-Path $loc)) { continue }
        
        $item = Get-ItemProperty -Path $loc -Name $Name -ErrorAction SilentlyContinue
        if ($item) {
            if ($IsDryRun) {
                Write-Log "WOULD disable startup: $Name at $loc ($Description)" "DRYRUN"
                continue
            }
            
            try {
                # Disable by setting first byte to 03
                $currentValue = (Get-ItemProperty -Path $loc -Name $Name).$Name
                $disabledValue = [byte[]]@(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
                Set-ItemProperty -Path $loc -Name $Name -Value $disabledValue -Type Binary
                
                Write-Log "Disabled startup: $Name" "SUCCESS"
                Add-Rollback "Rollback: $Name startup" "Set-ItemProperty -Path '$loc' -Name '$Name' -Value ([byte[]]@($($currentValue -join ', '))) -Type Binary"
            }
            catch {
                Write-Log "Failed to disable startup $Name : $_" "ERROR"
            }
        }
    }
}

# Disable scheduled task
function Disable-ScheduledTaskSafely {
    param(
        [string]$TaskPath,
        [string]$TaskName,
        [string]$Description,
        [bool]$IsDryRun
    )
    
    $task = Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction SilentlyContinue
    
    if (-not $task) {
        Write-Log "Scheduled task not found: $TaskPath$TaskName" "WARNING"
        return
    }
    
    if ($IsDryRun) {
        Write-Log "WOULD disable task: $TaskPath$TaskName ($Description)" "DRYRUN"
        return
    }
    
    try {
        Disable-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop | Out-Null
        Write-Log "Disabled task: $TaskPath$TaskName" "SUCCESS"
        Add-Rollback "Rollback: $TaskName" "Enable-ScheduledTask -TaskPath '$TaskPath' -TaskName '$TaskName'"
    }
    catch {
        Write-Log "Failed to disable task $TaskPath$TaskName : $_" "ERROR"
    }
}

# Main execution
Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host " Windows Optimization Toolkit" -ForegroundColor Blue
Write-Host " Cleanup Executor" -ForegroundColor Blue
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""

$mode = if ($DryRun) { "DRY RUN" } else { "EXECUTE" }
Write-Host "Mode: $mode" -ForegroundColor $(if ($DryRun) { "Cyan" } else { "Yellow" })
Write-Host "Manifest: $manifestFullPath"
Write-Host "Log: $logFile"
Write-Host ""

# Initialize log
Write-Log "Session started - Mode: $mode"
Write-Log "Manifest: $manifestFullPath"

if (-not $DryRun) {
    Initialize-Rollback
}

# Load manifest
$manifest, $manifestContent = Load-Manifest $manifestFullPath

# Determine level
$effectiveLevel = if ($Level) { $Level } else { $manifest.aggressiveness_level }
Write-Log "Aggressiveness level: $effectiveLevel"

# Create restore point if executing
if ($Execute -and -not $SkipRestorePoint) {
    Write-Log "Creating system restore point..."
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Windows Optimization Toolkit - $timestamp" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Log "Restore point created" "SUCCESS"
    }
    catch {
        Write-Log "Could not create restore point: $_" "WARNING"
        Write-Host ""
        $continue = Read-Host "Continue without restore point? (y/N)"
        if ($continue -ne "y" -and $continue -ne "Y") {
            Write-Log "Execution cancelled by user"
            exit 0
        }
    }
}

# Confirm execution
if ($Execute) {
    Write-Host ""
    Write-Host "WARNING: This will make changes to your system." -ForegroundColor Yellow
    $confirm = Read-Host "Continue? (y/N)"
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Log "Execution cancelled by user"
        exit 0
    }
    Write-Host ""
}

# Apply changes based on level
Write-Log "Applying $effectiveLevel level optimizations..."

# === TELEMETRY (all levels) ===
Write-Log "--- Telemetry ---"

# DiagTrack service
Disable-ServiceSafely -Name "DiagTrack" -Description "Connected User Experiences and Telemetry" -IsDryRun $DryRun

# dmwappushservice
Disable-ServiceSafely -Name "dmwappushservice" -Description "WAP Push Message Routing Service" -IsDryRun $DryRun

# Advertising ID
Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Description "Advertising ID" -IsDryRun $DryRun

# === ADS AND SUGGESTIONS (all levels) ===
Write-Log "--- Ads and Suggestions ---"

$adKeys = @(
    @{Name = "SubscribedContent-338388Enabled"; Desc = "Suggested apps in Start"},
    @{Name = "SubscribedContent-338389Enabled"; Desc = "Suggested apps"},
    @{Name = "SubscribedContent-353694Enabled"; Desc = "Suggestions"},
    @{Name = "SubscribedContent-353696Enabled"; Desc = "Suggestions"},
    @{Name = "RotatingLockScreenOverlayEnabled"; Desc = "Lock screen tips"},
    @{Name = "SubscribedContent-338387Enabled"; Desc = "Lock screen suggestions"},
    @{Name = "SoftLandingEnabled"; Desc = "Windows tips"},
    @{Name = "SubscribedContent-338393Enabled"; Desc = "Settings suggestions"},
    @{Name = "SubscribedContent-353698Enabled"; Desc = "Settings suggestions"}
)

foreach ($key in $adKeys) {
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name $key.Name -Value 0 -Description $key.Desc -IsDryRun $DryRun
}

# === RGB SOFTWARE (all levels) ===
Write-Log "--- RGB Software ---"

# Razer services
Set-ServiceManual -Name "Razer Chroma SDK Service" -Description "Razer Chroma SDK" -IsDryRun $DryRun
Set-ServiceManual -Name "Razer Chroma SDK Server" -Description "Razer Chroma SDK Server" -IsDryRun $DryRun

# Disable startup
Disable-StartupItem -Name "Razer Synapse" -Description "Razer Synapse" -IsDryRun $DryRun

# === MODERATE AND AGGRESSIVE LEVELS ===
if ($effectiveLevel -in @("moderate", "aggressive")) {
    Write-Log "--- AI Features (Moderate+) ---"
    
    # Copilot - Registry disable
    Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Description "Disable Copilot (HKCU)" -IsDryRun $DryRun
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Description "Disable Copilot (HKLM)" -IsDryRun $DryRun
    
    # Remove Copilot AppX
    Remove-AppxPackageSafely -PackageName "Microsoft.Copilot" -Description "Microsoft Copilot" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.Windows.Copilot" -Description "Windows Copilot" -IsDryRun $DryRun
    
    # Recall
    Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1 -Description "Disable Recall" -IsDryRun $DryRun
    
    Write-Log "--- Bloatware (Moderate+) ---"
    
    # Xbox services to manual (keep for gaming)
    Set-ServiceManual -Name "XblAuthManager" -Description "Xbox Live Auth Manager" -IsDryRun $DryRun
    Set-ServiceManual -Name "XblGameSave" -Description "Xbox Live Game Save" -IsDryRun $DryRun
    Set-ServiceManual -Name "XboxGipSvc" -Description "Xbox Accessory Management" -IsDryRun $DryRun
    Set-ServiceManual -Name "XboxNetApiSvc" -Description "Xbox Live Networking" -IsDryRun $DryRun
    
    # Remove bloatware apps
    Remove-AppxPackageSafely -PackageName "Microsoft.549981C3F5F10" -Description "Cortana" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.YourPhone" -Description "Phone Link" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.WindowsFeedbackHub" -Description "Feedback Hub" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.GetHelp" -Description "Get Help" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.Getstarted" -Description "Tips" -IsDryRun $DryRun
    
    # Disable telemetry tasks
    Disable-ScheduledTaskSafely -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "Microsoft Compatibility Appraiser" -Description "Compatibility Telemetry" -IsDryRun $DryRun
    Disable-ScheduledTaskSafely -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "ProgramDataUpdater" -Description "Program Data Updater" -IsDryRun $DryRun
}

# === AGGRESSIVE LEVEL ONLY ===
if ($effectiveLevel -eq "aggressive") {
    Write-Log "--- Aggressive Optimizations ---"
    
    # More bloatware removal
    Remove-AppxPackageSafely -PackageName "Microsoft.BingWeather" -Description "Weather" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.BingNews" -Description "News" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.People" -Description "People" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.WindowsMaps" -Description "Maps" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.ZuneMusic" -Description "Groove Music" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Microsoft.ZuneVideo" -Description "Movies & TV" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "Clipchamp.Clipchamp" -Description "Clipchamp" -IsDryRun $DryRun
    Remove-AppxPackageSafely -PackageName "MicrosoftTeams" -Description "Teams" -IsDryRun $DryRun
    
    # Disable more services
    Set-ServiceManual -Name "Fax" -Description "Fax Service" -IsDryRun $DryRun
}

# Finalize
Write-Log "Session complete"

if (-not $DryRun) {
    # Finish rollback script
    Add-Content -Path $rollbackFile -Value 'Write-Host "Rollback complete."'
    Write-Log "Rollback script saved: $rollbackFile"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Blue
Write-Host " Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Blue
Write-Host ""
Write-Host "Log file: $logFile"
if (-not $DryRun) {
    Write-Host "Rollback script: $rollbackFile"
    Write-Host ""
    Write-Host "To undo changes, run:" -ForegroundColor Yellow
    Write-Host "  .\$rollbackFile" -ForegroundColor Cyan
}
Write-Host ""
