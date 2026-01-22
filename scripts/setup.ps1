<#
.SYNOPSIS
    REAPER One-Time Setup
    
.DESCRIPTION
    Complete setup script that:
    1. Creates system restore point
    2. Runs cleanup with your chosen level
    3. Installs protection task (re-applies after Windows Update)
    4. Generates full audit log and rollback script
    
    After this, you don't need to run anything again unless Windows Update
    reverts your settings - the protection task handles that automatically.
    
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Level aggressive -SkipProtectionTask
#>

param(
    [ValidateSet("light", "moderate", "aggressive")]
    [string]$Level = "moderate",
    [string]$Profile,
    [switch]$SkipProtectionTask,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin -and -not $DryRun) {
    Write-Host ""
    Write-Host "  ERROR: This script requires Administrator privileges." -ForegroundColor Red
    Write-Host ""
    Write-Host "  Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Clear-Host
Write-Host ""
Write-Host "  ██████╗ ███████╗ █████╗ ██████╗ ███████╗██████╗ " -ForegroundColor Red
Write-Host "  ██╔══██╗██╔════╝██╔══██╗██╔══██╗██╔════╝██╔══██╗" -ForegroundColor Red
Write-Host "  ██████╔╝█████╗  ███████║██████╔╝█████╗  ██████╔╝" -ForegroundColor Red
Write-Host "  ██╔══██╗██╔══╝  ██╔══██║██╔═══╝ ██╔══╝  ██╔══██╗" -ForegroundColor Red
Write-Host "  ██║  ██║███████╗██║  ██║██║     ███████╗██║  ██║" -ForegroundColor Red
Write-Host "  ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝" -ForegroundColor Red
Write-Host ""
Write-Host "  ONE-TIME SETUP" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This will:" -ForegroundColor White
Write-Host "    1. Create a system restore point" -ForegroundColor Gray
Write-Host "    2. Disable unnecessary services ($Level level)" -ForegroundColor Gray
Write-Host "    3. Block telemetry and ads via registry" -ForegroundColor Gray
Write-Host "    4. Install protection task (re-applies after updates)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Level: $Level" -ForegroundColor Yellow
if ($Profile) {
    Write-Host "  Profile: $Profile" -ForegroundColor Yellow
}
Write-Host ""

if ($DryRun) {
    Write-Host "  MODE: DRY RUN (no changes will be made)" -ForegroundColor Cyan
    Write-Host ""
}

# Confirm
Write-Host "  After setup, you won't need to run this again." -ForegroundColor Green
Write-Host "  The protection task runs automatically after Windows Updates." -ForegroundColor Green
Write-Host ""
$confirm = Read-Host "  Ready to proceed? (y/N)"
if ($confirm -ne "y" -and $confirm -ne "Y") {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

# Step 1: Run cleanup
Write-Host ""
Write-Host "  STEP 1/2: Running cleanup..." -ForegroundColor Cyan
Write-Host ""

$cleanupScript = Join-Path $scriptDir "execute_cleanup.ps1"
$profileArg = if ($Profile) { "-Profile $Profile" } else { "" }
$cleanupArgs = if ($DryRun) { "-DryRun -Level $Level $profileArg" } else { "-Execute -Level $Level -AutoRollbackOnError $profileArg" }

& powershell.exe -ExecutionPolicy Bypass -File $cleanupScript $cleanupArgs.Split(" ")

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  Cleanup failed. Check the log for details." -ForegroundColor Red
    exit 1
}

# Step 2: Install protection task
if (-not $SkipProtectionTask -and -not $DryRun) {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  STEP 2/2: Installing protection task..." -ForegroundColor Cyan
    Write-Host ""
    
    $taskName = "REAPER-PostUpdate"
    $taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    
    if ($taskExists) {
        Write-Host "  Protection task already installed." -ForegroundColor Green
    } else {
        $protectionScript = Join-Path $scriptDir "post_update_check.ps1"
        
        $action = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$protectionScript`" -AutoReapply -Level $Level $profileArg"
        
        # Trigger: Windows Update event + logon fallback
        $subscription = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-WindowsUpdateClient/Operational">
    <Select Path="Microsoft-Windows-WindowsUpdateClient/Operational">
      *[System[(EventID=19 or EventID=20)]]
    </Select>
  </Query>
</QueryList>
"@
        $triggerEvent = New-ScheduledTaskTrigger -OnEvent -Subscription $subscription
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerEvent, $triggerLogon) -Principal $principal -Settings $settings -Description "REAPER: Re-applies service settings after Windows Update" | Out-Null
        
        Write-Host "  ✓ Protection task installed: $taskName" -ForegroundColor Green
    }
}

# Done
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ✓ SETUP COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host "  What happens now:" -ForegroundColor White
Write-Host "    • Services are disabled and will stay disabled" -ForegroundColor Gray
Write-Host "    • If Windows Update re-enables them, protection task fixes it" -ForegroundColor Gray
Write-Host "    • You don't need to run anything again" -ForegroundColor Gray
Write-Host ""
Write-Host "  Files created:" -ForegroundColor White
$logsDir = Join-Path $projectRoot "data\audit_logs"
Write-Host "    • Audit log: $logsDir\*_execution.log" -ForegroundColor Gray
Write-Host "    • Rollback:  $logsDir\*_rollback.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "  To undo everything:" -ForegroundColor Yellow
Write-Host "    1. Run the rollback script, OR" -ForegroundColor Gray
Write-Host "    2. Use System Restore (search 'Create a restore point')" -ForegroundColor Gray
Write-Host ""
