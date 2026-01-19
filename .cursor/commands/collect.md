# Collect Inventory

Runs the inventory collection script to gather current system state.

```bash
python scripts/collect_inventory.py --no-signatures
```

Use `--no-signatures` for faster collection (skips digital signature checks).

Output: `data/inventories/{timestamp}_*.yaml`
