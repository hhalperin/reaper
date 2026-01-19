---
name: safe-execution
description: Apply system changes with logging, rollback, and restore point protection
---

# Safe Execution

## When to Use

- Applying changes from manifest.yaml
- Disabling services or startup items
- Removing bloatware applications

## Safety Requirements

1. **Always dry-run first**
2. **Create restore point** before changes
3. **Log before/after state** for every change
4. **Generate rollback script** automatically
5. **Check critical_keep_list** before any action

## Usage

```powershell
# Preview changes
.\scripts\execute_cleanup.ps1 -DryRun

# Apply changes (requires Admin)
.\scripts\execute_cleanup.ps1 -Execute -Level light
```

Levels: `light`, `moderate`, `aggressive`

## PowerShell Pattern

```powershell
# Get before state
$before = Get-Service -Name $serviceName

# Apply change
Set-Service -Name $serviceName -StartupType Disabled
Stop-Service -Name $serviceName -Force

# Get after state
$after = Get-Service -Name $serviceName

# Log
"[$timestamp] $serviceName: $($before.StartType) -> Disabled"

# Rollback command
"Set-Service -Name '$serviceName' -StartupType $($before.StartType)"
```

## Forbidden Actions

Never modify:
- csrss, lsass, services, svchost, winlogon
- Windows Defender, Firewall
- Core networking services

## Output

| File | Contents |
|------|----------|
| `data/audit_logs/{ts}_execution.log` | All changes with timestamps |
| `data/audit_logs/{ts}_rollback.ps1` | PowerShell to undo changes |

## Rollback

```powershell
# If something breaks
.\data\audit_logs\{timestamp}_rollback.ps1

# Or use System Restore
```
