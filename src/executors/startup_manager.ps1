<#
.SYNOPSIS
    Startup item management functions for Windows Optimization Toolkit
    
.DESCRIPTION
    Provides functions to manage startup items via registry.
#>

$StartupPaths = @{
    UserRun = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    MachineRun = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    UserApproved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
    MachineApproved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
}

function Get-StartupItem {
    param([string]$Name)
    
    $results = @()
    
    foreach ($pathName in $StartupPaths.Keys) {
        $path = $StartupPaths[$pathName]
        if (-not (Test-Path $path)) { continue }
        
        $item = Get-ItemProperty -Path $path -Name $Name -ErrorAction SilentlyContinue
        if ($item) {
            $results += @{
                Name = $Name
                Location = $pathName
                Path = $path
                Value = $item.$Name
            }
        }
    }
    
    return $results
}

function Get-StartupEnabled {
    param(
        [string]$Name,
        [string]$ApprovedPath
    )
    
    if (-not (Test-Path $ApprovedPath)) { return $true }
    
    try {
        $value = (Get-ItemProperty -Path $ApprovedPath -Name $Name -ErrorAction Stop).$Name
        if ($value -is [byte[]]) {
            return $value[0] -notin @(0x02, 0x03, 0x06)
        }
    }
    catch {
        return $true
    }
    
    return $true
}

function Disable-StartupItem {
    param([string]$Name)
    
    $results = @()
    
    # Disable in User approved
    if (Test-Path $StartupPaths.UserApproved) {
        $item = Get-ItemProperty -Path $StartupPaths.UserApproved -Name $Name -ErrorAction SilentlyContinue
        if ($item) {
            $currentValue = $item.$Name
            $disabledValue = [byte[]]@(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            Set-ItemProperty -Path $StartupPaths.UserApproved -Name $Name -Value $disabledValue -Type Binary
            
            $results += @{
                Location = "UserApproved"
                Before = $currentValue
                After = $disabledValue
                RollbackCommand = "Set-ItemProperty -Path '$($StartupPaths.UserApproved)' -Name '$Name' -Value ([byte[]]@($($currentValue -join ', '))) -Type Binary"
            }
        }
    }
    
    # Disable in Machine approved (requires admin)
    if (Test-Path $StartupPaths.MachineApproved) {
        $item = Get-ItemProperty -Path $StartupPaths.MachineApproved -Name $Name -ErrorAction SilentlyContinue
        if ($item) {
            $currentValue = $item.$Name
            $disabledValue = [byte[]]@(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
            Set-ItemProperty -Path $StartupPaths.MachineApproved -Name $Name -Value $disabledValue -Type Binary
            
            $results += @{
                Location = "MachineApproved"
                Before = $currentValue
                After = $disabledValue
                RollbackCommand = "Set-ItemProperty -Path '$($StartupPaths.MachineApproved)' -Name '$Name' -Value ([byte[]]@($($currentValue -join ', '))) -Type Binary"
            }
        }
    }
    
    return $results
}

function Remove-StartupItem {
    param([string]$Name)
    
    $results = @()
    
    foreach ($pathName in @("UserRun", "MachineRun")) {
        $path = $StartupPaths[$pathName]
        if (-not (Test-Path $path)) { continue }
        
        $item = Get-ItemProperty -Path $path -Name $Name -ErrorAction SilentlyContinue
        if ($item) {
            $currentValue = $item.$Name
            Remove-ItemProperty -Path $path -Name $Name -ErrorAction Stop
            
            $results += @{
                Location = $pathName
                Before = $currentValue
                RollbackCommand = "Set-ItemProperty -Path '$path' -Name '$Name' -Value '$currentValue'"
            }
        }
    }
    
    return $results
}

Export-ModuleMember -Function Get-StartupItem, Get-StartupEnabled, Disable-StartupItem, Remove-StartupItem
