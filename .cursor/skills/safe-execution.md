# Skill: Safe Execution

## Purpose
Apply system changes with full auditability and rollback.

## Requirements
1. Check critical_keep_list first
2. Get before state
3. Apply change
4. Log after state
5. Generate rollback command

## PowerShell Pattern
```powershell
$before = Get-Service -Name $name
Set-Service -Name $name -StartupType Disabled
$after = Get-Service -Name $name

# Log
"[$(Get-Date)] $name: $($before.StartType) -> Disabled"

# Rollback
"Set-Service -Name '$name' -StartupType $($before.StartType)"
```

## Safety Checks
- Never touch items in critical_keep_list
- Always create restore point first
- Require -Execute flag (not default)
