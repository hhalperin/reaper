<#
.SYNOPSIS
    Install scheduled task for post-update protection
    
.DESCRIPTION
    Creates a Windows Scheduled Task that runs after Windows Update
    to check and reapply optimizations that may have been reverted.
    
.PARAMETER Uninstall
    Remove the scheduled task instead of installing it.
    
.EXAMPLE
    .\install_protection_task.ps1
    
.EXAMPLE
    .\install_protection_task.ps1 -Uninstall
#>

param(
    [switch]$Uninstall
)

$taskName = "WindowsOptimizationToolkit_PostUpdateCheck"
$taskPath = "\WindowsOptimizationToolkit\"

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERROR: Administrator privileges required." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator." -ForegroundColor Yellow
    exit 1
}

if ($Uninstall) {
    Write-Host "Removing scheduled task..." -ForegroundColor Yellow
    
    $existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
        Write-Host "Task removed successfully." -ForegroundColor Green
    } else {
        Write-Host "Task not found." -ForegroundColor Yellow
    }
    
    exit 0
}

Write-Host ""
Write-Host "Installing Post-Update Protection Task" -ForegroundColor Blue
Write-Host "======================================" -ForegroundColor Blue
Write-Host ""

# Get paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$postUpdateScript = Join-Path $scriptDir "post_update_check.ps1"

if (-not (Test-Path $postUpdateScript)) {
    Write-Host "ERROR: post_update_check.ps1 not found at $postUpdateScript" -ForegroundColor Red
    exit 1
}

# Remove existing task if present
$existingTask = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Removing existing task..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false
}

# Create the action - run PowerShell with the script
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$postUpdateScript`" -AutoReapply"

# Create triggers
# Trigger 1: After Windows Update (using event log)
# Event ID 19 = Installation Successful, Event ID 20 = Installation Failure but Restart Pending
$trigger1 = New-ScheduledTaskTrigger -AtLogOn

# We can't easily trigger on Windows Update completion via XML in PowerShell,
# so we'll use logon trigger + a manual trigger option

# Create principal - run with highest privileges
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable:$false `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

# Create and register the task
$task = New-ScheduledTask `
    -Action $action `
    -Principal $principal `
    -Trigger $trigger1 `
    -Settings $settings `
    -Description "Windows Optimization Toolkit - Checks for reverted optimizations after Windows Update and reapplies them."

Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -InputObject $task | Out-Null

Write-Host "Task installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Task Details:" -ForegroundColor Cyan
Write-Host "  Name: $taskName"
Write-Host "  Path: $taskPath"
Write-Host "  Trigger: At logon (to catch post-update reboots)"
Write-Host "  Action: Runs post_update_check.ps1 -AutoReapply"
Write-Host ""
Write-Host "The task will automatically check for reverted settings" -ForegroundColor Yellow
Write-Host "after each logon and reapply optimizations if needed." -ForegroundColor Yellow
Write-Host ""
Write-Host "To uninstall, run: .\install_protection_task.ps1 -Uninstall" -ForegroundColor Cyan
Write-Host ""
