"""Suspect filter - identifies processes and services that may be candidates for removal."""

import re
import yaml
from pathlib import Path
from typing import Any, Dict, List, Optional, Set


class SuspectFilter:
    """Filters collected data to identify suspect items for further analysis."""
    
    # Default bloatware patterns (will be extended from config)
    DEFAULT_PATTERNS = [
        r"(?i)chroma",
        r"(?i)synapse",
        r"(?i)icue",
        r"(?i)corsair",
        r"(?i)logitech.*gaming",
        r"(?i)razer",
        r"(?i)copilot",
        r"(?i)recall",
        r"(?i)cortana",
        r"(?i)gamebar",
        r"(?i)xbox(?!.*identity)",  # Xbox but not XboxIdentityProvider
        r"(?i)yourphone",
        r"(?i)teams",
        r"(?i)onedrive",
        r"(?i)edge.*update",
        r"(?i)adobe.*update",
        r"(?i)google.*update",
        r"(?i)spotify",
        r"(?i)discord",
        r"(?i)steam",
        r"(?i)epic.*games",
        r"(?i)riot",
        r"(?i)nvidia.*telemetry",
        r"(?i)geforce.*experience",
    ]
    
    def __init__(
        self,
        settings_path: Optional[Path] = None,
        known_processes_path: Optional[Path] = None,
        manifest_path: Optional[Path] = None,
    ):
        """Initialize the suspect filter.
        
        Args:
            settings_path: Path to settings.yaml for thresholds.
            known_processes_path: Path to known_processes.yaml database.
            manifest_path: Path to manifest.yaml for critical keep list.
        """
        self.settings = self._load_yaml(settings_path or Path("config/settings.yaml"))
        self.known_processes = self._load_yaml(known_processes_path or Path("config/known_processes.yaml"))
        self.manifest = self._load_yaml(manifest_path or Path("config/manifest.yaml"))
        
        # Build pattern list from defaults and config
        self.patterns = self._compile_patterns()
        
        # Build critical keep set
        self.critical_keep = self._build_critical_keep_set()
        
        # Get thresholds from settings
        filter_settings = self.settings.get("suspect_filter", {})
        self.high_memory_threshold = filter_settings.get("high_memory_threshold_percent", 2.0)
        self.high_cpu_threshold = filter_settings.get("high_cpu_threshold_percent", 5.0)
        self.flag_non_microsoft = filter_settings.get("flag_non_microsoft", True)
        
    def _load_yaml(self, path: Path) -> Dict[str, Any]:
        """Load a YAML file safely.
        
        Args:
            path: Path to YAML file.
            
        Returns:
            Parsed YAML content or empty dict.
        """
        try:
            if path.exists():
                with open(path, 'r', encoding='utf-8') as f:
                    return yaml.safe_load(f) or {}
        except (yaml.YAMLError, IOError):
            pass
        return {}
    
    def _compile_patterns(self) -> List[re.Pattern]:
        """Compile bloatware detection patterns.
        
        Returns:
            List of compiled regex patterns.
        """
        patterns = self.DEFAULT_PATTERNS.copy()
        
        # Add patterns from settings
        settings_patterns = self.settings.get("suspect_filter", {}).get("bloatware_patterns", [])
        patterns.extend(settings_patterns)
        
        # Compile all patterns
        compiled = []
        for pattern in patterns:
            try:
                compiled.append(re.compile(pattern))
            except re.error:
                pass  # Skip invalid patterns
                
        return compiled
    
    def _build_critical_keep_set(self) -> Set[str]:
        """Build set of names that should never be flagged as suspect.
        
        Returns:
            Set of process/service names to always keep.
        """
        keep_set = set()
        
        # From manifest critical_keep_list
        critical = self.manifest.get("critical_keep_list", {})
        for key in ["processes", "services"]:
            items = critical.get(key, [])
            keep_set.update(item.lower() for item in items)
            
        # From known_processes with CRITICAL safety rating
        for name, info in self.known_processes.items():
            if info.get("safety_rating") == "CRITICAL":
                keep_set.add(name.lower())
                
        return keep_set
    
    def filter_processes(self, processes: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter processes to identify suspects.
        
        Args:
            processes: List of process dictionaries from ProcessCollector.
            
        Returns:
            List of processes marked with suspect_reasons.
        """
        for proc in processes:
            reasons = self._get_suspect_reasons_process(proc)
            proc["is_suspect"] = len(reasons) > 0
            proc["suspect_reasons"] = reasons
            proc["known_info"] = self._get_known_info(proc.get("name", ""))
            
        return processes
    
    def filter_services(self, services: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter services to identify suspects.
        
        Args:
            services: List of service dictionaries from ServiceCollector.
            
        Returns:
            List of services marked with suspect_reasons.
        """
        for svc in services:
            reasons = self._get_suspect_reasons_service(svc)
            svc["is_suspect"] = len(reasons) > 0
            svc["suspect_reasons"] = reasons
            svc["known_info"] = self._get_known_info(svc.get("name", ""))
            
        return services
    
    def filter_startup_items(self, items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter startup items to identify suspects.
        
        Args:
            items: List of startup item dictionaries.
            
        Returns:
            List of items marked with suspect_reasons.
        """
        for item in items:
            reasons = self._get_suspect_reasons_startup(item)
            item["is_suspect"] = len(reasons) > 0
            item["suspect_reasons"] = reasons
            item["known_info"] = self._get_known_info(item.get("name", ""))
            
        return items
    
    def filter_tasks(self, tasks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter scheduled tasks to identify suspects.
        
        Args:
            tasks: List of task dictionaries.
            
        Returns:
            List of tasks marked with suspect_reasons.
        """
        for task in tasks:
            reasons = self._get_suspect_reasons_task(task)
            task["is_suspect"] = len(reasons) > 0
            task["suspect_reasons"] = reasons
            task["known_info"] = self._get_known_info(task.get("name", ""))
            
        return tasks
    
    def _get_suspect_reasons_process(self, proc: Dict[str, Any]) -> List[str]:
        """Determine why a process might be suspect.
        
        Args:
            proc: Process dictionary.
            
        Returns:
            List of reasons this process is suspect.
        """
        reasons = []
        name = proc.get("name", "").lower()
        
        # Check critical keep list
        if name in self.critical_keep:
            return []  # Never flag critical processes
            
        # Check bloatware patterns
        full_text = f"{proc.get('name', '')} {proc.get('exe_path', '')} {proc.get('cmdline', '')}"
        for pattern in self.patterns:
            if pattern.search(full_text):
                reasons.append(f"Matches bloatware pattern: {pattern.pattern}")
                break  # One pattern match is enough
                
        # Check high memory usage
        mem_percent = proc.get("memory_percent", 0)
        if mem_percent > self.high_memory_threshold:
            reasons.append(f"High memory usage: {mem_percent}%")
            
        # Check high CPU usage
        cpu_percent = proc.get("cpu_percent", 0)
        if cpu_percent > self.high_cpu_threshold:
            reasons.append(f"High CPU usage: {cpu_percent}%")
            
        # Check non-Microsoft signature
        if self.flag_non_microsoft:
            signature = proc.get("signature")
            if signature and "Microsoft" not in signature:
                reasons.append(f"Non-Microsoft signed: {signature}")
            elif signature is None and proc.get("exe_path"):
                # No signature found for executable
                reasons.append("Unsigned or signature not found")
                
        return reasons
    
    def _get_suspect_reasons_service(self, svc: Dict[str, Any]) -> List[str]:
        """Determine why a service might be suspect.
        
        Args:
            svc: Service dictionary.
            
        Returns:
            List of reasons this service is suspect.
        """
        reasons = []
        name = svc.get("name", "").lower()
        
        # Check critical keep list
        if name in self.critical_keep:
            return []
            
        # Check bloatware patterns
        full_text = f"{svc.get('name', '')} {svc.get('display_name', '')} {svc.get('path', '')}"
        for pattern in self.patterns:
            if pattern.search(full_text):
                reasons.append(f"Matches bloatware pattern: {pattern.pattern}")
                break
                
        # Non-Microsoft service running as Auto
        if not svc.get("is_microsoft") and svc.get("start_mode") == "Auto":
            reasons.append("Third-party service set to Auto start")
            
        # Running third-party service
        if not svc.get("is_microsoft") and svc.get("state") == "Running":
            reasons.append("Third-party service currently running")
            
        return reasons
    
    def _get_suspect_reasons_startup(self, item: Dict[str, Any]) -> List[str]:
        """Determine why a startup item might be suspect.
        
        Args:
            item: Startup item dictionary.
            
        Returns:
            List of reasons this item is suspect.
        """
        reasons = []
        name = item.get("name", "").lower()
        
        if name in self.critical_keep:
            return []
            
        # Check bloatware patterns
        full_text = f"{item.get('name', '')} {item.get('command', '')}"
        for pattern in self.patterns:
            if pattern.search(full_text):
                reasons.append(f"Matches bloatware pattern: {pattern.pattern}")
                break
                
        # All enabled startup items are worth reviewing
        if item.get("enabled", True):
            reasons.append("Enabled startup item")
            
        return reasons
    
    def _get_suspect_reasons_task(self, task: Dict[str, Any]) -> List[str]:
        """Determine why a scheduled task might be suspect.
        
        Args:
            task: Task dictionary.
            
        Returns:
            List of reasons this task is suspect.
        """
        reasons = []
        name = task.get("name", "").lower()
        
        if name in self.critical_keep:
            return []
            
        # Check bloatware patterns
        full_text = f"{task.get('name', '')} {task.get('path', '')} {task.get('actions', '')}"
        for pattern in self.patterns:
            if pattern.search(full_text):
                reasons.append(f"Matches bloatware pattern: {pattern.pattern}")
                break
                
        # Non-Microsoft task that runs at logon
        if not task.get("is_microsoft") and task.get("runs_at_logon"):
            reasons.append("Third-party task runs at logon/boot")
            
        # Enabled non-Microsoft task
        if not task.get("is_microsoft") and task.get("state") == "Ready":
            reasons.append("Third-party task is enabled")
            
        return reasons
    
    def _get_known_info(self, name: str) -> Optional[Dict[str, Any]]:
        """Look up known information about a process/service.
        
        Args:
            name: Name to look up.
            
        Returns:
            Known information dictionary or None.
        """
        # Try exact match first
        if name in self.known_processes:
            return self.known_processes[name]
            
        # Try case-insensitive match
        name_lower = name.lower()
        for known_name, info in self.known_processes.items():
            if known_name.lower() == name_lower:
                return info
                
        return None
    
    def get_suspects_only(self, items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter to only return suspect items.
        
        Args:
            items: List of filtered items.
            
        Returns:
            Only items where is_suspect is True.
        """
        return [item for item in items if item.get("is_suspect")]
    
    def get_summary(self, 
                   processes: List[Dict[str, Any]],
                   services: List[Dict[str, Any]],
                   startup_items: List[Dict[str, Any]],
                   tasks: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Get summary of suspect analysis.
        
        Args:
            processes: Filtered process list.
            services: Filtered service list.
            startup_items: Filtered startup items.
            tasks: Filtered task list.
            
        Returns:
            Summary statistics.
        """
        suspect_processes = self.get_suspects_only(processes)
        suspect_services = self.get_suspects_only(services)
        suspect_startup = self.get_suspects_only(startup_items)
        suspect_tasks = self.get_suspects_only(tasks)
        
        return {
            "processes": {
                "total": len(processes),
                "suspect": len(suspect_processes),
                "items": [{"name": p["name"], "reasons": p["suspect_reasons"]} for p in suspect_processes],
            },
            "services": {
                "total": len(services),
                "suspect": len(suspect_services),
                "items": [{"name": s["name"], "reasons": s["suspect_reasons"]} for s in suspect_services],
            },
            "startup_items": {
                "total": len(startup_items),
                "suspect": len(suspect_startup),
                "items": [{"name": i["name"], "reasons": i["suspect_reasons"]} for i in suspect_startup],
            },
            "tasks": {
                "total": len(tasks),
                "suspect": len(suspect_tasks),
                "items": [{"name": t["name"], "reasons": t["suspect_reasons"]} for t in suspect_tasks],
            },
            "total_suspects": len(suspect_processes) + len(suspect_services) + len(suspect_startup) + len(suspect_tasks),
        }


if __name__ == "__main__":
    # Quick test
    filter = SuspectFilter()
    
    # Test process filtering
    test_processes = [
        {"name": "RazerChroma.exe", "memory_percent": 1.5, "cpu_percent": 0.5, "signature": "Razer Inc."},
        {"name": "explorer.exe", "memory_percent": 2.0, "cpu_percent": 1.0, "signature": "Microsoft Corporation"},
        {"name": "chrome.exe", "memory_percent": 5.0, "cpu_percent": 2.0, "signature": "Google LLC"},
    ]
    
    filtered = filter.filter_processes(test_processes)
    for p in filtered:
        print(f"{p['name']}: suspect={p['is_suspect']}, reasons={p['suspect_reasons']}")
