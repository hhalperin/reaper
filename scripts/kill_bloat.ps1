# REAPER - Kill Bloat Script
# Run as Administrator!

#Requires -RunAsAdministrator

Write-Host "`n  REAPER - Bloat Killer" -ForegroundColor Red
Write-Host "  =====================`n"

# Services to disable
$services = @(
    "asus",
    "AsusCertService", 
    "AsusFanControlService",
    "asusm",
    "AsusUpdateCheck",
    "SamsungMagicianSVC",
    "ArmouryCrateService",
    "asComSvc",
    "ROG Live Service"
)

Write-Host "Disabling services..." -ForegroundColor Yellow
foreach ($svc in $services) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "  [X] $svc" -ForegroundColor Green
    }
}

Start-Sleep -Seconds 2

Write-Host "`nKilling processes..." -ForegroundColor Yellow
$procs = @(
    "asus_framework",
    "AsusCertService",
    "AsusFanControlService",
    "ArmourySwAgent",
    "ArmourySocketServer",
    "ArmouryHtmlDebugServer",
    "SamsungMagician",
    "SamsungMagicianSVC",
    "MigrationService",
    "Widgets",
    "iCloud*",
    "ApplePhotoStreams",
    "APSDaemon",
    "secd"
)

foreach ($p in $procs) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Host "  [X] $($_.ProcessName)" -ForegroundColor Green
    }
}

Write-Host "`nVerifying..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$remaining = Get-Process | Where-Object { 
    $_.ProcessName -match "asus|samsung|armoury|icloud|widget" 
}

if ($remaining) {
    Write-Host "`nStubborn processes (may need reboot):" -ForegroundColor Red
    $remaining | Select-Object ProcessName, Id | Format-Table -AutoSize
} else {
    Write-Host "`n  ALL BLOAT KILLED!" -ForegroundColor Green
}

Write-Host "`nService status:" -ForegroundColor Yellow
Get-Service | Where-Object { $_.Name -in $services } | 
    Select-Object Name, Status, StartType | Format-Table -AutoSize

Write-Host "`nDone! If processes remain, reboot to fully apply.`n" -ForegroundColor Cyan
