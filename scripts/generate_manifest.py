#!/usr/bin/env python3
"""
Generate manifest.yaml recommendations from analysis results.
Uses known_processes.yaml to provide recommendations.
"""

import yaml
import sys
import os
from pathlib import Path
from datetime import datetime

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))


def load_yaml(path: Path) -> dict:
    """Load a YAML file."""
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f) or {}


def find_latest_analysis(data_dir: Path) -> Path | None:
    """Find the most recent analysis file."""
    analysis_dir = data_dir / 'analysis'
    if not analysis_dir.exists():
        return None
    
    files = list(analysis_dir.glob('analysis_*.yaml'))
    if not files:
        return None
    
    return max(files, key=lambda p: p.stat().st_mtime)


def generate_recommendations(analysis: dict, known: dict) -> dict:
    """Generate manifest recommendations from analysis."""
    recommendations = {
        'generated_at': datetime.now().isoformat(),
        'services': {'disable': [], 'manual': [], 'keep': []},
        'startup': {'disable': [], 'keep': []},
        'apps': {'remove': [], 'keep': []},
        'unknown': []  # Items not in known database
    }
    
    # Process services
    if 'services' in analysis.get('summary', {}):
        for item in analysis['summary']['services'].get('items', []):
            name = item.get('name', '')
            
            # Look up in known database
            known_entry = known.get(name) or known.get(name.replace(' ', ''))
            
            if known_entry:
                rec = known_entry.get('recommendation', 'KEEP')
                if rec == 'DISABLE':
                    recommendations['services']['disable'].append({
                        'name': name,
                        'purpose': known_entry.get('purpose', ''),
                        'safety': known_entry.get('safety_rating', 'SAFE')
                    })
                elif rec == 'REMOVE':
                    recommendations['services']['disable'].append({
                        'name': name,
                        'purpose': known_entry.get('purpose', ''),
                        'safety': known_entry.get('safety_rating', 'SAFE')
                    })
                else:
                    recommendations['services']['keep'].append(name)
            else:
                recommendations['unknown'].append({
                    'type': 'service',
                    'name': name,
                    'reasons': item.get('reasons', [])
                })
    
    # Process startup items
    if 'startup_items' in analysis.get('summary', {}):
        for item in analysis['summary']['startup_items'].get('items', []):
            name = item.get('name', '')
            
            # Look up in known database
            known_entry = known.get(name) or known.get(name + '.exe')
            
            if known_entry:
                rec = known_entry.get('recommendation', 'KEEP')
                if rec in ('DISABLE', 'REMOVE'):
                    recommendations['startup']['disable'].append({
                        'name': name,
                        'purpose': known_entry.get('purpose', ''),
                        'safety': known_entry.get('safety_rating', 'SAFE')
                    })
                else:
                    recommendations['startup']['keep'].append(name)
            else:
                recommendations['unknown'].append({
                    'type': 'startup',
                    'name': name,
                    'reasons': item.get('reasons', [])
                })
    
    return recommendations


def main():
    project_root = Path(__file__).parent.parent
    data_dir = project_root / 'data'
    config_dir = project_root / 'config'
    
    # Find latest analysis
    analysis_path = find_latest_analysis(data_dir)
    if not analysis_path:
        print("No analysis file found. Run analyze_suspects.py first.")
        sys.exit(1)
    
    print(f"Loading analysis: {analysis_path}")
    analysis = load_yaml(analysis_path)
    
    # Load known processes
    known_path = config_dir / 'known_processes.yaml'
    print(f"Loading known database: {known_path}")
    known = load_yaml(known_path)
    
    # Generate recommendations
    recommendations = generate_recommendations(analysis, known)
    
    # Save recommendations
    output_path = data_dir / 'analysis' / f'recommendations_{datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}.yaml'
    with open(output_path, 'w', encoding='utf-8') as f:
        yaml.dump(recommendations, f, default_flow_style=False, allow_unicode=True, sort_keys=False)
    
    print(f"\nRecommendations saved to: {output_path}")
    
    # Print summary
    print("\n=== Summary ===")
    print(f"Services to disable: {len(recommendations['services']['disable'])}")
    print(f"Services to keep: {len(recommendations['services']['keep'])}")
    print(f"Startup to disable: {len(recommendations['startup']['disable'])}")
    print(f"Startup to keep: {len(recommendations['startup']['keep'])}")
    print(f"Unknown items (need research): {len(recommendations['unknown'])}")
    
    if recommendations['unknown']:
        print("\n=== Unknown Items (add to known_processes.yaml) ===")
        for item in recommendations['unknown'][:10]:  # Show first 10
            print(f"  [{item['type']}] {item['name']}")
        if len(recommendations['unknown']) > 10:
            print(f"  ... and {len(recommendations['unknown']) - 10} more")


if __name__ == '__main__':
    main()
