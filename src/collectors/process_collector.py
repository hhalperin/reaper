"""Process collector - gathers information about running processes."""

import psutil
from pathlib import Path
from typing import Any, Dict, List, Optional
import subprocess
import json

from .base_collector import BaseCollector


class ProcessCollector(BaseCollector):
    """Collects information about all running processes."""
    
    def __init__(
        self,
        output_dir: Optional[Path] = None,
        collect_cmdline: bool = True,
        collect_signatures: bool = True,
        min_memory_mb: float = 0,
    ):
        """Initialize process collector.
        
        Args:
            output_dir: Directory to save collected data.
            collect_cmdline: Whether to collect command line arguments.
            collect_signatures: Whether to attempt to get digital signatures.
            min_memory_mb: Minimum memory usage to include (filters noise).
        """
        super().__init__(output_dir)
        self.collect_cmdline = collect_cmdline
        self.collect_signatures = collect_signatures
        self.min_memory_mb = min_memory_mb
        self._signature_cache: Dict[str, Optional[str]] = {}
        
    @property
    def collector_name(self) -> str:
        return "processes"
    
    def collect(self) -> List[Dict[str, Any]]:
        """Collect information about all running processes.
        
        Returns:
            List of process information dictionaries.
        """
        processes = []
        
        for proc in psutil.process_iter():
            try:
                # Get process info with error handling for each attribute
                pinfo = self._get_process_info(proc)
                
                # Filter by minimum memory if specified
                if pinfo and pinfo.get("memory_mb", 0) >= self.min_memory_mb:
                    processes.append(pinfo)
                    
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                # Process may have terminated or we don't have access
                continue
                
        # Sort by memory usage descending
        processes.sort(key=lambda x: x.get("memory_mb", 0), reverse=True)
        
        return processes
    
    def _get_process_info(self, proc: psutil.Process) -> Optional[Dict[str, Any]]:
        """Get detailed information about a single process.
        
        Args:
            proc: psutil Process object.
            
        Returns:
            Dictionary with process information or None if inaccessible.
        """
        try:
            with proc.oneshot():
                pid = proc.pid
                name = proc.name()
                
                # Basic info
                info = {
                    "pid": pid,
                    "name": name,
                    "status": proc.status(),
                }
                
                # Executable path
                try:
                    exe_path = proc.exe()
                    info["exe_path"] = exe_path
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["exe_path"] = None
                    
                # Command line
                if self.collect_cmdline:
                    try:
                        cmdline = proc.cmdline()
                        info["cmdline"] = " ".join(cmdline) if cmdline else None
                    except (psutil.AccessDenied, psutil.NoSuchProcess):
                        info["cmdline"] = None
                        
                # Memory info
                try:
                    mem_info = proc.memory_info()
                    info["memory_mb"] = round(mem_info.rss / (1024 * 1024), 2)
                    info["memory_percent"] = round(proc.memory_percent(), 2)
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["memory_mb"] = 0
                    info["memory_percent"] = 0
                    
                # CPU info (need to call twice for accurate reading)
                try:
                    cpu_percent = proc.cpu_percent(interval=0.1)
                    info["cpu_percent"] = round(cpu_percent, 2)
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["cpu_percent"] = 0
                    
                # Parent process
                try:
                    parent = proc.parent()
                    if parent:
                        info["parent_pid"] = parent.pid
                        info["parent_name"] = parent.name()
                    else:
                        info["parent_pid"] = None
                        info["parent_name"] = None
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["parent_pid"] = None
                    info["parent_name"] = None
                    
                # Username
                try:
                    info["username"] = proc.username()
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["username"] = None
                    
                # Creation time
                try:
                    info["create_time"] = proc.create_time()
                except (psutil.AccessDenied, psutil.NoSuchProcess):
                    info["create_time"] = None
                    
                # Digital signature (if enabled and we have exe path)
                if self.collect_signatures and info.get("exe_path"):
                    info["signature"] = self._get_signature(info["exe_path"])
                else:
                    info["signature"] = None
                    
                return info
                
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            return None
    
    def _get_signature(self, exe_path: str) -> Optional[str]:
        """Get digital signature information for an executable.
        
        Args:
            exe_path: Path to executable.
            
        Returns:
            Signer name or None if not signed/accessible.
        """
        # Check cache first
        if exe_path in self._signature_cache:
            return self._signature_cache[exe_path]
            
        try:
            # Use PowerShell to get authenticode signature
            cmd = f'(Get-AuthenticodeSignature -FilePath "{exe_path}").SignerCertificate.Subject'
            result = subprocess.run(
                ["powershell", "-Command", cmd],
                capture_output=True,
                text=True,
                timeout=5,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0 and result.stdout.strip():
                # Parse the subject to get CN (Common Name)
                subject = result.stdout.strip()
                # Extract CN from subject like "CN=Microsoft Corporation, O=Microsoft Corporation..."
                for part in subject.split(","):
                    part = part.strip()
                    if part.startswith("CN="):
                        signature = part[3:]
                        self._signature_cache[exe_path] = signature
                        return signature
                        
            self._signature_cache[exe_path] = None
            return None
            
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
            self._signature_cache[exe_path] = None
            return None
    
    def get_summary(self, processes: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Get summary statistics for collected processes.
        
        Args:
            processes: List of process dictionaries.
            
        Returns:
            Summary statistics.
        """
        total_memory = sum(p.get("memory_mb", 0) for p in processes)
        total_cpu = sum(p.get("cpu_percent", 0) for p in processes)
        
        # Count by signature
        signature_counts: Dict[str, int] = {}
        for p in processes:
            sig = p.get("signature") or "Unknown/Unsigned"
            signature_counts[sig] = signature_counts.get(sig, 0) + 1
            
        # Top memory consumers
        top_memory = sorted(processes, key=lambda x: x.get("memory_mb", 0), reverse=True)[:10]
        
        # Top CPU consumers
        top_cpu = sorted(processes, key=lambda x: x.get("cpu_percent", 0), reverse=True)[:10]
        
        return {
            "total_processes": len(processes),
            "total_memory_mb": round(total_memory, 2),
            "total_cpu_percent": round(total_cpu, 2),
            "signature_distribution": signature_counts,
            "top_memory_consumers": [{"name": p["name"], "memory_mb": p.get("memory_mb", 0)} for p in top_memory],
            "top_cpu_consumers": [{"name": p["name"], "cpu_percent": p.get("cpu_percent", 0)} for p in top_cpu],
        }


if __name__ == "__main__":
    # Quick test
    collector = ProcessCollector(collect_signatures=False)  # Faster without signatures
    processes = collector.collect()
    print(f"Collected {len(processes)} processes")
    
    summary = collector.get_summary(processes)
    print(f"Total memory: {summary['total_memory_mb']} MB")
    print(f"Top memory consumers:")
    for p in summary['top_memory_consumers'][:5]:
        print(f"  {p['name']}: {p['memory_mb']} MB")
