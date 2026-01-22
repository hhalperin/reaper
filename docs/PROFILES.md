# Profiles

Profiles let you apply targeted overrides without editing scripts. They live in `config/profiles.json`.

## Fields

- `disable_services`: services to disable in addition to the selected level
- `keep_services`: services to keep even if the level would disable them
- `disable_tasks`: scheduled tasks to disable (full task path)
- `disable_startup_items`: startup item names to disable
- `registry`: registry overrides with `path`, `name`, `type`, `value`

## Example

```json
{
  "profiles": {
    "gaming_steam": {
      "description": "Prioritize gaming performance while keeping Steam functional.",
      "disable_services": ["edgeupdate", "edgeupdatem"],
      "keep_services": ["Steam Client Service"],
      "disable_startup_items": ["iCloud"],
      "registry": [
        {
          "path": "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\AdvertisingInfo",
          "name": "Enabled",
          "type": "DWord",
          "value": 0
        }
      ]
    }
  }
}
```

## Usage

```powershell
.\scripts\execute_cleanup.ps1 -Execute -Profile gaming_steam
```
