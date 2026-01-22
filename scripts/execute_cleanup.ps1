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

.PARAMETER Profile
    Optional profile name from config\profiles.json to apply overrides.

.PARAMETER ConfirmEach
    Prompt before each change (services, registry, tasks, startup).

.PARAMETER SkipRegistryBackup
    Skip exporting registry backups before changes.
    
.EXAMPLE
    .\execute_cleanup.ps1 -DryRun
    .\execute_cleanup.ps1 -Execute -Level moderate
#>

param(
    [switch]$DryRun,
    [switch]$Execute,
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level = "moderate",
    [string]$Profile,
    [switch]$SkipRestorePoint,
    [switch]$AutoRollbackOnError,
    [switch]$ConfirmEach,
    [switch]$SkipRegistryBackup
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
$backupDir = Join-Path $projectRoot "data\backups"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Ensure logs directory
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

$logFile = Join-Path $logsDir "$($timestamp)_execution.log"
$rollbackFile = Join-Path $logsDir "$($timestamp)_rollback.ps1"
$summaryFile = Join-Path $logsDir "$($timestamp)_summary.txt"
$profilesPath = Join-Path $projectRoot "config\profiles.json"
$registryBackupDir = Join-Path $backupDir "registry_$timestamp"
$registryBackupUsed = $false

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

function Confirm-Action {
    param(
        [string]$Prompt,
        [bool]$IsDryRun
    )
    
    if ($IsDryRun -or -not $ConfirmEach) {
        return $true
    }
    
    $answer = Read-Host $Prompt
    return ($answer -eq "y" -or $answer -eq "Y")
}

function Get-ProfileData {
    param([string]$ProfileName)
    
    if (-not $ProfileName) { return $null }
    
    if (-not (Test-Path $profilesPath)) {
        Write-Log "Profile file not found: $profilesPath" "WARN"
        return $null
    }
    
    try {
        $json = Get-Content -Path $profilesPath -Raw | ConvertFrom-Json
        $profile = $null
        
        if ($json.profiles) {
            foreach ($prop in $json.profiles.PSObject.Properties) {
                if ($prop.Name -eq $ProfileName) {
                    $profile = $prop.Value
                    break
                }
            }
        }
        
        if (-not $profile) {
            Write-Log "Profile '$ProfileName' not found in profiles.json" "ERROR"
            exit 1
        }
        
        return $profile
    }
    catch {
        Write-Log "Failed to load profile '$ProfileName': $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

function Normalize-Name {
    param([string]$Name)
    if ($null -eq $Name) { return "" }
    return $Name.ToLower()
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
        [object]$Value,
        [string]$Description,
        [string]$Type = "DWord",
        [bool]$IsDryRun
    )
    
    if ($IsDryRun) {
        Write-Log "WOULD SET: $Path\$Name = $Value ($Type)" "DRYRUN"
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
        
        switch ($Type) {
            "DWord" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force }
            "String" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -Force }
            default {
                Write-Log "Unsupported registry type '$Type' for $Path\$Name" "WARN"
                return $false
            }
        }
        
        Write-Log "SET: $Path\$Name = $Value" "SUCCESS"
        
        if ($existed -and $null -ne $currentValue) {
            Add-RollbackCommand "Restore $Name" "Set-ItemProperty -Path '$Path' -Name '$Name' -Value '$currentValue' -Type $Type"
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

function Convert-RegistryPathForRegExe {
    param([string]$Path)
    
    return $Path `
        -replace '^HKCU:\\', 'HKCU\' `
        -replace '^HKLM:\\', 'HKLM\'
}

function Backup-RegistryKeys {
    param(
        [array]$Keys,
        [string]$OutputDir,
        [bool]$IsDryRun
    )
    
    if ($IsDryRun) {
        Write-Log "WOULD BACKUP registry keys to $OutputDir" "DRYRUN"
        return
    }
    
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }
    
    $uniquePaths = $Keys | ForEach-Object { $_.Path } | Sort-Object -Unique
    foreach ($path in $uniquePaths) {
        if (-not (Test-Path $path)) { continue }
        
        $regPath = Convert-RegistryPathForRegExe -Path $path
        $safeName = ($regPath -replace '[\\/:*?"<>|]', '_')
        $outFile = Join-Path $OutputDir "$safeName.reg"
        
        try {
            & reg export $regPath $outFile /y | Out-Null
            Write-Log "Backed up: $regPath -> $outFile" "INFO"
        } catch {
            Write-Log "Failed to backup $regPath : $($_.Exception.Message)" "WARN"
        }
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
    Write-Host "Usage: .\execute_cleanup.ps1 -DryRun | -Execute [-Level light|moderate|aggressive] [-Profile name] [-ConfirmEach]" -ForegroundColor Yellow
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
if ($Profile) {
    Write-Host "  Profile: $Profile" -ForegroundColor White
}
Write-Host "  Log: $logFile" -ForegroundColor DarkGray
Write-Host ""

Write-Log "Session started - Mode: $mode, Level: $Level" "INFO"

$profileData = $null
if ($Profile) {
    $profileData = Get-ProfileData -ProfileName $Profile
    Write-Log "Profile loaded: $Profile" "INFO"
}

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
    # === SPYWARE/TELEMETRY (always disable) ===
    @{Name="DiagTrack"; Reason="SPYWARE: Telemetry - sends usage data to Microsoft"}
    @{Name="dmwappushservice"; Reason="SPYWARE: WAP push messages"}
    @{Name="WMPNetworkSvc"; Reason="SPYWARE: Media Player network sharing"}
    @{Name="WerSvc"; Reason="SPYWARE: Windows Error Reporting - sends crash data to Microsoft"}
    # NOTE: CDPUserSvc removed - breaks Night Light feature
    # NOTE: SSDPSRV removed - needed for network printer/device discovery
    @{Name="PcaSvc"; Reason="SPYWARE: Program Compatibility Assistant - telemetry"}
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

if ($profileData) {
    $keepSet = @{}
    foreach ($name in ($profileData.keep_services | Where-Object { $_ })) {
        $keepSet[(Normalize-Name $name)] = $true
    }
    
    $services = $services | Where-Object {
        -not $keepSet.ContainsKey((Normalize-Name $_.Name))
    }
    
    $existing = @{}
    foreach ($svc in $services) {
        $existing[(Normalize-Name $svc.Name)] = $true
    }
    
    foreach ($name in ($profileData.disable_services | Where-Object { $_ })) {
        $key = Normalize-Name $name
        if (-not $existing.ContainsKey($key)) {
            $services += @{Name=$name; Reason="Profile '$Profile' override"}
        }
    }
}

$foundServices = 0
$notFoundServices = @()

foreach ($svc in $services) {
    if (-not (Confirm-Action -Prompt "Disable service $($svc.Name)? (y/N)" -IsDryRun $DryRun)) {
        Write-Log "Skipped service: $($svc.Name)" "WARN"
        continue
    }
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

# TELEMETRY & TRACKING - Always disable these
$regKeys = @(
    # Advertising
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; Value=0; Desc="SPYWARE: Advertising ID tracking"}
    
    # App suggestions and ads
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338388Enabled"; Value=0; Desc="SPYWARE: Start menu ads"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338389Enabled"; Value=0; Desc="SPYWARE: App suggestions"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353694Enabled"; Value=0; Desc="SPYWARE: Settings suggestions"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353696Enabled"; Value=0; Desc="SPYWARE: Account notifications"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SoftLandingEnabled"; Value=0; Desc="SPYWARE: Windows tips/ads"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="RotatingLockScreenOverlayEnabled"; Value=0; Desc="SPYWARE: Lock screen ads"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SilentInstalledAppsEnabled"; Value=0; Desc="SPYWARE: Silent app installs"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="ContentDeliveryAllowed"; Value=0; Desc="SPYWARE: Content delivery"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="PreInstalledAppsEnabled"; Value=0; Desc="SPYWARE: Pre-installed app suggestions"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="PreInstalledAppsEverEnabled"; Value=0; Desc="SPYWARE: Block future pre-installs"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="OemPreInstalledAppsEnabled"; Value=0; Desc="SPYWARE: OEM bloatware suggestions"}
    
    # Telemetry settings
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name="TailoredExperiencesWithDiagnosticDataEnabled"; Value=0; Desc="SPYWARE: Tailored experiences"}
    @{Path="HKCU:\Software\Microsoft\Siuf\Rules"; Name="NumberOfSIUFInPeriod"; Value=0; Desc="SPYWARE: Feedback frequency"}
    
    # Activity tracking
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="EnableActivityFeed"; Value=0; Desc="SPYWARE: Activity feed"}
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="PublishUserActivities"; Value=0; Desc="SPYWARE: Publish activities"}
    @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="UploadUserActivities"; Value=0; Desc="SPYWARE: Upload activities to Microsoft"}
    
    # Location tracking - uses string value
    # Note: Location is handled separately as it uses a string value
    
    # App telemetry
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="Start_TrackProgs"; Value=0; Desc="SPYWARE: Track app usage"}
    @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="Start_TrackDocs"; Value=0; Desc="SPYWARE: Track recent documents"}
)

