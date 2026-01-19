---
name: suspect-filtering
description: Identify bloatware, telemetry, and unnecessary processes from inventory data
---

# Suspect Filtering

## When to Use

- After collecting inventory
- When adding new bloatware patterns
- Reviewing system for optimization targets

## Criteria

| Criterion | Description |
|-----------|-------------|
| Non-Microsoft signature | Third-party processes |
| High resource usage | >2% RAM or >5% CPU |
| Bloatware patterns | Regex matches (Chroma, Copilot, etc.) |
| Auto-start services | Third-party services set to Auto |

## Usage

```python
from src.analyzers import SuspectFilter

filter = SuspectFilter()

# Filter processes
filtered = filter.filter_processes(processes)
suspects = filter.get_suspects_only(filtered)

# Filter services
filtered_svc = filter.filter_services(services)
```

Or run the script:

```bash
python scripts/analyze_suspects.py
```

## Patterns

Defined in `config/settings.yaml`:

```yaml
bloatware_patterns:
  - "(?i)chroma"
  - "(?i)synapse"
  - "(?i)copilot"
  - "(?i)cortana"
  - "(?i)telemetry"
  - "(?i)edge.*update"
  - "(?i)google.*update"
```

## Critical Keep List

Never flag these (in `config/manifest.yaml`):

- csrss.exe, lsass.exe, services.exe, svchost.exe
- Windows Defender, Windows Update
- explorer.exe, winlogon.exe

## Output

`data/analysis/analysis_{timestamp}.yaml`
