# Skill: Suspect Filtering

## Purpose
Identify processes/services that are candidates for removal.

## Criteria
- Non-Microsoft digital signature
- High resource usage (>2% RAM, >5% CPU)
- Matches bloatware patterns (regex)
- Third-party auto-start services

## Usage
```python
from src.analyzers import SuspectFilter

filter = SuspectFilter()
filtered = filter.filter_processes(processes)
suspects = filter.get_suspects_only(filtered)
```

## Patterns
Defined in `config/settings.yaml`:
```yaml
bloatware_patterns:
  - "(?i)chroma"
  - "(?i)copilot"
```
