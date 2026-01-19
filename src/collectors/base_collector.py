"""Base collector class with common functionality."""

from abc import ABC, abstractmethod
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
import yaml
import json


class BaseCollector(ABC):
    """Abstract base class for all collectors."""
    
    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize the collector.
        
        Args:
            output_dir: Directory to save collected data. Defaults to data/inventories.
        """
        self.output_dir = output_dir or Path("data/inventories")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self.collected_at = datetime.now()
        
    @property
    @abstractmethod
    def collector_name(self) -> str:
        """Name of this collector for logging."""
        pass
    
    @abstractmethod
    def collect(self) -> List[Dict[str, Any]]:
        """Collect data and return as list of dictionaries.
        
        Returns:
            List of collected items as dictionaries.
        """
        pass
    
    def save(self, data: List[Dict[str, Any]], filename: Optional[str] = None) -> Path:
        """Save collected data to YAML file.
        
        Args:
            data: Data to save.
            filename: Optional filename. Defaults to collector_name_timestamp.yaml.
            
        Returns:
            Path to saved file.
        """
        if filename is None:
            timestamp = self.collected_at.strftime("%Y-%m-%d_%H-%M-%S")
            filename = f"{self.collector_name}_{timestamp}.yaml"
            
        filepath = self.output_dir / filename
        
        output = {
            "collector": self.collector_name,
            "collected_at": self.collected_at.isoformat(),
            "count": len(data),
            "items": data
        }
        
        with open(filepath, 'w', encoding='utf-8') as f:
            yaml.dump(output, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
            
        return filepath
    
    def collect_and_save(self, filename: Optional[str] = None) -> tuple[List[Dict[str, Any]], Path]:
        """Convenience method to collect and save in one call.
        
        Returns:
            Tuple of (collected data, file path).
        """
        data = self.collect()
        filepath = self.save(data, filename)
        return data, filepath


def get_system_info() -> Dict[str, Any]:
    """Get basic system information."""
    import platform
    import os
    
    return {
        "os_name": platform.system(),
        "os_version": platform.version(),
        "os_release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "hostname": platform.node(),
        "username": os.getlogin(),
    }
