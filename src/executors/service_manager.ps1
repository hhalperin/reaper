<#
.SYNOPSIS
    Service management functions for Windows Optimization Toolkit
    
.DESCRIPTION
    Provides functions to safely manage Windows services with logging and rollback.
#>

function Get-ServiceState {
    param([string]$Name)
    
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) {
        return $null
    }
    
    $wmiSvc = Get-WmiObject Win32_Service -Filter "Name='$Name'"
    
    return @{
        Name = $svc.Name
        DisplayName = $svc.DisplayName
        Status = $svc.Status.ToString()
        StartType = $wmiSvc.StartMode
        Path = $wmiSvc.PathName
        Account = $wmiSvc.StartName
    }
}

function Set-ServiceStartType {
    param(
        [string]$Name,
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string]$StartType,
        [switch]$StopIfRunning
    )
    
    $before = Get-ServiceState -Name $Name
    if (-not $before) {
        throw "Service not found: $Name"
    }
    
    if ($StopIfRunning -and $before.Status -eq "Running") {
        Stop-Service -Name $Name -Force -ErrorAction Stop
    }
    
    Set-Service -Name $Name -StartupType $StartType -ErrorAction Stop
    
    $after = Get-ServiceState -Name $Name
    
    return @{
        Before = $before
        After = $after
        RollbackCommand = "Set-Service -Name '$Name' -StartupType $($before.StartType)"
    }
}

function Disable-ServiceSafe {
    param([string]$Name)
    return Set-ServiceStartType -Name $Name -StartType Disabled -StopIfRunning
}

function Enable-ServiceSafe {
    param(
        [string]$Name,
        [ValidateSet("Automatic", "Manual")]
        [string]$StartType = "Automatic"
    )
    return Set-ServiceStartType -Name $Name -StartType $StartType
}

# Export functions
Export-ModuleMember -Function Get-ServiceState, Set-ServiceStartType, Disable-ServiceSafe, Enable-ServiceSafe
