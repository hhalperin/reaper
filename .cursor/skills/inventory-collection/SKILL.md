---
name: inventory-collection
description: Collect Windows system state - processes, services, startup items, scheduled tasks
---

# Inventory Collection

## When to Use

- Starting a new system analysis
- After Windows updates to check for changes
- Periodic system health audits

## Tools

| Tool | Purpose |
|------|---------|
| `psutil` | Process info, memory, CPU |
| `wmi` | Windows services |
| PowerShell | Startup items, scheduled tasks |

## Usage

```python
from src.collectors import ProcessCollector, ServiceCollector, StartupCollector, TaskCollector

# Collect processes
proc = ProcessCollector()
processes = proc.collect()
proc.save(processes)

# Collect services
svc = ServiceCollector()
services = svc.collect()
svc.save(services)
```

Or run the script:

```bash
python scripts/collect_inventory.py
python scripts/collect_inventory.py --no-signatures  # faster
```

## Output Format

```yaml
collector: processes
collected_at: "2026-01-19T10:00:00"
system_info:
  hostname: DESKTOP-XXX
  os: Windows 11
items:
  - name: "example.exe"
    pid: 1234
    memory_mb: 50.5
    cpu_percent: 0.1
    path: "C:\\Program Files\\..."
```

## Output Location

`data/inventories/{timestamp}_{type}.yaml`
