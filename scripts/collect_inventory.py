#!/usr/bin/env python3
"""
Collect comprehensive system inventory.

This script collects information about:
- Running processes
- Windows services
- Startup items
- Scheduled tasks

Usage:
    python scripts/collect_inventory.py [--no-signatures] [--output-dir PATH]
"""

import argparse
import sys
import os
from datetime import datetime
from pathlib import Path

# Fix encoding issues on Windows
if sys.platform == 'win32':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.collectors import ProcessCollector, ServiceCollector, StartupCollector, TaskCollector
from src.collectors.base_collector import get_system_info

# Try to import rich, but handle terminal compatibility issues
RICH_AVAILABLE = False
try:
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, TextColumn
    # Test if rich can output without errors
    test_console = Console(force_terminal=False, no_color=True)
    RICH_AVAILABLE = True
except (ImportError, Exception):
    RICH_AVAILABLE = False
    

def main():
    parser = argparse.ArgumentParser(description="Collect system inventory")
    parser.add_argument(
        "--no-signatures",
        action="store_true",
        help="Skip collecting digital signatures (faster but less info)"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/inventories"),
        help="Output directory for inventory files"
    )
    parser.add_argument(
        "--skip-microsoft-tasks",
        action="store_true",
        help="Skip Microsoft scheduled tasks (reduces output size)"
    )
    parser.add_argument(
        "--no-rich",
        action="store_true",
        help="Disable rich output formatting"
    )
    
    args = parser.parse_args()
    
    use_rich = RICH_AVAILABLE and not args.no_rich
    
    if use_rich:
        try:
            console = Console(force_terminal=True)
            console.print("\n[bold blue]Windows Optimization Toolkit - Inventory Collection[/bold blue]\n")
        except Exception:
            use_rich = False
            print("\nWindows Optimization Toolkit - Inventory Collection\n")
    else:
        print("\nWindows Optimization Toolkit - Inventory Collection\n")
        
    # Create output directory
    args.output_dir.mkdir(parents=True, exist_ok=True)
    
    # Generate timestamp for this collection
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    
    # Collect system info
    system_info = get_system_info()
    
    if use_rich:
        console.print(f"[dim]System: {system_info['os_name']} {system_info['os_release']}[/dim]")
        console.print(f"[dim]Host: {system_info['hostname']}[/dim]\n")
    else:
        print(f"System: {system_info['os_name']} {system_info['os_release']}")
        print(f"Host: {system_info['hostname']}\n")
        
    results = {}
    
    # Collect processes
    print("Collecting processes...")
    proc_collector = ProcessCollector(
        output_dir=args.output_dir,
        collect_signatures=not args.no_signatures,
    )
    processes = proc_collector.collect()
    proc_file = proc_collector.save(processes, f"processes_{timestamp}.yaml")
    results["processes"] = {
        "count": len(processes),
        "file": proc_file,
        "summary": proc_collector.get_summary(processes),
    }
    print(f"  Collected {len(processes)} processes")
        
    # Collect services
    print("Collecting services...")
    svc_collector = ServiceCollector(output_dir=args.output_dir)
    services = svc_collector.collect()
    svc_file = svc_collector.save(services, f"services_{timestamp}.yaml")
    results["services"] = {
        "count": len(services),
        "file": svc_file,
        "summary": svc_collector.get_summary(services),
    }
    print(f"  Collected {len(services)} services")
        
    # Collect startup items
    print("Collecting startup items...")
    startup_collector = StartupCollector(output_dir=args.output_dir)
    startup_items = startup_collector.collect()
    startup_file = startup_collector.save(startup_items, f"startup_{timestamp}.yaml")
    results["startup_items"] = {
        "count": len(startup_items),
        "file": startup_file,
        "summary": startup_collector.get_summary(startup_items),
    }
    print(f"  Collected {len(startup_items)} startup items")
        
    # Collect scheduled tasks
    print("Collecting scheduled tasks...")
    task_collector = TaskCollector(
        output_dir=args.output_dir,
        include_microsoft=not args.skip_microsoft_tasks,
    )
    tasks = task_collector.collect()
    task_file = task_collector.save(tasks, f"tasks_{timestamp}.yaml")
    results["scheduled_tasks"] = {
        "count": len(tasks),
        "file": task_file,
        "summary": task_collector.get_summary(tasks),
    }
    print(f"  Collected {len(tasks)} scheduled tasks")
        
    # Print summary
    if use_rich and 'console' in dir():
        console.print("\n[bold]Collection Summary[/bold]\n")
        
        table = Table(show_header=True)
        table.add_column("Category", style="cyan")
        table.add_column("Count", justify="right")
        table.add_column("File")
        
        table.add_row("Processes", str(results["processes"]["count"]), str(results["processes"]["file"]))
        table.add_row("Services", str(results["services"]["count"]), str(results["services"]["file"]))
        table.add_row("Startup Items", str(results["startup_items"]["count"]), str(results["startup_items"]["file"]))
        table.add_row("Scheduled Tasks", str(results["scheduled_tasks"]["count"]), str(results["scheduled_tasks"]["file"]))
        
        console.print(table)
        
        # Print some highlights
        console.print("\n[bold]Highlights[/bold]\n")
        
        proc_summary = results["processes"]["summary"]
        console.print(f"  Total process memory: [yellow]{proc_summary['total_memory_mb']:.0f} MB[/yellow]")
        
        svc_summary = results["services"]["summary"]
        third_party_auto = len(svc_summary.get("third_party_running_auto", []))
        console.print(f"  Third-party auto-start services running: [yellow]{third_party_auto}[/yellow]")
        
        task_summary = results["scheduled_tasks"]["summary"]
        third_party_logon = len(task_summary.get("third_party_logon_tasks", []))
        console.print(f"  Third-party logon tasks: [yellow]{third_party_logon}[/yellow]")
        
        console.print(f"\n[dim]Run 'python scripts/analyze_suspects.py' to identify optimization candidates.[/dim]\n")
    else:
        print("\nCollection Summary")
        print(f"  Processes: {results['processes']['count']}")
        print(f"  Services: {results['services']['count']}")
        print(f"  Startup Items: {results['startup_items']['count']}")
        print(f"  Scheduled Tasks: {results['scheduled_tasks']['count']}")
        print(f"\nFiles saved to: {args.output_dir}")
        print("\nRun 'python scripts/analyze_suspects.py' to identify optimization candidates.\n")
        
    return results


if __name__ == "__main__":
    main()
