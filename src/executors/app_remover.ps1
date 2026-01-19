<#
.SYNOPSIS
    AppX package management functions for Windows Optimization Toolkit
    
.DESCRIPTION
    Provides functions to remove AppX packages and prevent reinstallation.
#>

function Get-AppxPackageInfo {
    param([string]$Name)
    
    $packages = Get-AppxPackage -AllUsers -Name "*$Name*" -ErrorAction SilentlyContinue
    $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | 
                   Where-Object { $_.PackageName -like "*$Name*" }
    
    return @{
        Installed = $packages
        Provisioned = $provisioned
    }
}

function Remove-AppxPackageSafe {
    param(
        [string]$Name,
        [switch]$RemoveProvisioned
    )
    
    $info = Get-AppxPackageInfo -Name $Name
    $results = @()
    
    foreach ($pkg in $info.Installed) {
        try {
            $pkgInfo = @{
                Name = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Publisher = $pkg.Publisher
                Version = $pkg.Version
            }
            
            Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
            
            $results += @{
                Type = "AppxPackage"
                Package = $pkgInfo
                Success = $true
                Note = "Package removed. Reinstall from Microsoft Store if needed."
            }
        }
        catch {
            $results += @{
                Type = "AppxPackage"
                Package = $pkg.Name
                Success = $false
                Error = $_.Exception.Message
            }
        }
    }
    
    if ($RemoveProvisioned) {
        foreach ($pkg in $info.Provisioned) {
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                
                $results += @{
                    Type = "ProvisionedPackage"
                    Package = $pkg.PackageName
                    Success = $true
                    Note = "Provisioned package removed. Will not install for new users."
                }
            }
            catch {
                $results += @{
                    Type = "ProvisionedPackage"
                    Package = $pkg.PackageName
                    Success = $false
                    Error = $_.Exception.Message
                }
            }
        }
    }
    
    return $results
}

function Get-InstalledBloatware {
    # List of common bloatware package names
    $bloatwarePatterns = @(
        "Microsoft.BingWeather",
        "Microsoft.BingNews",
        "Microsoft.GetHelp",
        "Microsoft.Getstarted",
        "Microsoft.MicrosoftOfficeHub",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.People",
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.WindowsMaps",
        "Microsoft.YourPhone",
        "Microsoft.ZuneMusic",
        "Microsoft.ZuneVideo",
        "Microsoft.549981C3F5F10",  # Cortana
        "Clipchamp.Clipchamp",
        "Microsoft.Todos",
        "MicrosoftTeams",
        "Microsoft.Copilot",
        "Microsoft.Windows.Copilot"
    )
    
    $installed = @()
    
    foreach ($pattern in $bloatwarePatterns) {
        $pkgs = Get-AppxPackage -AllUsers -Name "*$pattern*" -ErrorAction SilentlyContinue
        foreach ($pkg in $pkgs) {
            $installed += @{
                Name = $pkg.Name
                PackageFullName = $pkg.PackageFullName
                Version = $pkg.Version
                Pattern = $pattern
            }
        }
    }
    
    return $installed
}

Export-ModuleMember -Function Get-AppxPackageInfo, Remove-AppxPackageSafe, Get-InstalledBloatware
