# Skill: Inventory Collection

## Purpose
Gather comprehensive system state for analysis.

## Capabilities
- Collect running processes with resource usage
- Enumerate Windows services and states
- Find startup items (registry, folders)
- List scheduled tasks

## Tools
- `psutil` - Process info
- `wmi` - Windows Management
- PowerShell cmdlets

## Usage
```python
from src.collectors import ProcessCollector, ServiceCollector

proc = ProcessCollector()
processes = proc.collect()
proc.save(processes)
```

## Output Format
```yaml
collector: processes
collected_at: "2026-01-19T10:00:00"
items:
  - name: "example.exe"
    pid: 1234
    memory_mb: 50.5
```