if ($Level -in @("moderate", "aggressive")) {
    $regKeys += @(
        # AI Features
        @{Path="HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"; Name="TurnOffWindowsCopilot"; Value=1; Desc="SPYWARE: Disable Copilot"}
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"; Name="TurnOffWindowsCopilot"; Value=1; Desc="SPYWARE: Disable Copilot (system)"}
        @{Path="HKCU:\Software\Policies\Microsoft\Windows\WindowsAI"; Name="DisableAIDataAnalysis"; Value=1; Desc="SPYWARE: Disable Recall"}
        @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"; Name="DisableAIDataAnalysis"; Value=1; Desc="SPYWARE: Disable Recall (system)"}
        
        # Cloud clipboard
        @{Path="HKCU:\Software\Microsoft\Clipboard"; Name="EnableClipboardHistory"; Value=0; Desc="SPYWARE: Clipboard history to cloud"}
        
        # Search
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="BingSearchEnabled"; Value=0; Desc="SPYWARE: Bing search integration"}
        @{Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="CortanaConsent"; Value=0; Desc="SPYWARE: Cortana consent"}
        
        # Input personalization (keylogger-like)
        @{Path="HKCU:\Software\Microsoft\InputPersonalization"; Name="RestrictImplicitInkCollection"; Value=1; Desc="SPYWARE: Ink data collection"}
        @{Path="HKCU:\Software\Microsoft\InputPersonalization"; Name="RestrictImplicitTextCollection"; Value=1; Desc="SPYWARE: Text data collection"}
        @{Path="HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"; Name="HarvestContacts"; Value=0; Desc="SPYWARE: Contact harvesting"}
        @{Path="HKCU:\Software\Microsoft\Personalization\Settings"; Name="AcceptedPrivacyPolicy"; Value=0; Desc="SPYWARE: Revoke personalization consent"}
    )
}

