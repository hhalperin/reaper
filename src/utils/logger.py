"""Audit logger - tracks all changes made by the toolkit."""

import json
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
import yaml


class AuditLogger:
    """Logs all changes with before/after state and rollback commands."""
    
    def __init__(self, output_dir: Optional[Path] = None):
        """Initialize the audit logger.
        
        Args:
            output_dir: Directory to save audit logs.
        """
        self.output_dir = output_dir or Path("data/audit_logs")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        self.session_id = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.log_file = self.output_dir / f"{self.session_id}_execution.log"
        self.rollback_file = self.output_dir / f"{self.session_id}_rollback.ps1"
        
        self.changes: List[Dict[str, Any]] = []
        self.rollback_commands: List[str] = []
        
        # Initialize log file
        self._write_header()
        
    def _write_header(self):
        """Write log file header."""
        with open(self.log_file, 'w', encoding='utf-8') as f:
            f.write(f"# Windows Optimization Toolkit - Audit Log\n")
            f.write(f"# Session: {self.session_id}\n")
            f.write(f"# Started: {datetime.now().isoformat()}\n")
            f.write(f"# {'=' * 70}\n\n")
            
    def log_change(
        self,
        action: str,
        target: str,
        target_type: str,
        before_state: Any,
        after_state: Any,
        rollback_command: str,
        success: bool = True,
        error: Optional[str] = None,
    ):
        """Log a change with full details.
        
        Args:
            action: The action performed (e.g., "disable_service").
            target: The target of the action (e.g., service name).
            target_type: Type of target (service, startup, registry, appx).
            before_state: State before the change.
            after_state: State after the change.
            rollback_command: PowerShell command to undo this change.
            success: Whether the change succeeded.
            error: Error message if failed.
        """
        timestamp = datetime.now().isoformat()
        
        change = {
            "timestamp": timestamp,
            "action": action,
            "target": target,
            "target_type": target_type,
            "before_state": before_state,
            "after_state": after_state,
            "rollback_command": rollback_command,
            "success": success,
            "error": error,
        }
        
        self.changes.append(change)
        
        # Write to log file immediately
        with open(self.log_file, 'a', encoding='utf-8') as f:
            status = "SUCCESS" if success else "FAILED"
            f.write(f"[{timestamp}] {status}: {action} - {target}\n")
            f.write(f"  Type: {target_type}\n")
            f.write(f"  Before: {before_state}\n")
            f.write(f"  After: {after_state}\n")
            if error:
                f.write(f"  Error: {error}\n")
            f.write(f"  Rollback: {rollback_command}\n")
            f.write("\n")
            
        # Add to rollback script if successful
        if success and rollback_command:
            self.rollback_commands.append(f"# Rollback: {action} - {target}")
            self.rollback_commands.append(rollback_command)
            self.rollback_commands.append("")
            
    def log_dry_run(
        self,
        action: str,
        target: str,
        target_type: str,
        current_state: Any,
        planned_state: Any,
    ):
        """Log a planned change during dry run.
        
        Args:
            action: The action that would be performed.
            target: The target of the action.
            target_type: Type of target.
            current_state: Current state.
            planned_state: What state would become.
        """
        timestamp = datetime.now().isoformat()
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(f"[{timestamp}] DRY-RUN: {action} - {target}\n")
            f.write(f"  Type: {target_type}\n")
            f.write(f"  Current: {current_state}\n")
            f.write(f"  Planned: {planned_state}\n")
            f.write("\n")
            
    def log_message(self, message: str, level: str = "INFO"):
        """Log a general message.
        
        Args:
            message: Message to log.
            level: Log level (INFO, WARNING, ERROR).
        """
        timestamp = datetime.now().isoformat()
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(f"[{timestamp}] {level}: {message}\n")
            
    def save_rollback_script(self) -> Path:
        """Save the rollback script.
        
        Returns:
            Path to the rollback script.
        """
        with open(self.rollback_file, 'w', encoding='utf-8') as f:
            f.write("# Windows Optimization Toolkit - Rollback Script\n")
            f.write(f"# Session: {self.session_id}\n")
            f.write(f"# Generated: {datetime.now().isoformat()}\n")
            f.write("#\n")
            f.write("# WARNING: This script reverses ALL changes from the session.\n")
            f.write("# Run as Administrator.\n")
            f.write("#\n")
            f.write("# Usage: .\\{}_rollback.ps1\n".format(self.session_id))
            f.write("\n")
            f.write("# Confirm before proceeding\n")
            f.write('$confirm = Read-Host "This will rollback all changes from session {}. Continue? (y/N)"\n'.format(self.session_id))
            f.write('if ($confirm -ne "y" -and $confirm -ne "Y") {\n')
            f.write('    Write-Host "Rollback cancelled."\n')
            f.write('    exit\n')
            f.write('}\n\n')
            f.write('Write-Host "Starting rollback..."\n\n')
            
            # Write rollback commands in reverse order
            for cmd in reversed(self.rollback_commands):
                f.write(f"{cmd}\n")
                
            f.write('\nWrite-Host "Rollback complete."\n')
            
        return self.rollback_file
    
    def get_summary(self) -> Dict[str, Any]:
        """Get summary of changes made.
        
        Returns:
            Summary statistics.
        """
        successful = [c for c in self.changes if c["success"]]
        failed = [c for c in self.changes if not c["success"]]
        
        # Group by type
        by_type: Dict[str, int] = {}
        for change in successful:
            t = change["target_type"]
            by_type[t] = by_type.get(t, 0) + 1
            
        return {
            "session_id": self.session_id,
            "total_changes": len(self.changes),
            "successful": len(successful),
            "failed": len(failed),
            "by_type": by_type,
            "log_file": str(self.log_file),
            "rollback_file": str(self.rollback_file),
        }
    
    def finalize(self) -> Dict[str, Any]:
        """Finalize the session and save all files.
        
        Returns:
            Session summary.
        """
        # Save rollback script
        self.save_rollback_script()
        
        # Write session summary to log
        summary = self.get_summary()
        
        with open(self.log_file, 'a', encoding='utf-8') as f:
            f.write(f"\n# {'=' * 70}\n")
            f.write(f"# Session Complete: {datetime.now().isoformat()}\n")
            f.write(f"# Total changes: {summary['total_changes']}\n")
            f.write(f"# Successful: {summary['successful']}\n")
            f.write(f"# Failed: {summary['failed']}\n")
            f.write(f"# Rollback script: {summary['rollback_file']}\n")
            
        # Save structured log as YAML too
        yaml_log = self.output_dir / f"{self.session_id}_changes.yaml"
        with open(yaml_log, 'w', encoding='utf-8') as f:
            yaml.dump({
                "session": summary,
                "changes": self.changes,
            }, f, default_flow_style=False, allow_unicode=True)
            
        return summary


if __name__ == "__main__":
    # Quick test
    logger = AuditLogger()
    
    logger.log_message("Starting test session")
    
    logger.log_change(
        action="disable_service",
        target="TestService",
        target_type="service",
        before_state={"StartType": "Automatic", "State": "Running"},
        after_state={"StartType": "Disabled", "State": "Stopped"},
        rollback_command='Set-Service -Name "TestService" -StartupType Automatic; Start-Service "TestService"',
        success=True,
    )
    
    summary = logger.finalize()
    print(f"Session complete. Summary: {summary}")
