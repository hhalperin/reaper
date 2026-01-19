"""Startup collector - gathers information about startup items."""

import subprocess
import json
import os
from pathlib import Path
from typing import Any, Dict, List, Optional
import winreg

from .base_collector import BaseCollector


class StartupCollector(BaseCollector):
    """Collects information about all startup items from various locations."""
    
    # Registry locations for startup items
    REGISTRY_LOCATIONS = [
        # Current user
        (winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run"),
        (winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\RunOnce"),
        (winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"),
        # Local machine (all users)
        (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\Run"),
        (winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\RunOnce"),
        (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"),
        # 32-bit on 64-bit
        (winreg.HKEY_LOCAL_MACHINE, r"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"),
    ]
    
    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize startup collector.
        
        Args:
            output_dir: Directory to save collected data.
        """
        super().__init__(output_dir)
        
    @property
    def collector_name(self) -> str:
        return "startup"
    
    def collect(self) -> List[Dict[str, Any]]:
        """Collect startup items from all sources.
        
        Returns:
            List of startup item dictionaries.
        """
        startup_items = []
        
        # Collect from registry
        startup_items.extend(self._collect_from_registry())
        
        # Collect from startup folders
        startup_items.extend(self._collect_from_folders())
        
        # Collect from Task Manager startup (different API)
        startup_items.extend(self._collect_from_task_manager())
        
        # Remove duplicates based on name
        seen = set()
        unique_items = []
        for item in startup_items:
            key = (item.get("name", "").lower(), item.get("source", ""))
            if key not in seen:
                seen.add(key)
                unique_items.append(item)
                
        return unique_items
    
    def _collect_from_registry(self) -> List[Dict[str, Any]]:
        """Collect startup items from registry.
        
        Returns:
            List of startup items from registry.
        """
        items = []
        
        for hive, path in self.REGISTRY_LOCATIONS:
            try:
                hive_name = "HKCU" if hive == winreg.HKEY_CURRENT_USER else "HKLM"
                
                with winreg.OpenKey(hive, path, 0, winreg.KEY_READ) as key:
                    i = 0
                    while True:
                        try:
                            name, value, _ = winreg.EnumValue(key, i)
                            
                            # Skip StartupApproved entries (they're status flags, not actual items)
                            if "StartupApproved" in path:
                                i += 1
                                continue
                                
                            item = {
                                "name": name,
                                "command": value if isinstance(value, str) else None,
                                "source": "registry",
                                "location": f"{hive_name}\\{path}",
                                "enabled": True,  # Will be updated based on StartupApproved
                            }
                            
                            # Check if disabled in StartupApproved
                            item["enabled"] = self._check_startup_approved(hive, name)
                            
                            items.append(item)
                            i += 1
                            
                        except OSError:
                            # No more values
                            break
                            
            except FileNotFoundError:
                # Registry key doesn't exist
                continue
            except PermissionError:
                # No access to key
                continue
                
        return items
    
    def _check_startup_approved(self, hive: int, name: str) -> bool:
        """Check if a startup item is enabled in StartupApproved.
        
        Args:
            hive: Registry hive.
            name: Name of the startup item.
            
        Returns:
            True if enabled, False if disabled.
        """
        approved_path = r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
        
        try:
            with winreg.OpenKey(hive, approved_path, 0, winreg.KEY_READ) as key:
                value, _ = winreg.QueryValueEx(key, name)
                # If first byte is 02 or 06, it's disabled
                if isinstance(value, bytes) and len(value) > 0:
                    return value[0] not in (0x02, 0x03, 0x06)
        except (FileNotFoundError, PermissionError, OSError):
            pass
            
        return True  # Default to enabled if we can't check
    
    def _collect_from_folders(self) -> List[Dict[str, Any]]:
        """Collect startup items from startup folders.
        
        Returns:
            List of startup items from folders.
        """
        items = []
        
        # User startup folder
        user_startup = Path(os.environ.get("APPDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
        
        # Common startup folder
        common_startup = Path(os.environ.get("PROGRAMDATA", "")) / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Startup"
        
        for folder, scope in [(user_startup, "user"), (common_startup, "all_users")]:
            if folder.exists():
                for item_path in folder.iterdir():
                    if item_path.is_file():
                        items.append({
                            "name": item_path.stem,
                            "command": str(item_path),
                            "source": "startup_folder",
                            "location": str(folder),
                            "scope": scope,
                            "enabled": True,
                            "file_type": item_path.suffix.lower(),
                        })
                        
        return items
    
    def _collect_from_task_manager(self) -> List[Dict[str, Any]]:
        """Collect startup items as shown in Task Manager.
        
        Returns:
            List of startup items from Task Manager.
        """
        items = []
        
        # Use PowerShell to get startup items via CIM
        ps_script = '''
        Get-CimInstance Win32_StartupCommand | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Command = $_.Command
                Location = $_.Location
                User = $_.User
            }
        } | ConvertTo-Json -Depth 3
        '''
        
        try:
            result = subprocess.run(
                ["powershell", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0 and result.stdout.strip():
                raw_items = json.loads(result.stdout)
                
                if isinstance(raw_items, dict):
                    raw_items = [raw_items]
                    
                for item in raw_items:
                    items.append({
                        "name": item.get("Name"),
                        "command": item.get("Command"),
                        "source": "wmi_startup",
                        "location": item.get("Location"),
                        "user": item.get("User"),
                        "enabled": True,
                    })
                    
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, json.JSONDecodeError):
            pass
            
        return items
    
    def get_summary(self, startup_items: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Get summary statistics for collected startup items.
        
        Args:
            startup_items: List of startup item dictionaries.
            
        Returns:
            Summary statistics.
        """
        # Count by source
        source_counts: Dict[str, int] = {}
        for item in startup_items:
            source = item.get("source", "Unknown")
            source_counts[source] = source_counts.get(source, 0) + 1
            
        # Count enabled vs disabled
        enabled_count = sum(1 for item in startup_items if item.get("enabled", True))
        disabled_count = len(startup_items) - enabled_count
        
        return {
            "total_items": len(startup_items),
            "enabled": enabled_count,
            "disabled": disabled_count,
            "by_source": source_counts,
            "items": [
                {"name": item["name"], "enabled": item.get("enabled", True), "source": item.get("source")}
                for item in startup_items
            ],
        }


if __name__ == "__main__":
    # Quick test
    collector = StartupCollector()
    items = collector.collect()
    print(f"Collected {len(items)} startup items")
    
    summary = collector.get_summary(items)
    print(f"Enabled: {summary['enabled']}, Disabled: {summary['disabled']}")
    print(f"By source: {summary['by_source']}")
