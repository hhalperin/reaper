"""AI Researcher - generates documentation for suspect processes."""

import yaml
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


class AIResearcher:
    """Researches suspect processes and generates documentation."""
    
    def __init__(
        self,
        output_dir: Optional[Path] = None,
        known_processes_path: Optional[Path] = None,
    ):
        """Initialize the AI researcher.
        
        Args:
            output_dir: Directory to save research results.
            known_processes_path: Path to known_processes.yaml database.
        """
        self.output_dir = output_dir or Path("data/analysis")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.known_processes = self._load_known_processes(
            known_processes_path or Path("config/known_processes.yaml")
        )
        
    def _load_known_processes(self, path: Path) -> Dict[str, Any]:
        """Load known processes database."""
        try:
            if path.exists():
                with open(path, 'r', encoding='utf-8') as f:
                    return yaml.safe_load(f) or {}
        except (yaml.YAMLError, IOError):
            pass
        return {}
    
    def research_item(self, item: Dict[str, Any], item_type: str) -> Dict[str, Any]:
        """Research a single suspect item.
        
        Args:
            item: The item to research.
            item_type: Type of item (process, service, startup, task).
            
        Returns:
            Research results dictionary.
        """
        name = item.get("name", "Unknown")
        
        # Check if we have known information
        known_info = item.get("known_info") or self._lookup_known(name)
        
        research = {
            "name": name,
            "type": item_type,
            "researched_at": datetime.now().isoformat(),
            "suspect_reasons": item.get("suspect_reasons", []),
        }
        
        if known_info:
            # Use known information
            research.update({
                "source": "known_processes_database",
                "category": known_info.get("category"),
                "publisher": known_info.get("publisher"),
                "purpose": known_info.get("purpose"),
                "recommendation": known_info.get("recommendation"),
                "safety_rating": known_info.get("safety_rating"),
                "notes": known_info.get("notes"),
                "requires_further_research": False,
            })
        else:
            # Mark for further research
            research.update({
                "source": "needs_research",
                "category": self._guess_category(item),
                "publisher": self._extract_publisher(item),
                "purpose": "Unknown - requires research",
                "recommendation": "REVIEW",
                "safety_rating": "UNKNOWN",
                "notes": self._generate_research_notes(item, item_type),
                "requires_further_research": True,
            })
            
        # Add item-specific details
        research["item_details"] = self._extract_item_details(item, item_type)
        
        return research
    
    def _lookup_known(self, name: str) -> Optional[Dict[str, Any]]:
        """Look up known information about an item.
        
        Args:
            name: Name to look up.
            
        Returns:
            Known information or None.
        """
        # Try exact match
        if name in self.known_processes:
            return self.known_processes[name]
            
        # Try case-insensitive
        name_lower = name.lower()
        for known_name, info in self.known_processes.items():
            if known_name.lower() == name_lower:
                return info
                
        # Try partial match (e.g., "RazerChroma.exe" matches "Razer")
        for known_name, info in self.known_processes.items():
            if known_name.lower() in name_lower or name_lower in known_name.lower():
                return info
                
        return None
    
    def _guess_category(self, item: Dict[str, Any]) -> str:
        """Attempt to guess category from item information.
        
        Args:
            item: Item dictionary.
            
        Returns:
            Guessed category.
        """
        name = item.get("name", "").lower()
        path = str(item.get("exe_path", item.get("path", item.get("command", "")))).lower()
        
        # Category hints
        if any(x in name or x in path for x in ["update", "updater"]):
            return "updater"
        if any(x in name or x in path for x in ["rgb", "chroma", "lighting", "icue"]):
            return "rgb_software"
        if any(x in name or x in path for x in ["copilot", "recall", "cortana", "ai"]):
            return "ai_feature"
        if any(x in name or x in path for x in ["telemetry", "diag", "feedback"]):
            return "telemetry"
        if any(x in name or x in path for x in ["game", "steam", "epic", "xbox"]):
            return "gaming"
        if any(x in name or x in path for x in ["driver", "drv"]):
            return "driver"
        if any(x in name or x in path for x in ["security", "antivirus", "defender"]):
            return "security"
            
        return "unknown"
    
    def _extract_publisher(self, item: Dict[str, Any]) -> Optional[str]:
        """Extract publisher information from item.
        
        Args:
            item: Item dictionary.
            
        Returns:
            Publisher name or None.
        """
        # From signature
        if item.get("signature"):
            return item["signature"]
            
        # From author (scheduled tasks)
        if item.get("author"):
            return item["author"]
            
        # Guess from path
        path = str(item.get("exe_path", item.get("path", ""))).lower()
        
        publishers = {
            "microsoft": "Microsoft",
            "google": "Google",
            "adobe": "Adobe",
            "nvidia": "NVIDIA",
            "amd": "AMD",
            "intel": "Intel",
            "razer": "Razer Inc.",
            "corsair": "Corsair",
            "logitech": "Logitech",
            "steam": "Valve",
            "discord": "Discord Inc.",
        }
        
        for key, publisher in publishers.items():
            if key in path:
                return publisher
                
        return None
    
    def _generate_research_notes(self, item: Dict[str, Any], item_type: str) -> str:
        """Generate research notes for an unknown item.
        
        Args:
            item: Item dictionary.
            item_type: Type of item.
            
        Returns:
            Research notes string.
        """
        notes = []
        
        name = item.get("name", "Unknown")
        notes.append(f"Item '{name}' requires manual research.")
        
        # Add search suggestions
        notes.append(f"\nSuggested searches:")
        notes.append(f"  - \"{name} what is\"")
        notes.append(f"  - \"{name} safe to disable\"")
        notes.append(f"  - \"{name} Windows 11\"")
        
        # Add path hint
        path = item.get("exe_path") or item.get("path") or item.get("command")
        if path:
            notes.append(f"\nFile location: {path}")
            
        # Add suspect reasons
        reasons = item.get("suspect_reasons", [])
        if reasons:
            notes.append(f"\nFlagged because:")
            for reason in reasons:
                notes.append(f"  - {reason}")
                
        return "\n".join(notes)
    
    def _extract_item_details(self, item: Dict[str, Any], item_type: str) -> Dict[str, Any]:
        """Extract relevant details based on item type.
        
        Args:
            item: Item dictionary.
            item_type: Type of item.
            
        Returns:
            Extracted details.
        """
        details = {"type": item_type}
        
        if item_type == "process":
            details.update({
                "pid": item.get("pid"),
                "exe_path": item.get("exe_path"),
                "memory_mb": item.get("memory_mb"),
                "cpu_percent": item.get("cpu_percent"),
                "parent": item.get("parent_name"),
            })
        elif item_type == "service":
            details.update({
                "display_name": item.get("display_name"),
                "state": item.get("state"),
                "start_mode": item.get("start_mode"),
                "path": item.get("path"),
                "account": item.get("account"),
            })
        elif item_type == "startup":
            details.update({
                "command": item.get("command"),
                "source": item.get("source"),
                "location": item.get("location"),
                "enabled": item.get("enabled"),
            })
        elif item_type == "task":
            details.update({
                "path": item.get("path"),
                "state": item.get("state"),
                "triggers": item.get("triggers"),
                "actions": item.get("actions"),
                "runs_at_logon": item.get("runs_at_logon"),
            })
            
        return details
    
    def research_all_suspects(
        self,
        processes: List[Dict[str, Any]],
        services: List[Dict[str, Any]],
        startup_items: List[Dict[str, Any]],
        tasks: List[Dict[str, Any]],
    ) -> Dict[str, List[Dict[str, Any]]]:
        """Research all suspect items from filtered lists.
        
        Args:
            processes: Filtered process list.
            services: Filtered service list.
            startup_items: Filtered startup items.
            tasks: Filtered task list.
            
        Returns:
            Dictionary of researched items by type.
        """
        results = {
            "processes": [],
            "services": [],
            "startup_items": [],
            "tasks": [],
        }
        
        # Research suspect processes
        for proc in processes:
            if proc.get("is_suspect"):
                research = self.research_item(proc, "process")
                results["processes"].append(research)
                
        # Research suspect services
        for svc in services:
            if svc.get("is_suspect"):
                research = self.research_item(svc, "service")
                results["services"].append(research)
                
        # Research suspect startup items
        for item in startup_items:
            if item.get("is_suspect"):
                research = self.research_item(item, "startup")
                results["startup_items"].append(research)
                
        # Research suspect tasks
        for task in tasks:
            if task.get("is_suspect"):
                research = self.research_item(task, "task")
                results["tasks"].append(research)
                
        return results
    
    def save_research(self, research: Dict[str, Any], filename: Optional[str] = None) -> Path:
        """Save research results to file.
        
        Args:
            research: Research results dictionary.
            filename: Optional filename.
            
        Returns:
            Path to saved file.
        """
        if filename is None:
            timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
            filename = f"research_{timestamp}.yaml"
            
        filepath = self.output_dir / filename
        
        with open(filepath, 'w', encoding='utf-8') as f:
            yaml.dump(research, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
            
        return filepath
    
    def save_individual_reports(self, results: Dict[str, List[Dict[str, Any]]]) -> List[Path]:
        """Save individual research reports for each item.
        
        Args:
            results: Research results from research_all_suspects.
            
        Returns:
            List of saved file paths.
        """
        saved_paths = []
        
        for item_type, items in results.items():
            for item in items:
                # Create safe filename
                name = item.get("name", "unknown")
                safe_name = "".join(c if c.isalnum() or c in "._-" else "_" for c in name)
                filename = f"{item_type}_{safe_name}.yaml"
                
                filepath = self.output_dir / filename
                
                with open(filepath, 'w', encoding='utf-8') as f:
                    yaml.dump(item, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
                    
                saved_paths.append(filepath)
                
        return saved_paths
    
    def generate_recommendations(self, results: Dict[str, List[Dict[str, Any]]]) -> Dict[str, List[Dict[str, Any]]]:
        """Generate action recommendations from research results.
        
        Args:
            results: Research results.
            
        Returns:
            Recommendations grouped by action type.
        """
        recommendations = {
            "REMOVE": [],
            "DISABLE": [],
            "KEEP": [],
            "REVIEW": [],
        }
        
        for item_type, items in results.items():
            for item in items:
                rec = item.get("recommendation", "REVIEW")
                recommendations[rec].append({
                    "name": item["name"],
                    "type": item_type,
                    "category": item.get("category"),
                    "purpose": item.get("purpose"),
                    "safety_rating": item.get("safety_rating"),
                })
                
        return recommendations


if __name__ == "__main__":
    # Quick test
    researcher = AIResearcher()
    
    test_item = {
        "name": "RazerChromaService",
        "is_suspect": True,
        "suspect_reasons": ["Matches bloatware pattern"],
        "signature": "Razer Inc.",
    }
    
    research = researcher.research_item(test_item, "service")
    print(yaml.dump(research, default_flow_style=False))