if ($profileData -and $profileData.registry) {
    foreach ($entry in $profileData.registry) {
        if (-not $entry.path -or -not $entry.name) { continue }
        
        $regKeys += @{
            Path = $entry.path
            Name = $entry.name
            Value = $entry.value
            Type = if ($entry.type) { $entry.type } else { "DWord" }
            Desc = "Profile '$Profile' override"
        }
    }
}

if (-not $DryRun -and -not $SkipRegistryBackup) {
    Write-Section "REGISTRY BACKUP"
    Backup-RegistryKeys -Keys $regKeys -OutputDir $registryBackupDir -IsDryRun $DryRun
    $registryBackupUsed = $true
}

foreach ($key in $regKeys) {
    if (-not (Confirm-Action -Prompt "Set registry $($key.Path)\$($key.Name)? (y/N)" -IsDryRun $DryRun)) {
        Write-Log "Skipped registry: $($key.Path)\$($key.Name)" "WARN"
        continue
    }
    
    $type = if ($key.ContainsKey("Type")) { $key.Type } else { "DWord" }
    Set-RegistrySafe -Path $key.Path -Name $key.Name -Value $key.Value -Description $key.Desc -Type $type -IsDryRun $DryRun
}

# ============================================================================
# STARTUP ITEMS
# ============================================================================

