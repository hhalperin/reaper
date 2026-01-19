"""Backup manager - creates system restore points and backs up registry."""

import subprocess
from datetime import datetime
from pathlib import Path
from typing import Optional


class BackupManager:
    """Manages system backups before making changes."""
    
    def __init__(self, backup_dir: Optional[Path] = None):
        """Initialize the backup manager.
        
        Args:
            backup_dir: Directory to save backup files.
        """
        self.backup_dir = backup_dir or Path("data/backups")
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        
    def create_restore_point(self, description: str = "Windows Optimization Toolkit") -> bool:
        """Create a Windows System Restore point.
        
        Args:
            description: Description for the restore point.
            
        Returns:
            True if successful, False otherwise.
        """
        # PowerShell command to create restore point
        # Note: Requires administrator privileges
        ps_script = f'''
        $description = "{description} - {datetime.now().strftime('%Y-%m-%d %H:%M')}"
        try {{
            # Enable System Restore if not enabled
            Enable-ComputerRestore -Drive "C:\\" -ErrorAction SilentlyContinue
            
            # Create restore point
            Checkpoint-Computer -Description $description -RestorePointType "MODIFY_SETTINGS"
            Write-Output "SUCCESS"
        }} catch {{
            Write-Output "FAILED: $($_.Exception.Message)"
        }}
        '''
        
        try:
            result = subprocess.run(
                ["powershell", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=120,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            return "SUCCESS" in result.stdout
            
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            return False
            
    def backup_registry_key(self, key_path: str, filename: Optional[str] = None) -> Optional[Path]:
        """Backup a registry key to a .reg file.
        
        Args:
            key_path: Full registry path (e.g., "HKCU\\Software\\...").
            filename: Optional filename for backup.
            
        Returns:
            Path to backup file, or None if failed.
        """
        if filename is None:
            # Create filename from key path
            safe_name = key_path.replace("\\", "_").replace("/", "_")
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"reg_backup_{safe_name}_{timestamp}.reg"
            
        filepath = self.backup_dir / filename
        
        try:
            result = subprocess.run(
                ["reg", "export", key_path, str(filepath), "/y"],
                capture_output=True,
                text=True,
                timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0 and filepath.exists():
                return filepath
                
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            pass
            
        return None
    
    def backup_service_config(self, service_name: str) -> Optional[Path]:
        """Backup service configuration.
        
        Args:
            service_name: Name of the service.
            
        Returns:
            Path to backup file, or None if failed.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"service_{service_name}_{timestamp}.txt"
        filepath = self.backup_dir / filename
        
        ps_script = f'''
        Get-Service -Name "{service_name}" | Format-List * | Out-String
        '''
        
        try:
            result = subprocess.run(
                ["powershell", "-Command", ps_script],
                capture_output=True,
                text=True,
                timeout=30,
                creationflags=subprocess.CREATE_NO_WINDOW
            )
            
            if result.returncode == 0:
                with open(filepath, 'w', encoding='utf-8') as f:
                    f.write(f"# Service backup: {service_name}\n")
                    f.write(f"# Backed up: {datetime.now().isoformat()}\n\n")
                    f.write(result.stdout)
                return filepath
                
        except (subprocess.TimeoutExpired, subprocess.SubprocessError, IOError):
            pass
            
        return None
    
    def backup_startup_items(self) -> Optional[Path]:
        """Backup all startup registry keys.
        
        Returns:
            Path to backup file, or None if failed.
        """
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        keys_to_backup = [
            "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            "HKLM\\Software\\Microsoft\\Windows\\CurrentVersion\\Run",
            "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run",
            "HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\StartupApproved\\Run",
        ]
        
        backup_files = []
        for key in keys_to_backup:
            safe_name = key.replace("\\", "_").replace("/", "_")
            filename = f"startup_{safe_name}_{timestamp}.reg"
            
            backup_path = self.backup_registry_key(key, filename)
            if backup_path:
                backup_files.append(backup_path)
                
        if backup_files:
            # Create a manifest file listing all backups
            manifest_file = self.backup_dir / f"startup_backup_manifest_{timestamp}.txt"
            with open(manifest_file, 'w', encoding='utf-8') as f:
                f.write(f"# Startup items backup\n")
                f.write(f"# Created: {datetime.now().isoformat()}\n\n")
                for bf in backup_files:
                    f.write(f"{bf}\n")
            return manifest_file
            
        return None
    
    def get_last_restore_points(self, count: int = 5) -> list:
        """Get list of recent restore points.
        
        Args:
            count: Number of restore points to retrieve.
            
        Returns:
            List of restore point information.
        """
        ps_script = f'''
        Get-ComputerRestorePoint | Select-Object -First {count} | ForEach-Object {{
            [PSCustomObject]@{{
                SequenceNumber = $_.SequenceNumber
                Description = $_.Description
                CreationTime = $_.CreationTime.ToString("o")
                RestorePointType = $_.RestorePointType
            }}
        }} | ConvertTo-Json
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
                import json
                points = json.loads(result.stdout)
                if isinstance(points, dict):
                    points = [points]
                return points
                
        except (subprocess.TimeoutExpired, subprocess.SubprocessError):
            pass
            
        return []


if __name__ == "__main__":
    # Quick test
    manager = BackupManager()
    
    print("Getting recent restore points...")
    points = manager.get_last_restore_points()
    for p in points:
        print(f"  {p.get('Description')} - {p.get('CreationTime')}")
        
    print("\nBacking up startup items...")
    result = manager.backup_startup_items()
    if result:
        print(f"  Backup saved to: {result}")
    else:
        print("  Backup failed or no items to backup")
