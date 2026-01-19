# REAPER - Usage Guide

**R**esource **E**valuation, **A**nalysis, **P**rocess **E**limination & **R**eporting

## Quick Start

### 1. Install Dependencies

```powershell
# Navigate to project directory
cd path\to\reaper

# Install Python dependencies
pip install -r requirements.txt
```

### 2. Collect System Inventory

```powershell
# Run inventory collection
python scripts/collect_inventory.py
```

This collects:
- All running processes (with resource usage)
- Windows services (with start types)
- Startup items (registry, folders)
- Scheduled tasks

Output is saved to `data/inventories/`.

### 3. Analyze for Suspects

```powershell
# Run analysis
python scripts/analyze_suspects.py
```

This identifies potential optimization targets based on:
- Non-Microsoft signed processes
- High resource usage
- Known bloatware patterns
- AI features (Copilot, Recall)

Output is saved to `data/analysis/`.

### 4. Review Recommendations

Open `data/analysis/analysis_*.yaml` to review:
- REMOVE recommendations (apps to uninstall)
- DISABLE recommendations (services/startup to disable)
- REVIEW recommendations (needs manual decision)

Edit `config/manifest.yaml` to customize decisions.

### 5. Preview Changes (Dry Run)

```powershell
# Run as Administrator
.\scripts\execute_cleanup.ps1 -DryRun
```

This shows what changes WOULD be made without actually changing anything.

### 6. Apply Changes

```powershell
# Run as Administrator
.\scripts\execute_cleanup.ps1 -Execute
```

This:
1. Creates a System Restore Point
2. Applies changes based on manifest
3. Logs all changes with rollback commands
4. Generates rollback script

### 7. Install Protection Task (Optional)

```powershell
# Run as Administrator
.\scripts\install_protection_task.ps1
```

This creates a scheduled task that:
- Runs after each logon
- Checks if settings were reverted
- Auto-reapplies optimizations

## Aggressiveness Levels

### Light (Default)
- Disables telemetry services
- Removes ads and suggestions
- Sets RGB software to manual start

### Moderate
- Everything in Light, plus:
- Disables Copilot and AI features
- Removes Cortana, Phone Link, Feedback Hub
- Sets Xbox services to manual

### Aggressive
- Everything in Moderate, plus:
- Removes Weather, News, Maps, etc.
- Removes Teams, Clipchamp
- Disables more optional services

## Rollback

If something goes wrong:

### Option 1: Use Generated Rollback Script
```powershell
.\data\audit_logs\[timestamp]_rollback.ps1
```

### Option 2: Use System Restore
1. Search "Create a restore point" in Start
2. Click "System Restore"
3. Choose the restore point created before changes

## Files and Directories

| Path | Purpose |
|------|---------|
| `config/manifest.yaml` | Master configuration - what to keep/remove |
| `config/known_processes.yaml` | Database of researched processes |
| `config/settings.yaml` | Tool settings and thresholds |
| `data/inventories/` | Collected system data |
| `data/analysis/` | Analysis results |
| `data/audit_logs/` | Execution logs and rollback scripts |
| `scripts/` | Entry point scripts |

## Troubleshooting

### "Access Denied" Errors
Run PowerShell as Administrator for execution scripts.

### Python Module Not Found
Ensure you're in the project directory and have installed dependencies:
```powershell
pip install -r requirements.txt
```

### Service Won't Disable
Some services are protected. Check if it's in the critical_keep_list in manifest.yaml.

### Changes Reverted After Update
Run the post-update check:
```powershell
.\scripts\post_update_check.ps1 -AutoReapply
```

Or install the protection task to do this automatically.
