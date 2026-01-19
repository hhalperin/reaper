# REAPER

**R**esource **E**valuation, **A**nalysis, **P**rocess **E**limination & **R**eporting

A forensic-grade Windows process investigation and removal toolkit. REAPER systematically inventories your system, identifies resource-draining bloatware, researches each suspect process, and executes surgical removal with full auditability and rollback capability.

```
    ___  _______  ___   ____  _______  ___  
   / _ \/ __/ _ |/ _ \ / __/ / __/ _ \/ _ \ 
  / , _/ _// __ / ___// _/  / _// , _/ , _/ 
 /_/|_/___/_/ |_/_/  /___/ /___/_/|_/_/|_|  
                                            
 Process Investigation & Elimination Toolkit
```

## Why REAPER?

Windows 11 ships with dozens of background processes you never asked for:
- **AI bloat**: Copilot, Recall, Cortana constantly running
- **Telemetry**: Microsoft harvesting your usage data 24/7
- **RGB software**: Razer, Corsair, Logitech services eating RAM
- **Updaters**: Google, Adobe, Edge update services polling constantly
- **Bloatware**: Pre-installed apps you'll never use

REAPER doesn't just blindly disable things. It **investigates** each process, **documents** its purpose, and lets you make informed decisions with full rollback capability.

## Features

| Feature | Description |
|---------|-------------|
| **Process Forensics** | Collects detailed info on all running processes, services, startup items, and scheduled tasks |
| **Intelligent Filtering** | Identifies suspects based on signatures, resource usage, and known bloatware patterns |
| **AI-Assisted Research** | Automatically documents each suspect's purpose and removal safety |
| **Manifest-Driven** | All decisions stored in YAML - version control your system config |
| **Surgical Execution** | Dry-run mode, per-change logging, auto-generated rollback scripts |
| **Update Protection** | Scheduled task re-applies settings after Windows Update reverts them |

## Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/hhalperin/reaper.git
cd reaper

# 2. Install dependencies
pip install -r requirements.txt

# 3. Investigate your system
python scripts/collect_inventory.py

# 4. Identify suspects
python scripts/analyze_suspects.py

# 5. Review findings
# Edit config/manifest.yaml to customize decisions

# 6. Preview changes (dry run)
.\scripts\execute_cleanup.ps1 -DryRun

# 7. Execute (as Administrator)
.\scripts\execute_cleanup.ps1 -Execute
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        REAPER PIPELINE                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ COLLECT  │───▶│ ANALYZE  │───▶│ MANIFEST │───▶│ EXECUTE  │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │               │               │               │         │
│       ▼               ▼               ▼               ▼         │
│  inventories/    analysis/      manifest.yaml   audit_logs/     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Phase 1: Collection

REAPER inventories four categories of system activity:

| Category | What's Collected |
|----------|------------------|
| **Processes** | PID, name, path, memory/CPU usage, parent process, digital signature |
| **Services** | Name, start type, state, executable path, account |
| **Startup Items** | Registry Run keys, startup folders, approved/disabled status |
| **Scheduled Tasks** | Task name, triggers, actions, last run time |

### Phase 2: Analysis

The suspect filter flags items based on:
- ❌ Non-Microsoft digital signatures
- ❌ High resource usage (configurable thresholds)
- ❌ Known bloatware patterns (Razer, Corsair, telemetry, etc.)
- ❌ AI-related processes (Copilot, Recall)
- ❌ Third-party services set to Auto-start

### Phase 3: Manifest

All decisions are stored in `config/manifest.yaml`:

```yaml
categories:
  ai_features:
    copilot:
      action: REMOVE
      methods:
        - type: registry
          path: "HKCU:\\Software\\Policies\\Microsoft\\Windows\\WindowsCopilot"
          name: "TurnOffWindowsCopilot"
          value: 1
        - type: appx_remove
          packages: ["Microsoft.Copilot"]
          
  rgb_software:
    razer_chroma:
      action: DISABLE
      services: ["Razer Chroma SDK Service"]
```

### Phase 4: Execution

Every change is:
1. **Logged** with before/after state
2. **Reversible** via auto-generated rollback script
3. **Protected** by system restore point

```
[2026-01-19 10:45:00] ACTION: Disable service "RzChromaSDKService"
[2026-01-19 10:45:00] BEFORE: StartType=Automatic, State=Running
[2026-01-19 10:45:01] AFTER: StartType=Disabled, State=Stopped
[2026-01-19 10:45:01] ROLLBACK: Set-Service -Name "RzChromaSDKService" -StartupType Automatic
```

## Aggressiveness Levels

| Level | What Gets Removed/Disabled |
|-------|---------------------------|
| **light** | Telemetry, ads/suggestions, RGB software set to manual |
| **moderate** | + Copilot, Recall, Cortana, Xbox services to manual, bloatware apps |
| **aggressive** | + Weather, News, Maps, Teams, Clipchamp, more services |

```powershell
# Apply specific level
.\scripts\execute_cleanup.ps1 -Execute -Level moderate
```

