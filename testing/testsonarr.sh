# --- sonarr-config ---
make sonarr-config

# --- sonarr-series ---
make sonarr-series | head -15

# --- sonarr-rescan (with and without ID) ---
make sonarr-rescan                      # should error
make sonarr-rescan SERIES_ID=2319       # should queue rescan

# --- sonarr-plan (no manifest → expect clear error) ---
make sonarr-plan

# --- sonarr-dry-run (no plan → expect clear error) ---
make sonarr-dry-run

# --- sonarr-dry-run (with synthetic plan) ---
mkdir -p artifacts && cat > artifacts/sonarr-reconcile-plan.json << 'EOF'
{
  "service": "sonarr",
  "generated_at": "2026-04-15 00:00:00",
  "counts": { "planned": 1 },
  "items": [
    {
      "service": "sonarr",
      "reconcile_status": "planned",
      "from_path": "/tv/11.22.63 (2016)",
      "to_path": "/tv2/11.22.63 (2016)",
      "remote_from_path": "/tv/11.22.63 (2016)",
      "remote_to_path": "/tv2/11.22.63 (2016)"
    }
  ]
}
EOF
make sonarr-dry-run

# --- cleanup ---
rm artifacts/sonarr-reconcile-plan.json && rmdir artifacts
