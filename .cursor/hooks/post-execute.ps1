# Post-execution hook - runs after system changes
# Validates results and generates report

param(
    [string]$LogFile
)

Write-Host "=== REAPER Post-Execute Hook ===" -ForegroundColor Cyan

# Check if log file exists
if ($LogFile -and (Test-Path $LogFile)) {
    $changes = Get-Content $LogFile | Where-Object { $_ -match "^\[" }
    $changeCount = $changes.Count
    
    Write-Host "Changes applied: $changeCount" -ForegroundColor Yellow
    
    # Check for errors in log
    $errors = Get-Content $LogFile | Where-Object { $_ -match "ERROR|FAILED" }
    if ($errors) {
        Write-Host "Errors detected:" -ForegroundColor Red
        $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    }
}

# Verify critical services still running
$criticalServices = @("Winmgmt", "EventLog", "PlugPlay", "Power")
$failed = @()

foreach ($svc in $criticalServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne "Running") {
        $failed += $svc
    }
}

if ($failed.Count -gt 0) {
    Write-Host "WARNING: Critical services not running: $($failed -join ', ')" -ForegroundColor Red
    Write-Host "Consider running rollback script." -ForegroundColor Yellow
} else {
    Write-Host "Critical services verified." -ForegroundColor Green
}

Write-Host "Post-execute complete." -ForegroundColor Green
exit 0
