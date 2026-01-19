#!/usr/bin/env python3
"""
Analyze collected inventory to identify suspect processes.

This script:
- Loads the most recent inventory files
- Filters items to identify suspects (bloatware, high resource, non-Microsoft)
- Researches each suspect using the known processes database
- Generates recommendations for the manifest

Usage:
    python scripts/analyze_suspects.py [--inventory-dir PATH] [--output-dir PATH]
"""

import argparse
import sys
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional

import yaml

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.analyzers import SuspectFilter, AIResearcher

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    RICH_AVAILABLE = True
except ImportError:
    RICH_AVAILABLE = False


def find_latest_inventory(inventory_dir: Path, prefix: str) -> Optional[Path]:
    """Find the most recent inventory file with given prefix."""
    files = list(inventory_dir.glob(f"{prefix}_*.yaml"))
    if not files:
        return None
    return max(files, key=lambda f: f.stat().st_mtime)


def load_inventory(filepath: Path) -> List[Dict[str, Any]]:
    """Load inventory from YAML file."""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
            return data.get("items", [])
    except (yaml.YAMLError, IOError, KeyError):
        return []


def main():
    parser = argparse.ArgumentParser(description="Analyze inventory for suspects")
    parser.add_argument(
        "--inventory-dir",
        type=Path,
        default=Path("data/inventories"),
        help="Directory containing inventory files"
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("data/analysis"),
        help="Output directory for analysis results"
    )
    parser.add_argument(
        "--save-individual",
        action="store_true",
        help="Save individual research files for each suspect"
    )
    
    args = parser.parse_args()
    
    if RICH_AVAILABLE:
        console = Console()
        console.print("\n[bold blue]Windows Optimization Toolkit - Suspect Analysis[/bold blue]\n")
    else:
        print("\nWindows Optimization Toolkit - Suspect Analysis\n")
        
    # Find latest inventory files
    inventory_files = {
        "processes": find_latest_inventory(args.inventory_dir, "processes"),
        "services": find_latest_inventory(args.inventory_dir, "services"),
        "startup": find_latest_inventory(args.inventory_dir, "startup"),
        "tasks": find_latest_inventory(args.inventory_dir, "tasks") or find_latest_inventory(args.inventory_dir, "scheduled_tasks"),
    }
    
    missing = [k for k, v in inventory_files.items() if v is None]
    if missing:
        msg = f"Missing inventory files for: {', '.join(missing)}"
        msg += "\nRun 'python scripts/collect_inventory.py' first."
        if RICH_AVAILABLE:
            console.print(f"[red]Error:[/red] {msg}")
        else:
            print(f"Error: {msg}")
        return 1
        
    if RICH_AVAILABLE:
        console.print("[dim]Loading inventory files...[/dim]")
    else:
        print("Loading inventory files...")
        
    # Load inventories
    processes = load_inventory(inventory_files["processes"])
    services = load_inventory(inventory_files["services"])
    startup_items = load_inventory(inventory_files["startup"])
    tasks = load_inventory(inventory_files["tasks"])
    
    if RICH_AVAILABLE:
        console.print(f"  Loaded {len(processes)} processes, {len(services)} services, "
                     f"{len(startup_items)} startup items, {len(tasks)} tasks\n")
    else:
        print(f"  Loaded {len(processes)} processes, {len(services)} services, "
              f"{len(startup_items)} startup items, {len(tasks)} tasks\n")
        
    # Initialize filter and researcher
    suspect_filter = SuspectFilter()
    researcher = AIResearcher(output_dir=args.output_dir)
    
    if RICH_AVAILABLE:
        console.print("[dim]Filtering for suspects...[/dim]")
    else:
        print("Filtering for suspects...")
        
    # Filter each category
    filtered_processes = suspect_filter.filter_processes(processes)
    filtered_services = suspect_filter.filter_services(services)
    filtered_startup = suspect_filter.filter_startup_items(startup_items)
    filtered_tasks = suspect_filter.filter_tasks(tasks)
    
    # Get summary
    summary = suspect_filter.get_summary(
        filtered_processes, filtered_services, filtered_startup, filtered_tasks
    )
    
    if RICH_AVAILABLE:
        console.print(f"\n[bold]Suspect Analysis Summary[/bold]\n")
        
        table = Table(show_header=True)
        table.add_column("Category", style="cyan")
        table.add_column("Total", justify="right")
        table.add_column("Suspects", justify="right", style="yellow")
        
        table.add_row("Processes", str(summary["processes"]["total"]), str(summary["processes"]["suspect"]))
        table.add_row("Services", str(summary["services"]["total"]), str(summary["services"]["suspect"]))
        table.add_row("Startup Items", str(summary["startup_items"]["total"]), str(summary["startup_items"]["suspect"]))
        table.add_row("Scheduled Tasks", str(summary["tasks"]["total"]), str(summary["tasks"]["suspect"]))
        table.add_row("", "", "")
        table.add_row("[bold]Total Suspects[/bold]", "", f"[bold yellow]{summary['total_suspects']}[/bold yellow]")
        
        console.print(table)
    else:
        print(f"\nSuspect Analysis Summary")
        print(f"  Processes: {summary['processes']['suspect']} / {summary['processes']['total']}")
        print(f"  Services: {summary['services']['suspect']} / {summary['services']['total']}")
        print(f"  Startup Items: {summary['startup_items']['suspect']} / {summary['startup_items']['total']}")
        print(f"  Scheduled Tasks: {summary['tasks']['suspect']} / {summary['tasks']['total']}")
        print(f"\n  Total Suspects: {summary['total_suspects']}")
        
    # Research suspects
    if RICH_AVAILABLE:
        console.print(f"\n[dim]Researching {summary['total_suspects']} suspects...[/dim]\n")
    else:
        print(f"\nResearching {summary['total_suspects']} suspects...\n")
        
    research_results = researcher.research_all_suspects(
        filtered_processes, filtered_services, filtered_startup, filtered_tasks
    )
    
    # Get recommendations
    recommendations = researcher.generate_recommendations(research_results)
    
    # Display recommendations
    if RICH_AVAILABLE:
        console.print("[bold]Recommendations[/bold]\n")
        
        for action, items in recommendations.items():
            if not items:
                continue
                
            color = {"REMOVE": "red", "DISABLE": "yellow", "KEEP": "green", "REVIEW": "blue"}.get(action, "white")
            
            console.print(f"[{color}]{action}[/{color}] ({len(items)} items):")
            for item in items[:10]:  # Show first 10
                console.print(f"  • {item['name']} ({item['type']}) - {item.get('purpose', 'Unknown')[:50]}")
            if len(items) > 10:
                console.print(f"  ... and {len(items) - 10} more")
            console.print()
    else:
        print("Recommendations\n")
        for action, items in recommendations.items():
            if not items:
                continue
            print(f"{action} ({len(items)} items):")
            for item in items[:10]:
                print(f"  - {item['name']} ({item['type']})")
            if len(items) > 10:
                print(f"  ... and {len(items) - 10} more")
            print()
            
    # Save results
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    
    # Save full analysis
    analysis_file = args.output_dir / f"analysis_{timestamp}.yaml"
    args.output_dir.mkdir(parents=True, exist_ok=True)
    
    full_results = {
        "analyzed_at": datetime.now().isoformat(),
        "summary": summary,
        "recommendations": recommendations,
        "research": research_results,
    }
    
    with open(analysis_file, 'w', encoding='utf-8') as f:
        yaml.dump(full_results, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
        
    if args.save_individual:
        researcher.save_individual_reports(research_results)
        
    if RICH_AVAILABLE:
        console.print(f"[dim]Analysis saved to: {analysis_file}[/dim]")
        console.print(f"\n[dim]Next steps:[/dim]")
        console.print(f"  1. Review the analysis file")
        console.print(f"  2. Update config/manifest.yaml with your decisions")
        console.print(f"  3. Run 'scripts/execute_cleanup.ps1 -DryRun' to preview changes")
        console.print(f"  4. Run 'scripts/execute_cleanup.ps1 -Execute' to apply changes\n")
    else:
        print(f"\nAnalysis saved to: {analysis_file}")
        print("\nNext steps:")
        print("  1. Review the analysis file")
        print("  2. Update config/manifest.yaml with your decisions")
        print("  3. Run 'scripts/execute_cleanup.ps1 -DryRun' to preview changes")
        print("  4. Run 'scripts/execute_cleanup.ps1 -Execute' to apply changes\n")
        
    return 0


if __name__ == "__main__":
    sys.exit(main())