Write-Section "STARTUP ITEMS"

$startupItems = @()
if ($Level -in @("moderate", "aggressive")) {
    $startupItems += @("iCloud", "iCloudDrive", "iCloud Services")
}

if ($profileData -and $profileData.disable_startup_items) {
    $startupItems += $profileData.disable_startup_items
}

$startupItems = $startupItems | Where-Object { $_ } | Sort-Object -Unique

if ($startupItems.Count -gt 0) {
    $startupManagerPath = Join-Path $projectRoot "src\executors\startup_manager.ps1"
    if (Test-Path $startupManagerPath) {
        . $startupManagerPath
    } else {
        Write-Log "Startup manager not found at $startupManagerPath" "WARN"
    }
}

$startupProcessed = 0
foreach ($item in $startupItems) {
    if (-not (Confirm-Action -Prompt "Disable startup item $item? (y/N)" -IsDryRun $DryRun)) {
        Write-Log "Skipped startup item: $item" "WARN"
        continue
    }
    
    if (-not (Get-Command Get-StartupItem -ErrorAction SilentlyContinue)) {
        Write-Log "Startup management functions unavailable. Skipping startup items." "WARN"
        break
    }
    
    $entries = Get-StartupItem -Name $item
    if (-not $entries -or $entries.Count -eq 0) {
        Write-Log "Startup item not found: $item" "INFO"
        continue
    }
    
    if ($DryRun) {
        Write-Log "WOULD DISABLE STARTUP: $item" "DRYRUN"
        $startupProcessed++
        continue
    }
    
    try {
        $removeResults = Remove-StartupItem -Name $item
        foreach ($res in $removeResults) {
            Write-Log "Removed startup entry: $item ($($res.Location))" "SUCCESS"
            Add-RollbackCommand "Restore startup entry $item ($($res.Location))" $res.RollbackCommand
        }
        
        $disableResults = Disable-StartupItem -Name $item
        foreach ($res in $disableResults) {
            Write-Log "Disabled startup approval: $item ($($res.Location))" "SUCCESS"
            Add-RollbackCommand "Restore startup approval $item ($($res.Location))" $res.RollbackCommand
        }
        
        if ($removeResults.Count -eq 0 -and $disableResults.Count -eq 0) {
            Write-Log "No startup changes needed for: $item" "INFO"
        } else {
            $script:SuccessCount++
        }
        
        $startupProcessed++
    } catch {
        Write-Log "Failed to update startup item $item : $($_.Exception.Message)" "ERROR"
        $script:ErrorCount++
    }
}

# ============================================================================
# SCHEDULED TASKS (Telemetry/Spyware)
# ============================================================================

Write-Section "SCHEDULED TASKS (Spyware)"

