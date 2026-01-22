#!/usr/bin/env python3
"""
Compare the two most recent inventory snapshots and report changes.

Usage:
    python scripts/diff_inventory.py [--inventory-dir PATH] [--output PATH]
"""

import argparse
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Tuple

import yaml


def load_yaml(path: Path) -> List[Dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
        return data or []
    except Exception:
        return []


def latest_two(files: Iterable[Path]) -> Tuple[Path, Path]:
    sorted_files = sorted(files, key=lambda p: p.stat().st_mtime)
    if len(sorted_files) < 2:
        raise RuntimeError("Need at least two snapshots to diff.")
    return sorted_files[-2], sorted_files[-1]


def build_map(
    items: List[Dict[str, Any]],
    key_fn: Callable[[Dict[str, Any]], Any],
    display_fn: Callable[[Dict[str, Any]], str],
) -> Dict[Any, str]:
    result: Dict[Any, str] = {}
    for item in items:
        key = key_fn(item)
        if key is None:
            continue
        result[key] = display_fn(item)
    return result


def diff_maps(old: Dict[Any, str], new: Dict[Any, str]) -> Tuple[List[str], List[str]]:
    added_keys = sorted(set(new.keys()) - set(old.keys()))
    removed_keys = sorted(set(old.keys()) - set(new.keys()))
    added = [new[k] for k in added_keys]
    removed = [old[k] for k in removed_keys]
    return added, removed


def write_section(lines: List[str], title: str, items: List[str]) -> None:
    lines.append(f"## {title}")
    if not items:
        lines.append("- None")
        lines.append("")
        return
    for item in items:
        lines.append(f"- {item}")
    lines.append("")


def main() -> None:
    parser = argparse.ArgumentParser(description="Diff the two most recent inventory snapshots")
    parser.add_argument("--inventory-dir", type=Path, default=Path("data/inventories"))
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    inventory_dir = args.inventory_dir
    if not inventory_dir.exists():
        raise SystemExit(f"Inventory directory not found: {inventory_dir}")

    process_old, process_new = latest_two(inventory_dir.glob("processes_*.yaml"))
    service_old, service_new = latest_two(inventory_dir.glob("services_*.yaml"))
    startup_old, startup_new = latest_two(inventory_dir.glob("startup_*.yaml"))
    task_old, task_new = latest_two(inventory_dir.glob("tasks_*.yaml"))

    old_processes = load_yaml(process_old)
    new_processes = load_yaml(process_new)
    old_services = load_yaml(service_old)
    new_services = load_yaml(service_new)
    old_startup = load_yaml(startup_old)
    new_startup = load_yaml(startup_new)
    old_tasks = load_yaml(task_old)
    new_tasks = load_yaml(task_new)

    proc_old_map = build_map(
        old_processes,
        key_fn=lambda p: (p.get("name"), p.get("exe_path")),
        display_fn=lambda p: f"{p.get('name')} | {p.get('exe_path') or 'unknown'}",
    )
    proc_new_map = build_map(
        new_processes,
        key_fn=lambda p: (p.get("name"), p.get("exe_path")),
        display_fn=lambda p: f"{p.get('name')} | {p.get('exe_path') or 'unknown'}",
    )

    svc_old_map = build_map(
        old_services,
        key_fn=lambda s: s.get("name"),
        display_fn=lambda s: f"{s.get('name')} | {s.get('start_mode')} | {s.get('state')}",
    )
    svc_new_map = build_map(
        new_services,
        key_fn=lambda s: s.get("name"),
        display_fn=lambda s: f"{s.get('name')} | {s.get('start_mode')} | {s.get('state')}",
    )

    startup_old_map = build_map(
        old_startup,
        key_fn=lambda s: (s.get("name"), s.get("location")),
        display_fn=lambda s: f"{s.get('name')} | {s.get('location')}",
    )
    startup_new_map = build_map(
        new_startup,
        key_fn=lambda s: (s.get("name"), s.get("location")),
        display_fn=lambda s: f"{s.get('name')} | {s.get('location')}",
    )

    task_old_map = build_map(
        old_tasks,
        key_fn=lambda t: t.get("full_path"),
        display_fn=lambda t: f"{t.get('full_path')} | {t.get('state')}",
    )
    task_new_map = build_map(
        new_tasks,
        key_fn=lambda t: t.get("full_path"),
        display_fn=lambda t: f"{t.get('full_path')} | {t.get('state')}",
    )

    proc_added, proc_removed = diff_maps(proc_old_map, proc_new_map)
    svc_added, svc_removed = diff_maps(svc_old_map, svc_new_map)
    startup_added, startup_removed = diff_maps(startup_old_map, startup_new_map)
    task_added, task_removed = diff_maps(task_old_map, task_new_map)

    report_lines: List[str] = []
    report_lines.append("# REAPER Inventory Diff")
    report_lines.append("")
    report_lines.append(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    report_lines.append("")
    report_lines.append("## Snapshot Files")
    report_lines.append(f"- Processes: `{process_old.name}` -> `{process_new.name}`")
    report_lines.append(f"- Services: `{service_old.name}` -> `{service_new.name}`")
    report_lines.append(f"- Startup: `{startup_old.name}` -> `{startup_new.name}`")
    report_lines.append(f"- Tasks: `{task_old.name}` -> `{task_new.name}`")
    report_lines.append("")

    write_section(report_lines, "Processes Added", proc_added)
    write_section(report_lines, "Processes Removed", proc_removed)
    write_section(report_lines, "Services Added", svc_added)
    write_section(report_lines, "Services Removed", svc_removed)
    write_section(report_lines, "Startup Items Added", startup_added)
    write_section(report_lines, "Startup Items Removed", startup_removed)
    write_section(report_lines, "Tasks Added", task_added)
    write_section(report_lines, "Tasks Removed", task_removed)

    output_path = args.output
    if output_path is None:
        reports_dir = Path("data/reports")
        reports_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        output_path = reports_dir / f"diff_{stamp}.md"
    else:
        output_path.parent.mkdir(parents=True, exist_ok=True)

    output_path.write_text("\n".join(report_lines) + "\n", encoding="utf-8")
    print(f"Diff report written to: {output_path}")


if __name__ == "__main__":
    main()
