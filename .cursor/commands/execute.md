# Execute Cleanup

Apply changes defined in manifest.yaml. Requires Administrator.

```powershell
.\scripts\execute_cleanup.ps1 -Execute -Level light
```

Creates restore point, logs all changes, generates rollback script.

Output: `data/audit_logs/{timestamp}_*.log` and `*_rollback.ps1`