$tasksToDisable = @(
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator"; Reason="SPYWARE: CEIP data collection"}
    @{Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip"; Reason="SPYWARE: USB usage telemetry"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser"; Reason="SPYWARE: App compatibility telemetry"}
    @{Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater"; Reason="SPYWARE: Program inventory"}
    @{Path="\Microsoft\Windows\Autochk\"; Name="Proxy"; Reason="SPYWARE: Autochk telemetry"}
    @{Path="\Microsoft\Windows\DiskDiagnostic\"; Name="Microsoft-Windows-DiskDiagnosticDataCollector"; Reason="SPYWARE: Disk diagnostic data"}
    @{Path="\Microsoft\Windows\Feedback\Siuf\"; Name="DmClient"; Reason="SPYWARE: Feedback data"}
    @{Path="\Microsoft\Windows\Feedback\Siuf\"; Name="DmClientOnScenarioDownload"; Reason="SPYWARE: Feedback scenarios"}
    @{Path="\Microsoft\Windows\Windows Error Reporting\"; Name="QueueReporting"; Reason="SPYWARE: Error report queue"}
    @{Path="\Microsoft\Windows\PI\"; Name="Sqm-Tasks"; Reason="SPYWARE: SQM telemetry"}
)

if ($Level -in @("moderate", "aggressive")) {
    $tasksToDisable += @(
        @{Path="\Microsoft\Windows\Maps\"; Name="MapsToastTask"; Reason="Maps notification spam"}
        @{Path="\Microsoft\Windows\Maps\"; Name="MapsUpdateTask"; Reason="Maps updates - disable if not using"}
        @{Path="\Microsoft\Office\"; Name="Office ClickToRun Service Monitor"; Reason="Office telemetry"}
        @{Path="\Microsoft\Office\"; Name="OfficeTelemetryAgentFallBack2016"; Reason="Office telemetry"}
        @{Path="\Microsoft\Office\"; Name="OfficeTelemetryAgentLogOn2016"; Reason="Office telemetry"}
    )
}

if ($profileData -and $profileData.disable_tasks) {
    foreach ($fullPath in $profileData.disable_tasks) {
        if (-not $fullPath) { continue }
        $lastSlash = $fullPath.LastIndexOf("\")
        if ($lastSlash -lt 1) { continue }
        $taskPath = $fullPath.Substring(0, $lastSlash + 1)
        $taskName = $fullPath.Substring($lastSlash + 1)
        if (-not $taskName) { continue }
        
        $tasksToDisable += @{
            Path = $taskPath
            Name = $taskName
            Reason = "Profile '$Profile' override"
        }
    }
}

$taskCount = 0
foreach ($task in $tasksToDisable) {
    $fullPath = $task.Path + $task.Name
    try {
        $existingTask = Get-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($existingTask) {
            if (-not (Confirm-Action -Prompt "Disable task $fullPath? (y/N)" -IsDryRun $DryRun)) {
                Write-Log "Skipped task: $fullPath" "WARN"
                continue
            }
            if ($DryRun) {
                Write-Log "WOULD DISABLE: $fullPath" "DRYRUN"
                Write-Log "  Reason: $($task.Reason)" "DRYRUN"
            } else {
                Disable-ScheduledTask -TaskPath $task.Path -TaskName $task.Name -ErrorAction Stop | Out-Null
                Write-Log "Disabled task: $fullPath" "SUCCESS" "[OK]"
                Add-Content -Path $rollbackFile -Value "Enable-ScheduledTask -TaskPath '$($task.Path)' -TaskName '$($task.Name)'"
                $script:SuccessCount++
            }
            $taskCount++
        }
    } catch {
        Write-Log "Failed to disable task $fullPath : $_" "ERROR" "[FAIL]"
        $script:ErrorCount++
    }
}

Write-Log "Tasks processed: $taskCount" "INFO"

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
"@

if ($Profile) {
    $summaryText += "`nProfile: $Profile"
}

$summaryText += @"

Results:
  Services processed: $foundServices
  Registry keys: $($regKeys.Count)
  Startup items: $startupProcessed
  Scheduled tasks: $taskCount
  Successful: $($script:SuccessCount)
  Failed: $($script:ErrorCount)

Log file: $logFile
"@

if (-not $DryRun) {
    $summaryText += "`nRollback: $rollbackFile"
}

if ($registryBackupUsed) {
    $summaryText += "`nRegistry backup: $registryBackupDir"
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