## Project Structure

```
reaper/
├── AGENTS.md                 # AI agent definitions
├── README.md                 # You are here
├── requirements.txt          # Python dependencies
│
├── config/
│   ├── manifest.yaml         # Master keep/remove decisions
│   ├── known_processes.yaml  # Pre-researched process database (70+ entries)
│   └── settings.yaml         # Tool configuration
│
├── src/
│   ├── collectors/           # Data collection modules
│   │   ├── process_collector.py
│   │   ├── service_collector.py
│   │   ├── startup_collector.py
│   │   └── task_collector.py
│   ├── analyzers/            # Suspect identification
│   │   ├── suspect_filter.py
│   │   └── ai_researcher.py
│   ├── executors/            # PowerShell action modules
│   └── utils/                # Logging, backup utilities
│
├── scripts/
│   ├── collect_inventory.py  # Phase 1: Gather system state
│   ├── analyze_suspects.py   # Phase 2: Identify bloat
│   ├── execute_cleanup.ps1   # Phase 3: Apply changes
│   ├── post_update_check.ps1 # Phase 4: Maintain after updates
│   └── install_protection_task.ps1
│
├── data/
│   ├── inventories/          # Raw system snapshots
│   ├── analysis/             # Research results
│   └── audit_logs/           # Execution history + rollback scripts
│
└── docs/
    └── USAGE.md              # Detailed usage guide
```

## Configuration

### settings.yaml

```yaml
# Suspect detection thresholds
suspect_filter:
  high_memory_threshold_percent: 2.0  # Flag processes using >2% RAM
  high_cpu_threshold_percent: 5.0     # Flag processes using >5% CPU
  flag_non_microsoft: true            # Flag all non-MS signed processes
  
  # Regex patterns to always flag
  bloatware_patterns:
    - "(?i)chroma"
    - "(?i)synapse"
    - "(?i)copilot"
    - "(?i)cortana"
    - "(?i)telemetry"
```

### known_processes.yaml

Pre-researched database of 70+ processes:

```yaml
csrss.exe:
  category: core
  publisher: Microsoft
  purpose: Client/Server Runtime - handles console windows
  recommendation: KEEP
  safety_rating: CRITICAL
  notes: Windows will not boot without this

RzChromaSDKService:
  category: utility
  publisher: Razer Inc.
  purpose: RGB lighting synchronization
  recommendation: DISABLE
  safety_rating: SAFE
  notes: Devices work without it, just lose RGB sync
```

## Safety Features

| Feature | Description |
|---------|-------------|
| **Critical Keep List** | 40+ processes/services that are NEVER touched |
| **Dry Run Mode** | Preview all changes before applying |
| **System Restore Point** | Auto-created before any execution |
| **Audit Logging** | Every change logged with timestamp |
| **Rollback Scripts** | Auto-generated PowerShell to undo changes |
| **Signature Verification** | Distinguishes Microsoft from third-party |

## Post-Update Protection

Windows Update loves to re-enable things you disabled. REAPER includes a protection system:

```powershell
# Install scheduled task (runs after each logon)
.\scripts\install_protection_task.ps1

# Or run manually after updates
.\scripts\post_update_check.ps1 -AutoReapply
```

## Requirements

- **OS**: Windows 10/11 (tested on Windows 11 Home 25H2)
- **Python**: 3.10+
- **PowerShell**: 5.1+ (run as Administrator for changes)
- **Permissions**: Admin rights required for service/registry modifications

## Dependencies

```
psutil>=5.9.0      # Process information
wmi>=1.5.1         # Windows Management Instrumentation  
PyYAML>=6.0        # Configuration parsing
rich>=13.0.0       # Beautiful CLI output
python-dateutil    # Date handling
```

## Use Cases

### Gaming Rig Optimization
```powershell
# Disable RGB software, game launchers from startup
.\scripts\execute_cleanup.ps1 -Execute -Level light
```

### Developer Workstation
```powershell
# Remove telemetry, Copilot, keep essential services
.\scripts\execute_cleanup.ps1 -Execute -Level moderate
```

### Maximum Performance
```powershell
# Strip everything non-essential
.\scripts\execute_cleanup.ps1 -Execute -Level aggressive
```

## Contributing

1. Fork the repo
2. Add new patterns to `config/known_processes.yaml`
3. Test on your system
4. Submit PR with before/after metrics

## Disclaimer

⚠️ **Use at your own risk.** This tool modifies system services and registry settings. While REAPER includes multiple safety features (dry-run, restore points, rollback scripts), improper use could affect system stability.

Always:
- Run dry-run first
- Review the manifest before executing
- Keep the rollback script
- Test on non-critical systems first

## License

MIT License - See LICENSE file

## Credits

Inspired by:
- [Win11Debloat](https://github.com/Raphire/Win11Debloat)
- [RemoveWindowsAI](https://github.com/zoicware/RemoveWindowsAI)
- The frustration of watching Copilot consume resources on a machine that should be fast

---

**REAPER** - *Because your processes should fear you, not the other way around.*
