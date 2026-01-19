"""Task collector - gathers information about scheduled tasks."""

import subprocess
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from .base_collector import BaseCollector


class TaskCollector(BaseCollector):
    """Collects information about Windows scheduled tasks."""
    
    def __init__(self, output_dir: Optional[Path] = None, include_microsoft: bool = True):
        """Initialize task collector.
        
        Args:
            output_dir: Directory to save collected data.
            include_microsoft: Whether to include Microsoft tasks (can be many).
        """
        super().__init__(output_dir)
        self.include_microsoft = include_microsoft
        
    @property
    def collector_name(self) -> str:
        return "scheduled_tasks"
    
    def collect(self) -> List[Dict[str, Any]]:
        """Collect information about all scheduled tasks.
        
        Returns:
            List of scheduled task dictionaries.
        """
        tasks = []
        
        # Use PowerShell to get scheduled tasks
        ps_script = '''
        Get-ScheduledTask | ForEach-Object {
            $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
            [PSCustomObject]@{
                TaskName = $_.TaskName
                TaskPath = $_.TaskPath
                State = $_.State.ToString()
                Description = $_.Description
                Author = $_.Author
                Principal = $_.Principal.UserId
                RunLevel = $_.Principal.RunLevel.ToString()
                LastRunTime = if ($info) { $info.LastRunTime.ToString("o") } else { $null }
                NextRunTime = if ($info) { $info.NextRunTime.ToString("o") } else { $null }
                LastTaskResult = if ($info) { $info.LastTaskResult } else { $null }
                Triggers = ($_.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join ", "
                Actions = ($_.Actions | ForEach-Object { 
                    if ($_.Execute) { $_.Execute + " " + $_.Arguments }
                    else { $_.CimClass.CimClassName }
                }) -join "; "
            }
        } | ConvertTo-Json -Depth 3
        '''
        
        try:
            result = subprocess.run(
                ["powershell", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=120,  # Can take a while with many tasks
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0 and result.stdout.strip():
                raw_tasks = json.loads(result.stdout)
                
                if isinstance(raw_tasks, dict):
                    raw_tasks = [raw_tasks]
                    
                for task in raw_tasks:
                    task_path = task.get("TaskPath", "")
                    
                    # Skip Microsoft tasks if not included
                    if not self.include_microsoft and task_path.startswith("\\Microsoft\\"):
                        continue
                        
                    task_info = {
                        "name": task.get("TaskName"),
                        "path": task_path,
                        "full_path": task_path + task.get("TaskName", ""),
                        "state": task.get("State"),
                        "description": task.get("Description"),
                        "author": task.get("Author"),
                        "run_as": task.get("Principal"),
                        "run_level": task.get("RunLevel"),
                        "last_run": task.get("LastRunTime"),
                        "next_run": task.get("NextRunTime"),
                        "last_result": task.get("LastTaskResult"),
                        "triggers": task.get("Triggers"),
                        "actions": task.get("Actions"),
                        "is_microsoft": task_path.startswith("\\Microsoft\\"),
                    }
                    
                    # Determine if this is a logon task
                    triggers = task.get("Triggers", "")
                    task_info["runs_at_logon"] = "LogonTrigger" in triggers or "BootTrigger" in triggers
                    
                    tasks.append(task_info)
                    
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, json.JSONDecodeError) as e:
            print(f"Error collecting scheduled tasks: {e}")
            
        # Sort by path and name
        tasks.sort(key=lambda x: (x.get("path", ""), x.get("name", "")))
        
        return tasks
    
    def get_logon_tasks(self, tasks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter to only tasks that run at logon/boot.
        
        Args:
            tasks: List of task dictionaries.
            
        Returns:
            Filtered list of logon tasks.
        """
        return [t for t in tasks if t.get("runs_at_logon")]
    
    def get_third_party_tasks(self, tasks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Filter to only non-Microsoft tasks.
        
        Args:
            tasks: List of task dictionaries.
            
        Returns:
            Filtered list of third-party tasks.
        """
        return [t for t in tasks if not t.get("is_microsoft")]
    
    def get_summary(self, tasks: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Get summary statistics for collected tasks.
        
        Args:
            tasks: List of task dictionaries.
            
        Returns:
            Summary statistics.
        """
        # Count by state
        state_counts: Dict[str, int] = {}
        for task in tasks:
            state = task.get("state", "Unknown")
            state_counts[state] = state_counts.get(state, 0) + 1
            
        # Microsoft vs third-party
        microsoft_count = sum(1 for t in tasks if t.get("is_microsoft"))
        third_party_count = len(tasks) - microsoft_count
        
        # Logon tasks
        logon_tasks = self.get_logon_tasks(tasks)
        third_party_logon = [t for t in logon_tasks if not t.get("is_microsoft")]
        
        return {
            "total_tasks": len(tasks),
            "state_distribution": state_counts,
            "microsoft_tasks": microsoft_count,
            "third_party_tasks": third_party_count,
            "logon_boot_tasks": len(logon_tasks),
            "third_party_logon_tasks": [
                {"name": t["name"], "path": t["path"], "state": t.get("state")}
                for t in third_party_logon
            ],
        }


if __name__ == "__main__":
    # Quick test
    collector = TaskCollector(include_microsoft=False)  # Faster, skip Microsoft tasks
    tasks = collector.collect()
    print(f"Collected {len(tasks)} tasks (excluding Microsoft)")
    
    summary = collector.get_summary(tasks)
    print(f"Third-party logon tasks:")
    for t in summary['third_party_logon_tasks'][:10]:
        print(f"  {t['name']}: {t['state']}")
