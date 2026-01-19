"""Service collector - gathers information about Windows services."""

import subprocess
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base_collector import BaseCollector


class ServiceCollector(BaseCollector):
    """Collects information about all Windows services."""
    
    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize service collector.
        
        Args:
            output_dir: Directory to save collected data.
        """
        super().__init__(output_dir)
        
    @property
    def collector_name(self) -> str:
        return "services"
    
    def collect(self) -> List[Dict[str, Any]]:
        """Collect information about all Windows services.
        
        Returns:
            List of service information dictionaries.
        """
        services = []
        
        # Use PowerShell to get detailed service information
        ps_script = '''
        Get-WmiObject Win32_Service | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                DisplayName = $_.DisplayName
                Description = $_.Description
                State = $_.State
                StartMode = $_.StartMode
                PathName = $_.PathName
                StartName = $_.StartName
                ProcessId = $_.ProcessId
                AcceptStop = $_.AcceptStop
                AcceptPause = $_.AcceptPause
            }
        } | ConvertTo-Json -Depth 3
        '''
        
        try:
            result = subprocess.run(
                ["powershell", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=60,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0 and result.stdout.strip():
                raw_services = json.loads(result.stdout)
                
                # Handle single service case (PowerShell returns object instead of array)
                if isinstance(raw_services, dict):
                    raw_services = [raw_services]
                    
                for svc in raw_services:
                    service_info = {
                        "name": svc.get("Name"),
                        "display_name": svc.get("DisplayName"),
                        "description": svc.get("Description"),
                        "state": svc.get("State"),
                        "start_mode": svc.get("StartMode"),
                        "path": svc.get("PathName"),
                        "account": svc.get("StartName"),
                        "pid": svc.get("ProcessId"),
                        "can_stop": svc.get("AcceptStop"),
                        "can_pause": svc.get("AcceptPause"),
                    }
                    
                    # Determine if this is a Microsoft service
                    service_info["is_microsoft"] = self._is_microsoft_service(service_info)
                    
                    services.append(service_info)
                    
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, json.JSONDecodeError) as e:
            print(f"Error collecting services: {e}")
            # Fallback to simpler method
            services = self._collect_fallback()
            
        # Sort by name
        services.sort(key=lambda x: x.get("name", "").lower())
        
        return services
    
    def _collect_fallback(self) -> List[Dict[str, Any]]:
        """Fallback method using sc query if WMI fails.
        
        Returns:
            List of service information dictionaries.
        """
        services = []
        
        try:
            result = subprocess.run(
                ["sc", "query", "state=", "all"],
                capture_output=True,
                text=True,
                timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0:
                current_service = {}
                for line in result.stdout.split('\n'):
                    line = line.strip()
                    if line.startswith("SERVICE_NAME:"):
                        if current_service:
                            services.append(current_service)
                        current_service = {"name": line.split(":", 1)[1].strip()}
                    elif line.startswith("DISPLAY_NAME:"):
                        current_service["display_name"] = line.split(":", 1)[1].strip()
                    elif line.startswith("STATE"):
                        # Parse state like "4  RUNNING"
                        parts = line.split()
                        if len(parts) >= 3:
                            current_service["state"] = parts[2]
                            
                if current_service:
                    services.append(current_service)
                    
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            pass
            
        return services
    
    def _is_microsoft_service(self, service: Dict[str, Any]) -> bool:
        """Determine if a service is from Microsoft.
        
        Args:
            service: Service information dictionary.
            
        Returns:
            True if service appears to be from Microsoft.
        """
        path = service.get("path", "") or ""
        name = service.get("name", "") or ""
        
        # Check path for Microsoft indicators
        microsoft_paths = [
            "\\windows\\",
            "\\microsoft\\",
            "\\program files\\windows",
            "\\system32\\",
            "\\syswow64\\",
        ]
        
        path_lower = path.lower()
        for mp in microsoft_paths:
            if mp in path_lower:
                return True
                
        # Check service name patterns
        microsoft_prefixes = [
            "wua", "wu", "win", "wmi", "rpc", "dcom", "net", "lsa", "sam",
            "eventlog", "plug", "power", "prof", "security", "sens", "theme",
            "audio", "bits", "crypt", "dhcp", "dns", "defender", "firewall"
        ]
        
        name_lower = name.lower()
        for prefix in microsoft_prefixes:
            if name_lower.startswith(prefix):
                return True
                
        return False
    
    def get_summary(self, services: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Get summary statistics for collected services.
        
        Args:
            services: List of service dictionaries.
            
        Returns:
            Summary statistics.
        """
        # Count by state
        state_counts: Dict[str, int] = {}
        for s in services:
            state = s.get("state", "Unknown")
            state_counts[state] = state_counts.get(state, 0) + 1
            
        # Count by start mode
        start_mode_counts: Dict[str, int] = {}
        for s in services:
            mode = s.get("start_mode", "Unknown")
            start_mode_counts[mode] = start_mode_counts.get(mode, 0) + 1
            
        # Microsoft vs third-party
        microsoft_count = sum(1 for s in services if s.get("is_microsoft"))
        third_party_count = len(services) - microsoft_count
        
        # Running automatic services (potential optimization targets)
        running_auto = [s for s in services 
                       if s.get("state") == "Running" and s.get("start_mode") == "Auto"
                       and not s.get("is_microsoft")]
        
        return {
            "total_services": len(services),
            "state_distribution": state_counts,
            "start_mode_distribution": start_mode_counts,
            "microsoft_services": microsoft_count,
            "third_party_services": third_party_count,
            "third_party_running_auto": [
                {"name": s["name"], "display_name": s.get("display_name")}
                for s in running_auto
            ],
        }


if __name__ == "__main__":
    # Quick test
    collector = ServiceCollector()
    services = collector.collect()
    print(f"Collected {len(services)} services")
    
    summary = collector.get_summary(services)
    print(f"Running: {summary['state_distribution'].get('Running', 0)}")
    print(f"Third-party auto-start services running:")
    for s in summary['third_party_running_auto'][:10]:
        print(f"  {s['name']}: {s['display_name']}")
